//
//  MeetingArchive.swift
//  SVS App
//
//  Created by Codex on 10.02.26.
//

import Foundation

struct MeetingArchive: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    var meetingDate: Date
    var archivedAt: Date
    var archivedByUserId: String
    var topicCount: Int
    var protocolText: String
    var topics: [MeetingTopic]
}
