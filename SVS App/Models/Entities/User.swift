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
    var birthday: Date? = nil
    var pushNotificationsEnabled: Bool = true
    var receiveAdminPushes: Bool = false
    var meetingSchedulePushEnabled: Bool = true

    var color: Color {
        Color.svsAccentColor(from: colorName)
    }
}
