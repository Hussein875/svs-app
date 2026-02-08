//
//  MainView.swift
//  SVS App
//
//  Created by Hussein Souleiman on 23.12.25.
//
import Foundation
import SwiftUI
import UIKit
import VisionKit
import PDFKit
import UniformTypeIdentifiers
import AVFoundation
import FirebaseAuth
import FirebaseStorage
import FirebaseFirestore

struct MainView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab: MainTab = .calendar
    @State private var homePushDestination: HomePushDestination?
    @State private var lastHandledPushRouteKey: String = ""
    @State private var lastHandledPushRouteAt: Date = .distantPast

    var body: some View {
        TabView(selection: $selectedTab) {
            // Urlaub
            CalendarScreen()
                .tabItem {
                    Label("Kalender", systemImage: "calendar")
                }
                .tag(MainTab.calendar)

            WorkHomeView(pushDestination: $homePushDestination)
                .tabItem {
                    Label("Mein Bereich", systemImage: "person.crop.circle")
                }
                .tag(MainTab.home)
            
            // Scanner
            ScannerScreen()
                .tabItem {
                    Label("Scanner", systemImage: "doc.viewfinder")
                }
                .tag(MainTab.scanner)
            
            // Admin-spezifische Tabs
            if appState.currentUser?.role == .admin {
                AdminConsoleView()
                    .tabItem {
                        Label("Admin", systemImage: "shield.lefthalf.filled")
                    }
                    .tag(MainTab.admin)
            }

            // Menü Tab
            MenuView()
                .tabItem {
                    Label("Menü", systemImage: "gearshape")
                }
                .tag(MainTab.menu)
        }
        .onReceive(NotificationCenter.default.publisher(for: .pushRoute)) { notification in
            guard let route = notification.userInfo?["route"] as? PushRoute else { return }
            handlePushRoute(route)
        }
        .onAppear {
            customizeMoreTab(title: "Mehr")
            if let bufferedRoute = PushNotificationRouter.consumeBufferedRoute() {
                handlePushRoute(bufferedRoute)
            }
        }
        .onChange(of: appState.currentUser?.role) { role in
            if role != .admin && selectedTab == .admin {
                selectedTab = .calendar
            }
        }
    }

    private func handlePushRoute(_ route: PushRoute) {
        if isRecentDuplicate(route) {
            return
        }

        switch route.type {
        case .leaveRequestNew:
            if appState.currentUser?.role == .admin {
                selectedTab = .admin
            } else {
                selectedTab = .calendar
            }

        case .leaveRequestApproved, .leaveRequestRejected:
            selectedTab = .home
            homePushDestination = HomePushDestination(
                kind: .myRequests,
                entityId: asUUID(route.entityId)
            )

        case .taskAssigned:
            selectedTab = .home
            homePushDestination = HomePushDestination(
                kind: .tasksAssigned,
                entityId: asUUID(route.entityId)
            )

        case .taskCompleted:
            selectedTab = .home
            homePushDestination = HomePushDestination(
                kind: .tasksCompleted,
                entityId: asUUID(route.entityId)
            )

        case .commissionNew:
            if appState.currentUser?.role == .admin {
                selectedTab = .admin
            } else {
                selectedTab = .home
            }

        case .unknown:
            selectedTab = .home
        }
    }

    private func asUUID(_ raw: String?) -> UUID? {
        guard let raw else { return nil }
        return UUID(uuidString: raw)
    }

    private func isRecentDuplicate(_ route: PushRoute) -> Bool {
        let key = "\(route.type.rawValue)|\(route.entityId ?? "")|\(route.decision ?? "")"
        let now = Date()

        if key == lastHandledPushRouteKey,
           now.timeIntervalSince(lastHandledPushRouteAt) < 1.2 {
            return true
        }

        lastHandledPushRouteKey = key
        lastHandledPushRouteAt = now
        return false
    }
}

private enum MainTab: Hashable {
    case calendar
    case home
    case scanner
    case admin
    case menu
}

private struct HomePushDestination: Identifiable, Hashable {
    enum Kind: Hashable {
        case tasksAssigned
        case tasksCompleted
        case myRequests
    }

    let id = UUID()
    let kind: Kind
    let entityId: UUID?
}

// MARK: - Scanner

private struct ScannerScreen: View {
    @EnvironmentObject var appState: AppState

    @State private var isPresentingScanner = false
    @State private var isPresentingShare = false
    @State private var scannedPDFURL: URL? = nil
    @State private var gutachtenNr: String = ""
    @State private var uiErrorMessage: String? = nil
    @State private var isUploadingToDrive = false
    @State private var driveUploadSuccessMessage: String? = nil


