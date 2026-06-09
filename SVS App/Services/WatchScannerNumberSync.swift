//
//  WatchScannerNumberSync.swift
//  SVS App
//

import Foundation
import WatchConnectivity

final class WatchScannerNumberSync: NSObject, WCSessionDelegate {
    static let shared = WatchScannerNumberSync()

    private var pendingPayload: [String: Any]?

    func activate() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func send(numberText: String, statusText: String) {
        let payload: [String: Any] = [
            "numberText": numberText,
            "statusText": statusText,
            "updatedAt": Date().timeIntervalSince1970,
        ]

        guard WCSession.isSupported() else { return }
        let session = WCSession.default

        if session.activationState != .activated {
            pendingPayload = payload
            activate()
            return
        }

        deliver(payload, via: session)
    }

    private func deliver(_ payload: [String: Any], via session: WCSession) {
        guard session.isPaired else { return }

        session.transferUserInfo(payload)

        if session.isWatchAppInstalled && session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { _ in }
        }
    }

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        guard activationState == .activated else { return }

        if let pendingPayload {
            self.pendingPayload = nil
            deliver(pendingPayload, via: session)
            return
        }

        let snapshot = ScannerWidgetStore.loadSnapshot()
        deliver(
            [
                "numberText": snapshot.numberText,
                "statusText": snapshot.statusText,
                "updatedAt": snapshot.updatedAt?.timeIntervalSince1970 ?? Date().timeIntervalSince1970,
            ],
            via: session
        )
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
}
