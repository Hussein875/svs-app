//
//  Task.swift
//  SVS App
//
//  Created by Hussein Souleiman on 23.12.25.
//
import Foundation
import SwiftUI

struct Task: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var details: String
    var dueDate: Date?
    var status: TaskStatus
    var assignedUserId: UUID
    var creatorUserId: UUID
    var createdAt: Date
}
