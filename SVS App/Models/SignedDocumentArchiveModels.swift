//
//  SignedDocumentArchiveModels.swift
//  SVS App
//

import Foundation

enum SignedArchiveSelection: Identifiable, Hashable {
    case remote(DocumentSigningLinkStatus)
    case local(LocalSignedDocumentRecord)

    var id: String {
        switch self {
        case .remote(let link):
            return "remote-\(link.id)"
        case .local(let record):
            return "local-\(record.id)"
        }
    }

    var signedAt: Date? {
        switch self {
        case .remote(let link):
            return link.signedAt
        case .local(let record):
            return record.signedAt
        }
    }

    var canOpenPDF: Bool {
        switch self {
        case .remote(let link):
            return link.canOpenSignedPDF
        case .local(let record):
            return LocalSignedDocumentArchive.pdfURL(for: record) != nil
        }
    }
}

struct SignedArchiveEntry: Identifiable, Hashable {
    let id: String
    let selection: SignedArchiveSelection
    let title: String
    let documentTitle: String
    let signedAt: Date?
    let accidentDateIso: String?
    let sourceLabel: String
    let canOpenPDF: Bool

    static func fromRemote(_ link: DocumentSigningLinkStatus) -> SignedArchiveEntry {
        SignedArchiveEntry(
            id: "remote-\(link.id)",
            selection: .remote(link),
            title: link.displayName,
            documentTitle: link.overviewDocumentLabel,
            signedAt: link.signedAt,
            accidentDateIso: link.accidentDateIso,
            sourceLabel: "Kunde online",
            canOpenPDF: link.canOpenSignedPDF
        )
    }

    static func fromLocal(_ record: LocalSignedDocumentRecord) -> SignedArchiveEntry {
        SignedArchiveEntry(
            id: "local-\(record.id)",
            selection: .local(record),
            title: record.displayName,
            documentTitle: record.documentTitle,
            signedAt: record.signedAt,
            accidentDateIso: nil,
            sourceLabel: "In App",
            canOpenPDF: LocalSignedDocumentArchive.pdfURL(for: record) != nil
        )
    }
}
