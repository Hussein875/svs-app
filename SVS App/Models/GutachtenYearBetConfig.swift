//
//  GutachtenYearBetConfig.swift
//  SVS App
//

import Foundation

enum GutachtenYearBetConfig {
    /// Standard-Wette-Jahr, falls in Firestore noch keins gesetzt ist.
    static let defaultYear = 2026

    /// Erstes Jahr mit Wette-Daten — nicht weiter zurück wechseln.
    static let firstBetYear = 2025

    static let settingsDocumentId = "_settings"

    static var currentCalendarYear: Int {
        Calendar.current.component(.year, from: Date())
    }

    /// Jahrwechsel erst ab dem Kalenderjahr nach `defaultYear` (ab 2027).
    static var canSelectMultipleYears: Bool {
        currentCalendarYear > defaultYear
    }

    static var minimumSelectableYear: Int { firstBetYear }

    static var maximumSelectableYear: Int { currentCalendarYear }

    static func clampYear(_ year: Int) -> Int {
        max(minimumSelectableYear, min(year, maximumSelectableYear))
    }

    static var displayYear: Int {
        canSelectMultipleYears ? clampYear(currentCalendarYear) : defaultYear
    }
}

enum GutachtenYearBetFormatters {
    /// Gutachten-Nummern mit Tausenderpunkt (ab 10.000).
    static func gutachtenNumber(_ value: Int) -> String {
        if value < 10_000 {
            return "\(value)"
        }
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = "."
        formatter.usesGroupingSeparator = true
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)"
    }

    /// Kalenderjahr — nie mit Tausendertrennzeichen.
    static func year(_ value: Int) -> String {
        "\(value)"
    }
}
