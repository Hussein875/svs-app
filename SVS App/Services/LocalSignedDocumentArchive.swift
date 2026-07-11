//
//  LocalSignedDocumentArchive.swift
//  SVS App
//

import Foundation

struct LocalSignedDocumentRecord: Identifiable, Codable, Hashable {
    let id: String
    let documentId: String
    let documentTitle: String
    let signedAt: Date
    let storedFileName: String
    let label: String?

    var displayName: String {
        let trimmed = label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? documentTitle : trimmed
    }
}

enum LocalSignedDocumentArchive {
    private static let folderName = "LocalSignedDocuments"
    private static let manifestName = "manifest.json"

    static func archive(
        pdfAt sourceURL: URL,
        document: CompanyDocument,
        label: String? = nil
    ) throws -> LocalSignedDocumentRecord {
        let id = UUID().uuidString
        let storedFileName = "\(id).pdf"
        let destinationURL = archiveDirectory.appendingPathComponent(storedFileName)

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try FileManager.default.removeItem(at: destinationURL)
        }
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)

        let record = LocalSignedDocumentRecord(
            id: id,
            documentId: document.id,
            documentTitle: document.title,
            signedAt: Date(),
            storedFileName: storedFileName,
            label: label
        )

        var records = allRecords()
        records.insert(record, at: 0)
        try saveRecords(records)
        return record
    }

    static func allRecords() -> [LocalSignedDocumentRecord] {
        guard let data = try? Data(contentsOf: manifestURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let records = try? decoder.decode([LocalSignedDocumentRecord].self, from: data) else {
            return []
        }
        return records.filter { pdfURL(for: $0) != nil }
    }

    static func pdfURL(for record: LocalSignedDocumentRecord) -> URL? {
        let url = archiveDirectory.appendingPathComponent(record.storedFileName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    static func delete(record: LocalSignedDocumentRecord) throws {
        if let url = pdfURL(for: record) {
            try? FileManager.default.removeItem(at: url)
        }
        let remaining = allRecords().filter { $0.id != record.id }
        try saveRecords(remaining)
    }

    private static var archiveDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        let directory = base.appendingPathComponent(folderName, isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static var manifestURL: URL {
        archiveDirectory.appendingPathComponent(manifestName)
    }

    private static func saveRecords(_ records: [LocalSignedDocumentRecord]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(records)
        try data.write(to: manifestURL, options: .atomic)
    }
}