    private var userAccentColor: Color {
        Color.svsAccentColor(from: appState.currentUser?.colorName)
    }

    private var currentYearInterval: DateInterval {
        let cal = Calendar.current
        let year = cal.component(.year, from: Date())
        let start = cal.date(from: DateComponents(year: year, month: 1, day: 1)) ?? Date()
        let end = cal.date(from: DateComponents(year: year + 1, month: 1, day: 1))
            ?? Date().addingTimeInterval(60 * 60 * 24 * 365)
        return DateInterval(start: start, end: end)
    }

    private var currentYear2: String {
        let y = Calendar.current.component(.year, from: Date())
        return String(format: "%02d", y % 100)
    }

    private var formattedScanName: String {
        let digits = gutachtenNr.filter { $0.isNumber }
        let trimmed = String(digits.prefix(4))
        let zeros = max(0, 4 - trimmed.count)
        let nr = String(repeating: "0", count: zeros) + trimmed
        return "\(nr)/\(currentYear2)"
    }

    // Same as formattedScanName, but WITHOUT leading zeros (e.g. 0191/26 -> 191/26)
    private var formattedScanNameNoLeadingZeros: String {
        let digits = gutachtenNr.filter { $0.isNumber }
        let trimmed = String(digits.prefix(4))
        // Int(...) removes leading zeros automatically.
        let number = Int(trimmed) ?? 0
        return "\(number)/\(currentYear2)"
    }

    // Extracts GA number from a generated file name like:
    // 0191_26_20260130_105709.pdf -> 191/26
    private func gaNumber(fromFileName fileName: String) -> String? {
        // Remove extension and split by underscore
        let base = (fileName as NSString).deletingPathExtension
        let parts = base.split(separator: "_")
        guard parts.count >= 2 else { return nil }

        let first = String(parts[0])
        let second = String(parts[1])

        // Remove leading zeros from the first part
        let number = Int(first) ?? 0
        return "\(number)/\(second)"
    }

    private let uploadScanToDriveEndpoint =
      URL(string: "https://us-central1-svs-app-864ed.cloudfunctions.net/uploadScanToDrive")!

    private var isErrorPresented: Binding<Bool> {
        Binding(
            get: { uiErrorMessage != nil },
            set: { _ in uiErrorMessage = nil }
        )
    }

    private var isDriveSuccessPresented: Binding<Bool> {
        Binding(
            get: { driveUploadSuccessMessage != nil },
            set: { _ in driveUploadSuccessMessage = nil }
        )
    }

    @ViewBuilder
    private var headerSection: some View {
        HStack(spacing: 10) {
            Image(systemName: "doc.viewfinder")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.tint)

            Text("Scanner")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.secondary)

