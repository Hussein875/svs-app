//
//  UltraExpertPriorDamageService.swift
//  SVS App
//
//  Vorschaden-Check: FIN in UltraExpert suchen, Gutachtennummern zurückgeben.
//

import FirebaseAuth
import Foundation

enum UltraExpertPriorDamageError: LocalizedError {
    case notSignedIn
    case invalidVin
    case notConfigured
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Nicht angemeldet."
        case .invalidVin:
            return "Keine gültige FIN vorhanden."
        case .notConfigured:
            return "UltraExpert-Prüfung ist auf dem Server noch nicht eingerichtet."
        case .serverError(let message):
            return message
        }
    }
}

struct UltraExpertPriorDamageMatch: Decodable, Equatable {
    let gutachtenNumber: String
    let dossierId: String?
    let dossierUrl: String?
}

struct UltraExpertPriorDamageResult: Decodable, Equatable {
    let ok: Bool
    let vin: String
    let matchCount: Int
    let gutachtenNumbers: [String]
    let matches: [UltraExpertPriorDamageMatch]
    let error: String?
    let code: String?

    var hasPriorReports: Bool {
        matchCount > 0 || !gutachtenNumbers.isEmpty
    }
}

enum UltraExpertPriorDamageService {
    private static let checkEndpoint = URL(
        string: "https://us-central1-svs-app-864ed.cloudfunctions.net/checkUltraExpertPriorDamageHttp"
    )!

    static func check(vin rawVin: String) async throws -> UltraExpertPriorDamageResult {
        guard Auth.auth().currentUser != nil else {
            throw UltraExpertPriorDamageError.notSignedIn
        }

        let vin = VehicleIdentificationStore.normalizeVin(rawVin)
        guard vin.count >= 11 else {
            throw UltraExpertPriorDamageError.invalidVin
        }

        let idToken = try await Auth.auth().currentUser!.getIDToken()
        return try await callCheckEndpoint(idToken: idToken, vin: vin)
    }

    private static func callCheckEndpoint(
        idToken: String,
        vin: String
    ) async throws -> UltraExpertPriorDamageResult {
        var request = URLRequest(url: checkEndpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = ["vin": vin]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        let rawText = String(data: data, encoding: .utf8) ?? ""

        let decoded: UltraExpertPriorDamageResult
        do {
            decoded = try JSONDecoder().decode(UltraExpertPriorDamageResult.self, from: data)
        } catch {
            throw UltraExpertPriorDamageError.serverError(
                "Unerwartete Server-Antwort (HTTP \(status)): \(rawText.prefix(500))"
            )
        }

        if status == 503 || decoded.code == "not_configured" {
            throw UltraExpertPriorDamageError.notConfigured
        }

        guard decoded.ok else {
            let message = decoded.error ?? "HTTP \(status)"
            throw UltraExpertPriorDamageError.serverError(message)
        }

        return decoded
    }
}
