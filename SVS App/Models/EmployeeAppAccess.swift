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
            user.dashboardAccessEnabled = false
            user.requestsAccessEnabled = false
            user.tasksAccessEnabled = false
            user.meetingAccessEnabled = false
            user.onCallAccessEnabled = false
            user.ordersPlacementAccessEnabled = false
            user.accidentSketchAccessEnabled = false
            user.allowedLawyerPowerIds = []
        case .scannerAndWessels:
            user.scannerOnlyMode = false
            user.documentsAccessEnabled = true
            user.myUploadsAccessEnabled = false
            user.stargutachterAccessEnabled = false
            user.commissionAccessEnabled = false
            user.dashboardAccessEnabled = false
            user.requestsAccessEnabled = false
            user.tasksAccessEnabled = false
            user.meetingAccessEnabled = false
            user.onCallAccessEnabled = false
            user.ordersPlacementAccessEnabled = true
            user.accidentSketchAccessEnabled = true
            user.allowedLawyerPowerIds = ["av-wessels"]
        case .scannerUploadsAndWessels:
            user.scannerOnlyMode = false
            user.documentsAccessEnabled = true
            user.myUploadsAccessEnabled = true
            user.stargutachterAccessEnabled = false
            user.commissionAccessEnabled = false
            user.dashboardAccessEnabled = false
            user.requestsAccessEnabled = false
            user.tasksAccessEnabled = false
            user.meetingAccessEnabled = false
            user.onCallAccessEnabled = false
            user.ordersPlacementAccessEnabled = true
            user.accidentSketchAccessEnabled = true
            user.allowedLawyerPowerIds = ["av-wessels"]
        }
    }
}

enum EmployeeAppAccessSummary {
    static func chips(for user: User) -> [String] {
        UserHomeAccessSummary.chips(for: user)
    }
}

struct EmployeeAccessDraft: Equatable {
    var scannerOnlyMode: Bool = true
    var documentsAccessEnabled: Bool = false
    var myUploadsAccessEnabled: Bool = false
    var stargutachterAccessEnabled: Bool = false
    var commissionAccessEnabled: Bool = false
    var dashboardAccessEnabled: Bool = false
    var requestsAccessEnabled: Bool = false
    var tasksAccessEnabled: Bool = false
    var meetingAccessEnabled: Bool = false
    var onCallAccessEnabled: Bool = false
    var ordersPlacementAccessEnabled: Bool = true
    var accidentSketchAccessEnabled: Bool = true
    var allowedLawyerPowerIds: [String] = []

    init() {}

    init(from user: User) {
        scannerOnlyMode = user.scannerOnlyMode
        documentsAccessEnabled = user.documentsAccessEnabled
        myUploadsAccessEnabled = user.myUploadsAccessEnabled
        stargutachterAccessEnabled = user.stargutachterAccessEnabled
        commissionAccessEnabled = user.commissionAccessEnabled
        dashboardAccessEnabled = user.dashboardAccessEnabled
        requestsAccessEnabled = user.requestsAccessEnabled
        tasksAccessEnabled = user.tasksAccessEnabled
        meetingAccessEnabled = user.meetingAccessEnabled
        onCallAccessEnabled = user.onCallAccessEnabled
        ordersPlacementAccessEnabled = user.ordersPlacementAccessEnabled
        accidentSketchAccessEnabled = user.accidentSketchAccessEnabled
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
        updated.dashboardAccessEnabled = dashboardAccessEnabled
        updated.requestsAccessEnabled = requestsAccessEnabled
        updated.tasksAccessEnabled = tasksAccessEnabled
        updated.meetingAccessEnabled = meetingAccessEnabled
        updated.onCallAccessEnabled = onCallAccessEnabled
        updated.ordersPlacementAccessEnabled = ordersPlacementAccessEnabled
        updated.accidentSketchAccessEnabled = accidentSketchAccessEnabled
        updated.allowedLawyerPowerIds = allowedLawyerPowerIds
        return updated
    }
}

// MARK: - Home tile visibility

struct HomeTileAccess {
    let user: User

    var showsDashboard: Bool { user.dashboardAccessEnabled }
    var showsCommission: Bool { user.commissionAccessEnabled }
    var showsDocuments: Bool { user.documentsAccessEnabled }
    var showsMyUploads: Bool { user.myUploadsAccessEnabled }
    var showsStargutachter: Bool { user.stargutachterAccessEnabled }
    var showsRequests: Bool { user.requestsAccessEnabled }
    var showsTasks: Bool { user.tasksAccessEnabled }
    var showsMeeting: Bool { user.meetingAccessEnabled }
    var showsOnCall: Bool { user.onCallAccessEnabled }
    var showsOrdersPlacement: Bool { user.ordersPlacementAccessEnabled }
    var showsAccidentSketch: Bool { user.accidentSketchAccessEnabled }