            Spacer(minLength: 0)
        }
        .padding(.top, 8)

        Text("Dokument scannen")
            .font(.largeTitle.bold())

        Text(
            "Scanne Dokumente mit der Kamera, erstelle automatisch "
              + "eine PDF und exportiere sie oder lege sie in Google Drive "
              + "ab."
        )
        .font(.subheadline)
        .foregroundColor(.secondary)
    }

    @ViewBuilder
    private var numberFieldSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Gutachten-Nr.")
                .font(.caption)
                .foregroundColor(.secondary)

            HStack(spacing: 8) {
                TextField("0000", text: $gutachtenNr)
                    .keyboardType(.numberPad)
                    .submitLabel(.done)
                    .onChange(of: gutachtenNr) { newValue in
                        let digits = newValue.filter { $0.isNumber }
                        gutachtenNr = String(digits.prefix(4))
                    }

                Text("/ \(currentYear2)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
            )

            Text("Dateiname: \(formattedScanName)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    @ViewBuilder
    private var scanButton: some View {
        Button {
            startScan()
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 16, weight: .semibold))
                Text("Scan starten")
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(userAccentColor.opacity(0.28), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func scannedActions(url: URL) -> some View {
        HStack(spacing: 12) {
            Button {
                isPresentingShare = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "square.and.arrow.up")
                    Text("Exportieren")
                }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .disabled(isUploadingToDrive)
            .opacity(isUploadingToDrive ? 0.6 : 1.0)

            Button {
                _Concurrency.Task { await uploadCurrentScanToDrive() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.up.doc")
                    Text("In Drive ablegen")
                }
                .font(.subheadline.weight(.semibold))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(userAccentColor.opacity(0.22), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .disabled(isUploadingToDrive)
            .opacity(isUploadingToDrive ? 0.6 : 1.0)
        }

        if isUploadingToDrive {
            HStack(spacing: 10) {
                ProgressView()
                Text("Wird in Google Drive abgelegt …")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 6)
        }

        VStack(alignment: .leading, spacing: 8) {
            Text("Vorschau")
                .font(.headline)

            PDFPreview(url: url)
                .frame(height: 360)
                .clipShape(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.secondary.opacity(0.10), lineWidth: 1)
                )
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 34, weight: .semibold))
                .foregroundColor(.secondary)

            Text("Noch kein Scan")
                .font(.headline)

            Text(
                "Tippe auf „Scan starten“, um ein Dokument zu erfassen "
                  + "und als PDF zu speichern."
            )
            .font(.subheadline)
            .foregroundColor(.secondary)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.secondary.opacity(0.10), lineWidth: 1)
        )
        .padding(.top, 4)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    headerSection

                    VStack(spacing: 12) {
                        numberFieldSection
                        scanButton

                        if let url = scannedPDFURL {
                            scannedActions(url: url)
                        } else {
                            emptyState
                        }
                    }
                    .padding(.top, 4)

                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 22)
            }
            .background(Color(.systemGroupedBackground))
            .tint(userAccentColor)
            .scrollDismissesKeyboard(.interactively)
            .contentShape(Rectangle())
            .onTapGesture { hideKeyboard() }
            .navigationTitle("Scanner")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $isPresentingScanner) {
                DocumentScanner { images in
                    do {
                        let safeBase = sanitizedFileName(formattedScanName)
                        let finalName = "\(safeBase)_\(timestampString()).pdf"
                        let url = try makePDF(from: images, fileName: finalName)
                        scannedPDFURL = url
                    } catch {
                        uiErrorMessage =
                          "PDF konnte nicht erstellt werden: "
                          + error.localizedDescription
                    }
                } onCancel: {
                    // no-op
                }
                .ignoresSafeArea()
            }
            .sheet(isPresented: $isPresentingShare) {
                if let url = scannedPDFURL {
                    ShareSheet(activityItems: [url])
                        .ignoresSafeArea()
                } else {
                    VStack(spacing: 12) {
                        Text("Keine Datei vorhanden")
                        Button("Schließen") { isPresentingShare = false }
                    }
                    .padding()
                }
            }
            .alert("Scanner", isPresented: isErrorPresented) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(uiErrorMessage ?? "")
            }
            .alert("Google Drive", isPresented: isDriveSuccessPresented) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(driveUploadSuccessMessage ?? "")
            }
        }
    }

    // MARK: - Scanner bootstrap (permissions + device support)

    private func startScan() {
        // VisionKit scanner is not supported on Simulator and some devices.
        guard VNDocumentCameraViewController.isSupported else {
            uiErrorMessage = "Der Dokumentenscanner wird auf diesem Gerät nicht unterstützt (z. B. Simulator)."
            return
        }

        // Check camera permission before presenting to avoid runtime failures.
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            isPresentingScanner = true

        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted {
                        isPresentingScanner = true
                    } else {
                        uiErrorMessage = "Kamerazugriff wurde abgelehnt. Bitte in iOS Einstellungen unter Datenschutz → Kamera erlauben."
                    }
                }
            }

        case .denied, .restricted:
            uiErrorMessage = "Kein Kamerazugriff. Bitte in iOS Einstellungen unter Datenschutz → Kamera erlauben."

        @unknown default:
            uiErrorMessage = "Kamerazugriff konnte nicht geprüft werden."
        }
    }

    // MARK: - PDF helpers

    private func sanitizedFileName(_ input: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let cleaned = input.components(separatedBy: invalid).joined(separator: "_")
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Scan" : cleaned
    }

    private func timestampString() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "yyyyMMdd_HHmmss"
        return f.string(from: Date())
    }

    private func makePDF(from images: [UIImage], fileName: String) throws -> URL {
        guard !images.isEmpty else {
            throw NSError(domain: "Scanner", code: 1, userInfo: [NSLocalizedDescriptionKey: "Keine Seiten gescannt."])
        }

        let pageRect = CGRect(x: 0, y: 0, width: 595, height: 842) // A4 @ 72dpi approx

        let renderer = UIGraphicsPDFRenderer(bounds: pageRect)
        let data = renderer.pdfData { ctx in
            for img in images {
                ctx.beginPage()

                let fitted = fitRect(for: img.size, in: pageRect.insetBy(dx: 18, dy: 18))
                img.draw(in: fitted)
            }
        }

        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SVS_Scans", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(fileName)

        try data.write(to: url, options: .atomic)
        return url
    }

    private func fitRect(for imageSize: CGSize, in container: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return container }
        let sx = container.width / imageSize.width
        let sy = container.height / imageSize.height
        let s = min(sx, sy)

        let w = imageSize.width * s
        let h = imageSize.height * s

        let x = container.minX + (container.width - w) / 2
        let y = container.minY + (container.height - h) / 2
        return CGRect(x: x, y: y, width: w, height: h)
    }

    // MARK: - Drive upload

    private func uploadCurrentScanToDrive() async {
        guard !isUploadingToDrive else { return }
        guard let localURL = scannedPDFURL else {
            uiErrorMessage = "Keine PDF vorhanden."
            return
        }

        guard let user = Auth.auth().currentUser else {
            uiErrorMessage = "Nicht angemeldet."
            return
        }

        isUploadingToDrive = true
        defer { isUploadingToDrive = false }

        do {
            let safeBase = sanitizedFileName(formattedScanName)
            let finalName = "\(safeBase)_\(timestampString()).pdf"

            let storagePath = "scans/\(user.uid)/\(finalName)"
            try await uploadFileToFirebaseStorage(
                localURL: localURL,
                storagePath: storagePath
            )

            let idToken = try await user.getIDToken()
            let driveFileId = try await callUploadScanToDrive(
                idToken: idToken,
                storagePath: storagePath,
                fileName: finalName
            )

            driveUploadSuccessMessage =
              "Datei wurde in Google Drive abgelegt. (ID: \(driveFileId))"
        } catch {
            uiErrorMessage = "Drive-Upload fehlgeschlagen: \(error.localizedDescription)"
        }
    }

    private func uploadFileToFirebaseStorage(
        localURL: URL,
        storagePath: String
    ) async throws {
        let ref = Storage.storage().reference().child(storagePath)
        let metadata = StorageMetadata()
        metadata.contentType = "application/pdf"

        _ = try await ref.putFileAsync(from: localURL, metadata: metadata)
    }

    private func callUploadScanToDrive(
        idToken: String,
        storagePath: String,
        fileName: String
    ) async throws -> String {
        var request = URLRequest(url: uploadScanToDriveEndpoint)
        request.httpMethod = "POST"
        request.setValue(
            "Bearer \(idToken)",
            forHTTPHeaderField: "Authorization"
        )
        request.setValue(
            "application/json",
            forHTTPHeaderField: "Content-Type"
        )

        let body: [String: Any] = [
            "storagePath": storagePath,
            "fileName": fileName,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let http = response as? HTTPURLResponse
        let status = http?.statusCode ?? -1
        let rawText = String(data: data, encoding: .utf8) ?? ""

        struct Payload: Decodable {
            let ok: Bool
            let driveFileId: String?
            let error: String?
        }

        if status < 200 || status >= 300 {
            print("[Drive] uploadScanToDrive HTTP", status)
            if !rawText.isEmpty { print("[Drive] body:", rawText) }
        }

        do {
            let decoded = try JSONDecoder().decode(Payload.self, from: data)
            if decoded.ok, let id = decoded.driveFileId, !id.isEmpty {
                return id
            }

            let msg = decoded.error ?? "HTTP \(status)"
            throw NSError(
                domain: "Drive",
                code: status,
                userInfo: [NSLocalizedDescriptionKey: msg]
            )
        } catch {
            // Non-JSON or unexpected payload; expose raw response for debugging.
            let prefix = rawText.prefix(500)
            let msg =
              "Unerwartete Server-Antwort (HTTP \(status)): \(prefix)"
            throw NSError(
                domain: "Drive",
                code: status,
                userInfo: [NSLocalizedDescriptionKey: msg]
            )
        }
    }
}

