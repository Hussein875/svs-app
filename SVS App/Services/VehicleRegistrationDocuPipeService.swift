//
//  VehicleRegistrationDocuPipeService.swift
//  SVS App
//
//  Serverseitige Fahrzeugschein-Erkennung via DocuPipe (Firebase Function).
//

import FirebaseAuth
import Foundation
import UIKit

enum VehicleRegistrationDocuPipeError: LocalizedError {
    case notSignedIn
    case unreadableImage
    case notConfigured
    case noData
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Nicht angemeldet."
        case .unreadableImage:
            return "Das Foto konnte nicht gelesen werden."
        case .notConfigured:
            return "DocuPipe ist auf dem Server noch nicht eingerichtet."
        case .noData:
            return "Auf dem Fahrzeugschein wurden keine verwertbaren Daten erkannt."
        case .serverError(let message):
            return message
        }
    }

    /// Fehler, bei denen auf lokale Vision-OCR zurückgefallen werden kann.
    var allowsVisionFallback: Bool {
        switch self {
        case .notConfigured, .noData, .serverError:
            return true
        case .notSignedIn, .unreadableImage:
            return false
        }
    }
}

enum VehicleRegistrationDocuPipeService {
    private static let recognizeEndpoint = URL(
        string: "https://us-central1-svs-app-864ed.cloudfunctions.net/recognizeVehicleRegistrationHttp"
    )!

    static func recognize(from image: UIImage) async throws -> VehicleRegistrationOCRResult {
        guard Auth.auth().currentUser != nil else {
            throw VehicleRegistrationDocuPipeError.notSignedIn
        }

        guard let jpegData = image.jpegData(compressionQuality: 0.85) else {
            throw VehicleRegistrationDocuPipeError.unreadableImage
        }

        let idToken = try await Auth.auth().currentUser!.getIDToken()
        return try await callRecognizeEndpoint(
            idToken: idToken,
            imageBase64: jpegData.base64EncodedString()
        )
    }

    private static func callRecognizeEndpoint(
        idToken: String,
        imageBase64: String
    ) async throws -> VehicleRegistrationOCRResult {
        var request = URLRequest(url: recognizeEndpoint)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = ["imageBase64": imageBase64]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        let rawText = String(data: data, encoding: .utf8) ?? ""

        struct Payload: Decodable {
            let ok: Bool
            let code: String?
            let error: String?
            let clientLastName: String?
            let clientFirstName: String?
            let clientName: String?
            let streetAndNumber: String?
            let postalCode: String?
            let city: String?
            let licensePlate: String?
            let vin: String?
            let firstRegistrationDate: String?
            let rawText: String?
        }

        let decoded: Payload
        do {
            decoded = try JSONDecoder().decode(Payload.self, from: data)
        } catch {
            throw VehicleRegistrationDocuPipeError.serverError(
                "Unerwartete Server-Antwort (HTTP \(status)): \(rawText.prefix(500))"
            )
        }

        if status == 503 || decoded.code == "not_configured" {
            throw VehicleRegistrationDocuPipeError.notConfigured
        }

        guard decoded.ok else {
            let message = decoded.error ?? "HTTP \(status)"
            throw VehicleRegistrationDocuPipeError.serverError(message)
        }

        let result = VehicleRegistrationOCRResult(
            clientLastName: decoded.clientLastName,
            clientFirstName: decoded.clientFirstName,
            clientName: decoded.clientName,
            streetAndNumber: decoded.streetAndNumber,
            postalCode: decoded.postalCode,
            city: decoded.city,
            licensePlate: decoded.licensePlate,
            vin: decoded.vin,
            firstRegistrationDate: decoded.firstRegistrationDate
                .flatMap(VehicleIdentificationStore.parseFirstRegistrationDate),
            rawText: decoded.rawText ?? ""
        )

        guard hasUsefulData(in: result) else {
            throw VehicleRegistrationDocuPipeError.noData
        }

        return result
    }

    private static func hasUsefulData(in result: VehicleRegistrationOCRResult) -> Bool {
        let fields = [
            result.clientLastName,
            result.clientFirstName,
            result.clientName,
            result.streetAndNumber,
            result.postalCode,
            result.city,
            result.licensePlate,
        ]

        return fields.contains { value in
            guard let value else { return false }
            return !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}
