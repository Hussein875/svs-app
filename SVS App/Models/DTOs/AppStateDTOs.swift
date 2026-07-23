//
//  AppStateDTOs.swift
//  SVS App
//
//  Extracted DTOs and profile model from AppState.swift for readability.
//

import Foundation
import FirebaseFirestore

struct UserProfile: Codable {
    var name: String
    var roleRaw: String
    var colorName: String
    var annualLeaveDays: Int
    var email: String
    var birthday: Date?
    var shortCode: String?
    var pushEnabled: Bool
    var receiveAdminPushes: Bool
    var meetingSchedulePushEnabled: Bool
    var commissionAccessEnabled: Bool
    var stargutachterAccessEnabled: Bool
    var documentsAccessEnabled: Bool
    var myUploadsAccessEnabled: Bool
    var scannerOnlyMode: Bool
    var isProcurementOfficer: Bool
    var dashboardAccessEnabled: Bool
    var requestsAccessEnabled: Bool
    var tasksAccessEnabled: Bool
    var meetingAccessEnabled: Bool
    var onCallAccessEnabled: Bool
    var ordersPlacementAccessEnabled: Bool
    var accidentSketchAccessEnabled: Bool
    var allowedLawyerPowerIds: [String]
    var vermittlungMode: VermittlungMode

    init(name: String,
         roleRaw: String,
         colorName: String,
         annualLeaveDays: Int,
         email: String,
         birthday: Date? = nil,
         shortCode: String? = nil,
         pushEnabled: Bool = true,
         receiveAdminPushes: Bool = false,
         meetingSchedulePushEnabled: Bool = true,
         commissionAccessEnabled: Bool = false,
         stargutachterAccessEnabled: Bool = false,
         documentsAccessEnabled: Bool = false,
         myUploadsAccessEnabled: Bool = false,
         scannerOnlyMode: Bool = true,
         isProcurementOfficer: Bool = false,
         dashboardAccessEnabled: Bool = true,
         requestsAccessEnabled: Bool = true,
         tasksAccessEnabled: Bool = true,
         meetingAccessEnabled: Bool = true,
         onCallAccessEnabled: Bool = true,
         ordersPlacementAccessEnabled: Bool = true,
         accidentSketchAccessEnabled: Bool = true,
         allowedLawyerPowerIds: [String] = [],
         vermittlungMode: VermittlungMode = .off) {
        self.name = name
        self.roleRaw = roleRaw
        self.colorName = colorName
        self.annualLeaveDays = annualLeaveDays
        self.email = email
        self.birthday = birthday
        self.shortCode = shortCode
        self.pushEnabled = pushEnabled
        self.receiveAdminPushes = receiveAdminPushes
        self.meetingSchedulePushEnabled = meetingSchedulePushEnabled
        self.commissionAccessEnabled = commissionAccessEnabled
        self.stargutachterAccessEnabled = stargutachterAccessEnabled
        self.documentsAccessEnabled = documentsAccessEnabled
        self.myUploadsAccessEnabled = myUploadsAccessEnabled
        self.scannerOnlyMode = scannerOnlyMode
        self.isProcurementOfficer = isProcurementOfficer
        self.dashboardAccessEnabled = dashboardAccessEnabled
        self.requestsAccessEnabled = requestsAccessEnabled
        self.tasksAccessEnabled = tasksAccessEnabled
        self.meetingAccessEnabled = meetingAccessEnabled
        self.onCallAccessEnabled = onCallAccessEnabled
        self.ordersPlacementAccessEnabled = ordersPlacementAccessEnabled
        self.accidentSketchAccessEnabled = accidentSketchAccessEnabled
        self.allowedLawyerPowerIds = allowedLawyerPowerIds
        self.vermittlungMode = vermittlungMode
    }