// MARK: - Document Scanner (VisionKit)

private struct DocumentScanner: UIViewControllerRepresentable {
    let onFinish: ([UIImage]) -> Void
    let onCancel: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish, onCancel: onCancel) }

    func makeUIViewController(context: Context) -> VNDocumentCameraViewController {
        let vc = VNDocumentCameraViewController()
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: VNDocumentCameraViewController, context: Context) { }

    final class Coordinator: NSObject, VNDocumentCameraViewControllerDelegate {
        let onFinish: ([UIImage]) -> Void
        let onCancel: () -> Void

        init(onFinish: @escaping ([UIImage]) -> Void, onCancel: @escaping () -> Void) {
            self.onFinish = onFinish
            self.onCancel = onCancel
        }

        func documentCameraViewControllerDidCancel(_ controller: VNDocumentCameraViewController) {
            controller.dismiss(animated: true)
            onCancel()
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFailWithError error: Error) {
            controller.dismiss(animated: true)
            onCancel()
            print("[Scanner] VNDocumentCamera failed:", error.localizedDescription)
        }

        func documentCameraViewController(_ controller: VNDocumentCameraViewController, didFinishWith scan: VNDocumentCameraScan) {
            var images: [UIImage] = []
            images.reserveCapacity(scan.pageCount)
            for i in 0..<scan.pageCount {
                images.append(scan.imageOfPage(at: i))
            }
            controller.dismiss(animated: true)
            onFinish(images)
        }
    }
}

