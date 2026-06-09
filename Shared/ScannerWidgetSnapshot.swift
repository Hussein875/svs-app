//
//  ScannerWidgetSnapshot.swift
//  Shared between app, widgets, and watch.
//

import Foundation

enum ScannerWidgetSnapshot {
    static let appGroupID = "group.de.svs.SVS-App"
    static let widgetKind = "GutachtenNumberWidget"
    static let watchWidgetKind = "GutachtenNumberWidget"

    private enum Key {
        static let numberText = "scanner.widget.numberText"
        static let statusText = "scanner.widget.statusText"
        static let updatedAt = "scanner.widget.updatedAt"
    }

    struct Data: Equatable {
        let numberText: String
        let statusText: String
        let updatedAt: Date?
    }

    static func load() -> Data {
        guard let defaults = UserDefaults(suiteName: appGroupID) else {
            return placeholder()
        }

        let number = defaults.string(forKey: Key.numberText)
        let status = defaults.string(forKey: Key.statusText)
        let timestamp = defaults.double(forKey: Key.updatedAt)
        let updatedAt = timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : nil

        return Data(
            numberText: number?.isEmpty == false ? number! : placeholderNumberText(),
            statusText: status?.isEmpty == false ? status! : "Öffne SVS Office",
            updatedAt: updatedAt
        )
    }

    static func save(numberText: String, statusText: String, updatedAt: Date = Date()) {
        guard let defaults = UserDefaults(suiteName: appGroupID) else { return }
        defaults.set(numberText, forKey: Key.numberText)
        defaults.set(statusText, forKey: Key.statusText)
        defaults.set(updatedAt.timeIntervalSince1970, forKey: Key.updatedAt)
    }

    private static func placeholder() -> Data {
        Data(
            numberText: placeholderNumberText(),
            statusText: "Öffne SVS Office",
            updatedAt: nil
        )
    }

    private static func placeholderNumberText() -> String {
        let year = Calendar.current.component(.year, from: Date())
        let year2 = String(format: "%02d", year % 100)
        return "–/\(year2)"
    }
}
