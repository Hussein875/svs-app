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
    var shortCode: String? = nil
    /// Nur für externe Mitarbeiter relevant: Admin kann Prämie-Kachel deaktivieren.
    var commissionAccessEnabled: Bool = false
    /// Nur für externe Mitarbeiter relevant: Admin kann Stargutachter-Kachel deaktivieren.
    var stargutachterAccessEnabled: Bool = false
    /// Kachel „Dokumente“ in Mein Bereich.
    var documentsAccessEnabled: Bool = false
    /// Kachel „Meine Uploads“ in Mein Bereich.
    var myUploadsAccessEnabled: Bool = false
    /// Versteckt „Mein Bereich“ – nur Scanner und Menü.
    var scannerOnlyMode: Bool = true
    /// Opt-in-Liste der sichtbaren Anwaltsvollmachten (leer = keine).
    var allowedLawyerPowerIds: [String] = []

    var color: Color {
        Color.svsAccentColor(from: colorName)
    }

    func canViewLawyerPower(id: String) -> Bool {
        if role == .admin || role == .expert { return true }
        return allowedLawyerPowerIds.contains(id)
    }

    mutating func applyDefaultEmployeeAccess() {
        EmployeeAppAccessTemplate.allOff.apply(to: &self)
    }
}
