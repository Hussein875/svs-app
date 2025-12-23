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