// MARK: - PDF Preview (PDFKit)

private struct PDFPreview: UIViewRepresentable {
    let url: URL

    final class Coordinator {
        var lastURL: URL?
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true
        v.displayMode = .singlePageContinuous
        v.displayDirection = .vertical
        v.usePageViewController(true, withViewOptions: nil)
        v.backgroundColor = UIColor.secondarySystemBackground

        // Set initial document safely on main.
        DispatchQueue.main.async {
            v.document = PDFDocument(url: url)
        }

        context.coordinator.lastURL = url
        return v
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        // Avoid repeated PDFDocument creation; PDFKit is sensitive to rapid updates.
        guard context.coordinator.lastURL != url else { return }
        context.coordinator.lastURL = url

        DispatchQueue.main.async {
            uiView.document = PDFDocument(url: url)
        }
    }
}

// MARK: - Share Sheet

private struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    let applicationActivities: [UIActivity]? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: activityItems, applicationActivities: applicationActivities)
        return vc
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) { }
}

// MARK: - Arbeit (Home)

private struct WorkHomeView: View {
    @EnvironmentObject var appState: AppState
    @Binding var pushDestination: HomePushDestination?

    private var displayName: String {
        let name = appState.currentUser?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "" : name
    }

    private var userAccentColor: Color {
        Color.svsAccentColor(from: appState.currentUser?.colorName)
    }

    private var currentYearInterval: DateInterval {
        let cal = Calendar.current
        let year = cal.component(.year, from: Date())
        let start = cal.date(from: DateComponents(year: year, month: 1, day: 1)) ?? Date()
        let end = cal.date(from: DateComponents(year: year + 1, month: 1, day: 1))
            ?? Date().addingTimeInterval(60 * 60 * 24 * 365)
        return DateInterval(start: start, end: end)
    }

    // Quick numbers
    private var myOpenTasksCount: Int {
        guard let me = appState.currentUser else { return 0 }
        return appState.tasks.filter { $0.assignedUserId == me.id && $0.status == .open }.count
    }

    private var myActiveRequestsCount: Int {
        guard let me = appState.currentUser else { return 0 }
        let today = Calendar.current.startOfDay(for: Date())
        return appState.leaveRequests
            .filter { $0.user.id == me.id }
            .filter { $0.endDate >= today }
            .filter { $0.type != .onCallSaturday }
            .count
    }

    private var myOnCallSaturdaysThisYearCount: Int {
        guard let me = appState.currentUser else { return 0 }
        return appState.leaveRequests
            .filter { $0.user.id == me.id }
            .filter { $0.type == .onCallSaturday }
            .filter { currentYearInterval.contains($0.startDate) }
            .count
    }

    private var openMeetingTopicsCount: Int {
        appState.meetingTopics.filter { $0.status == .open }.count
    }

