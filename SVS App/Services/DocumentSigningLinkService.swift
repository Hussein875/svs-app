//
//  DocumentSigningLinkService.swift
//  SVS App
//

import FirebaseAuth
import Foundation

struct DocumentSigningLinkResult: Identifiable, Hashable {
    let id: String
    let url: URL
    let expiresAt: Date?
    let documentTitle: String
}

enum DocumentSigningLinkError: LocalizedError {
    case notSignedIn
    case invalidEndpoint
    case unsupportedDocument
    case missingSourcePDF
    case serverError(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Nicht angemeldet. Bitte erneut einloggen."
        case .invalidEndpoint:
            return "Dokument-Link-URL ist ungültig."
        case .unsupportedDocument:
            return "Für dieses Dokument ist Remote-Unterschrift noch nicht verfügbar."
        case .missingSourcePDF:
            return "PDF konnte nicht geladen werden."
        case .serverError(let message):
            return message
        case .invalidResponse:
            return "Serverantwort ungültig."
        }
    }
}

enum DocumentSigningLinkService {
    private static let defaultTTLDays = 14

    /// Öffentliches Unterschriftsformular (Firebase Hosting).
    static let publicFormBaseURL = URL(
        string: "https://svs-app-864ed.web.app/document-sign"
    )!

    private static var createEndpoint: URL? {
        URL(string: "https://us-central1-svs-app-864ed.cloudfunctions.net/createDocumentSigningLink")
    }

    private static var downloadEndpoint: URL? {
        URL(string: "https://us-central1-svs-app-864ed.cloudfunctions.net/getDocumentSigningDownload")
    }

    private static var deleteEndpoint: URL? {
        URL(string: "https://us-central1-svs-app-864ed.cloudfunctions.net/deleteDocumentSigningLink")
    }

    static func publicSigningURL(forToken token: String) -> URL? {
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        var components = URLComponents(
            url: publicFormBaseURL,
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [
            URLQueryItem(name: "token", value: trimmed),
        ]
        return components?.url
    }

    static func createRemoteSigningLink(
        document: CompanyDocument,
        sourcePDFURL: URL,
        accidentDate: Date,
        customerName: String = "",
        notes: String = ""
    ) async throws -> DocumentSigningLinkResult {
        guard document.supportsRemoteSigning else {
            throw DocumentSigningLinkError.unsupportedDocument
        }

        guard let user = Auth.auth().currentUser else {
            throw DocumentSigningLinkError.notSignedIn
        }

        guard let createEndpoint else {
            throw DocumentSigningLinkError.invalidEndpoint
        }

        let textOverlays = prefilledTextOverlays(for: document, accidentDate: accidentDate)
        let prefilledURL = try PDFSignatureService.textStampedPDFURL(
            sourceURL: sourcePDFURL,
            textOverlays: textOverlays,
            outputBaseName: document.resourceName
        )

        let prefilledData = try Data(contentsOf: prefilledURL)
        let prefilledPdfBase64 = prefilledData.base64EncodedString()

        let idToken = try await user.getIDToken()

        var request = URLRequest(url: createEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime]

        var payload: [String: Any] = [
            "documentId": document.id,
            "accidentDateIso": isoFormatter.string(from: accidentDate),
            "ttlDays": defaultTTLDays,
            "prefilledPdfBase64": prefilledPdfBase64,
        ]

        let trimmedCustomer = customerName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedCustomer.isEmpty {
            payload["customerName"] = trimmedCustomer
        }

        let trimmedNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedNotes.isEmpty {
            payload["notes"] = trimmedNotes
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: payload)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw DocumentSigningLinkError.invalidResponse
        }

        guard (200...299).contains(http.statusCode) else {
            let serverText = String(data: data, encoding: .utf8) ?? ""
            throw DocumentSigningLinkError.serverError(
                "Link konnte nicht erstellt werden (\(http.statusCode)). \(serverText)".trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        struct CreateLinkResponse: Decodable {
            let ok: Bool?
            let token: String?
            let url: String?
            let expiresAt: String?
            let documentTitle: String?
        }

        let decoded = try JSONDecoder().decode(CreateLinkResponse.self, from: data)
        guard decoded.ok == true, let token = decoded.token else {
            throw DocumentSigningLinkError.invalidResponse
        }

        let shareURL = publicSigningURL(forToken: token)
            ?? decoded.url.flatMap(URL.init(string:))
            ?? publicFormBaseURL

        let expiresAt = decoded.expiresAt.flatMap { ISO8601DateFormatter().date(from: $0) }

        return DocumentSigningLinkResult(
            id: token,
            url: shareURL,
            expiresAt: expiresAt,
            documentTitle: decoded.documentTitle ?? document.title
        )
    }

    private static var signedPDFCacheDirectory: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = base.appendingPathComponent("RemoteSignedPDFs", isDirectory: true)
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory
    }

    static func cachedSignedPDFURL(linkToken: String) -> URL? {
        let trimmed = linkToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let cached = signedPDFCacheDirectory.appendingPathComponent("\(trimmed).pdf")
        return FileManager.default.fileExists(atPath: cached.path) ? cached : nil
    }

    static func clearCachedSignedPDF(linkToken: String) {
        let trimmed = linkToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let cached = signedPDFCacheDirectory.appendingPathComponent("\(trimmed).pdf")
        try? FileManager.default.removeItem(at: cached)
    }

    static func replaceCachedSignedPDF(linkToken: String, sourceURL: URL) throws {
        let trimmed = linkToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let cacheURL = signedPDFCacheDirectory.appendingPathComponent("\(trimmed).pdf")
        let data = try Data(contentsOf: sourceURL)
        try data.write(to: cacheURL, options: .atomic)
    }

    static func deleteSigningLink(token: String) async throws {
        guard let user = Auth.auth().currentUser else {
            throw DocumentSigningLinkError.notSignedIn
        }

        guard let deleteEndpoint else {
            throw DocumentSigningLinkError.invalidEndpoint
        }

        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw DocumentSigningLinkError.invalidResponse
        }

        let idToken = try await user.getIDToken()
        var request = URLRequest(url: deleteEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["token": trimmed])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw DocumentSigningLinkError.invalidResponse
        }

