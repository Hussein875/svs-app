//
//  AppDeepLink.swift
//  SVS App
//

import Foundation

enum AppDeepLink {
    static let dashboardURL = URL(string: "svsapp://dashboard")!

    static func handle(_ url: URL, appState: AppState) {
        guard url.scheme?.lowercased() == "svsapp" else { return }

        let host = (url.host ?? "").lowercased()
        let path = url.path
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            .lowercased()

        if host == "dashboard" || path == "dashboard" {
            DispatchQueue.main.async {
                appState.pendingHomePushDestination = HomePushDestination(
                    kind: .dashboard,
                    entityId: nil
                )
            }
        }
    }
}