    init(from user: User) {
        self.name = user.name
        self.roleRaw = user.role.rawValue
        self.colorName = user.colorName
        self.annualLeaveDays = user.annualLeaveDays
        self.email = user.email
        self.birthday = user.birthday
        self.shortCode = user.shortCode
        self.pushEnabled = user.pushNotificationsEnabled
        self.receiveAdminPushes = user.receiveAdminPushes
        self.meetingSchedulePushEnabled = user.meetingSchedulePushEnabled
        self.commissionAccessEnabled = user.commissionAccessEnabled
        self.stargutachterAccessEnabled = user.stargutachterAccessEnabled
        self.documentsAccessEnabled = user.documentsAccessEnabled
        self.myUploadsAccessEnabled = user.myUploadsAccessEnabled
        self.scannerOnlyMode = user.scannerOnlyMode
        self.isProcurementOfficer = user.isProcurementOfficer
        self.dashboardAccessEnabled = user.dashboardAccessEnabled
        self.requestsAccessEnabled = user.requestsAccessEnabled
        self.tasksAccessEnabled = user.tasksAccessEnabled
        self.meetingAccessEnabled = user.meetingAccessEnabled
        self.onCallAccessEnabled = user.onCallAccessEnabled
        self.ordersPlacementAccessEnabled = user.ordersPlacementAccessEnabled
        self.accidentSketchAccessEnabled = user.accidentSketchAccessEnabled
        self.allowedLawyerPowerIds = user.allowedLawyerPowerIds
        self.vermittlungMode = user.vermittlungMode
    }

