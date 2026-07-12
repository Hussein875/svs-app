//
//  ScannerReservationService.swift
//  SVS App
//

import FirebaseAuth
import Foundation

struct ScannerSequenceInfo: Equatable {
    let nextNumber: Int
    let year2: String

    var displayNumber: String { "\(nextNumber)/\(year2)" }
}

struct ScannerReservationResult: Equatable, Codable {
    let reservationId: String
    let number: Int
    let year2: String
    let scanName: String

    var displayNumber: String { "\(number)/\(year2)" }
}

enum ScannerReservationService {
    private static var previewEndpoint: URL? {
        URL(string: "https://us-central1-svs-app-864ed.cloudfunctions.net/getScannerSequencePreviewHttp")
    }

    private static var reserveEndpoint: URL? {
        URL(string: "https://us-central1-svs-app-864ed.cloudfunctions.net/reserveScannerNumberHttp")
    }

    private static var cancelEndpoint: URL? {
        URL(string: "https://us-central1-svs-app-864ed.cloudfunctions.net/cancelScannerNumberHttp")
    }

    static func fetchCurrentSequence() async throws -> ScannerSequenceInfo {
        let payload = try await callEndpoint(previewEndpoint, body: [:])
        guard let nextNumber = payload["nextNumber"] as? Int else {
            throw ScannerReservationError.invalidResponse
        }
        let year2 = (payload["year2"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? currentYear2()
        return ScannerSequenceInfo(nextNumber: nextNumber, year2: year2)
    }

    static func reserve(scanName: String) async throws -> ScannerReservationResult {
        let trimmed = scanName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw ScannerReservationError.emptyScanName
        }

        let payload = try await callEndpoint(
            reserveEndpoint,
            body: ["scanName": trimmed]
        )

        guard let reservationId = payload["reservationId"] as? String,
              let number = payload["number"] as? Int else {
            throw ScannerReservationError.invalidResponse
        }

        let year2 = (payload["year2"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            ?? currentYear2()

        return ScannerReservationResult(
            reservationId: reservationId,
            number: number,
            year2: year2,
            scanName: trimmed
        )
    }

    static func cancel(reservationId: String) async throws {
        _ = try await callEndpoint(
            cancelEndpoint,
            body: ["reservationId": reservationId]
        )
    }

    private static func callEndpoint(
        _ endpoint: URL?,
        body: [String: Any]
    ) async throws -> [String: Any] {
        guard let user = Auth.auth().currentUser else {
            throw ScannerReservationError.notSignedIn
        }
        guard let endpoint else {
            throw ScannerReservationError.invalidEndpoint
        }

        let idToken = try await user.getIDToken()
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        let rawText = String(data: data, encoding: .utf8) ?? ""

        guard let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ScannerReservationError.serverError(
                "Unerwartete Server-Antwort (HTTP \(status)): \(rawText.prefix(200))"
            )
        }

        if let ok = payload["ok"] as? Bool, !ok {
            let message = (payload["error"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw ScannerReservationError.serverError(
                message?.isEmpty == false ? message! : "Scanner-Anfrage fehlgeschlagen."
            )
        }

        return payload
    }

    private static func currentYear2() -> String {
        let year = Calendar.current.component(.year, from: Date())
        return String(format: "%02d", year % 100)
    }
}

enum ScannerReservationError: LocalizedError {
    case notSignedIn
    case invalidEndpoint
    case invalidResponse
    case emptyScanName
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Nicht angemeldet."
        case .invalidEndpoint:
            return "Scanner-URL ist ungültig."
        case .invalidResponse:
            return "Ungültige Server-Antwort."
        case .emptyScanName:
            return "Bitte einen Ordnernamen für das Gutachten eingeben."
        case .serverError(let message):
            return message
        }
    }
}
