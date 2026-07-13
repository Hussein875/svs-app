//
//  VehicleRegistrationOCRService.swift
//  SVS App
//
//  Erkennt Text auf dem Fahrzeugschein (Zulassungsbescheinigung Teil I)
//  per Apple Vision. Parser nutzt Feld-Codes (C.1.1 …) und die linke Spalte.
//

import Foundation
import UIKit
import Vision

enum VehicleRegistrationOCRError: LocalizedError {
    case unreadableImage
    case noTextFound

    var errorDescription: String? {
        switch self {
        case .unreadableImage:
            return "Das Foto konnte nicht gelesen werden."
        case .noTextFound:
            return "Auf dem Fahrzeugschein wurde kein Text erkannt."
        }
    }
}

enum VehicleRegistrationOCRService {
    private struct OCRLine {
        let text: String
        let box: CGRect
    }

    static func recognize(from image: UIImage) async throws -> VehicleRegistrationOCRResult {
        guard let cgImage = image.cgImage else {
            throw VehicleRegistrationOCRError.unreadableImage
        }

        var lines = try recognizeLines(in: cgImage)

        // Zweiter Lauf: linke Halter-Spalte vergrößert (Namen stehen dort).
        if let cropped = cropLeftColumn(cgImage, widthFraction: 0.38),
           let croppedLines = try? recognizeLines(in: cropped) {
            lines = mergeLines(lines, with: croppedLines)
        }

        guard !lines.isEmpty else {
            throw VehicleRegistrationOCRError.noTextFound
        }

        let texts = lines.map(\.text)
        return parse(lines: lines, rawText: texts.joined(separator: "\n"))
    }

    private static func recognizeLines(in cgImage: CGImage) throws -> [OCRLine] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        // Namen (z. B. Hassan, Khatuev) werden sonst oft „korrigiert“.
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["de-DE", "de-AT", "de-CH"]

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try handler.perform([request])

