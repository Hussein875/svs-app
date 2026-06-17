//
//  ScannerUploadEntry.swift
//  SVS App
//

import Foundation
import FirebaseFirestore

struct ScannerUploadEntry: Identifiable, Hashable {
    let id: String
    let number: Int
    let year2: String
    let scanName: String
    let driveFolderName: String
    let driveFolderId: String
    let status: String
    let uploadedFileName: String?
    let createdAt: Date?
    let uploadedAt: Date?

    var numberLabel: String {
        "\(number)/\(year2)"
    }

    var isUploaded: Bool {
        status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "uploaded"
    }

    var driveFolderURL: URL? {
        let folderId = driveFolderId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !folderId.isEmpty else { return nil }
        return URL(string: "https://drive.google.com/drive/folders/\(folderId)")
    }

    var subtitle: String {
        let name = scanName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty {
            return name
        }
        let folder = driveFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
        return folder.isEmpty ? "Unfallgutachten" : folder
    }

    init?(id: String, data: [String: Any]) {
        guard let number = data["number"] as? Int else { return nil }

        let year2 = (data["year2"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !year2.isEmpty else { return nil }

        let driveFolderId = (data["driveFolderId"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !driveFolderId.isEmpty else { return nil }

        self.id = id
        self.number = number
        self.year2 = year2
        self.scanName = (data["scanName"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.driveFolderName = (data["driveFolderName"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.driveFolderId = driveFolderId
        self.status = (data["status"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "reserved"
        self.uploadedFileName = (data["uploadedFileName"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.createdAt = Self.date(from: data["createdAt"])
        self.uploadedAt = Self.date(from: data["uploadedAt"])
    }

    private static func date(from value: Any?) -> Date? {
        if let timestamp = value as? Timestamp {
            return timestamp.dateValue()
        }
        if let date = value as? Date {
            return date
        }
        return nil
    }
}
