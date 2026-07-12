//
//  AbtretungserklaerungPDFRenderer.swift
//  SVS App
//
//  Schreibt Funnel-Daten als Text-Overlays auf ae.pdf.
//  Koordinaten aus ae.pdf kalibriert (pdftotext -bbox).
//  Formularwerte: einheitlicher Versatz nach oben (aeValueLineLiftY).
//

import Foundation
import UIKit

enum AbtretungserklaerungPDFRenderer {
    private static let germanDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "dd.MM.yyyy"
        return formatter
    }()

    /// Erzeugt ein signierbares PDF mit allen Formularwerten.
    static func renderFilledPDF(
        sourceURL: URL,
        form: AbtretungserklaerungForm
    ) throws -> URL {
        let overlays = textOverlays(for: form)
        return try PDFSignatureService.textStampedPDFURL(
            sourceURL: sourceURL,
            textOverlays: overlays,
            outputBaseName: "ae-ausgefuellt"
        )
    }

    static func textOverlays(for form: AbtretungserklaerungForm) -> [PDFTextOverlay] {
        var overlays: [PDFTextOverlay] = []

        func add(_ id: AbtretungserklaerungField, _ value: String?) {
            let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !trimmed.isEmpty else { return }
            overlays.append(PDFTextOverlay(text: trimmed, placement: AbtretungserklaerungPlacementStore.placement(for: id)))
        }

        add(.clientName, form.clientName)
        add(.streetAndNumber, form.streetAndNumber)
        add(.postalCodeAndCity, form.postalCodeAndCity)
        add(.phoneOrEmail, form.phoneOrEmail)
        add(.licensePlate, GermanLicensePlateFormatter.format(form.licensePlate))
        add(.opponentName, form.opponentName)
        add(.insuranceCompany, form.insuranceCompany)
        add(.claimOrPolicyNumber, form.claimOrPolicyNumber)
        add(.opponentLicensePlate, GermanLicensePlateFormatter.format(form.opponentLicensePlate))
        add(.damageLocation, form.damageLocation)
        add(.gutachtenNumber, form.gutachtenNumber)

        add(.damageDate, germanDateFormatter.string(from: form.damageDate))

        add(.signingDate, germanDateFormatter.string(from: form.signingDate))

        if let isVatDeductible = form.isVatDeductible {
            add(.vatYes, isVatDeductible ? "X" : nil)
            add(.vatNo, isVatDeductible ? nil : "X")
        }

        return overlays
    }
}

/// PDF-Felder der AE – Koordinaten aus ae.pdf kalibriert (pdftotext -bbox).
enum AbtretungserklaerungField: String, CaseIterable, Identifiable {
    case clientName
    case streetAndNumber
    case postalCodeAndCity
    case phoneOrEmail
    case licensePlate
    case opponentName
    case insuranceCompany
    case claimOrPolicyNumber
    case opponentLicensePlate
    case damageDate
    case damageLocation
    case gutachtenNumber
    case vatYes
    case vatNo
    case signingDate
    case signatureImage

    var id: String { rawValue }

    /// Felder, die im Positionsschritt verschoben werden können.
    static var adjustableFields: [AbtretungserklaerungField] {
        allCases.filter { $0 != .signatureImage }
    }

    var label: String {
        switch self {
        case .clientName: return "Auftraggeber / Anspruchsteller"
        case .streetAndNumber: return "Straße und Hausnummer"
        case .postalCodeAndCity: return "PLZ / Ort"
        case .phoneOrEmail: return "Telefon / E-Mail"
        case .licensePlate: return "Amtliches Kennzeichen"
        case .opponentName: return "Unfallgegner"
        case .insuranceCompany: return "Versicherung"
        case .claimOrPolicyNumber: return "Schaden-Nr. / Versicherungs-Nr."
        case .opponentLicensePlate: return "Kennzeichen des Unfallgegners"
        case .damageDate: return "Schadentag"
        case .damageLocation: return "Schadenort"
        case .gutachtenNumber: return "Gutachten-Nr."
        case .vatYes: return "Vorsteuerabzug: Ja"
        case .vatNo: return "Vorsteuerabzug: Nein"
        case .signingDate: return "Ort / Datum"
        case .signatureImage: return "Unterschrift"
        }
    }

    var placement: PDFSignaturePlacement {
        AbtretungserklaerungPlacementStore.placement(for: self)
    }

    var defaultPlacement: PDFSignaturePlacement {
        switch self {
        case .clientName:
            return PDFSignaturePlacement.pageValueLine(y: 0.1541)
        case .streetAndNumber:
            return PDFSignaturePlacement.pageValueLine(y: 0.1754)
        case .postalCodeAndCity:
            return PDFSignaturePlacement.pageValueLine(y: 0.1964)
        case .phoneOrEmail:
            return PDFSignaturePlacement.pageValueLine(y: 0.2177)
        case .licensePlate:
            return PDFSignaturePlacement.pageValueLine(y: 0.2390)
        case .opponentName:
            return PDFSignaturePlacement.pageValueLine(y: 0.2809)
        case .insuranceCompany:
            return PDFSignaturePlacement.pageValueLine(y: 0.3022)
        case .claimOrPolicyNumber:
            return PDFSignaturePlacement.pageValueLine(y: 0.3232)
        case .opponentLicensePlate:
            return PDFSignaturePlacement.pageValueLine(y: 0.3446)
        case .damageDate:
            return PDFSignaturePlacement.pageValueLine(y: 0.3661)
        case .damageLocation:
            return PDFSignaturePlacement.pageValueLine(y: 0.3870)
        case .gutachtenNumber:
            return PDFSignaturePlacement.pageValueLine(y: 0.4083)
        case .vatYes:
            return PDFSignaturePlacement.pageCheckbox(
                x: 0.464,
                y: 0.414 + PDFSignaturePlacement.pagePixels(3)
            )
        case .vatNo:
            return PDFSignaturePlacement.pageCheckbox(
                x: 0.523,
                y: 0.414 + PDFSignaturePlacement.pagePixels(3)
            )
        case .signingDate:
            return PDFSignaturePlacement(
                pageIndex: 0,
                x: 0.107,
                y: 0.898 + PDFSignaturePlacement.pagePixels(7),
                width: 0.20,
                height: 0.025
            )
        case .signatureImage:
            return PDFSignaturePlacement(
                pageIndex: 0,
                x: 0.579,
                y: 0.878,
                width: 0.235,
                height: 0.075
            )
        }
    }
}

private extension PDFSignaturePlacement {
    static let pageHeight: CGFloat = 841.890

    fileprivate static func pagePixels(_ pixels: CGFloat) -> CGFloat {
        pixels / pageHeight
    }

    fileprivate static let aeValueLineLiftY: CGFloat = 15.0 / pageHeight

    static func pageValueLine(y: CGFloat) -> PDFSignaturePlacement {
        PDFSignaturePlacement(
            pageIndex: 0,
            x: 0.454,
            y: max(0, y - aeValueLineLiftY),
            width: 0.435,
            height: 0.022
        )
    }

    static func pageCheckbox(x: CGFloat, y: CGFloat) -> PDFSignaturePlacement {
        PDFSignaturePlacement(
            pageIndex: 0,
            x: x,
            y: y,
            width: 0.022,
            height: 0.022
        )
    }
}