    var showsProcurementInbox: Bool {
        user.role == .admin || user.isProcurementOfficer
    }

    var procurementInboxShowsAllOrders: Bool {
        user.role == .admin
    }
}

struct HomeTileAccessDefaults {
    var dashboardAccessEnabled: Bool
    var commissionAccessEnabled: Bool
    var documentsAccessEnabled: Bool
    var myUploadsAccessEnabled: Bool
    var stargutachterAccessEnabled: Bool
    var requestsAccessEnabled: Bool
    var tasksAccessEnabled: Bool
    var meetingAccessEnabled: Bool
    var onCallAccessEnabled: Bool
    var ordersPlacementAccessEnabled: Bool
    var accidentSketchAccessEnabled: Bool
    var scannerOnlyMode: Bool

    static func forRole(_ role: UserRole) -> HomeTileAccessDefaults {
        switch role {
        case .employee:
            return HomeTileAccessDefaults(
                dashboardAccessEnabled: false,
                commissionAccessEnabled: false,
                documentsAccessEnabled: false,
                myUploadsAccessEnabled: false,
                stargutachterAccessEnabled: false,
                requestsAccessEnabled: false,
                tasksAccessEnabled: false,
                meetingAccessEnabled: false,
                onCallAccessEnabled: false,
                ordersPlacementAccessEnabled: true,
                accidentSketchAccessEnabled: true,
                scannerOnlyMode: true
            )
        case .admin, .expert:
            return HomeTileAccessDefaults(
                dashboardAccessEnabled: true,
                commissionAccessEnabled: true,
                documentsAccessEnabled: true,
                myUploadsAccessEnabled: true,
                stargutachterAccessEnabled: true,
                requestsAccessEnabled: true,
                tasksAccessEnabled: true,
                meetingAccessEnabled: true,
                onCallAccessEnabled: true,
                ordersPlacementAccessEnabled: true,
                accidentSketchAccessEnabled: true,
                scannerOnlyMode: false
            )
        }
    }

    func apply(to user: inout User) {
        user.dashboardAccessEnabled = dashboardAccessEnabled
        user.commissionAccessEnabled = commissionAccessEnabled
        user.documentsAccessEnabled = documentsAccessEnabled
        user.myUploadsAccessEnabled = myUploadsAccessEnabled
        user.stargutachterAccessEnabled = stargutachterAccessEnabled
        user.requestsAccessEnabled = requestsAccessEnabled
        user.tasksAccessEnabled = tasksAccessEnabled
        user.meetingAccessEnabled = meetingAccessEnabled
        user.onCallAccessEnabled = onCallAccessEnabled
        user.ordersPlacementAccessEnabled = ordersPlacementAccessEnabled
        user.accidentSketchAccessEnabled = accidentSketchAccessEnabled
        user.scannerOnlyMode = scannerOnlyMode
    }
}

enum UserHomeAccessSummary {
    static func chips(for user: User) -> [String] {
        let access = HomeTileAccess(user: user)
        var chips: [String] = []

        if user.role == .employee, user.scannerOnlyMode {
            chips.append("Nur Scanner")
        }
        if access.showsDashboard { chips.append("Dashboard") }
        if access.showsCommission { chips.append("Prämie") }
        if access.showsDocuments { chips.append("Dokumente") }
        if access.showsMyUploads { chips.append("Uploads") }
        if access.showsStargutachter { chips.append("Stargutachter") }
        if access.showsRequests { chips.append("Abwesenheiten") }
        if access.showsTasks { chips.append("Aufgaben") }
        if access.showsMeeting { chips.append("Meeting") }
        if access.showsOnCall { chips.append("Bereitschaft") }
        if access.showsOrdersPlacement { chips.append("Bestellen") }
        if access.showsAccidentSketch { chips.append("Schadenhergang") }
        if access.showsProcurementInbox { chips.append("Bestell-Inbox") }

        for document in CompanyDocumentsCatalog.lawyerPowerItems
        where user.allowedLawyerPowerIds.contains(document.id) {
            chips.append(document.title)
        }

        if chips.isEmpty {
            chips.append(user.role == .employee ? "Kein Zugang" : "Keine Kacheln")
        }
        return chips
    }
}
