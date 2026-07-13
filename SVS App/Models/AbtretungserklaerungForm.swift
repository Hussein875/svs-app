//
//  AbtretungserklaerungForm.swift
//  SVS App
//
//  Formularmodell für den AE-Funnel (Abtretungserklärung).
//  PDF-Felder wurden aus ae.pdf abgeleitet.
//

import Foundation

/// Alle ausfüllbaren Felder der internen Abtretungserklärung.
struct AbtretungserklaerungForm: Equatable, Codable {
    var gutachtenNumber: String = ""
    var gutachtenReservationId: String?

    var clientLastName: String = ""
    var clientFirstName: String = ""
    var streetAndNumber: String = ""
    var postalCodeAndCity: String = ""
    var phoneOrEmail: String = ""
    var licensePlate: String = ""
    /// Fahrzeug-Identifizierungsnummer (FIN), z. B. aus Fahrzeugschein-Scan.
    var vin: String = ""
    /// Erstzulassung (Feld B), nur lokal – nicht für AE-PDF.
    var firstRegistrationDate: Date?

    var opponentName: String = ""
    var insuranceCompany: String = ""
    var claimOrPolicyNumber: String = ""
    var opponentLicensePlate: String = ""
    var damageDate: Date = Date()
    var damageLocation: String = ""

    var isVatDeductible: Bool?

    var signingDate: Date = Date()

    /// Vollständiger Name für PDF (Vorname Nachname).
    var clientName: String {
        let last = clientLastName.trimmingCharacters(in: .whitespacesAndNewlines)
        let first = clientFirstName.trimmingCharacters(in: .whitespacesAndNewlines)
        if last.isEmpty { return first }
        if first.isEmpty { return last }
        return "\(first) \(last)"
    }

    var isReadyForPreview: Bool {
        !clientLastName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !streetAndNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !postalCodeAndCity.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !licensePlate.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !damageLocation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

/// Schritte des geführten Funnels (kurze Screens, GA-Nr. am Ende).
enum AbtretungserklaerungFunnelStep: Int, CaseIterable, Identifiable {
    case vehicleRegistrationScan = 0
    case clientIdentity
    case clientAddress
    case accidentDetails
    case vatChoice
    case preview
    case gutachtenNumber
    case signature

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .vehicleRegistrationScan:
            return "Fahrzeugschein"
        case .clientIdentity:
            return "Auftraggeber"
        case .clientAddress:
            return "Adresse"
        case .accidentDetails:
            return "Unfall"
        case .vatChoice:
            return "Vorsteuer"
        case .preview:
            return "Vorschau"
        case .gutachtenNumber:
            return "Gutachten-Nr."
        case .signature:
            return "Unterschrift"
        }
    }

    var subtitle: String {
        switch self {
        case .vehicleRegistrationScan:
            return "Optional fotografieren – Daten werden übernommen"
        case .clientIdentity:
            return "Nachname, Vorname und Kennzeichen prüfen"
        case .clientAddress:
            return "Adresse ergänzen oder korrigieren"
        case .accidentDetails:
            return "Schadenort, Schadentag, Kennzeichen Gegner – optional mehr unten"
        case .vatChoice:
            return "Vorsteuerabzugsberechtigt?"
        case .preview:
            return "Ausgefülltes Dokument kontrollieren"
        case .gutachtenNumber:
            return "Nummer reservieren oder ohne Nummer fortfahren"
        case .signature:
            return "Kundenunterschrift auf dem PDF"
        }
    }
}

enum AbtretungserklaerungScanNameBuilder {
    /// Ordnername nur aus Nachname, z. B. „Khatuev“.
    static func suggestedFolderName(clientLastName: String) -> String {
        let trimmed = clientLastName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        return trimmed
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "de_DE"))
            .replacingOccurrences(of: " ", with: "_")
            .replacingOccurrences(of: "/", with: "-")
    }
}

/// Ergebnis der Fahrzeugschein-Erkennung (Vision OCR + Parser).
struct VehicleRegistrationOCRResult: Equatable {
    var clientLastName: String?
    var clientFirstName: String?
    var clientName: String?
    var streetAndNumber: String?
    var postalCode: String?
    var city: String?
    var licensePlate: String?
    var vin: String?
    var firstRegistrationDate: Date?
    var rawText: String

    var postalCodeAndCity: String? {
        let plz = postalCode?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let ort = city?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !plz.isEmpty || !ort.isEmpty else { return nil }
        if plz.isEmpty { return ort }
        if ort.isEmpty { return plz }
        return "\(plz) \(ort)"
    }

    func apply(to form: inout AbtretungserklaerungForm) {
        if let clientLastName, !clientLastName.isEmpty {
            form.clientLastName = clientLastName
        }
        if let clientFirstName, !clientFirstName.isEmpty {
            form.clientFirstName = clientFirstName
        }
        if form.clientLastName.isEmpty, form.clientFirstName.isEmpty,
           let clientName, !clientName.isEmpty {
            let parts = clientName
                .split(whereSeparator: \.isWhitespace)
                .map(String.init)
            if parts.count >= 2 {
                form.clientLastName = parts[0]
                form.clientFirstName = parts.dropFirst().joined(separator: " ")
            } else {
                form.clientLastName = clientName
            }
        }
        if let streetAndNumber, !streetAndNumber.isEmpty { form.streetAndNumber = streetAndNumber }
        if let combined = postalCodeAndCity { form.postalCodeAndCity = combined }
        if let licensePlate, !licensePlate.isEmpty {
            form.licensePlate = GermanLicensePlateFormatter.format(licensePlate)
        }
        if let vin, !vin.isEmpty {
            form.vin = VehicleIdentificationStore.normalizeVin(vin)
        }
        if let resolvedFirstRegistrationDate = VehicleIdentificationStore.resolveErstzulassungDate(
            parsedFromSchema: firstRegistrationDate,
            rawText: rawText
        ) {
            form.firstRegistrationDate = resolvedFirstRegistrationDate
        }

        if !form.licensePlate.isEmpty,
           !form.vin.isEmpty || form.firstRegistrationDate != nil {
            VehicleIdentificationStore.remember(
                licensePlate: form.licensePlate,
                vin: form.vin.isEmpty ? nil : form.vin,
                firstRegistrationDate: form.firstRegistrationDate
            )
        }
    }
}
