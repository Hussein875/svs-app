//
//  DocumentSigningStatusService.swift
//  SVS App
//

import Combine
import FirebaseAuth
import Foundation

struct DocumentSigningLinkStatus: Identifiable, Hashable {
    let id: String
    let documentId: String
    let documentTitle: String
    let customerName: String?
    let status: String
    let signedPdfAvailable: Bool
    let accidentDateIso: String?
    let signingDateIso: String?
    let createdAt: Date?
    let signedAt: Date?
    let expiresAt: Date?

    var isSigned: Bool {
        status == "signed" || signedAt != nil
    }

    var canOpenSignedPDF: Bool {
        isSigned && signedPdfAvailable
    }

    var isExpired: Bool {
        guard !isSigned, let expiresAt else { return false }
        return expiresAt < Date()
    }

    var displayName: String {
        let name = customerName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "Ohne Kundenname" : name
    }

    var localPDFFileName: String {
        let safeName = displayName
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
        return "wessels-\(safeName)-\(id.prefix(8)).pdf"
    }

    var statusLabel: String {
        if isSigned { return "Fertig" }
        if isExpired { return "Abgelaufen" }
        return "Offen"
    }

    var overviewDocumentLabel: String {
        let title = documentTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        return title.isEmpty ? "Dokument" : title
    }

}

@MainActor
final class DocumentSigningStatusViewModel: ObservableObject {
    @Published private(set) var links: [DocumentSigningLinkStatus] = []
    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String?

    private var pollTask: _Concurrency.Task<Void, Never>?
    private var documentIdFilter: String?
    private static var listEndpoint: URL? {
        URL(string: "https://us-central1-svs-app-864ed.cloudfunctions.net/listDocumentSigningLinks")
    }

    func start(documentId: String) {
        documentIdFilter = documentId
        startPolling()
    }

    func startAll() {
        documentIdFilter = nil
        startPolling()
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = _Concurrency.Task {
            while !_Concurrency.Task.isCancelled {
                await fetchLinks()
                try? await _Concurrency.Task.sleep(nanoseconds: 15_000_000_000)
            }
        }
    }

    func refresh(documentId: String) async {
        documentIdFilter = documentId
        await fetchLinks()
    }

    func refreshAll() async {
        documentIdFilter = nil
        await fetchLinks()
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    func removeLinkLocally(token: String) {
        links.removeAll { $0.id == token }
    }

    func deleteLink(token: String) async throws {
        try await DocumentSigningLinkService.deleteSigningLink(token: token)
        removeLinkLocally(token: token)
    }

    private func fetchLinks() async {
        guard !_Concurrency.Task.isCancelled else { return }

        guard let user = Auth.auth().currentUser else {
            links = []
            lastError = "Nicht angemeldet."
            return
        }

        guard let listEndpoint = Self.listEndpoint else {
            lastError = "Listen-URL ist ungültig."
            return
        }

        isLoading = links.isEmpty
        lastError = nil

        do {
            var components = URLComponents(url: listEndpoint, resolvingAgainstBaseURL: false)
            if let documentIdFilter, !documentIdFilter.isEmpty {
                components?.queryItems = [
                    URLQueryItem(name: "documentId", value: documentIdFilter),
                ]
            }
            guard let requestURL = components?.url else {
                lastError = "Listen-URL ist ungültig."
                return
            }

            let idToken = try await user.getIDToken()
            var request = URLRequest(url: requestURL)
            request.httpMethod = "GET"
            request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await URLSession.shared.data(for: request)

            guard let http = response as? HTTPURLResponse else {
                lastError = "Serverantwort ungültig."
                return
            }

            guard (200...299).contains(http.statusCode) else {
                let serverText = String(data: data, encoding: .utf8) ?? ""
                lastError = "Links konnten nicht geladen werden (\(http.statusCode)). \(serverText)"
                return
            }

            struct ListResponse: Decodable {
                struct Row: Decodable {
                    let token: String?
                    let documentId: String?
                    let documentTitle: String?
                    let customerName: String?
                    let status: String?
                    let signedPdfAvailable: Bool?
                    let accidentDateIso: String?
                    let signingDateIso: String?
                    let createdAt: String?
                    let signedAt: String?
                    let expiresAt: String?
                }

                let ok: Bool?
                let links: [Row]?
            }

            let decoded = try JSONDecoder().decode(ListResponse.self, from: data)
            guard decoded.ok == true else {
                lastError = "Links konnten nicht geladen werden."
                return
            }

            let isoParser = ISO8601DateFormatter()
            isoParser.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

            func parseDate(_ raw: String?) -> Date? {
                guard let raw, !raw.isEmpty else { return nil }
                if let date = isoParser.date(from: raw) { return date }
                isoParser.formatOptions = [.withInternetDateTime]
                return isoParser.date(from: raw)
            }

            links = (decoded.links ?? []).compactMap { row in
                guard let token = row.token, !token.isEmpty else { return nil }
                let status = row.status ?? "unused"
                let signedAt = parseDate(row.signedAt)
                let isSignedRow = status == "signed" || signedAt != nil
                return DocumentSigningLinkStatus(
                    id: token,
                    documentId: row.documentId ?? "",
                    documentTitle: row.documentTitle ?? "",
                    customerName: row.customerName,
                    status: status,
                    signedPdfAvailable: row.signedPdfAvailable ?? isSignedRow,
                    accidentDateIso: row.accidentDateIso,
                    signingDateIso: row.signingDateIso,
                    createdAt: parseDate(row.createdAt),
                    signedAt: signedAt,
                    expiresAt: parseDate(row.expiresAt)
                )
            }
            lastError = nil
        } catch {
            if !_Concurrency.Task.isCancelled {
                lastError = error.localizedDescription
            }
        }

        isLoading = false
    }
}