        let lines = sortedLines(from: request.results ?? [])
        guard !lines.isEmpty else {
            throw VehicleRegistrationOCRError.noTextFound
        }
        return lines
    }

    private static func cropLeftColumn(_ image: CGImage, widthFraction: CGFloat) -> CGImage? {
        let width = CGFloat(image.width) * widthFraction
        let rect = CGRect(x: 0, y: 0, width: width, height: CGFloat(image.height))
        return image.cropping(to: rect)
    }

    private static func mergeLines(_ base: [OCRLine], with extra: [OCRLine]) -> [OCRLine] {
        var merged = base
        for line in extra {
            let duplicate = merged.contains { existing in
                existing.text.caseInsensitiveCompare(line.text) == .orderedSame
                    || existing.text.localizedCaseInsensitiveContains(line.text)
            }
            if !duplicate {
                merged.append(line)
            }
        }
        return merged.sorted { lhs, rhs in
            if abs(lhs.box.midY - rhs.box.midY) > 0.018 {
                return lhs.box.midY > rhs.box.midY
            }
            return lhs.box.minX < rhs.box.minX
        }
    }

    // MARK: - OCR ordering

    private static func sortedLines(from results: [VNRecognizedTextObservation]) -> [OCRLine] {
        results
            .compactMap { observation -> OCRLine? in
                guard let text = observation.topCandidates(1).first?.string
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                      !text.isEmpty else { return nil }
                return OCRLine(text: text, box: observation.boundingBox)
            }
            .sorted { lhs, rhs in
                if abs(lhs.box.midY - rhs.box.midY) > 0.018 {
                    return lhs.box.midY > rhs.box.midY
                }
                return lhs.box.minX < rhs.box.minX
            }
    }

    // MARK: - Parser

    private static func parse(lines: [OCRLine], rawText: String) -> VehicleRegistrationOCRResult {
        let texts = lines.map(\.text)

        var lastName: String?
        var firstName: String?
        var street: String?
        var plz: String?
        var city: String?
        var plate: String?
        var vin: String?
        var firstRegistrationDate: Date?

        // Erstzulassung (Feld B): oben links — vor dem allgemeinen Zeilen-Scan.
        firstRegistrationDate = parseFirstRegistrationDateSpatial(lines: lines)

        // 1) Feld-Codes C.1.1 / C.1.2 / C.1.3 (auch OCR-Varianten wie „C1.2 Vor“)
        for (index, line) in lines.enumerated() {
            let normalized = normalizedFieldCode(line.text)

            if vin == nil, let parsedVin = matchVehicleIdentificationNumber(line.text) {
                vin = parsedVin
            }

            if plate == nil, let fieldA = matchFieldAPlate(line.text) {
                plate = fieldA
            }

            if normalized.contains("C11") || normalized.hasPrefix("C1.1") {
                lastName = valueAfterLabel(in: line.text)
                    ?? nearestValueLine(after: index, in: lines, filter: looksLikePersonName)?.text
            }

            if normalized.contains("C12") || normalized.hasPrefix("C1.2") {
                firstName = valueAfterLabel(in: line.text)
                    ?? nearestValueLine(after: index, in: lines, filter: looksLikePersonName)?.text
            }

            if normalized.contains("C13") || normalized.hasPrefix("C1.3") {
                if let value = valueAfterLabel(in: line.text) {
                    applyAddressValue(value, street: &street, plz: &plz, city: &city)
                } else if let addressLine = nearestValueLine(after: index, in: lines, filter: { looksLikeStreet($0) || matchGermanPostalLine($0) != nil }) {
                    applyAddressValue(addressLine.text, street: &street, plz: &plz, city: &city)
                }
            }

            if plz == nil, let match = matchGermanPostalLine(line.text) {
                plz = match.plz
                city = match.city
            }

            if street == nil, let combined = matchStreetPostalCombined(line.text) {
                street = combined.street
                plz = plz ?? combined.plz
                city = city ?? combined.city
            }
        }

        // 2) Halter-Spalte links unter Kennzeichen (Feld A)
        let spatial = parseOwnerColumnSpatial(lines: lines)
        lastName = lastName ?? spatial.lastName
        firstName = firstName ?? spatial.firstName
        street = street ?? spatial.street
        plz = plz ?? spatial.plz
        city = city ?? spatial.city
        plate = plate ?? spatial.plate

        plate = plate ?? lines.compactMap { matchFieldAPlate($0.text) }.first
        vin = vin ?? lines.compactMap { matchVehicleIdentificationNumber($0.text) }.first
            ?? matchVehicleIdentificationNumber(rawText)
        firstRegistrationDate = firstRegistrationDate
            ?? VehicleIdentificationStore.parseErstzulassungDateFromScheinText(rawText)

        let mergedName: String? = {
            let last = lastName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let first = firstName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if last.isEmpty, first.isEmpty { return nil }
            if last.isEmpty { return first }
            if first.isEmpty { return last }
            return "\(first) \(last)"
        }()

        return VehicleRegistrationOCRResult(
            clientLastName: lastName,
            clientFirstName: firstName,
            clientName: mergedName,
            streetAndNumber: street,
            postalCode: plz,
            city: city,
            licensePlate: plate.map(GermanLicensePlateFormatter.format),
            vin: vin,
            firstRegistrationDate: firstRegistrationDate,
            rawText: rawText
        )
    }

    private static func matchFirstRegistrationDate(_ text: String) -> Date? {
        let normalized = normalizedFieldCode(text)
        let lowered = text.lowercased()
        let mentionsErstzulassung = lowered.contains("erstzulassung")
            || normalized == "B"
            || normalized.hasPrefix("B.")
        guard mentionsErstzulassung else { return nil }
        return extractGermanDate(from: text)
    }

    private static func parseFirstRegistrationDateSpatial(lines: [OCRLine]) -> Date? {
        // Feld B (Erstzulassung) steht oben links auf dem Schein — nicht rechts (Feld 6 / Baujahr).
        let topLeftZone = lines.filter { $0.box.midX < 0.55 && $0.box.midY > 0.38 }

        for line in topLeftZone {
            if isForbiddenErstzulassungContext(line.text) { continue }
            if let date = matchFirstRegistrationDate(line.text) {
                return date
            }
        }

        for (index, line) in topLeftZone.enumerated() {
            if isForbiddenErstzulassungContext(line.text) { continue }

            let normalized = normalizedFieldCode(line.text)
            let mentionsFieldB = normalized == "B"
                || line.text.localizedCaseInsensitiveContains("erstzulassung")
            guard mentionsFieldB else { continue }

            if let date = extractGermanDate(from: line.text) {
                return date
            }

            let neighbors = topLeftZone[(index + 1)...].prefix(4)
            for neighbor in neighbors {
                if abs(neighbor.box.midY - line.box.midY) > 0.06 { break }
                if isForbiddenErstzulassungContext(neighbor.text) { continue }
                if let date = extractGermanDate(from: neighbor.text) {
                    return date
                }
            }
        }

        if let fieldBLine = topLeftZone.first(where: { line in
            let trimmed = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            return normalizedFieldCode(trimmed) == "B" || trimmed == "B"
        }) {
            for neighbor in topLeftZone {
                guard abs(neighbor.box.midY - fieldBLine.box.midY) < 0.08
                    || abs(neighbor.box.midX - fieldBLine.box.midX) < 0.18 else {
                    continue
                }
                if isForbiddenErstzulassungContext(neighbor.text) { continue }
                if let date = extractGermanDate(from: neighbor.text) {
                    return date
                }
            }
        }

        return nil
    }

    private static func isForbiddenErstzulassungContext(_ text: String) -> Bool {
        let lowered = text.lowercased()
        if lowered.contains("datum zu 4") { return true }
        if lowered.contains("produktion") || lowered.contains("baudatum") { return true }
        if lowered.contains("baujahr") { return true }
        if lowered.contains("datum dieser zulassung") { return true }
        if text.range(of: #"(?:^|\s)6\b"#, options: .regularExpression) != nil,
           lowered.contains("datum") {
            return true
        }
        return false
    }

    private static func extractGermanDate(from text: String) -> Date? {
        guard let match = text.range(
            of: #"\d{2}\.\d{2}\.\d{4}"#,
            options: .regularExpression
        ) else {
            return nil
        }
        return VehicleIdentificationStore.parseFirstRegistrationDate(
            String(text[match])
        )
    }

    private static func matchVehicleIdentificationNumber(_ text: String) -> String? {
        let upper = text.uppercased()
        let pattern = #"[A-HJ-NPR-Z0-9]{17}"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(upper.startIndex..<upper.endIndex, in: upper)
        guard let match = regex.firstMatch(in: upper, range: range),
              let swiftRange = Range(match.range, in: upper) else {
            return nil
        }
        return VehicleIdentificationStore.normalizeVin(String(upper[swiftRange]))
    }

    /// Linke Spalte unter Feld (A): Nachname, Vorname, Straße, PLZ.
    private static func parseOwnerColumnSpatial(lines: [OCRLine]) -> (
        lastName: String?,
        firstName: String?,
        street: String?,
        plz: String?,
        city: String?,
        plate: String?
    ) {
        let leftColumn = lines.filter { $0.box.midX < 0.30 }

        guard let plateLine = leftColumn
            .compactMap({ line -> OCRLine? in
                matchFieldAPlate(line.text) != nil ? line : nil
            })
            .max(by: { $0.box.midY < $1.box.midY }) else {
            return (nil, nil, nil, nil, nil, nil)
        }

        let plate = matchFieldAPlate(plateLine.text)
        let ownerZone = leftColumn.filter { line in
            line.box.midY < plateLine.box.midY - 0.008
                && line.box.midY > 0.12
                && !isOwnerBlockNoise(line.text)
        }.sorted { $0.box.midY > $1.box.midY }

        var lastName: String?
        var firstName: String?
        var street: String?
        var plz: String?
        var city: String?
        var nameCandidates: [String] = []

        for line in ownerZone {
            let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if isFieldLabelLine(text) { continue }

            if let combined = matchStreetPostalCombined(text) {
                street = street ?? combined.street
                plz = plz ?? combined.plz
                city = city ?? combined.city
                continue
            }
            if let postal = matchGermanPostalLine(text) {
                plz = plz ?? postal.plz
                city = city ?? postal.city
                continue
            }
            if looksLikeStreet(text) {
                street = street ?? text
                continue
            }
            if looksLikePersonName(text) {
                nameCandidates.append(text)
            }
        }

        if let first = nameCandidates.first {
            lastName = first
            if nameCandidates.count > 1 {
                firstName = nameCandidates[1]
            }
        }

        return (lastName, firstName, street, plz, city, plate)
    }

    private static func nearestValueLine(
        after index: Int,
        in lines: [OCRLine],
        filter: (String) -> Bool
    ) -> OCRLine? {
        guard index + 1 < lines.count else { return nil }
        let anchor = lines[index]
        let candidates = lines[(index + 1)...].prefix(4)
        return candidates.first { line in
            filter(line.text)
                && abs(line.box.midX - anchor.box.midX) < 0.12
                && !isFieldLabelLine(line.text)
        }
    }

    private static func normalizedFieldCode(_ text: String) -> String {
        text.uppercased()
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "de_DE"))
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ".", with: "")
    }

    private static func isFieldLabelLine(_ text: String) -> Bool {
        let normalized = normalizedFieldCode(text)
        if normalized.hasPrefix("C1") { return true }
        if normalized.hasPrefix("C2") || normalized.hasPrefix("C3") { return true }
        if text.count <= 12, text.range(of: #"C\.?1\.?[123]"#, options: .regularExpression) != nil {
            return true
        }
        return false
    }

    private static func applyAddressValue(
        _ value: String,
        street: inout String?,
        plz: inout String?,
        city: inout String?
    ) {
        if let combined = matchStreetPostalCombined(value) {
            street = street ?? combined.street
            plz = plz ?? combined.plz
            city = city ?? combined.city
        } else if let postal = matchGermanPostalLine(value) {
            plz = plz ?? postal.plz
            city = city ?? postal.city
        } else {
            street = street ?? value
        }
    }

    private static func valueAfterLabel(in line: String) -> String? {
        guard let range = line.range(of: ":") else { return nil }
        let value = line[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, !isFieldLabelLine(value) else { return nil }
        return value
    }

    private static func matchGermanPostalLine(_ line: String) -> (plz: String, city: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^(\d{5})\s+(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
              let plzRange = Range(match.range(at: 1), in: trimmed),
              let cityRange = Range(match.range(at: 2), in: trimmed) else {
            return nil
        }
        return (String(trimmed[plzRange]), String(trimmed[cityRange]))
    }

    private static func matchStreetPostalCombined(_ line: String) -> (street: String, plz: String, city: String)? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^(.+?),\s*(\d{5})\s+(.+)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
              let streetRange = Range(match.range(at: 1), in: trimmed),
              let plzRange = Range(match.range(at: 2), in: trimmed),
              let cityRange = Range(match.range(at: 3), in: trimmed) else {
            return nil
        }
        return (
            String(trimmed[streetRange]).trimmingCharacters(in: .whitespacesAndNewlines),
            String(trimmed[plzRange]),
            String(trimmed[cityRange])
        )
    }

    /// Feld (A) – z. B. „HB SV 226“.
    private static func matchFieldAPlate(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let pattern = #"^[A-ZÄÖÜ]{1,3}\s+[A-ZÄÖÜ]{1,2}\s+\d{1,4}$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..., in: trimmed)),
              let range = Range(match.range, in: trimmed) else {
            return nil
        }
        return String(trimmed[range])
    }

    private static func looksLikeStreet(_ line: String) -> Bool {
        let lower = line.lowercased()
        if lower.contains("str.") || lower.contains("straße") || lower.contains("strasse") { return true }
        if lower.contains("weg") || lower.contains("allee") || lower.contains("platz") || lower.contains("ring") {
            return true
        }
        if lower.contains("kämpe") || lower.contains("kampe") { return true }
        return line.range(of: #"\d+\s*$"#, options: .regularExpression) != nil
    }

    private static func looksLikePersonName(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard (2...60).contains(trimmed.count) else { return false }
        guard !isFieldLabelLine(trimmed) else { return false }
        guard matchFieldAPlate(trimmed) == nil else { return false }
        guard matchGermanPostalLine(trimmed) == nil else { return false }
        guard !looksLikeStreet(trimmed) else { return false }
        guard trimmed.range(of: #"\d{2}\.\d{2}\.\d{4}"#, options: .regularExpression) == nil else { return false }
        guard trimmed.range(of: #"^\d{5}\b"#, options: .regularExpression) == nil else { return false }

        let letterCount = trimmed.filter(\.isLetter).count
        return letterCount >= max(2, trimmed.count / 2)
    }

    private static func isOwnerBlockNoise(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        if looksLikePersonName(trimmed) { return false }
        if trimmed.localizedCaseInsensitiveContains("zulassungsbescheinigung") { return true }
        if trimmed.localizedCaseInsensitiveContains("europ") { return true }
        if trimmed.localizedCaseInsensitiveContains("bundesrepublik") { return true }
        if trimmed.localizedCaseInsensitiveContains("deutschland") { return true }
        if trimmed.range(of: #"HB-[A-Z]-\d"#, options: .regularExpression) != nil { return true }
        if trimmed.range(of: #"^\d{2}/\d{4}$"#, options: .regularExpression) != nil { return true }
        if isFieldLabelLine(trimmed) { return true }
        return false
    }
}
