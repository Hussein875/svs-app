//
//  CompanyDocument.swift
//  SVS App
//

import Foundation

enum CompanyDocumentSection: String, CaseIterable, Identifiable {
    case internalDocuments
    case lawyerPowers

    var id: String { rawValue }

    var title: String {
        switch self {
        case .internalDocuments:
            return "Interne Dokumente"
        case .lawyerPowers:
            return "Anwaltsvollmachten"
        }
    }

    var footer: String? {
        switch self {
        case .internalDocuments:
            return "Abtretungserklärung und Begleitdokument – zentrale Unterlagen für das Team."
        case .lawyerPowers:
            return "Vollmachten der Partnerkanzleien zum Ansehen, Download und Weiterleiten."
        }
    }
}

struct CompanyDocument: Identifiable, Hashable {
    let id: String
    let title: String
    let subtitle: String?
    let section: CompanyDocumentSection
    /// Exakter PDF-Dateiname ohne Endung (wie im Ordner CompanyDocuments).
    let fileName: String
    let accentSymbol: String
}

enum CompanyDocumentsCatalog {
    static let folderName = "CompanyDocuments"

    static let items: [CompanyDocument] = [
        CompanyDocument(
            id: "ae",
            title: "Abtretungserklärung",
            subtitle: "AE",
            section: .internalDocuments,
            fileName: "Abtretungserklärung (AE)",
            accentSymbol: "doc.text.fill"
        ),
        CompanyDocument(
            id: "bd",
            title: "Begleitdokument",
            subtitle: "BD · Bearbeitungsdokument",
            section: .internalDocuments,
            fileName: "Bearbeitungsdokument (BD)",
            accentSymbol: "doc.append.fill"
        ),
        CompanyDocument(
            id: "av-wessels",
            title: "Wessels",
            subtitle: "Anwaltskanzlei",
            section: .lawyerPowers,
            fileName: "Anwaltskanzlei Wessels Vollmacht",
            accentSymbol: "building.columns.fill"
        ),
        CompanyDocument(
            id: "av-goecmen",
            title: "Göcmen",
            subtitle: "Anwaltskanzlei",
            section: .lawyerPowers,
            fileName: "Anwaltskanzlei Göcmen Vollmacht",
            accentSymbol: "building.columns.fill"
        ),
        CompanyDocument(
            id: "av-kaya",
            title: "Kaya",
            subtitle: "Anwaltskanzlei",
            section: .lawyerPowers,
            fileName: "Anwaltskanzlei Kaya Vollmacht",
            accentSymbol: "building.columns.fill"
        ),
        CompanyDocument(
            id: "av-hijazi",
            title: "Hijazi",
            subtitle: "Anwaltskanzlei",
            section: .lawyerPowers,
            fileName: "Anwaltskanzlei Hijazi Vollmacht",
            accentSymbol: "building.columns.fill"
        ),
        CompanyDocument(
            id: "av-zeppelin",
            title: "Zeppelin",
            subtitle: "Anwaltskanzlei",
            section: .lawyerPowers,
            fileName: "Anwaltskanzlei Zeppelin Vollmacht",
            accentSymbol: "building.columns.fill"
        ),
    ]

    static var availableItems: [CompanyDocument] {
        items.filter { bundleURL(for: $0) != nil }
    }

    static func availableItems(in section: CompanyDocumentSection) -> [CompanyDocument] {
        availableItems.filter { $0.section == section }
    }

    static func bundleURL(for document: CompanyDocument) -> URL? {
        if let direct = Bundle.main.url(
            forResource: document.fileName,
            withExtension: "pdf",
            subdirectory: folderName
        ) {
            return direct
        }

        let candidates = Bundle.main.urls(
            forResourcesWithExtension: "pdf",
            subdirectory: folderName
        ) ?? []

        let target = normalizedFileName(document.fileName)
        return candidates.first {
            normalizedFileName($0.deletingPathExtension().lastPathComponent) == target
        }
    }

    private static func normalizedFileName(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .replacingOccurrences(of: " ", with: "")
            .lowercased()
    }
}