    private var nextMeetingShortText: String {
        guard let next = appState.nextMeetingAt else { return "Nicht gesetzt" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "dd.MM · HH:mm"
        return f.string(from: next)
    }

    private var nextMyOnCallSaturdayText: String {
        guard let me = appState.currentUser else { return "—" }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        let next = appState.leaveRequests
            .filter { $0.user.id == me.id }
            .filter { $0.type == .onCallSaturday }
            .map { cal.startOfDay(for: $0.startDate) }
            .filter { $0 >= today }
            .sorted()
            .first

        guard let next else { return "Keine geplant" }

        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "EEE, dd.MM"
        return f.string(from: next)
    }

    private var upcomingFreeSaturdaysCount: Int {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let saturdays = allSaturdays(in: currentYearInterval)
        return saturdays
            .filter { $0 >= today }
            .filter { sat in
                !appState.leaveRequests.contains(where: {
                    $0.type == .onCallSaturday && cal.isDate($0.startDate, inSameDayAs: sat)
                })
            }
            .count
    }

    private func allSaturdays(in interval: DateInterval) -> [Date] {
        let cal = Calendar.current
        var dates: [Date] = []
        var d = cal.startOfDay(for: interval.start)

        // Advance to first Saturday.
        while cal.component(.weekday, from: d) != 7 {
            guard let next = cal.date(byAdding: .day, value: 1, to: d) else { break }
            d = next
        }

        // Collect Saturdays until end.
        while d < interval.end {
            dates.append(d)
            guard let next = cal.date(byAdding: .day, value: 7, to: d) else { break }
            d = next
        }

        return dates
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // MARK: Header (clean)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 10) {
                            Image(systemName: "car.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.tint)

                            Text("Mein Bereich")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.secondary)

                            Spacer(minLength: 0)
                        }

                        Text(displayName.isEmpty ? "Mein Bereich" : "Hallo, \(displayName)")
                            .font(.largeTitle.bold())
                            .foregroundColor(.primary)

                        // Subtle accent underline
                        Capsule(style: .continuous)
                            .fill(.tint)
                            .frame(width: 54, height: 4)
                            .padding(.top, 4)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 8)

                    // MARK: Quick numbers
                    VStack(spacing: 12) {
                        HStack(spacing: 12) {
                            StatTextPill(
                                title: "Nächste Bereitschaft",
                                valueText: nextMyOnCallSaturdayText,
                                systemImage: "calendar.badge.clock"
                            )
                            StatTextPill(
                                title: "Nächstes Meeting",
                                valueText: nextMeetingShortText,
                                systemImage: "person.3.fill"
                            )
                        }
                    }
                    .padding(.horizontal, 18)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Start")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)
                            .padding(.horizontal, 2)

