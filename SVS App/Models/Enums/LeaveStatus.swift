//
//  LeaveStatus.swift
//  SVS App
//
//  Created by Codex on 10.02.26.
//

import Foundation

enum LeaveStatus: String, CaseIterable, Codable {
    case pending = "Offen"
    case approved = "Genehmigt"
    case rejected = "Abgelehnt"
}
