//
//  ScannerWidgetStore.swift
//  SVS App
//

import Foundation
import WidgetKit

enum ScannerWidgetStore {
    static let appGroupID = "group.de.svs.SVS-App"
    static let widgetKind = "GutachtenNumberWidget"

    private enum Key {
        static let numberText = "scanner.widget.numberText"
        static let statusText = "scanner.widget.statusText"
        static let isReserved = "scanner.widget.isReserved"
        static let updatedAt = "scanner.widget.updatedAt"
    }

    private static var didBootstrapThisSession = false

    struct Snapshot: Equatable {
        let numberText: String
        let statusText: String
        let updatedAt: Date?
    }

    private static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupID)
    }

    static func isReservedActive() -> Bool {
        sharedDefaults?.bool(forKey: Key.isReserved) ?? false
    }

    static func bootstrapForSessionIfNeeded() {
        guard !didBootstrapThisSession else { return }
        didBootstrapThisSession = true
        // Nach App-Neustart gibt es keine aktive Scanner-Session mehr.
        endReservation()
        requestWidgetRefresh()
    }

    static func requestWidgetRefresh() {
        WidgetCenter.shared.reloadTimelines(ofKind: widgetKind)
    }

    static func endReservation() {
        sharedDefaults?.set(false, forKey: Key.isReserved)
    }

    static func publishAvailable(number: Int, year2: String) {
        guard !isReservedActive() else { return }
        publish(number: number, year2: year2, isReserved: false)
    }

    static func publish(number: Int, year2: String, isReserved: Bool) {
        publish(
            numberText: "\(number)/\(year2)",
            statusText: isReserved ? "Reserviert" : "Verfügbar",
            isReserved: isReserved
        )
    }

    static func publish(numberText: String, statusText: String, isReserved: Bool) {
        guard let defaults = sharedDefaults else { return }
        defaults.set(numberText, forKey: Key.numberText)
        defaults.set(statusText, forKey: Key.statusText)
        defaults.set(isReserved, forKey: Key.isReserved)
        defaults.set(Date().timeIntervalSince1970, forKey: Key.updatedAt)
        requestWidgetRefresh()
        WatchScannerNumberSync.shared.send(numberText: numberText, statusText: statusText)
    }

    static func loadSnapshot() -> Snapshot {
        guard let defaults = sharedDefaults else {
            return placeholderSnapshot()
        }

        let number = defaults.string(forKey: Key.numberText)
        let status = defaults.string(forKey: Key.statusText)
        let timestamp = defaults.double(forKey: Key.updatedAt)
        let updatedAt = timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : nil

        return Snapshot(
            numberText: number?.isEmpty == false ? number! : placeholderNumberText(),
            statusText: status?.isEmpty == false ? status! : "Öffne SVS Office",
            updatedAt: updatedAt
        )
    }

    static func clear() {
        guard let defaults = sharedDefaults else { return }
        defaults.removeObject(forKey: Key.numberText)
        defaults.removeObject(forKey: Key.statusText)
        defaults.removeObject(forKey: Key.isReserved)
        defaults.removeObject(forKey: Key.updatedAt)
        requestWidgetRefresh()
        let placeholder = placeholderNumberText()
        WatchScannerNumberSync.shared.send(numberText: placeholder, statusText: "Öffne SVS Office")
    }

    private static func placeholderSnapshot() -> Snapshot {
        Snapshot(
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
