//
//  Enums.swift
//  SVS App
//
//  Created by Hussein Souleiman on 23.12.25.
//

import Foundation
import SwiftUI

enum UserRole: String, Codable {
    case admin
    case employee
    case expert
}

enum LeaveType: String, Codable {
    case vacation = "Urlaub"
    case sick = "Krankheit"
    case onCallSaturday = "Bereitschaft"
}

enum LeaveStatus: String, CaseIterable, Codable {
    case pending = "Offen"
    case approved = "Genehmigt"
    case rejected = "Abgelehnt"
}

enum TaskStatus: String, Codable {
    case open
    case done
}

enum PayoutMethod: String, Codable, CaseIterable {
    case paypal = "PayPal"
    case iban = "IBAN"
}

enum CommissionStatus: String, Codable {
    case open = "Offen"
    case paid = "Ausgezahlt"
}

struct CommissionEntry: Identifiable, Codable, Equatable {
    let id: UUID

    var recipientName: String
    var recipientAddress: String
    var amountEUR: Decimal

    var payoutMethod: PayoutMethod
    var payoutTarget: String // PayPal-Mail oder IBAN (normalisiert)

    var status: CommissionStatus

    // Audit
    var createdAt: Date
    var createdByUserId: String
    var paidAt: Date?
    var paidByUserId: String?
}