                        VStack(spacing: 12) {
                            NavigationLink {
                                MyRequestsScreen()
                            } label: {
                                WorkCard(
                                    title: "Abwesenheiten",
                                    subtitle: "Urlaub, Krankheit, Bereitschaft",
                                    systemImage: "doc.text",
                                    trailingValue: myActiveRequestsCount
                                )
                            }
                            .buttonStyle(.plain)

                            NavigationLink {
                                TasksView()
                            } label: {
                                WorkCard(
                                    title: "Aufgaben",
                                    subtitle: "Offene To-dos",
                                    systemImage: "checklist",
                                    trailingValue: myOpenTasksCount
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 18)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Weitere Bereiche")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)
                            .padding(.horizontal, 2)

                        HStack(spacing: 12) {
                            NavigationLink {
                                MyOnCallSaturdaysScreen()
                            } label: {
                                CompactWorkCard(
                                    title: "Bereitschaft",
                                    systemImage: "calendar.badge.clock",
                                    badgeText: myOnCallSaturdaysThisYearCount > 0 ? "\(myOnCallSaturdaysThisYearCount)" : nil
                                )
                            }
                            .buttonStyle(.plain)

                            NavigationLink {
                                MeetingTopicsView()
                            } label: {
                                CompactWorkCard(
                                    title: "Meeting",
                                    systemImage: "person.3.fill",
                                    badgeText: openMeetingTopicsCount > 0 ? "\(openMeetingTopicsCount)" : nil
                                )
                            }
                            .buttonStyle(.plain)
                        }

                        HStack(spacing: 12) {
                            NavigationLink {
                                ProvisionenView()
                            } label: {
                                CompactWorkCard(
                                    title: "Provision",
                                    systemImage: "eurosign.circle",
                                    badgeText: nil
                                )
                            }
                            .buttonStyle(.plain)

                            NavigationLink {
                                DashboardView()
                            } label: {
                                CompactWorkCard(
                                    title: "Dashboard",
                                    systemImage: "chart.bar.xaxis",
                                    badgeText: nil
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 18)
                }
            }
            .navigationDestination(item: $pushDestination) { destination in
                switch destination.kind {
                case .tasksAssigned:
                    TasksView()
                case .tasksCompleted:
                    TasksView(
                        startInAssignedByMe: true,
                        startInDoneFilter: true
                    )
                case .myRequests:
                    MyRequestsScreen()
                }
            }
            .background(Color(.systemGroupedBackground))
            .tint(userAccentColor)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct MyOnCallSaturdaysScreen: View {
    @EnvironmentObject var appState: AppState
    @State private var deleteTarget: LeaveRequest?
    @State private var isConfirmingDelete = false
    @State private var deleteErrorMessage: String? = nil

    private var meId: String {
        appState.currentUser?.id ?? ""
    }

    private var userAccentColor: Color {
        Color.svsAccentColor(from: appState.currentUser?.colorName)
    }

    private var isDeleteErrorPresented: Binding<Bool> {
        Binding(
            get: { deleteErrorMessage != nil },
            set: { _ in deleteErrorMessage = nil }
        )
    }

    private var currentYearInterval: DateInterval {
        let cal = Calendar.current
        let year = cal.component(.year, from: Date())
        let start = cal.date(from: DateComponents(year: year, month: 1, day: 1)) ?? Date()
        let end = cal.date(from: DateComponents(year: year + 1, month: 1, day: 1)) ?? Date().addingTimeInterval(60 * 60 * 24 * 365)
        return DateInterval(start: start, end: end)
    }

    private var myCountThisYear: Int {
        appState.leaveRequests
            .filter { $0.user.id == meId }
            .filter { $0.type == .onCallSaturday }
            .filter { currentYearInterval.contains($0.startDate) }
            .count
    }

    private func allSaturdays(in interval: DateInterval) -> [Date] {
        let cal = Calendar.current
        var dates: [Date] = []
        var d = cal.startOfDay(for: interval.start)

        while cal.component(.weekday, from: d) != 7 {
            guard let next = cal.date(byAdding: .day, value: 1, to: d) else { break }
            d = next
        }

        while d < interval.end {
            dates.append(d)
            guard let next = cal.date(byAdding: .day, value: 7, to: d) else { break }
            d = next
        }

        return dates
    }

    private func onCallRequest(for date: Date) -> LeaveRequest? {
        let cal = Calendar.current
        return appState.leaveRequests.first(where: {
            $0.type == .onCallSaturday && cal.isDate($0.startDate, inSameDayAs: date)
        })
    }

    private func isMine(_ r: LeaveRequest?) -> Bool {
        guard let r else { return false }
        return r.user.id == meId
    }

    private func format(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "EEE, dd.MM.yyyy"
        return f.string(from: date)
    }

    // Helper for displaying a Saturday row
    private func saturdayRow(
        sat: Date,
        mine: Bool,
        taken: Bool,
        ownerName: String,
        format: String,
        showTrash: Bool,
        onTrash: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(
                    mine ? Color.green.opacity(0.18) :
                        (taken ? Color.orange.opacity(0.18) : Color.blue.opacity(0.12))
                )
                .frame(width: 40, height: 40)
                .overlay(
                    Image(systemName: mine ? "checkmark" : (taken ? "lock.fill" : "plus"))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.tint)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(format)
                    .font(.headline)
                if mine {
                    Text("Meine Bereitschaft")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else if taken {
                    let label = ownerName.isEmpty ? "Belegt" : "Belegt · \(ownerName)"
                    Text(label)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                } else {
                    Text("Frei")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            Spacer(minLength: 0)

            if !taken {
                // Show capsule affordance, but not as a link.
                Text("Eintragen")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color(.secondarySystemBackground)))
            } else if showTrash {
                Button {
                    onTrash()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.red)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(.secondarySystemBackground))
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Bereitschaft löschen")
            }
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.secondary.opacity(0.10), lineWidth: 1)
        )
    }

    var body: some View {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let saturdays = allSaturdays(in: currentYearInterval)
        let upcomingSaturdays = Array(saturdays.filter { $0 >= today }.prefix(8))

        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Samstage")
                        .font(.headline)

                    VStack(spacing: 10) {
                        ForEach(upcomingSaturdays, id: \.self) { sat in
                            let r = onCallRequest(for: sat)
                            let mine = isMine(r)
                            let taken = (r != nil)
                            let ownerName = r?.user.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

                            let row = saturdayRow(
                                sat: sat,
                                mine: mine,
                                taken: taken,
                                ownerName: ownerName,
                                format: format(sat),
                                showTrash: mine,
                                onTrash: {
                                    if let req = r {
                                        deleteTarget = req
                                        isConfirmingDelete = true
                                    }
                                }
                            )

                            if !taken {
                                // Only free Saturdays are tappable (create new on-call).
                                NavigationLink {
                                    NewOnCallSaturdayView(prefilledDate: sat)
                                } label: {
                                    row
                                }
                                .buttonStyle(.plain)
                            } else {
                                // Taken Saturdays are not tappable. My own show a trash button.
                                row
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 22)
        }
        .background(Color(.systemGroupedBackground))
        .tint(userAccentColor)
        .navigationTitle("Bereitschaft")
        .navigationBarTitleDisplayMode(.inline)
        .alert(
            "Bereitschaft löschen?",
            isPresented: $isConfirmingDelete,
            presenting: deleteTarget
        ) { req in
            Button("Löschen", role: .destructive) {
                deleteOnCall(req)
                deleteTarget = nil
            }
            Button("Abbrechen", role: .cancel) {
                deleteTarget = nil
            }
        } message: { _ in
            Text("Möchtest du die Bereitschaft wirklich löschen?")
        }
        .alert("Löschen fehlgeschlagen", isPresented: isDeleteErrorPresented) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(deleteErrorMessage ?? "")
        }
    }

