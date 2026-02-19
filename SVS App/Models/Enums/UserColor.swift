//
//  UserColor.swift
//  SVS App
//
//  Created by Codex on 10.02.26.
//

import SwiftUI

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
    case brown

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
        case .brown: return .brown
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
        case .brown: return "Braun"
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
        case "braun", "brown": return .brown
        default: return .blue
        }
    }
}
