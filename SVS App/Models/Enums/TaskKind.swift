//
//  TaskKind.swift
//  SVS App
//

import Foundation

enum TaskKind: String, Codable, CaseIterable, Identifiable {
    case general
    case order

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "Aufgabe"
        case .order: return "Bestellung"
        }
    }

    var listTitle: String {
        switch self {
        case .general: return "Aufgaben"
        case .order: return "Bestellungen"
        }
    }
}

enum TaskProcurement {
    /// Zuständige für Büromaterial-Bestellungen (z. B. Yasmin/Ysmin).
    static func resolveOfficer(in users: [User]) -> User? {
        if let flagged = users.first(where: { $0.isProcurementOfficer }) {
            return flagged
        }

        return users.first { user in
            let normalized = user.name
                .folding(options: .diacriticInsensitive, locale: Locale(identifier: "de_DE"))
                .lowercased()
            return normalized.contains("ysmin")
                || normalized.contains("yasmin")
                || normalized.contains("jasmin")
        }
    }
}
