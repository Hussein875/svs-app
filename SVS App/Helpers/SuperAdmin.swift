//
//  SuperAdmin.swift
//  SVS App
//

import Foundation

enum SuperAdmin {
    static let email = "hussein.souleiman@sv-souleiman.de"
    static let displayTitle = "Superadmin"

    static func isSuperAdmin(email rawEmail: String?) -> Bool {
        let normalized = rawEmail?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""
        return normalized == email
    }

    static func isSuperAdmin(user: User?) -> Bool {
        guard let user else { return false }
        return isSuperAdmin(email: user.email)
    }

    static func displayRoleTitle(for user: User) -> String {
        if isSuperAdmin(user: user) {
            return displayTitle
        }
        return roleLabel(for: user.role)
    }
}
