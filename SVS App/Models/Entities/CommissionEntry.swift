//
//  CommissionEntry.swift
//  SVS App
//
//  Created by Codex on 10.02.26.
//

import Foundation

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
