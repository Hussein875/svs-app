//
//  MainViewScanner.swift
//  SVS App
//
//  Extracted from MainView.swift for readability.
//

import Foundation
import SwiftUI
import UIKit
import VisionKit
import UniformTypeIdentifiers
import AVFoundation
import FirebaseAuth
import FirebaseFirestore
import FirebaseStorage

// MARK: - Scanner

private struct ScannerSequencePreview: Equatable {
    let nextNumber: Int
    let year2: String
}

private struct ScannerReservationState: Equatable {
    let reservationId: String
    let number: Int
    let year2: String
    let scanName: String
    let driveFolderName: String
}

struct ScannerScreen: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.scenePhase) private var scenePhase

    @State private var isPresentingScanner = false
    @State private var isPresentingShare = false
    @State private var scannedImages: [UIImage] = []
    @State private var scannedPDFURL: URL? = nil
    @State private var scanName: String = ""
    @State private var scannerSequence: ScannerSequencePreview? = nil
    @State private var scannerSequenceListener: ListenerRegistration? = nil
    @State private var uiErrorMessage: String? = nil
    @State private var isUploadingToDrive = false
    @State private var isLoadingScannerSequence = false
    @State private var isReservingScanNumber = false
    @State private var reservedScan: ScannerReservationState? = nil
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

    private var activeYear2: String {
        reservedScan?.year2 ?? scannerSequence?.year2 ?? currentYear2
    }

    private var trimmedScanName: String {
        scanName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedScanNumber: String? {
        guard let number = reservedScan?.number else { return nil }
        return String(number)
    }

    private func normalizedInitialsComponent(from rawValue: String?) -> String? {
        let trimmed = (rawValue ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let folded = trimmed.folding(
            options: [.diacriticInsensitive, .widthInsensitive, .caseInsensitive],
            locale: Locale(identifier: "de_DE")
        )
        let words = folded
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
        let initials = words.compactMap { word in
            word.first.map { String($0).lowercased() }
        }.joined()

        return initials.isEmpty ? nil : initials
    }

    private func normalizedShortCodeComponent(from rawValue: String?) -> String? {
        let trimmed = (rawValue ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let folded = trimmed.folding(
            options: [.diacriticInsensitive, .widthInsensitive, .caseInsensitive],
            locale: Locale(identifier: "de_DE")
        )
        let replaced = folded.map { char -> Character in
            if char.isLetter || char.isNumber {
                return Character(String(char).lowercased())
            }
            if char == "_" || char == "-" {
                return "_"
            }
            return "_"
        }

        let collapsed = String(replaced)
            .replacingOccurrences(
                of: "_+",
                with: "_",
                options: .regularExpression
            )
            .trimmingCharacters(in: CharacterSet(charactersIn: "_"))

        return collapsed.isEmpty ? nil : collapsed
    }

    private var normalizedScanName: String? {
        normalizedInitialsComponent(from: scanName)
    }

    private var normalizedScannerUserName: String? {
        normalizedShortCodeComponent(from: appState.currentUser?.shortCode)
            ?? normalizedInitialsComponent(from: appState.currentUser?.name)
    }

    private var scannerFileBaseName: String {
        let numberPart = normalizedScanNumber ?? "none"
        let namePart = normalizedScanName ?? "none"
        let userPart = normalizedScannerUserName ?? "none"
        return "scan__nr_\(numberPart)__jahr_\(activeYear2)__name_\(namePart)__user_\(userPart)"
    }

    private var scannerDisplayFileName: String {
        "\(scannerFileBaseName).pdf"
    }

    private var temporaryScansDirectoryURL: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "SVS_Scans",
            isDirectory: true
        )
    }

    private var uploadScanToDriveEndpoint: URL? {
        URL(string: "https://us-central1-svs-app-864ed.cloudfunctions.net/uploadScanToDrive")
    }
    private var scannerSequencePreviewEndpoint: URL? {
        URL(string: "https://us-central1-svs-app-864ed.cloudfunctions.net/getScannerSequencePreviewHttp")
    }
    private var reserveScannerNumberEndpoint: URL? {
        URL(string: "https://us-central1-svs-app-864ed.cloudfunctions.net/reserveScannerNumberHttp")
    }

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

    private var currentScannerNumberText: String {
        if let reservedScan {
            return "\(reservedScan.number)/\(reservedScan.year2)"
        }
        if let scannerSequence {
            return "\(scannerSequence.nextNumber)/\(scannerSequence.year2)"
        }
        return "–/\(currentYear2)"
    }

    private var previewDriveFolderName: String {
        let namePart = trimmedScanName.isEmpty ? "Name fehlt" : trimmedScanName
        return "\(currentScannerNumberText) Unfallgutachten \(namePart)"
    }

    private var canReserveScannerNumber: Bool {
        reservedScan == nil &&
        !trimmedScanName.isEmpty &&
        scannerSequence != nil &&
        !isLoadingScannerSequence &&
        !isReservingScanNumber
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

            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(reservedScan == nil ? "Aktuell verfügbar" : "Reserviert")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)

                    Text(currentScannerNumberText)
                        .font(.title3.weight(.bold))
                        .foregroundColor(.primary)
                }

                Spacer(minLength: 8)

                if isLoadingScannerSequence || isReservingScanNumber {
                    ProgressView()
                        .controlSize(.small)
                } else if reservedScan != nil {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.title3.weight(.semibold))
                        .foregroundColor(userAccentColor)
                }
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

            Text("Name")
                .font(.caption)
                .foregroundColor(.secondary)

            TextField("Name", text: $scanName)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onChange(of: scanName) { _, _ in
                    refreshScanPDFIfNeeded()
                }
                .disabled(reservedScan != nil)
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

            if let reservedScan {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Drive-Ordner")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Text(reservedScan.driveFolderName)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.primary)
                }
                .padding(.top, 4)
            } else {
                Text(previewDriveFolderName)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.top, 2)

                Button {
                    _Concurrency.Task { await reserveCurrentScannerNumber() }
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "number.circle.fill")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Nummer reservieren")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
                .disabled(!canReserveScannerNumber)
                .opacity(canReserveScannerNumber ? 1.0 : 0.6)
            }
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
                Text(scannedImages.isEmpty ? "Scan starten" : "Scan ergänzen")
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
        .disabled(reservedScan == nil)
        .opacity(reservedScan == nil ? 0.6 : 1.0)
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

        if !scannedImages.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Seiten (\(scannedImages.count))")
                    .font(.headline)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Array(scannedImages.enumerated()), id: \.offset) { item in
                            pageThumbnail(image: item.element, index: item.offset)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
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
    private func pageThumbnail(image: UIImage, index: Int) -> some View {
        ZStack(alignment: .topTrailing) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 88, height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(Color.secondary.opacity(0.18), lineWidth: 1)
                )

            Button {
                deleteScannedPage(at: index)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white, Color.red)
            }
            .padding(6)
            .buttonStyle(.plain)
            .accessibilityLabel("Seite \(index + 1) löschen")
        }
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
            .onAppear {
                startScannerSequenceListenerIfNeeded()
                DispatchQueue.main.async {
                    _Concurrency.Task { await refreshScannerSequencePreview() }
                }
            }
            .onChange(of: scenePhase) { _, newPhase in
                guard newPhase == .active else { return }
                DispatchQueue.main.async {
                    _Concurrency.Task { await refreshScannerSequencePreview() }
                }
            }
            .onDisappear {
                stopScannerSequenceListener()
            }
            .navigationTitle("Scanner")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $isPresentingScanner) {
                DocumentScanner { images in
                    scannedImages.append(contentsOf: images)
                    rebuildPDFFromScannedImages()
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
        guard reservedScan != nil else {
            uiErrorMessage = "Bitte zuerst die aktuelle Gutachten-Nummer reservieren."
            return
        }

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

        let dir = temporaryScansDirectoryURL
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
        guard let reservedScan else {
            uiErrorMessage = "Bitte zuerst die aktuelle Gutachten-Nummer reservieren."
            return
        }

        guard let user = Auth.auth().currentUser else {
            uiErrorMessage = "Nicht angemeldet."
            return
        }

        isUploadingToDrive = true
        defer { isUploadingToDrive = false }

        do {
            let safeBase = sanitizedFileName(scannerFileBaseName)
            let finalName = "\(safeBase)__ts_\(timestampString()).pdf"

            let storageObjectName =
                "\(reservedScan.reservationId)__\(finalName)"
            let storagePath = "scans/\(user.uid)/\(storageObjectName)"
            try await uploadFileToFirebaseStorage(
                localURL: localURL,
                storagePath: storagePath
            )

            let idToken = try await user.getIDToken()
            _ = try await callUploadScanToDrive(
                idToken: idToken,
                storagePath: storagePath,
                reservationId: reservedScan.reservationId,
                fileName: finalName
            )

            resetScannerSession(removeAllTempFiles: true)
            driveUploadSuccessMessage =
              "Datei wurde in Google Drive abgelegt."
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
        reservationId: String?,
        fileName: String
    ) async throws -> String {
        guard let uploadScanToDriveEndpoint else {
            throw NSError(
                domain: "Drive",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Upload-URL ist ungültig."]
            )
        }

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
            "reservationId": reservationId as Any,
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

    private func deleteScannedPage(at index: Int) {
        guard scannedImages.indices.contains(index) else { return }
        scannedImages.remove(at: index)
        rebuildPDFFromScannedImages()
    }

    private func resetScannerSession(removeAllTempFiles: Bool) {
        if let oldURL = scannedPDFURL {
            try? FileManager.default.removeItem(at: oldURL)
        }
        if removeAllTempFiles {
            try? FileManager.default.removeItem(at: temporaryScansDirectoryURL)
        }

        scannedImages = []
        scannedPDFURL = nil
        scanName = ""
        reservedScan = nil
        isPresentingShare = false

        _Concurrency.Task { @MainActor in
            await refreshScannerSequencePreview()
        }
    }

    private func refreshScanPDFIfNeeded() {
        guard !scannedImages.isEmpty else { return }
        rebuildPDFFromScannedImages()
    }

    private func rebuildPDFFromScannedImages() {
        guard !scannedImages.isEmpty else {
            if let oldURL = scannedPDFURL {
                try? FileManager.default.removeItem(at: oldURL)
            }
            scannedPDFURL = nil
            return
        }

        do {
            let safeBase = sanitizedFileName(scannerFileBaseName)
            let finalName = "\(safeBase)__ts_\(timestampString()).pdf"
            let newURL = try makePDF(from: scannedImages, fileName: finalName)

            if let oldURL = scannedPDFURL, oldURL != newURL {
                try? FileManager.default.removeItem(at: oldURL)
            }
            scannedPDFURL = newURL
        } catch {
            uiErrorMessage = "PDF konnte nicht aktualisiert werden: \(error.localizedDescription)"
        }
    }

    private func startScannerSequenceListenerIfNeeded() {
        guard scannerSequenceListener == nil else { return }

        scannerSequenceListener = Firestore.firestore()
            .collection("scannerMeta")
            .document("current")
            .addSnapshotListener(includeMetadataChanges: false) { snapshot, error in
                if let error {
                    if self.scannerSequence == nil {
                        self.uiErrorMessage = "Aktuelle Scanner-Nummer konnte nicht geladen werden: \(error.localizedDescription)"
                    }
                    return
                }

                guard let data = snapshot?.data() else { return }
                guard let nextNumber = data["nextNumber"] as? Int else { return }
                let year2 = (data["year2"] as? String)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? self.currentYear2

                self.scannerSequence = ScannerSequencePreview(
                    nextNumber: nextNumber,
                    year2: year2
                )
            }
    }

    private func stopScannerSequenceListener() {
        scannerSequenceListener?.remove()
        scannerSequenceListener = nil
    }

    @MainActor
    private func refreshScannerSequencePreview() async {
        guard !isLoadingScannerSequence else { return }
        isLoadingScannerSequence = true
        defer { isLoadingScannerSequence = false }

        do {
            guard let user = Auth.auth().currentUser else {
                uiErrorMessage = "Nicht angemeldet."
                return
            }

            let idToken = try await user.getIDToken()
            guard let scannerSequencePreviewEndpoint else {
                throw NSError(
                    domain: "Scanner",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Scanner-Preview-URL ist ungültig."]
                )
            }
            let payload = try await callScannerHttpEndpoint(
                scannerSequencePreviewEndpoint,
                idToken: idToken
            )

            guard let nextNumber = payload["nextNumber"] as? Int else {
                throw NSError(
                    domain: "Scanner",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Ungültige Server-Antwort."]
                )
            }

            let year2 = (payload["year2"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? currentYear2

            scannerSequence = ScannerSequencePreview(
                nextNumber: nextNumber,
                year2: year2
            )
            uiErrorMessage = nil
        } catch {
            if scannerSequence == nil {
                uiErrorMessage = "Aktuelle Scanner-Nummer konnte nicht geladen werden: \(error.localizedDescription)"
            }
        }
    }

    @MainActor
    private func reserveCurrentScannerNumber() async {
        guard !isReservingScanNumber else { return }
        guard !trimmedScanName.isEmpty else {
            uiErrorMessage = "Bitte zuerst den Namen für den Unfallgutachten-Ordner eingeben."
            return
        }

        isReservingScanNumber = true
        defer { isReservingScanNumber = false }

        do {
            guard let user = Auth.auth().currentUser else {
                uiErrorMessage = "Nicht angemeldet."
                return
            }

            let idToken = try await user.getIDToken()
            guard let reserveScannerNumberEndpoint else {
                throw NSError(
                    domain: "Scanner",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Scanner-Reservierungs-URL ist ungültig."]
                )
            }
            let payload = try await callScannerHttpEndpoint(
                reserveScannerNumberEndpoint,
                idToken: idToken,
                body: ["scanName": trimmedScanName]
            )

            guard let reservationId = payload["reservationId"] as? String,
                  let number = payload["number"] as? Int else {
                throw NSError(
                    domain: "Scanner",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Ungültige Server-Antwort."]
                )
            }

            let year2 = (payload["year2"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? currentYear2
            let driveFolderName = (payload["driveFolderName"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let driveFolderReady = (payload["driveFolderReady"] as? Bool) ?? false
            let warning = (payload["warning"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)

            reservedScan = ScannerReservationState(
                reservationId: reservationId,
                number: number,
                year2: year2,
                scanName: trimmedScanName,
                driveFolderName: driveFolderName
            )
            refreshScanPDFIfNeeded()

            if !driveFolderReady, let warning, !warning.isEmpty {
                driveUploadSuccessMessage = warning
            }
            uiErrorMessage = nil
        } catch {
            await refreshScannerSequencePreview()
            uiErrorMessage = "Scanner-Nummer konnte nicht reserviert werden: \(error.localizedDescription)"
        }
    }

    private func callScannerHttpEndpoint(
        _ endpoint: URL,
        idToken: String,
        body: [String: Any] = [:]
    ) async throws -> [String: Any] {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let http = response as? HTTPURLResponse
        let status = http?.statusCode ?? -1
        let rawText = String(data: data, encoding: .utf8) ?? ""

        let jsonObject = try JSONSerialization.jsonObject(with: data)
        guard let payload = jsonObject as? [String: Any] else {
            let prefix = rawText.prefix(500)
            throw NSError(
                domain: "Scanner",
                code: status,
                userInfo: [NSLocalizedDescriptionKey: "Unerwartete Server-Antwort (HTTP \(status)): \(prefix)"]
            )
        }

        if let ok = payload["ok"] as? Bool, !ok {
            let msg = String(payload["error"] as? String ?? "Scanner-Anfrage fehlgeschlagen.")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw NSError(
                domain: "Scanner",
                code: status,
                userInfo: [NSLocalizedDescriptionKey: msg.isEmpty ? "Scanner-Anfrage fehlgeschlagen." : msg]
            )
        }

        return payload
    }
}
