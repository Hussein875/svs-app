//
//  PayoutMethod.swift
//  SVS App
//
//  Created by Codex on 10.02.26.
//

import Foundation

enum PayoutMethod: String, Codable, CaseIterable {
    case paypal = "PayPal"
    case iban = "IBAN"
}
