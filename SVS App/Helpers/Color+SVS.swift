//
//  Color+SVS.swift
//  SVS App
//
//  Created by Hussein Souleiman on 22.01.26.
//

import SwiftUI

// MARK: - Central color definition (single source of truth)
enum UserColor: String, CaseIterable, Identifiable {
    case blue
    case green
    case orange
    case purple
    case red
    case pink
    case yellow
    case gray
    case mint
    case teal
    case indigo

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .blue: return .blue
        case .green: return .green
        case .orange: return .orange
        case .purple: return .purple
        case .red: return .red
        case .pink: return .pink
        case .yellow: return .yellow
        case .gray: return .gray
        case .mint: return .mint
        case .teal: return .teal
        case .indigo: return .indigo
        }
    }

    var germanName: String {
        switch self {
        case .blue: return "Blau"
        case .green: return "Grün"
        case .orange: return "Orange"
        case .purple: return "Lila"
        case .red: return "Rot"
        case .pink: return "Pink"
        case .yellow: return "Gelb"
        case .gray: return "Grau"
        case .mint: return "Mint"
        case .teal: return "Türkis"
        case .indigo: return "Indigo"
        }
    }

    static func from(_ raw: String?) -> UserColor {
        let key = (raw ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        switch key {
        case "blau", "blue": return .blue
        case "grün", "gruen", "green": return .green
        case "rot", "red": return .red
        case "orange": return .orange
        case "lila", "purple": return .purple
        case "pink": return .pink
        case "gelb", "yellow": return .yellow
        case "grau", "gray", "grey": return .gray
        case "mint": return .mint
        case "teal": return .teal
        case "indigo": return .indigo
        default: return .blue
        }
    }
}

// MARK: - Compatibility helpers used across the app
extension Color {

    static func svsAccentColor(from colorName: String?) -> Color {
        UserColor.from(colorName).color
    }

    static func svsGermanColorName(from colorName: String?) -> String {
        UserColor.from(colorName).germanName
    }
}