    private func deleteOnCall(_ req: LeaveRequest) {
        // Keep a snapshot for rollback.
        let snapshot = appState.leaveRequests

        // Optimistic UI update: remove locally so the Saturday becomes "Frei" immediately.
        appState.leaveRequests.removeAll { $0.id == req.id }

        // Persist delete to Firestore.
        _Concurrency.Task {
            do {
                // Assumption: Firestore document id equals req.id.uuidString.
                // If your backend uses a different document id, adjust here.
                try await Firestore.firestore()
                    .collection("leaveRequests")
                    .document(req.id.uuidString)
                    .delete()
            } catch {
                // Roll back local state and show error.
                await MainActor.run {
                    appState.leaveRequests = snapshot
                    deleteErrorMessage = error.localizedDescription
                }
            }
        }
    }
}

private struct StatPill: View {
    let title: String
    let value: Int
    let systemImage: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .allowsTightening(true)

                Text("\(value)")
                    .font(.headline)
                    .foregroundColor(.primary)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 12)
        .frame(minHeight: 56)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.secondary.opacity(0.10), lineWidth: 1)
        )
    }
}

private struct StatTextPill: View {
    let title: String
    let valueText: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .allowsTightening(true)

                Text(valueText)
                    .font(.headline)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .allowsTightening(true)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 12)
        .frame(minHeight: 56)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.secondary.opacity(0.10), lineWidth: 1)
        )
    }
}

private struct WorkCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let trailingValue: Int

    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.tint.opacity(0.12))
                .frame(width: 44, height: 44)
                .overlay(
                    Image(systemName: systemImage)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.tint)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if trailingValue > 0 {
                Text("\(trailingValue)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color(.secondarySystemBackground)))
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color(UIColor.tertiaryLabel))
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.secondary.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 5)
    }
}

private struct CompactWorkCard: View {
    let title: String
    let systemImage: String
    let badgeText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(.tint.opacity(0.12))
                    .frame(width: 36, height: 36)
                    .overlay(
                        Image(systemName: systemImage)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.tint)
                    )

                Spacer(minLength: 0)

                if let badgeText {
                    Text(badgeText)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Capsule().fill(Color(.secondarySystemBackground)))
                }
            }

            Text(title)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.primary)
                .lineLimit(2)
                .minimumScaleFactor(0.9)
                .allowsTightening(true)
        }
        .frame(maxWidth: .infinity, minHeight: 94, alignment: .topLeading)
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.secondary.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 5)
    }
}

private func customizeMoreTab(title: String) {
    // TabView uses an underlying UITabBarController. If there are too many tabs,
    // iOS adds a system "More" tab (UINavigationController). We can rename it.
    DispatchQueue.main.async {
        guard let tabBarController = UIApplication.shared.findTabBarController() else { return }
        tabBarController.moreNavigationController.tabBarItem.title = title
        tabBarController.moreNavigationController.navigationBar.topItem?.title = title
    }
}

private extension UIApplication {
    func findTabBarController() -> UITabBarController? {
        // Find the key window's root and search for a UITabBarController.
        let scenes = connectedScenes
            .compactMap { $0 as? UIWindowScene }

        for scene in scenes {
            if let window = scene.windows.first(where: { $0.isKeyWindow }),
               let root = window.rootViewController {
                return root.findTabBarController()
            }
        }
        return nil
    }
}

private extension UIViewController {
    func findTabBarController() -> UITabBarController? {
        if let tab = self as? UITabBarController { return tab }

        for child in children {
            if let found = child.findTabBarController() { return found }
        }

        if let presented = presentedViewController,
           let found = presented.findTabBarController() {
            return found
        }

        return nil
    }
}

private func hideKeyboard() {
    UIApplication.shared.sendAction(
        #selector(UIResponder.resignFirstResponder),
        to: nil,
        from: nil,
        for: nil
    )
}