    init?(from data: [String: Any]) {
        guard
            let name = data["name"] as? String,
            let roleRaw = data["roleRaw"] as? String,
            let colorName = data["colorName"] as? String,
            let annualLeaveDays = data["annualLeaveDays"] as? Int,
            let email = data["email"] as? String
        else { return nil }

        self.name = name
        self.roleRaw = roleRaw
        self.colorName = colorName
        self.annualLeaveDays = annualLeaveDays
        self.email = email
        self.shortCode = (data["shortCode"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.pushEnabled = (data["pushEnabled"] as? Bool) ?? true
        self.receiveAdminPushes = (data["receiveAdminPushes"] as? Bool) ?? false
        self.meetingSchedulePushEnabled =
            (data["meetingSchedulePushEnabled"] as? Bool) ?? true
        let role = UserRole(rawValue: roleRaw) ?? .employee
        let defaults = HomeTileAccessDefaults.forRole(role)
        self.commissionAccessEnabled =
            (data["commissionAccessEnabled"] as? Bool) ?? defaults.commissionAccessEnabled
        self.stargutachterAccessEnabled =
            (data["stargutachterAccessEnabled"] as? Bool) ?? defaults.stargutachterAccessEnabled
        self.documentsAccessEnabled =
            (data["documentsAccessEnabled"] as? Bool) ?? defaults.documentsAccessEnabled
        self.myUploadsAccessEnabled =
            (data["myUploadsAccessEnabled"] as? Bool) ?? defaults.myUploadsAccessEnabled
        self.scannerOnlyMode =
            (data["scannerOnlyMode"] as? Bool) ?? defaults.scannerOnlyMode
        self.isProcurementOfficer =
            (data["isProcurementOfficer"] as? Bool) ?? false
        self.dashboardAccessEnabled =
            (data["dashboardAccessEnabled"] as? Bool) ?? defaults.dashboardAccessEnabled
        self.requestsAccessEnabled =
            (data["requestsAccessEnabled"] as? Bool) ?? defaults.requestsAccessEnabled
        self.tasksAccessEnabled =
            (data["tasksAccessEnabled"] as? Bool) ?? defaults.tasksAccessEnabled
        self.meetingAccessEnabled =
            (data["meetingAccessEnabled"] as? Bool) ?? defaults.meetingAccessEnabled
        self.onCallAccessEnabled =
            (data["onCallAccessEnabled"] as? Bool) ?? defaults.onCallAccessEnabled
        self.ordersPlacementAccessEnabled =
            (data["ordersPlacementAccessEnabled"] as? Bool) ?? defaults.ordersPlacementAccessEnabled
        self.accidentSketchAccessEnabled =
            (data["accidentSketchAccessEnabled"] as? Bool) ?? defaults.accidentSketchAccessEnabled
        self.allowedLawyerPowerIds = (data["allowedLawyerPowerIds"] as? [String]) ?? []
        if let modeRaw = data["vermittlungModeRaw"] as? String,
           let mode = VermittlungMode(rawValue: modeRaw) {
            self.vermittlungMode = mode
        } else if (data["vermittlungCheckboxEnabled"] as? Bool) == true {
            self.vermittlungMode = .manual
        } else {
            self.vermittlungMode = defaults.vermittlungMode
        }
        if let ts = data["birthday"] as? Timestamp {
            self.birthday = ts.dateValue()
        } else if let d = data["birthday"] as? Date {
            self.birthday = d
        } else if let s = data["birthday"] as? String {
            let iso = ISO8601DateFormatter()
            self.birthday = iso.date(from: s)
        } else {
            self.birthday = nil
        }
    }

    func toDictionary() -> [String: Any] {
        var dict: [String: Any] = [
            "name": name,
            "roleRaw": roleRaw,
            "colorName": colorName,
            "annualLeaveDays": annualLeaveDays,
            "email": email,
            "pushEnabled": pushEnabled,
            "commissionAccessEnabled": commissionAccessEnabled,
            "stargutachterAccessEnabled": stargutachterAccessEnabled,
            "documentsAccessEnabled": documentsAccessEnabled,
            "myUploadsAccessEnabled": myUploadsAccessEnabled,
            "scannerOnlyMode": scannerOnlyMode,
            "isProcurementOfficer": isProcurementOfficer,
            "dashboardAccessEnabled": dashboardAccessEnabled,
            "requestsAccessEnabled": requestsAccessEnabled,
            "tasksAccessEnabled": tasksAccessEnabled,
            "meetingAccessEnabled": meetingAccessEnabled,
            "onCallAccessEnabled": onCallAccessEnabled,
            "ordersPlacementAccessEnabled": ordersPlacementAccessEnabled,
            "accidentSketchAccessEnabled": accidentSketchAccessEnabled,
            "allowedLawyerPowerIds": allowedLawyerPowerIds,
            "vermittlungModeRaw": vermittlungMode.rawValue
        ]
        // Keep this dictionary compatible with current Firestore rules.
        // Admin push routing preference is written by callable function.
        if let birthday {
            dict["birthday"] = Timestamp(date: birthday)
        }
        if let shortCode, !shortCode.isEmpty {
            dict["shortCode"] = shortCode
        }
        return dict
    }

    func toUser(id: String) -> User {
        User(
            id: id,
            name: name,
            role: UserRole(rawValue: roleRaw) ?? .employee,
            colorName: colorName,
            annualLeaveDays: annualLeaveDays,
            email: email,
            birthday: birthday,
            pushNotificationsEnabled: pushEnabled,
            receiveAdminPushes: receiveAdminPushes,
            meetingSchedulePushEnabled: meetingSchedulePushEnabled,
            shortCode: shortCode,
            commissionAccessEnabled: commissionAccessEnabled,
            stargutachterAccessEnabled: stargutachterAccessEnabled,
            documentsAccessEnabled: documentsAccessEnabled,
            myUploadsAccessEnabled: myUploadsAccessEnabled,
            dashboardAccessEnabled: dashboardAccessEnabled,
            requestsAccessEnabled: requestsAccessEnabled,
            tasksAccessEnabled: tasksAccessEnabled,
            meetingAccessEnabled: meetingAccessEnabled,
            onCallAccessEnabled: onCallAccessEnabled,
            ordersPlacementAccessEnabled: ordersPlacementAccessEnabled,
            accidentSketchAccessEnabled: accidentSketchAccessEnabled,
            isProcurementOfficer: isProcurementOfficer,
            scannerOnlyMode: scannerOnlyMode,
            allowedLawyerPowerIds: allowedLawyerPowerIds,
            vermittlungMode: vermittlungMode
        )
    }
}
// MARK: - Firestore Commissions DTO

struct CommissionDTO {
    var id: String
    var recipientName: String
    var recipientAddress: String
    var amount: Double
    var payoutMethodRaw: String
    var payoutTarget: String
    var statusRaw: String
    var createdAt: Timestamp
    var createdByUid: String
    var paidAt: Timestamp?
    var paidByUid: String?

    init?(id: String, data: [String: Any]) {
        // Support both the legacy schema (recipientName/recipientAddress/...) and
        // the newer "provision" schema (recommenderName, recommenderStreet, payoutIban, etc.).

        // --- id
        // Prefer token if it is a UUID string (used by the new provision flow);
        // otherwise fall back to the document id.
        let token = data["token"] as? String
        if let token, !token.isEmpty {
            self.id = token
        } else {
            self.id = id
        }

        // --- createdAt / createdByUid (required)
        guard
            let createdAt = data["createdAt"] as? Timestamp,
            let createdByUid = data["createdByUid"] as? String
        else { return nil }
        self.createdAt = createdAt
        self.createdByUid = createdByUid

        // --- status
        let statusRaw = (data["statusRaw"] as? String) ?? (data["status"] as? String) ?? "submitted"
        self.statusRaw = statusRaw

        // --- payout method
        let payoutMethodRaw = (data["payoutMethodRaw"] as? String) ?? (data["payoutMethod"] as? String) ?? "paypal"
        self.payoutMethodRaw = payoutMethodRaw

        // --- amount
        if let amount = data["amount"] as? Double {
            self.amount = amount
        } else if let amount = data["amount"] as? Int {
            self.amount = Double(amount)
        } else if let amount = data["amount"] as? NSNumber {
            self.amount = amount.doubleValue
        } else {
            self.amount = 0
        }

        // --- recipient name (legacy: recipientName; new: recommenderName or customerName)
        let recipientName =
            (data["recipientName"] as? String)
            ?? (data["recommenderName"] as? String)
            ?? (data["customerName"] as? String)
            ?? "Unbekannt"
        self.recipientName = recipientName

        // --- recipient address
        if let legacyAddress = data["recipientAddress"] as? String, !legacyAddress.isEmpty {
            self.recipientAddress = legacyAddress
        } else {
            let street = (data["recommenderStreet"] as? String) ?? ""
            let zip = (data["recommenderZip"] as? String) ?? ""
            let city = (data["recommenderCity"] as? String) ?? ""
            let line1 = [street].filter { !$0.isEmpty }.joined(separator: " ")
            let line2 = [zip, city].filter { !$0.isEmpty }.joined(separator: " ")
            let address = [line1, line2].filter { !$0.isEmpty }.joined(separator: "\n")
            self.recipientAddress = address.isEmpty ? "-" : address
        }

        // --- payout target
        // Legacy: payoutTarget; New: payoutIban / payoutPaypal depending on payoutMethod.
        if let legacyTarget = data["payoutTarget"] as? String, !legacyTarget.isEmpty {
            self.payoutTarget = legacyTarget
        } else {
            if payoutMethodRaw.lowercased() == "iban" {
                self.payoutTarget = (data["payoutIban"] as? String) ?? ""
            } else {
                self.payoutTarget = (data["payoutPaypal"] as? String) ?? ""
            }
        }

        // --- paidAt / paidByUid (optional)
        self.paidAt = data["paidAt"] as? Timestamp
        self.paidByUid = data["paidByUid"] as? String
    }

    init(from entry: CommissionEntry, actorUid: String) {
        self.id = entry.id.uuidString
        self.recipientName = entry.recipientName
        self.recipientAddress = entry.recipientAddress
        self.amount = (entry.amountEUR as NSDecimalNumber).doubleValue
        self.payoutMethodRaw = entry.payoutMethod.rawValue
        self.payoutTarget = entry.payoutTarget
        self.statusRaw = entry.status.rawValue
        self.createdAt = Timestamp(date: entry.createdAt)
        self.createdByUid = entry.createdByUserId.isEmpty ? actorUid : entry.createdByUserId
        self.paidAt = entry.paidAt.map { Timestamp(date: $0) }
        self.paidByUid = entry.paidByUserId
    }

    func toDictionary() -> [String: Any] {
        var d: [String: Any] = [
            "recipientName": recipientName,
            "recipientAddress": recipientAddress,
            "amount": amount,
            "payoutMethodRaw": payoutMethodRaw,
            "payoutTarget": payoutTarget,
            "statusRaw": statusRaw,
            "createdAt": createdAt,
            "createdByUid": createdByUid
        ]
        if let paidAt { d["paidAt"] = paidAt }
        if let paidByUid { d["paidByUid"] = paidByUid }
        return d
    }
}

// MARK: - Firestore Tasks DTO

struct TaskDTO {
    var id: String
    var title: String
    var details: String
    var dueDate: Timestamp?
    var statusRaw: String
    var kindRaw: String?
    var assignedUserId: String
    var creatorUserId: String
    var createdAt: Timestamp
    var updatedAt: Timestamp?
    var updatedByUserId: String?

    init?(id: String, data: [String: Any]) {
        guard
            let title = data["title"] as? String,
            let details = data["details"] as? String,
            let statusRaw = data["statusRaw"] as? String,
            let assignedUserId = data["assignedUserId"] as? String,
            let creatorUserId = data["creatorUserId"] as? String,
            let createdAt = data["createdAt"] as? Timestamp
        else { return nil }

        self.id = id
        self.title = title
        self.details = details
        self.statusRaw = statusRaw
        self.kindRaw = (data["kindRaw"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        self.assignedUserId = assignedUserId.trimmingCharacters(in: .whitespacesAndNewlines)
        self.creatorUserId = creatorUserId.trimmingCharacters(in: .whitespacesAndNewlines)
        self.createdAt = createdAt
        self.dueDate = data["dueDate"] as? Timestamp
        self.updatedAt = data["updatedAt"] as? Timestamp
        self.updatedByUserId = (data["updatedByUserId"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    init(from task: Task) {
        self.id = task.id.uuidString
        self.title = task.title
        self.details = task.details
        self.statusRaw = task.status.rawValue
        self.kindRaw = task.kind.rawValue
        self.assignedUserId = task.assignedUserId.trimmingCharacters(in: .whitespacesAndNewlines)
        self.creatorUserId = task.creatorUserId.trimmingCharacters(in: .whitespacesAndNewlines)
        self.createdAt = Timestamp(date: task.createdAt)
        self.dueDate = task.dueDate.map { Timestamp(date: $0) }
        self.updatedAt = task.updatedAt.map { Timestamp(date: $0) }
        self.updatedByUserId = task.updatedByUserId?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func toDictionary() -> [String: Any] {
        var d: [String: Any] = [
            "title": title,
            "details": details,
            "statusRaw": statusRaw,
            "kindRaw": kindRaw ?? TaskKind.general.rawValue,
            "assignedUserId": assignedUserId,
            "creatorUserId": creatorUserId,
            "createdAt": createdAt
        ]
        if let dueDate { d["dueDate"] = dueDate }
        if let updatedAt { d["updatedAt"] = updatedAt }
        if let updatedByUserId, !updatedByUserId.isEmpty {
            d["updatedByUserId"] = updatedByUserId
        }
        return d
    }
}

// MARK: - Firestore MeetingTopics DTO

struct MeetingTopicDTO {
    var id: String
    var title: String
    var details: String
    var statusRaw: String
    var createdAt: Timestamp
    var createdByUserId: String
    var updatedAt: Timestamp?
    var updatedByUserId: String?

    init?(id: String, data: [String: Any]) {
        guard
            let title = data["title"] as? String,
            let statusRaw = data["statusRaw"] as? String,
            let createdAt = data["createdAt"] as? Timestamp,
            let createdByUserId = data["createdByUserId"] as? String
        else { return nil }

        self.id = id
        self.title = title
        self.details = (data["details"] as? String) ?? ""
        self.statusRaw = statusRaw
        self.createdAt = createdAt
        self.createdByUserId = createdByUserId
        self.updatedAt = data["updatedAt"] as? Timestamp
        self.updatedByUserId = data["updatedByUserId"] as? String
    }

    init(from topic: MeetingTopic) {
        self.id = topic.id.uuidString
        self.title = topic.title
        self.details = topic.details
        self.statusRaw = topic.status.rawValue
        self.createdAt = Timestamp(date: topic.createdAt)
        self.createdByUserId = topic.createdByUserId
        self.updatedAt = topic.updatedAt.map { Timestamp(date: $0) }
        self.updatedByUserId = topic.updatedByUserId
    }

    func toDictionary() -> [String: Any] {
        var d: [String: Any] = [
            "title": title,
            "details": details,
            "statusRaw": statusRaw,
            "createdAt": createdAt,
            "createdByUserId": createdByUserId
        ]
        if let updatedAt { d["updatedAt"] = updatedAt }
        if let updatedByUserId { d["updatedByUserId"] = updatedByUserId }
        return d
    }
}

struct MeetingArchiveDTO {
    var id: String
    var meetingDate: Timestamp
    var archivedAt: Timestamp?
    var archivedByUserId: String
    var topicCount: Int
    var protocolText: String
    var topics: [[String: Any]]

    init?(id: String, data: [String: Any]) {
        guard let meetingDate = data["meetingDate"] as? Timestamp else { return nil }

        self.id = id
        self.meetingDate = meetingDate
        self.archivedAt = data["archivedAt"] as? Timestamp
        self.archivedByUserId = (data["archivedByUserId"] as? String) ?? ""
        self.topicCount = (data["topicCount"] as? Int) ?? 0
        self.protocolText = (data["protocolText"] as? String) ?? ""
        self.topics = (data["topics"] as? [[String: Any]]) ?? []
    }
}

struct LeaveRequestDTO {
    var id: String
    var userEmail: String
    var startDate: Timestamp
    var endDate: Timestamp
    var typeRaw: String
    var reason: String
    var statusRaw: String
    var createdAt: Timestamp
    var createdByEmail: String
    var updatedAt: Timestamp?
    var updatedByEmail: String?
    var userId: String?
    var createdByUid: String?
    var updatedByUid: String?
    
    init?(id: String, data: [String: Any]) {
        guard
            let userEmail = data["userEmail"] as? String,
            let startDate = data["startDate"] as? Timestamp,
            let endDate = data["endDate"] as? Timestamp,
            let typeRaw = data["typeRaw"] as? String,
            let reason = data["reason"] as? String,
            let statusRaw = data["statusRaw"] as? String,
            let createdAt = data["createdAt"] as? Timestamp,
            let createdByEmail = data["createdByEmail"] as? String
        else { return nil }
        
        self.id = id
        self.userEmail = userEmail
        self.startDate = startDate
        self.endDate = endDate
        self.typeRaw = typeRaw
        self.reason = reason
        self.statusRaw = statusRaw
        self.createdAt = createdAt
        self.createdByEmail = createdByEmail
        self.updatedAt = data["updatedAt"] as? Timestamp
        self.updatedByEmail = data["updatedByEmail"] as? String
        self.userId = data["userId"] as? String
        self.createdByUid = data["createdByUid"] as? String
        self.updatedByUid = data["updatedByUid"] as? String
    }
    
    init(from request: LeaveRequest, currentActorEmail: String) {
        self.id = request.id.uuidString
        self.userEmail = request.user.email.lowercased()
        self.startDate = Timestamp(date: request.startDate)
        self.endDate = Timestamp(date: request.endDate)
        self.typeRaw = request.type.rawValue
        self.reason = request.reason
        self.statusRaw = request.status.rawValue
        self.createdAt = Timestamp(date: request.createdAt)
        self.createdByEmail = currentActorEmail

        // Firebase UID references (preferred)
        self.userId = request.user.id
        self.createdByUid = request.createdByUserId

        if let u = request.updatedAt {
            self.updatedAt = Timestamp(date: u)
        } else {
            self.updatedAt = nil
        }
        self.updatedByEmail = nil
        self.updatedByUid = request.updatedByUserId
    }
    
    func toDictionary() -> [String: Any] {
        var d: [String: Any] = [
            // Keep email fields for compatibility/debugging
            "userEmail": userEmail,
            "startDate": startDate,
            "endDate": endDate,
            "typeRaw": typeRaw,
            "reason": reason,
            "statusRaw": statusRaw,
            "createdAt": createdAt,
            "createdByEmail": createdByEmail
        ]

        // Preferred UID fields
        if let userId { d["userId"] = userId }
        if let createdByUid { d["createdByUid"] = createdByUid }
        if let updatedByUid { d["updatedByUid"] = updatedByUid }

        if let updatedAt { d["updatedAt"] = updatedAt }
        if let updatedByEmail { d["updatedByEmail"] = updatedByEmail }

        return d
    }
}
