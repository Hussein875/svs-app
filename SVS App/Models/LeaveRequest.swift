//
//  LeaveRequest.swift
//  SVS App
//
//  Created by Hussein Souleiman on 23.12.25.
//
import Foundation
import SwiftUI

struct LeaveRequest: Identifiable, Codable, Hashable {
    let id: UUID
    var user: User
    var startDate: Date
    var endDate: Date
    var type: LeaveType
    var reason: String
    var status: LeaveStatus

    // Audit
    var createdAt: Date
    var createdByUserId: String
    var updatedAt: Date?
    var updatedByUserId: String?

    enum CodingKeys: String, CodingKey {
        case id, user, startDate, endDate, type, reason, status
        case createdAt, createdByUserId, updatedAt, updatedByUserId
    }

    // Backward-compatible decoding for older stored entries
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        user = try c.decode(User.self, forKey: .user)
        startDate = try c.decode(Date.self, forKey: .startDate)
        endDate = try c.decode(Date.self, forKey: .endDate)
        type = try c.decode(LeaveType.self, forKey: .type)
        reason = (try c.decodeIfPresent(String.self, forKey: .reason)) ?? ""
        status = try c.decode(LeaveStatus.self, forKey: .status)

        // If missing, default to the user as creator and now as creation date
        createdAt = (try c.decodeIfPresent(Date.self, forKey: .createdAt)) ?? Date()
        createdByUserId = (try c.decodeIfPresent(String.self, forKey: .createdByUserId)) ?? user.id
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
        updatedByUserId = try c.decodeIfPresent(String.self, forKey: .updatedByUserId)
    }

    init(id: UUID,
         user: User,
         startDate: Date,
         endDate: Date,
         type: LeaveType,
         reason: String,
         status: LeaveStatus,
         createdAt: Date,
         createdByUserId: String,
         updatedAt: Date? = nil,
         updatedByUserId: String? = nil) {
        self.id = id
        self.user = user
        self.startDate = startDate
        self.endDate = endDate
        self.type = type
        self.reason = reason
        self.status = status
        self.createdAt = createdAt
        self.createdByUserId = createdByUserId
        self.updatedAt = updatedAt
        self.updatedByUserId = updatedByUserId
    }
}
