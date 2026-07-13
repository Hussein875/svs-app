//
//  GermanLicensePlateFormatter.swift
//  SVS App
//

import Foundation

/// Formatiert deutsche Kennzeichen im üblichen Stil: `HB-AB 1234`
/// (Ortskürzel-Buchstaben Ziffern).
enum GermanLicensePlateFormatter {
    /// Beispiel für Platzhalter und Hinweise in der UI.
    static let displayExample = "HB-AB 1234"

    static func format(_ input: String) -> String {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "" }

        let alphanumeric = trimmed
            .uppercased()
            .filter { $0.isLetter || $0.isNumber }
        guard !alphanumeric.isEmpty else {
            return normalizeSpacing(trimmed)
        }

        let digitCount = alphanumeric.reversed().prefix(while: \.isNumber).count

        // Noch keine Ziffern — Großschreibung/Abstände, Format nicht erzwingen.
        if digitCount == 0 {
            return normalizeSpacing(trimmed)
        }

        guard (1...4).contains(digitCount) else {
            return normalizeSpacing(trimmed)
        }

        let digits = String(alphanumeric.suffix(digitCount))
        let letters = String(alphanumeric.dropLast(digitCount))
        guard !letters.isEmpty, letters.allSatisfy(\.isLetter),
              let split = splitLicenseLetters(letters) else {
            return normalizeSpacing(trimmed)
        }

        return "\(split.city)-\(split.series) \(digits)"
    }

    private static func normalizeSpacing(_ input: String) -> String {
        input
            .uppercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Aufteilung der Buchstaben vor den Ziffern (Ortskürzel + Erkennungsbuchstaben).
    private static func splitLicenseLetters(_ letters: String) -> (city: String, series: String)? {
        let chars = Array(letters)
        let count = chars.count
        guard count >= 2 else { return nil }

        switch count {
        case 2:
            return (String(chars[0]), String(chars[1]))
        case 3:
            return (String(chars[0...1]), String(chars[2]))
        case 4:
            return (String(chars[0...1]), String(chars[2...3]))
        case 5:
            return (String(chars[0...2]), String(chars[3...4]))
        default:
            return (String(chars[0...2]), String(chars[3...]))
        }
    }
}
