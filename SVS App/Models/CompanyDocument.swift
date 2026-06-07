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
    /// PDF-Basisname ohne Endung (ASCII, z. B. "ae").
    let resourceName: String
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
            resourceName: "ae",
            accentSymbol: "doc.text.fill"
        ),
        CompanyDocument(
            id: "bd",
            title: "Begleitdokument",
            subtitle: "BD · Bearbeitungsdokument",
            section: .internalDocuments,
            resourceName: "bd",
            accentSymbol: "doc.append.fill"
        ),
        CompanyDocument(
            id: "av-wessels",
            title: "Wessels",
            subtitle: "Anwaltskanzlei",
            section: .lawyerPowers,
            resourceName: "av-wessels",
            accentSymbol: "building.columns.fill"
        ),
        CompanyDocument(
            id: "av-goecmen",
            title: "Göcmen",
            subtitle: "Anwaltskanzlei",
            section: .lawyerPowers,
            resourceName: "av-goecmen",
            accentSymbol: "building.columns.fill"
        ),
        CompanyDocument(
            id: "av-kaya",
            title: "Kaya",
            subtitle: "Anwaltskanzlei",
            section: .lawyerPowers,
            resourceName: "av-kaya",
            accentSymbol: "building.columns.fill"
        ),
        CompanyDocument(
            id: "av-hijazi",
            title: "Hijazi",
            subtitle: "Anwaltskanzlei",
            section: .lawyerPowers,
            resourceName: "av-hijazi",
            accentSymbol: "building.columns.fill"
        ),
        CompanyDocument(
            id: "av-zeppelin",
            title: "Zeppelin",
            subtitle: "Anwaltskanzlei",
            section: .lawyerPowers,
            resourceName: "av-zeppelin",
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
        let searchDirectories: [String?] = [folderName, nil]

        for directory in searchDirectories {
            if let url = Bundle.main.url(
                forResource: document.resourceName,
                withExtension: "pdf",
                subdirectory: directory
            ) {
                return url
            }
        }

        return bundledPDFIndex()[document.resourceName]
    }

    private static var cachedPDFIndex: [String: URL]?
    private static let pdfIndexLock = NSLock()

    private static func bundledPDFIndex() -> [String: URL] {
        pdfIndexLock.lock()
        defer { pdfIndexLock.unlock() }

        if let cachedPDFIndex {
            return cachedPDFIndex
        }

        var index: [String: URL] = [:]

        func ingest(_ urls: [URL]) {
            for url in urls {
                let key = url.deletingPathExtension().lastPathComponent.lowercased()
                index[key] = url
            }
        }

        ingest(Bundle.main.urls(forResourcesWithExtension: "pdf", subdirectory: folderName) ?? [])
        ingest(Bundle.main.urls(forResourcesWithExtension: "pdf", subdirectory: nil) ?? [])

        if let resourceURL = Bundle.main.resourceURL,
           let enumerator = FileManager.default.enumerator(
            at: resourceURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
           ) {
            for case let fileURL as URL in enumerator where fileURL.pathExtension.lowercased() == "pdf" {
                let key = fileURL.deletingPathExtension().lastPathComponent.lowercased()
                index[key] = fileURL
            }
        }

        cachedPDFIndex = index
        return index
    }
}
