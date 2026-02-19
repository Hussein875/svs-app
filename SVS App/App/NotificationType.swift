//
//  NotificationType.swift
//  SVS App
//
//  Created by Codex on 10.02.26.
//

import Foundation

/// High-level push types emitted by the backend (FCM `data.type`).
///
/// Notes:
/// - The raw values must match the `data.type` values sent by Cloud Functions.
/// - Keep this enum small and focused; add new cases only when you also add routing logic.
enum NotificationType: String, Codable, CaseIterable {
    /// A new leave request was created.
    case leaveRequestNew = "leave_request_new"

    /// A leave request was approved.
    case leaveRequestApproved = "leave_request_approved"

    /// A leave request was rejected.
    case leaveRequestRejected = "leave_request_rejected"

    /// A task was assigned or reassigned.
    case taskAssigned = "task_assigned"

    /// A task was marked as completed.
    case taskCompleted = "task_completed"

    /// A new commission entry was created (admin payout needed).
    case commissionNew = "commission_new"

    /// Catch-all for any type we don't explicitly support yet.
    case unknown = "unknown"
}
