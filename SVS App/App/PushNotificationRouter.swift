//
//  PushNotificationRouter.swift
//  SVS App
//
//  Created by Hussein Souleiman on 01.02.26.
//

import Foundation

/// A normalized route extracted from a push notification.
///
/// Store this in app state and/or use it to navigate.
struct PushRoute: Equatable, Codable {
    /// Parsed push type.
    var type: NotificationType

    /// Optional entity identifier depending on the push type.
    /// - For leave requests: `requestId`
    /// - For tasks: `taskId`
    /// - For commissions: `commissionId`
    var entityId: String?

    /// Optional helper field for additional data (e.g., decision for leave requests).
    var decision: String?
    var leaveTypeRaw: String?

    /// Raw `userInfo` payload as a debug-only string (not for persistence).
    var debugDescription: String?

    /// Creates a route from an FCM payload.
    ///
    /// - Parameter userInfo: `UNNotification` userInfo.
    init(userInfo: [AnyHashable: Any]) {
        let payload = PushPayload(userInfo: userInfo)

        self.type = NotificationType(rawValue: payload.typeRaw ?? "") ?? .unknown

        // Best-effort mapping: different push types carry different keys.
        switch self.type {
        case .leaveRequestNew, .leaveRequestApproved, .leaveRequestRejected, .leaveRequestOnCallAssigned:
            self.entityId = payload.string("requestId")
            self.decision = payload.string("decision")
            self.leaveTypeRaw = payload.leaveTypeRaw

        case .taskAssigned, .taskCompleted:
            self.entityId = payload.string("taskId")

        case .commissionNew:
            self.entityId = payload.string("commissionId")

        case .unknown:
            self.entityId = payload.firstStringValue(in: ["requestId", "taskId", "commissionId"])
        }

        self.debugDescription = payload.prettyPrintedDebug
    }
}

/// NotificationCenter bridge used by the app to react to push taps.
extension Notification.Name {
    /// Posted whenever the user taps a push notification and we have a parsed route.
    static let pushRoute = Notification.Name("svs.pushRoute")
}

/// Parses push notifications (FCM) into normalized app routes.
///
/// Usage:
/// - Call `PushNotificationRouter.handlePushTap(userInfo:)` from `UNUserNotificationCenterDelegate`.
/// - Observe `Notification.Name.pushRoute` in SwiftUI and route accordingly.
final class PushNotificationRouter {
    private static let routeBufferQueue = DispatchQueue(label: "svs.push.router.routeBuffer")
    private static var bufferedRoute: PushRoute?

    /// Returns and clears the last buffered route from a push tap.
    ///
    /// Useful when the notification tap happened before SwiftUI attached observers.
    static func consumeBufferedRoute() -> PushRoute? {
        routeBufferQueue.sync {
            defer { bufferedRoute = nil }
            return bufferedRoute
        }
    }

    /// Extracts a route from a push payload.
    ///
    /// - Parameter userInfo: The raw `userInfo` dictionary.
    /// - Returns: A `PushRoute` if a meaningful route could be created; otherwise `nil`.
    static func route(from userInfo: [AnyHashable: Any]) -> PushRoute? {
        let payload = PushPayload(userInfo: userInfo)

        // If the push doesn't even carry a type, we can still create an `.unknown` route,
        // but only if it contains at least one known id key.
        let type = NotificationType(rawValue: payload.typeRaw ?? "") ?? .unknown
        let hasAnyId = payload.firstStringValue(in: ["requestId", "taskId", "commissionId"]) != nil

        if type == .unknown && !hasAnyId {
            return nil
        }

        return PushRoute(userInfo: userInfo)
    }

    /// Handles a push tap and posts a `Notification.Name.pushRoute` event.
    ///
    /// - Parameter userInfo: The raw `UNNotification` userInfo dictionary.
    static func handlePushTap(userInfo: [AnyHashable: Any]) {
        guard let route = route(from: userInfo) else {
            // Still log for debugging.
            #if DEBUG
            let payload = PushPayload(userInfo: userInfo)
            print("[PushTap][Router] ignored push (no route)\n\(payload.prettyPrintedDebug)")
            #endif
            return
        }

        #if DEBUG
        print("[PushTap][Router] route=\(route.type.rawValue) id=\(route.entityId ?? "—") decision=\(route.decision ?? "—")")
        #endif

        routeBufferQueue.sync {
            bufferedRoute = route
        }

        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .pushRoute, object: nil, userInfo: ["route": route])
        }
    }
}

// MARK: - Internal payload helper

/// A small helper wrapper to read values safely from `userInfo`.
private struct PushPayload {
    let userInfo: [AnyHashable: Any]

    init(userInfo: [AnyHashable: Any]) {
        self.userInfo = userInfo
    }

    /// The raw `type` value inside the push `data` dictionary (we send it top-level in Gen2).
    var typeRaw: String? {
        string("type")
    }

    var leaveTypeRaw: String? {
        string("leaveTypeRaw")
            ?? string("typeRaw")
            ?? string("requestTypeRaw")
            ?? alertBody
    }

    /// Reads a string value for a given key from the payload.
    func string(_ key: String) -> String? {
        if let v = userInfo[key] {
            let s = String(describing: v).trimmingCharacters(in: .whitespacesAndNewlines)
            return s.isEmpty ? nil : s
        }
        return nil
    }

    private var alertBody: String? {
        if let aps = userInfo["aps"] as? [AnyHashable: Any] {
            if let alert = aps["alert"] as? [AnyHashable: Any],
               let body = alert["body"] {
                let s = String(describing: body).trimmingCharacters(in: .whitespacesAndNewlines)
                if !s.isEmpty { return s }
            }

            if let alert = aps["alert"] {
                let s = String(describing: alert).trimmingCharacters(in: .whitespacesAndNewlines)
                if !s.isEmpty { return s }
            }
        }

        return string("gcm.notification.body") ?? string("body")
    }

    /// Tries multiple keys and returns the first string value found.
    func firstStringValue(in keys: [String]) -> String? {
        for k in keys {
            if let s = string(k) { return s }
        }
        return nil
    }

    /// Pretty printed payload for debug logging.
    var prettyPrintedDebug: String {
        // Convert to a JSON-serializable dictionary.
        var dict: [String: Any] = [:]
        for (k, v) in userInfo {
            dict[String(describing: k)] = v
        }

        guard JSONSerialization.isValidJSONObject(dict),
              let data = try? JSONSerialization.data(withJSONObject: dict, options: [.prettyPrinted]),
              let str = String(data: data, encoding: .utf8)
        else {
            return String(describing: userInfo)
        }
        return str
    }
}
