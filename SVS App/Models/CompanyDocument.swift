//
//  CompanyDocument.swift
//  SVS App
//

import Foundation

enum CompanyDocumentSection: String, CaseIterable, Identifiable {
    case internalDocuments
    case lawyerPowers
    case stargutachter

    var id: String { rawValue }

    var title: String {
        switch self {
        case .internalDocuments:
            return "Interne Dokumente"
        case .lawyerPowers:
            return "Anwaltsvollmachten"
        case .stargutachter:
            return "Stargutachter"
        }
    }

    var footer: String? {
        switch self {
        case .internalDocuments:
            return "Abtretungserklärung und Begleitdokument – zentrale Unterlagen für das Team."
        case .lawyerPowers:
            return "Vollmachten der Partnerkanzleien zum Ansehen, Download und Weiterleiten."
        case .stargutachter:
            return "Abtretungserklärung für Stargutachter-Fälle."
        }
    }

    var usesLawyerPowerAccess: Bool {
        switch self {
        case .lawyerPowers, .stargutachter:
            return true
        case .internalDocuments:
            return false
        }
    }
}

enum CompanyDocumentTextFieldKind: Hashable {
    case signingDate
    case accidentDate(prefix: String)
    case freeText(placeholder: String? = nil)
    case partyPair(separator: String)
}

struct CompanyDocumentInkField: Identifiable, Hashable {
    let id: String
    let label: String
    let defaultPlacement: PDFSignaturePlacement
}

struct CompanyDocumentTextField: Identifiable, Hashable {
    let id: String
    let label: String
    let kind: CompanyDocumentTextFieldKind
    let defaultPlacement: PDFSignaturePlacement

    var isDateField: Bool {
        switch kind {
        case .signingDate, .accidentDate:
            return true
        case .freeText, .partyPair:
            return false
        }
    }

    var isPartyPair: Bool {
        if case .partyPair = kind { return true }
        return false
    }

    var freeTextPlaceholder: String? {
        switch kind {
        case .freeText(let placeholder):
            return placeholder
        default:
            return nil
        }
    }

    func renderedText(date: Date, customText: String, secondaryText: String = "") -> String {
        switch kind {
        case .signingDate:
            return Self.germanDateFormatter.string(from: date)
        case .accidentDate(let prefix):
            return prefix + Self.germanDateFormatter.string(from: date)
        case .freeText:
            return customText.trimmingCharacters(in: .whitespacesAndNewlines)
        case .partyPair(let separator):
            let client = customText.trimmingCharacters(in: .whitespacesAndNewlines)
            let opponent = secondaryText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !client.isEmpty || !opponent.isEmpty else { return "" }
            if client.isEmpty { return opponent }
            if opponent.isEmpty { return client }
            return client + separator + opponent
        }
    }

    private static let germanDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "dd.MM.yyyy"
        return formatter
    }()
}

struct CompanyDocument: Identifiable, Hashable {
    private static let accidentDatePrefix = "Verkehrsunfall vom "

    let id: String
    let title: String
    let subtitle: String?
    let section: CompanyDocumentSection
    /// PDF-Basisname ohne Endung (ASCII, z. B. "ae").
    let resourceName: String
    let accentSymbol: String

    /// Direkt auf der PDF zeichnen (wie Markup auf dem iPad) – statt Unterschrift/Formular-Pads.
    var usesDirectPDFDrawing: Bool {
        id == "bd"
    }

    /// Einmal-Link für Kundenunterschrift (Web-Formular).
    var supportsRemoteSigning: Bool {
        id == "av-wessels"
    }

    /// Geführter Formular-Funnel zum Ausfüllen der PDF.
    var supportsFormFunnel: Bool {
        id == "ae"
    }

    /// Textfelder, die beim Signieren auf das PDF gesetzt werden (Datum immer enthalten).
    var textFields: [CompanyDocumentTextField] {
        var fields: [CompanyDocumentTextField] = []

        if id == "av-goecmen" {
            fields.append(
                CompanyDocumentTextField(
                    id: "case-matter",
                    label: "In Sachen",
                    kind: .partyPair(separator: " ./. "),
                    defaultPlacement: caseMatterPlacement
                )
            )
        }

        if section == .lawyerPowers {
            fields.append(
                CompanyDocumentTextField(
                    id: "accident-date",
                    label: "Unfalldatum",
                    kind: .accidentDate(prefix: Self.accidentDatePrefix),
                    defaultPlacement: accidentDatePlacement
                )
            )
        }

        if id != "bd" {
            fields.append(
                CompanyDocumentTextField(
                    id: "signing-date",
                    label: "Datum",
                    kind: .signingDate,
                    defaultPlacement: signingDatePlacement
                )
            )
        }

        return fields
    }

    var inkFields: [CompanyDocumentInkField] {
        []
    }

    var inkFieldsOnDrawStep: Bool {
        false
    }

