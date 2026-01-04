//
//  User.swift
//  SVS App
//
//  Created by Hussein Souleiman on 23.12.25.
//
import Foundation
import SwiftUI

struct User: Identifiable, Hashable, Codable {
    /// Firebase Auth UID für echte Nutzer. Für Einladungen (vor erstem Login): "invite:<email>"
    let id: String
    var name: String
    var role: UserRole
    var colorName: String
    var annualLeaveDays: Int
    var email: String

    var color: Color {
        switch colorName {
        case "blue": return .blue
        case "green": return .green
        case "orange": return .orange
        case "purple": return .purple
        case "red": return .red
        case "pink": return .pink
        case "teal": return .teal
        case "indigo": return .indigo
        case "yellow": return .yellow
        default: return .gray
        }
    }
}
