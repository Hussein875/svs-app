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
import FirebaseStorage

// MARK: - Scanner

struct ScannerScreen: View {
    @EnvironmentObject var appState: AppState

    @State private var isPresentingScanner = false
    @State private var isPresentingShare = false
    @State private var scannedImages: [UIImage] = []
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

            Text("Dateiname: \(formattedScanNameNoLeadingZeros)")
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
            .navigationTitle("Scanner")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $isPresentingScanner) {
                DocumentScanner { images in
                    scannedImages = images
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
            let safeBase = sanitizedFileName(formattedScanNameNoLeadingZeros)
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

    private func deleteScannedPage(at index: Int) {
        guard scannedImages.indices.contains(index) else { return }
        scannedImages.remove(at: index)
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
            let safeBase = sanitizedFileName(formattedScanNameNoLeadingZeros)
            let finalName = "\(safeBase)_\(timestampString()).pdf"
            let newURL = try makePDF(from: scannedImages, fileName: finalName)

            if let oldURL = scannedPDFURL, oldURL != newURL {
                try? FileManager.default.removeItem(at: oldURL)
            }
            scannedPDFURL = newURL
        } catch {
            uiErrorMessage = "PDF konnte nicht aktualisiert werden: \(error.localizedDescription)"
        }
    }
}
