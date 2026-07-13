//
//  ScannerDriveUploadService.swift
//  SVS App
//

import FirebaseAuth
import FirebaseStorage
import Foundation

struct ScannerDriveUploadResult: Equatable {
    let driveFileId: String
    let driveFolderURL: URL?
    let fotosFolderURL: URL?
}

enum ScannerDriveUploadService {
    private static let uploadEndpoint = URL(
        string: "https://us-central1-svs-app-864ed.cloudfunctions.net/uploadScanToDrive"
    )!

    static func uploadPDF(
        localURL: URL,
        fileName: String,
        reservationId: String,
        useReservationFolder: Bool
    ) async throws -> ScannerDriveUploadResult {
        guard let user = Auth.auth().currentUser else {
            throw ScannerDriveUploadError.notSignedIn
        }

        let storageObjectName = "\(reservationId)__\(sanitizedStorageName(fileName))"
        let storagePath = "scans/\(user.uid)/\(storageObjectName)"
        try await uploadFileToFirebaseStorage(localURL: localURL, storagePath: storagePath)

        let idToken = try await user.getIDToken()
        return try await callUploadScanToDrive(
            idToken: idToken,
            storagePath: storagePath,
            reservationId: reservationId,
            fileName: fileName,
            useReservationFolder: useReservationFolder
        )
    }

    private static func uploadFileToFirebaseStorage(
        localURL: URL,
        storagePath: String
    ) async throws {
        let ref = Storage.storage().reference().child(storagePath)
        let metadata = StorageMetadata()
        metadata.contentType = "application/pdf"
        _ = try await ref.putFileAsync(from: localURL, metadata: metadata)
    }

    private static func callUploadScanToDrive(
        idToken: String,
        storagePath: String,
        reservationId: String,
        fileName: String,
        useReservationFolder: Bool
    ) async throws -> ScannerDriveUploadResult {
        var request = URLRequest(url: uploadEndpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(idToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "storagePath": storagePath,
            "reservationId": reservationId,
            "fileName": fileName,
            "useReservationFolder": useReservationFolder,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        let rawText = String(data: data, encoding: .utf8) ?? ""

        struct Payload: Decodable {
            let ok: Bool
            let driveFileId: String?
            let driveFolderUrl: String?
            let fotosFolderUrl: String?
            let error: String?
        }

        do {
            let decoded = try JSONDecoder().decode(Payload.self, from: data)
            if decoded.ok, let id = decoded.driveFileId, !id.isEmpty {
                return ScannerDriveUploadResult(
                    driveFileId: id,
                    driveFolderURL: decoded.driveFolderUrl.flatMap(URL.init(string:)),
                    fotosFolderURL: decoded.fotosFolderUrl.flatMap(URL.init(string:))
                )
            }

            let message = decoded.error ?? "HTTP \(status)"
            throw ScannerDriveUploadError.serverError(message)
        } catch let error as ScannerDriveUploadError {
            throw error
        } catch {
            let prefix = rawText.prefix(500)
            throw ScannerDriveUploadError.serverError(
                "Unerwartete Server-Antwort (HTTP \(status)): \(prefix)"
            )
        }
    }

    private static func sanitizedStorageName(_ input: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\?%*|\"<>:")
        let cleaned = input.components(separatedBy: invalid).joined(separator: "_")
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? "Dokument.pdf"
            : cleaned
    }
}

enum ScannerDriveUploadError: LocalizedError {
    case notSignedIn
    case serverError(String)

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Nicht angemeldet."
        case .serverError(let message):
            return message
        }
    }
}
