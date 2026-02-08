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

struct MeetingArchive: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var meetingDate: Date
    var archivedAt: Date
    var archivedByUserId: String
    var topicCount: Int
    var protocolText: String
    var topics: [MeetingTopic]
}
