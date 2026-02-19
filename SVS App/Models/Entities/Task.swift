//
//  Task.swift
//  SVS App
//
//  Created by Hussein Souleiman on 23.12.25.
//
import Foundation
import SwiftUI

struct Task: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var title: String
    var details: String
    var dueDate: Date?
    var status: TaskStatus
    var assignedUserId: String
    var creatorUserId: String
    var createdAt: Date
    var updatedAt: Date? = nil
    var updatedByUserId: String? = nil
}
