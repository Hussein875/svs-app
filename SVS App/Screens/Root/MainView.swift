//
//  MainView.swift
//  SVS App
//
//  Created by Hussein Souleiman on 23.12.25.
//
import Foundation
import SwiftUI
import UIKit

struct MainView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedTab: MainTab = .calendar
    @State private var homePushDestination: HomePushDestination?
    @State private var adminPushDestination: AdminPushDestination?
    @State private var lastHandledPushRouteKey: String = ""
    @State private var lastHandledPushRouteAt: Date = .distantPast

    var body: some View {
        TabView(selection: $selectedTab) {
            // Urlaub
            CalendarScreen()
                .tabItem {
                    Label("Kalender", systemImage: "calendar")
                }
                .tag(MainTab.calendar)

            WorkHomeView(pushDestination: $homePushDestination)
                .tabItem {
                    Label("Mein Bereich", systemImage: "person.crop.circle")
                }
                .tag(MainTab.home)
            
            // Scanner
            ScannerScreen()
                .tabItem {
                    Label("Scanner", systemImage: "doc.viewfinder")
                }
                .tag(MainTab.scanner)
            
            // Admin-spezifische Tabs
            if appState.currentUser?.role == .admin {
                AdminConsoleView(pushDestination: $adminPushDestination)
                    .tabItem {
                        Label("Admin", systemImage: "shield.lefthalf.filled")
                    }
                    .tag(MainTab.admin)
            }

            // Menü Tab
            MenuView()
                .tabItem {
                    Label("Menü", systemImage: "gearshape")
                }
                .tag(MainTab.menu)
        }
        .onReceive(NotificationCenter.default.publisher(for: .pushRoute)) { notification in
            guard let route = notification.userInfo?["route"] as? PushRoute else { return }
            handlePushRoute(route)
        }
        .onAppear {
            customizeMoreTab(title: "Mehr")
            if let bufferedRoute = PushNotificationRouter.consumeBufferedRoute() {
                handlePushRoute(bufferedRoute)
            }
            consumePendingHomePushDestination()
        }
        .onChange(of: appState.pendingHomePushDestination) { _, _ in
            consumePendingHomePushDestination()
        }
        .onChange(of: appState.currentUser?.role) { _, role in
            if role != .admin && selectedTab == .admin {
                selectedTab = .calendar
            }
        }
    }

    private func consumePendingHomePushDestination() {
        guard let destination = appState.pendingHomePushDestination else { return }
        appState.pendingHomePushDestination = nil
        selectedTab = .home
        homePushDestination = destination
    }

    private func handlePushRoute(_ route: PushRoute) {
        if isRecentDuplicate(route) {
            return
        }

        switch route.type {
        case .leaveRequestNew:
            if appState.currentUser?.role == .admin {
                selectedTab = .admin
                adminPushDestination = AdminPushDestination(
                    kind: isOnCallRequest(route.leaveTypeRaw) ? .onCallSaturdays : .requests,
                    entityId: asUUID(route.entityId)
                )
            } else {
                selectedTab = .calendar
            }

        case .leaveRequestApproved, .leaveRequestRejected:
            selectedTab = .home
            homePushDestination = HomePushDestination(
                kind: .myRequests,
                entityId: asUUID(route.entityId)
            )

        case .leaveRequestOnCallAssigned:
            selectedTab = .home
            homePushDestination = HomePushDestination(
                kind: .myOnCallSaturdays,
                entityId: asUUID(route.entityId)
            )

        case .taskAssigned:
            selectedTab = .home
            homePushDestination = HomePushDestination(
                kind: .tasksAssigned,
                entityId: asUUID(route.entityId)
            )

        case .taskCompleted:
            selectedTab = .home
            homePushDestination = HomePushDestination(
                kind: .tasksCompleted,
                entityId: asUUID(route.entityId)
            )

        case .commissionNew:
            if appState.currentUser?.role == .admin {
                selectedTab = .admin
                adminPushDestination = AdminPushDestination(
                    kind: .commissions,
                    entityId: asUUID(route.entityId)
                )
            } else {
                selectedTab = .home
            }

        case .unknown:
            selectedTab = .home
        }
    }

    private func asUUID(_ raw: String?) -> UUID? {
        guard let raw else { return nil }
        return UUID(uuidString: raw)
    }

    private func isOnCallRequest(_ leaveTypeRaw: String?) -> Bool {
        let normalized = (leaveTypeRaw ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return normalized.contains("bereitschaft")
            || normalized.contains("oncall")
            || normalized.contains("on_call")
    }

    private func isRecentDuplicate(_ route: PushRoute) -> Bool {
        let key = "\(route.type.rawValue)|\(route.entityId ?? "")|\(route.decision ?? "")"
        let now = Date()

        if key == lastHandledPushRouteKey,
           now.timeIntervalSince(lastHandledPushRouteAt) < 1.2 {
            return true
        }

        lastHandledPushRouteKey = key
        lastHandledPushRouteAt = now
        return false
    }
}

private enum MainTab: Hashable {
    case calendar
    case home
    case scanner
    case admin
    case menu
}

struct HomePushDestination: Identifiable, Hashable {
    enum Kind: Hashable {
        case tasksAssigned
        case tasksCompleted
        case myRequests
        case myOnCallSaturdays
        case dashboard
    }

    let id = UUID()
    let kind: Kind
    let entityId: UUID?
}


private func customizeMoreTab(title: String) {
    // TabView uses an underlying UITabBarController. If there are too many tabs,
    // iOS adds a system "More" tab (UINavigationController). We can rename it.
    DispatchQueue.main.async {
        guard let tabBarController = UIApplication.shared.findTabBarController() else { return }
        tabBarController.moreNavigationController.tabBarItem.title = title
        tabBarController.moreNavigationController.navigationBar.topItem?.title = title
    }
}

private extension UIApplication {
    func findTabBarController() -> UITabBarController? {
        // Find the key window's root and search for a UITabBarController.
        let scenes = connectedScenes
            .compactMap { $0 as? UIWindowScene }

        for scene in scenes {
            if let window = scene.windows.first(where: { $0.isKeyWindow }),
               let root = window.rootViewController {
                return root.findTabBarController()
            }
        }
        return nil
    }
}

private extension UIViewController {
    func findTabBarController() -> UITabBarController? {
        if let tab = self as? UITabBarController { return tab }

        for child in children {
            if let found = child.findTabBarController() { return found }
        }

        if let presented = presentedViewController,
           let found = presented.findTabBarController() {
            return found
        }

        return nil
    }
}
