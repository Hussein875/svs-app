//
//  EmployeeAppAccess.swift
//  SVS App
//

import Foundation

/// Vorlagen und Hilfen für den App-Zugang externer Mitarbeiter.
enum EmployeeAppAccessTemplate: String, CaseIterable, Identifiable {
    case allOff = "Alles aus (nur Scanner)"
    case scannerAndWessels = "Scanner + Wessels"
    case scannerUploadsAndWessels = "Scanner, Uploads + Wessels"

    var id: String { rawValue }

    func apply(to user: inout User) {
        switch self {
        case .allOff:
            user.scannerOnlyMode = true
            user.documentsAccessEnabled = false
            user.myUploadsAccessEnabled = false
            user.stargutachterAccessEnabled = false
            user.commissionAccessEnabled = false
            user.allowedLawyerPowerIds = []
        case .scannerAndWessels:
            user.scannerOnlyMode = false
            user.documentsAccessEnabled = true
            user.myUploadsAccessEnabled = false
            user.stargutachterAccessEnabled = false
            user.commissionAccessEnabled = false
            user.allowedLawyerPowerIds = ["av-wessels"]
        case .scannerUploadsAndWessels:
            user.scannerOnlyMode = false
            user.documentsAccessEnabled = true
            user.myUploadsAccessEnabled = true
            user.stargutachterAccessEnabled = false
            user.commissionAccessEnabled = false
            user.allowedLawyerPowerIds = ["av-wessels"]
        }
    }

    static func defaultAccessFields() -> (
        scannerOnlyMode: Bool,
        documentsAccessEnabled: Bool,
        myUploadsAccessEnabled: Bool,
        stargutachterAccessEnabled: Bool,
        commissionAccessEnabled: Bool,
        allowedLawyerPowerIds: [String]
    ) {
        var user = User(
            id: "template",
            name: "",
            role: .employee,
            colorName: "blue",
            annualLeaveDays: 0,
            email: ""
        )
        EmployeeAppAccessTemplate.allOff.apply(to: &user)
        return (
            user.scannerOnlyMode,
            user.documentsAccessEnabled,
            user.myUploadsAccessEnabled,
            user.stargutachterAccessEnabled,
            user.commissionAccessEnabled,
            user.allowedLawyerPowerIds
        )
    }
}

enum EmployeeAppAccessSummary {
    static func chips(for user: User) -> [String] {
        guard user.role == .employee else { return [] }

        var chips: [String] = []
        if user.scannerOnlyMode {
            chips.append("Nur Scanner")
        }
        if user.documentsAccessEnabled {
            chips.append("Dokumente")
        }
        if user.myUploadsAccessEnabled {
            chips.append("Uploads")
        }
        if user.stargutachterAccessEnabled {
            chips.append("Stargutachter")
        }
        if user.commissionAccessEnabled {
            chips.append("Prämie")
        }

        for document in CompanyDocumentsCatalog.lawyerPowerItems
        where user.allowedLawyerPowerIds.contains(document.id) {
            chips.append(document.title)
        }

        if chips.isEmpty {
            chips.append("Kein Zugang")
        }
        return chips
    }
}

struct EmployeeAccessDraft: Equatable {
    var scannerOnlyMode: Bool = true
    var documentsAccessEnabled: Bool = false
    var myUploadsAccessEnabled: Bool = false
    var stargutachterAccessEnabled: Bool = false
    var commissionAccessEnabled: Bool = false
    var allowedLawyerPowerIds: [String] = []

    init() {}

    init(from user: User) {
        scannerOnlyMode = user.scannerOnlyMode
        documentsAccessEnabled = user.documentsAccessEnabled
        myUploadsAccessEnabled = user.myUploadsAccessEnabled
        stargutachterAccessEnabled = user.stargutachterAccessEnabled
        commissionAccessEnabled = user.commissionAccessEnabled
        allowedLawyerPowerIds = user.allowedLawyerPowerIds
    }

    mutating func apply(template: EmployeeAppAccessTemplate) {
        var user = User(
            id: "draft",
            name: "",
            role: .employee,
            colorName: "blue",
            annualLeaveDays: 0,
            email: ""
        )
        template.apply(to: &user)
        self = EmployeeAccessDraft(from: user)
    }

    func merged(into user: User) -> User {
        var updated = user
        updated.scannerOnlyMode = scannerOnlyMode
        updated.documentsAccessEnabled = documentsAccessEnabled
        updated.myUploadsAccessEnabled = myUploadsAccessEnabled
        updated.stargutachterAccessEnabled = stargutachterAccessEnabled
        updated.commissionAccessEnabled = commissionAccessEnabled
        updated.allowedLawyerPowerIds = allowedLawyerPowerIds
        return updated
    }
}