    /// Unterschriftsfeld auf Seite 1 (UIKit-Koordinaten, Anteile 0…1).
    var signaturePlacement: PDFSignaturePlacement {
        switch id {
        case "ae":
            return PDFSignaturePlacement(pageIndex: 0, x: 0.579, y: 0.865, width: 0.235, height: 0.075)
        case "stargutachter-ae":
            return PDFSignaturePlacement(pageIndex: 0, x: 0.06, y: 0.68, width: 0.52, height: 0.14)
        case "bd":
            return PDFSignaturePlacement(pageIndex: 0, x: 0.06, y: 0.74, width: 0.48, height: 0.12)
        case "av-wessels":
            return PDFSignaturePlacement(pageIndex: 0, x: 0.077, y: 0.762, width: 0.36, height: 0.085)
        case "av-goecmen":
            return PDFSignaturePlacement(pageIndex: 0, x: 0.52, y: 0.84, width: 0.38, height: 0.10)
        case "av-kaya":
            return PDFSignaturePlacement(pageIndex: 0, x: 0.32, y: 0.93, width: 0.35, height: 0.08)
        case "av-hijazi":
            return PDFSignaturePlacement(pageIndex: 0, x: 0.48, y: 0.86, width: 0.38, height: 0.10)
        case "av-zeppelin":
            return PDFSignaturePlacement(pageIndex: 0, x: 0.55, y: 0.90, width: 0.35, height: 0.08)
        default:
            return PDFSignaturePlacement(pageIndex: 0, x: 0.08, y: 0.72, width: 0.44, height: 0.12)
        }
    }

    private var signingDatePlacement: PDFSignaturePlacement {
        switch id {
        case "ae":
            return PDFSignaturePlacement(pageIndex: 0, x: 0.107, y: 0.912, width: 0.20, height: 0.025)
        case "stargutachter-ae":
            return PDFSignaturePlacement(pageIndex: 0, x: 0.06, y: 0.60, width: 0.28, height: 0.045)
        case "bd":
            return PDFSignaturePlacement(pageIndex: 0, x: 0.06, y: 0.66, width: 0.28, height: 0.045)
        case "av-wessels":
            // Kalibriert: +5 pt rechts, −10 pt oben (A4)
            return PDFSignaturePlacement(pageIndex: 0, x: 0.588, y: 0.788, width: 0.28, height: 0.045)
        case "av-goecmen":
            return PDFSignaturePlacement(pageIndex: 0, x: 0.06, y: 0.88, width: 0.38, height: 0.045)
        case "av-kaya":
            return PDFSignaturePlacement(pageIndex: 0, x: 0.08, y: 0.90, width: 0.48, height: 0.045)
        case "av-hijazi":
            return PDFSignaturePlacement(pageIndex: 0, x: 0.10, y: 0.88, width: 0.30, height: 0.045)
        case "av-zeppelin":
            return PDFSignaturePlacement(pageIndex: 0, x: 0.10, y: 0.92, width: 0.38, height: 0.04)
        default:
            return PDFSignaturePlacement(pageIndex: 0, x: 0.06, y: 0.62, width: 0.28, height: 0.045)
        }
    }

    /// Göcmen: „Name ./. Name“ bei „in Sachen:“ (über „wegen:“ / Unfalldatum).
    private var caseMatterPlacement: PDFSignaturePlacement {
        PDFSignaturePlacement(pageIndex: 0, x: 0.22, y: 0.15, width: 0.55, height: 0.04)
    }

    /// „Verkehrsunfall vom …“ – gleicher Text, Startposition je Kanzlei-PDF unterschiedlich.
    private var accidentDatePlacement: PDFSignaturePlacement {
        switch id {
        case "av-wessels":
            return PDFSignaturePlacement(pageIndex: 0, x: 0.198, y: 0.159, width: 0.55, height: 0.045)
        case "av-goecmen":
            return PDFSignaturePlacement(pageIndex: 0, x: 0.22, y: 0.20, width: 0.55, height: 0.04)
        case "av-kaya":
            return PDFSignaturePlacement(pageIndex: 0, x: 0.44, y: 0.25, width: 0.52, height: 0.04)
        case "av-hijazi":
            return PDFSignaturePlacement(pageIndex: 0, x: 0.08, y: 0.155, width: 0.55, height: 0.04)
        case "av-zeppelin":
            return PDFSignaturePlacement(pageIndex: 0, x: 0.38, y: 0.29, width: 0.52, height: 0.035)
        default:
            return PDFSignaturePlacement(pageIndex: 0, x: 0.08, y: 0.12, width: 0.58, height: 0.045)
        }
    }

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
        CompanyDocument(
            id: "stargutachter-ae",
            title: "Abtretungserklärung",
            subtitle: "Stargutachter · AE",
            section: .stargutachter,
            resourceName: "stargutachter",
            accentSymbol: "star.fill"
        ),
    ]

    static var availableItems: [CompanyDocument] {
        items.filter { bundleURL(for: $0) != nil }
    }

    static func availableItems(in section: CompanyDocumentSection) -> [CompanyDocument] {
        availableItems.filter { $0.section == section }
    }

    static var lawyerPowerItems: [CompanyDocument] {
        availableItems.filter { $0.section.usesLawyerPowerAccess }
    }

    static var allLawyerPowerIds: [String] {
        lawyerPowerItems.map(\.id)
    }

    static var remoteSigningItems: [CompanyDocument] {
        items.filter(\.supportsRemoteSigning)
    }

    static var abtretungserklaerungDocument: CompanyDocument? {
        items.first { $0.id == "ae" }
    }

    static var abtretungserklaerungPDFURL: URL? {
        guard let document = abtretungserklaerungDocument else { return nil }
        return bundleURL(for: document)
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
