//
//  WatchExtensionDelegate.swift
//  SVS Watch App
//

import Foundation
import WatchConnectivity
import WatchKit
import WidgetKit

final class WatchExtensionDelegate: NSObject, WKExtensionDelegate, WCSessionDelegate {
    func applicationDidFinishLaunching() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {}

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        applyPayload(userInfo)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        applyPayload(message)
    }

    private func applyPayload(_ payload: [String: Any]) {
        let numberText = (payload["numberText"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let statusText = (payload["statusText"] as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !numberText.isEmpty else { return }

        let timestamp = payload["updatedAt"] as? TimeInterval ?? Date().timeIntervalSince1970
        ScannerWidgetSnapshot.save(
            numberText: numberText,
            statusText: statusText.isEmpty ? "Verfügbar" : statusText,
            updatedAt: Date(timeIntervalSince1970: timestamp)
        )
        WidgetCenter.shared.reloadTimelines(ofKind: ScannerWidgetSnapshot.watchWidgetKind)
    }
}