        guard (200...299).contains(http.statusCode) else {
            let serverText = String(data: data, encoding: .utf8) ?? ""
            throw DocumentSigningLinkError.serverError(
                "Link konnte nicht gelöscht werden (\(http.statusCode)). \(serverText)"
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        clearCachedSignedPDF(linkToken: trimmed)
    }

    /// Lädt das signierte PDF vom Server und speichert es lokal im Cache.
    static func downloadSignedPDF(
        linkToken: String,
        fileName: String
    ) async throws -> URL {
        if let cached = cachedSignedPDFURL(linkToken: linkToken) {
            return cached
        }

        let payload = try await fetchSignedPDFPayload(linkToken: linkToken)
        let data: Data

        if let base64 = payload.base64,
           let decoded = Data(base64Encoded: base64),
           !decoded.isEmpty {
            data = decoded
        } else if let remoteURL = payload.url {
            let (downloaded, response) = try await URLSession.shared.data(from: remoteURL)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                throw DocumentSigningLinkError.serverError(
                    "PDF-Download fehlgeschlagen (\(http.statusCode))."
                )
            }
            data = downloaded
        } else {
            throw DocumentSigningLinkError.serverError(
                "Signiertes PDF ist noch nicht verfügbar. Bitte kurz warten und erneut versuchen."
            )
        }

        guard !data.isEmpty else {
            throw DocumentSigningLinkError.serverError("PDF-Datei ist leer.")
        }

        let trimmed = linkToken.trimmingCharacters(in: .whitespacesAndNewlines)
        let cacheURL = signedPDFCacheDirectory.appendingPathComponent("\(trimmed).pdf")
        try data.write(to: cacheURL, options: .atomic)

        let friendlyURL = signedPDFCacheDirectory.appendingPathComponent(fileName)
        if friendlyURL != cacheURL {
            try? FileManager.default.removeItem(at: friendlyURL)
            try? FileManager.default.copyItem(at: cacheURL, to: friendlyURL)
        }

        return cacheURL
    }

    private struct SignedPDFPayload {
        let url: URL?
        let base64: String?
    }

    private static func fetchSignedPDFPayload(linkToken: String) async throws -> SignedPDFPayload {
        guard let user = Auth.auth().currentUser else {
            throw DocumentSigningLinkError.notSignedIn
        }

        guard let downloadEndpoint else {
            throw DocumentSigningLinkError.invalidEndpoint
        }

        let trimmed = linkToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw DocumentSigningLinkError.invalidResponse
        }

        var components = URLComponents(url: downloadEndpoint, resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "token", value: trimmed)]
        guard let requestURL = components?.url else {
            throw DocumentSigningLinkError.invalidEndpoint
        }

        let idToken = try await user.getIDToken()

        var request = URLRequest(url: requestURL)
        request.httpMethod = "GET"
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let http = response as? HTTPURLResponse else {
            throw DocumentSigningLinkError.invalidResponse
        }

        guard (200...299).contains(http.statusCode) else {
            let serverText = String(data: data, encoding: .utf8) ?? ""
            throw DocumentSigningLinkError.serverError(
                "PDF konnte nicht geladen werden (\(http.statusCode)). \(serverText)"
                    .trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        struct DownloadResponse: Decodable {
            let ok: Bool?
            let status: String?
            let signedPdfUrl: String?
            let signedPdfBase64: String?
            let error: String?
        }

        let decoded = try JSONDecoder().decode(DownloadResponse.self, from: data)
        guard decoded.ok == true else {
            let serverError = decoded.error?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !serverError.isEmpty {
                throw DocumentSigningLinkError.serverError(serverError)
            }
            throw DocumentSigningLinkError.serverError("Signiertes PDF ist noch nicht verfügbar.")
        }

        if let base64 = decoded.signedPdfBase64?.trimmingCharacters(in: .whitespacesAndNewlines),
           !base64.isEmpty {
            return SignedPDFPayload(url: nil, base64: base64)
        }

        if let urlString = decoded.signedPdfUrl?.trimmingCharacters(in: .whitespacesAndNewlines),
           let url = URL(string: urlString) {
            return SignedPDFPayload(url: url, base64: nil)
        }

        if decoded.status == "signed" {
            throw DocumentSigningLinkError.serverError(
                "PDF wurde unterschrieben, konnte aber nicht geladen werden. Bitte erneut versuchen."
            )
        }

        throw DocumentSigningLinkError.serverError("Signiertes PDF ist noch nicht verfügbar.")
    }

    private static func prefilledTextOverlays(
        for document: CompanyDocument,
        accidentDate: Date
    ) -> [PDFTextOverlay] {
        document.textFields.compactMap { field in
            switch field.kind {
            case .accidentDate:
                let text = field.renderedText(date: accidentDate, customText: "", secondaryText: "")
                guard !text.isEmpty else { return nil }
                return PDFTextOverlay(text: text, placement: field.defaultPlacement)
            case .signingDate, .freeText, .partyPair:
                return nil
            }
        }
    }
}
