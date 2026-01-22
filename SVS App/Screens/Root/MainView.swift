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

struct MainView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        TabView {
            // Urlaub
            CalendarScreen()
                .tabItem {
                    Label("Kalender", systemImage: "calendar")
                }

            WorkHomeView()
                .tabItem {
                    Label("Mein Bereich", systemImage: "person.crop.circle")
                }
            
            // Scanner
            ScannerScreen()
                .tabItem {
                    Label("Scanner", systemImage: "doc.viewfinder")
                }
            
            // Admin-spezifische Tabs
            if appState.currentUser?.role == .admin {
                AdminConsoleView()
                    .tabItem {
                        Label("Admin", systemImage: "shield.lefthalf.filled")
                    }
            }

            // Menü Tab
            MenuView()
                .tabItem {
                    Label("Menü", systemImage: "gearshape")
                }
        }
        .onAppear {
            // 1) UI-Kleinkram
            customizeMoreTab(title: "Mehr")
        }
    }

}

// MARK: - Scanner

private struct ScannerScreen: View {
    @EnvironmentObject var appState: AppState

    @State private var isPresentingScanner = false
    @State private var isPresentingShare = false
    @State private var scannedPDFURL: URL? = nil
    @State private var fileName: String = "Scan"
    @State private var uiErrorMessage: String? = nil


    private var userAccentColor: Color {
        Color.svsAccentColor(from: appState.currentUser?.colorName)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {

                    // Header
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

                    Text("Scanne Dokumente mit der Kamera, erstelle automatisch eine PDF und exportiere sie. Drive-Upload binden wir als nächsten Schritt an.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    // Controls
                    VStack(spacing: 12) {
                        HStack(spacing: 12) {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Dateiname")
                                    .font(.caption)
                                    .foregroundColor(.secondary)

                                TextField("Scan", text: $fileName)
                                    .textInputAutocapitalization(.words)
                                    .submitLabel(.done)
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
                            }
                        }


                        // Primary action
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

                        if let url = scannedPDFURL {
                            // Actions for the scanned PDF
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

                                Button {
                                    // Placeholder for Drive upload
                                    isPresentingShare = true
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
                            }

                            // Preview
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Vorschau")
                                    .font(.headline)

                                PDFPreview(url: url)
                                    .frame(height: 360)
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                                            .stroke(Color.secondary.opacity(0.10), lineWidth: 1)
                                    )

                            }
                            .padding(.top, 4)
                        } else {
                            // Empty state
                            VStack(spacing: 10) {
                                Image(systemName: "doc.text.magnifyingglass")
                                    .font(.system(size: 34, weight: .semibold))
                                    .foregroundColor(.secondary)

                                Text("Noch kein Scan")
                                    .font(.headline)

                                Text("Tippe auf „Scan starten“, um ein Dokument zu erfassen und als PDF zu speichern.")
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
            .onTapGesture {
                hideKeyboard()
            }
            .navigationTitle("Scanner")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $isPresentingScanner) {
                DocumentScanner { images in
                    do {
                        let safeBase = sanitizedFileName(fileName.isEmpty ? "Scan" : fileName)
                        let finalName = "\(safeBase)_\(timestampString()).pdf"
                        let url = try makePDF(from: images, fileName: finalName)
                        scannedPDFURL = url
                    } catch {
                        uiErrorMessage = "PDF konnte nicht erstellt werden: \(error.localizedDescription)"
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
            .alert("Scanner", isPresented: Binding(get: { uiErrorMessage != nil }, set: { _ in uiErrorMessage = nil })) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(uiErrorMessage ?? "")
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

    func makeUIView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true
        v.displayMode = .singlePageContinuous
        v.displayDirection = .vertical
        v.usePageViewController(true, withViewOptions: nil)
        v.backgroundColor = UIColor.secondarySystemBackground
        return v
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        uiView.document = PDFDocument(url: url)
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

    private var displayName: String {
        let name = appState.currentUser?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "" : name
    }

    private var userAccentColor: Color {
        Color.svsAccentColor(from: appState.currentUser?.colorName)
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
            .count
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
                    HStack(spacing: 12) {
                        StatPill(title: "Aktive Anträge", value: myActiveRequestsCount, systemImage: "doc.text")
                        StatPill(title: "Offene Aufgaben", value: myOpenTasksCount, systemImage: "checklist")
                    }
                    .padding(.horizontal, 18)

                    // MARK: Cards
                    VStack(spacing: 12) {
                        NavigationLink {
                            MyRequestsScreen()
                        } label: {
                            WorkCard(
                                title: "Anträge",
                                subtitle: "Urlaub, Krankheit",
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
                                subtitle: "To-dos",
                                systemImage: "checklist",
                                trailingValue: myOpenTasksCount
                            )
                        }
                        .buttonStyle(.plain)

                        NavigationLink {
                            ProvisionenView()
                        } label: {
                            WorkCard(
                                title: "Provision",
                                subtitle: "Vermittlungsprovision",
                                systemImage: "eurosign.circle",
                                trailingValue: 0
                            )
                        }
                        .buttonStyle(.plain)

                        NavigationLink {
                            DashboardView()
                        } label: {
                            WorkCard(
                                title: "Dashboard",
                                subtitle: "Übersicht",
                                systemImage: "chart.bar.xaxis",
                                trailingValue: 0
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 18)
                }
            }
            .background(Color(.systemGroupedBackground))
            .tint(userAccentColor)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
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

                Text("\(value)")
                    .font(.headline)
                    .foregroundColor(.primary)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 12)
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
