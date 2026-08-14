//
//  AppAccessFeature.swift
//  SVS App
//

import Foundation

enum AppAccessFeatureGroup: String, CaseIterable, Identifiable {
    case gutachten = "Gutachten"
    case home = "Mein Bereich"
    case roles = "Rollen & Zuständigkeiten"
    case lawyerPowers = "Anwaltsvollmachten"

    var id: String { rawValue }
}

enum AppAccessBooleanFeature: String, CaseIterable, Identifiable {
    case digitalAe
    case homeAreaVisible
    case dashboard
    case commission
    case documents
    case myUploads
    case requests
    case tasks
    case meeting
    case onCall
    case ordersPlacement
    case accidentSketch
    case stargutachter
    case procurementOfficer

    var id: String { rawValue }

    var group: AppAccessFeatureGroup {
        switch self {
        case .digitalAe:
            return .gutachten
        case .homeAreaVisible, .dashboard, .commission, .documents, .myUploads,
             .requests, .tasks, .meeting, .onCall, .ordersPlacement,
             .accidentSketch, .stargutachter:
            return .home
        case .procurementOfficer:
            return .roles
        }
    }

    var title: String {
        switch self {
        case .digitalAe: return "AE digital"
        case .homeAreaVisible: return "Mein Bereich"
        case .dashboard: return "Dashboard"
        case .commission: return "Prämie"
        case .documents: return "Dokumente"
        case .myUploads: return "Meine Gutachten"
        case .requests: return "Abwesenheiten"
        case .tasks: return "Aufgaben"
        case .meeting: return "Meeting"
        case .onCall: return "Bereitschaft"
        case .ordersPlacement: return "Bestellungen aufgeben"
        case .accidentSketch: return "Schadenhergang"
        case .stargutachter: return "Stargutachter"
        case .procurementOfficer: return "Zuständig für Bestellungen"
        }
    }

    var subtitle: String {
        switch self {
        case .digitalAe:
            return "Abtretungserklärung im Gutachten-Tab digital ausfüllen"
        case .homeAreaVisible:
            return "Tab „Mein Bereich“ statt nur Scanner"
        case .dashboard:
            return "Kachel Dashboard"
        case .commission:
            return "Kachel Prämie"
        case .documents:
            return "Kachel Dokumente und Vollmachten"
        case .myUploads:
            return "Kachel Meine Gutachten"
        case .requests:
            return "Kachel Abwesenheiten"
        case .tasks:
            return "Kachel Aufgaben"
        case .meeting:
            return "Kachel Meeting"
        case .onCall:
            return "Kachel Bereitschaft"
        case .ordersPlacement:
            return "Kachel Bestellungen aufgeben"
        case .accidentSketch:
            return "Kachel Schadenhergang"
        case .stargutachter:
            return "Kachel Stargutachter"
        case .procurementOfficer:
            return "Erhält und bearbeitet Bestellanfragen"
        }
    }

    var systemImage: String {
        switch self {
        case .digitalAe: return "signature"
        case .homeAreaVisible: return "person.crop.circle"
        case .dashboard: return "chart.bar.xaxis"
        case .commission: return "eurosign.circle"
        case .documents: return "folder.fill"
        case .myUploads: return "icloud.and.arrow.up.fill"
        case .requests: return "doc.text"
        case .tasks: return "checklist"
        case .meeting: return "person.3.fill"
        case .onCall: return "calendar"
        case .ordersPlacement: return "cart"
        case .accidentSketch: return "pencil.and.scribble"
        case .stargutachter: return "star.fill"
        case .procurementOfficer: return "tray.full.fill"
        }
    }

    func isEnabled(for user: User) -> Bool {
        switch self {
        case .digitalAe: return user.digitalAeAccessEnabled
        case .homeAreaVisible: return !user.scannerOnlyMode
        case .dashboard: return user.dashboardAccessEnabled
        case .commission: return user.commissionAccessEnabled
        case .documents: return user.documentsAccessEnabled
        case .myUploads: return user.myUploadsAccessEnabled
        case .requests: return user.requestsAccessEnabled
        case .tasks: return user.tasksAccessEnabled
        case .meeting: return user.meetingAccessEnabled
        case .onCall: return user.onCallAccessEnabled
        case .ordersPlacement: return user.ordersPlacementAccessEnabled
        case .accidentSketch: return user.accidentSketchAccessEnabled
        case .stargutachter: return user.stargutachterAccessEnabled
        case .procurementOfficer: return user.isProcurementOfficer
        }
    }

    func apply(enabled: Bool, to user: inout User) {
        switch self {
        case .digitalAe:
            user.digitalAeAccessEnabled = enabled
        case .homeAreaVisible:
            user.scannerOnlyMode = !enabled
        case .dashboard:
            user.dashboardAccessEnabled = enabled
        case .commission:
            user.commissionAccessEnabled = enabled
        case .documents:
            user.documentsAccessEnabled = enabled
        case .myUploads:
            user.myUploadsAccessEnabled = enabled
        case .requests:
            user.requestsAccessEnabled = enabled
        case .tasks:
            user.tasksAccessEnabled = enabled
        case .meeting:
            user.meetingAccessEnabled = enabled
        case .onCall:
            user.onCallAccessEnabled = enabled
        case .ordersPlacement:
            user.ordersPlacementAccessEnabled = enabled
        case .accidentSketch:
            user.accidentSketchAccessEnabled = enabled
        case .stargutachter:
            user.stargutachterAccessEnabled = enabled
        case .procurementOfficer:
            user.isProcurementOfficer = enabled
        }
    }

    static func features(in group: AppAccessFeatureGroup) -> [AppAccessBooleanFeature] {
        allCases.filter { $0.group == group }
    }

    static var groupedFeatures: [(group: AppAccessFeatureGroup, features: [AppAccessBooleanFeature])] {
        AppAccessFeatureGroup.allCases.map { group in
            (group, features(in: group))
        }
    }
}

struct AppAccessLawyerPowerFeature: Identifiable, Hashable {
    let document: CompanyDocument

    var id: String { document.id }

    var title: String { document.title }

    var subtitle: String? { document.subtitle }

    func isEnabled(for user: User) -> Bool {
        user.allowedLawyerPowerIds.contains(document.id)
    }

    func apply(enabled: Bool, to user: inout User) {
        if enabled {
            if !user.allowedLawyerPowerIds.contains(document.id) {
                user.allowedLawyerPowerIds.append(document.id)
            }
        } else {
            user.allowedLawyerPowerIds.removeAll { $0 == document.id }
        }
        user.allowedLawyerPowerIds.sort()
    }
}

enum AppAccessFeatureCatalog {
    static var lawyerPowerFeatures: [AppAccessLawyerPowerFeature] {
        CompanyDocumentsCatalog.lawyerPowerItems.map(AppAccessLawyerPowerFeature.init)
    }
}
