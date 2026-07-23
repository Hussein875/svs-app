//
//  VermittlungMode.swift
//  SVS App
//

import Foundation

/// Steuert, wie Vermittlungen beim Gutachten-Upload erfasst werden.
enum VermittlungMode: String, Codable, CaseIterable, Identifiable {
    /// Keine Vermittlungserfassung.
    case off
    /// Checkbox im Scanner — Nutzer setzt Haken bei eigener Vermittlung.
    case manual
    /// Jeder Upload zählt automatisch als Vermittlung des Uploaders (ohne Checkbox).
    case automatic

    var id: String { rawValue }

    var germanTitle: String {
        switch self {
        case .off:
            return "Aus"
        case .manual:
            return "Checkbox beim Upload"
        case .automatic:
            return "Automatisch (eigene Fälle)"
        }
    }

    var germanDescription: String {
        switch self {
        case .off:
            return "Keine Vermittlung wird erfasst."
        case .manual:
            return "Nutzer markiert eigene Vermittlungen per Haken im Scanner."
        case .automatic:
            return "Jeder Upload wird intern als eigene Vermittlung gezählt — ohne Haken."
        }
    }
}
