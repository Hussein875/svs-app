//
//  MeetingTopic.swift
//  SVS App
//
//  Created by Codex on 08.02.26.
//

import Foundation

struct MeetingTopic: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var title: String
    var details: String
    var status: MeetingTopicStatus
    var createdAt: Date
    var createdByUserId: String
    var updatedAt: Date?
    var updatedByUserId: String?
}
