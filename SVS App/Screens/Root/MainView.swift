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

    var body: some View {
        TabView {
            // Urlaub
            CalendarScreen()
                .tabItem {
                    Label("Kalender", systemImage: "calendar")
                }

            MyRequestsScreen()
                .tabItem {
                    Label("Meine Anträge", systemImage: "doc.text")
                }
            
            // Für alle sichtbar
            TasksView()
                .tabItem {
                    Label("Aufgaben", systemImage: "checklist")
                }

            // Admin-spezifische Tabs
            if let user = appState.currentUser {
                if user.role == .admin {
                    AdminConsoleView()
                        .tabItem {
                            Label("Admin", systemImage: "shield.lefthalf.filled")
                        }
                }

                // Provisionen nur für Admin & Sachverständige
                if user.role == .admin || user.role == .expert {
                    ProvisionenView()
                        .tabItem {
                            Label("Provisionen", systemImage: "eurosign")
                        }
                }
            }



            DashboardView()
                .tabItem {
                    Label("Dashboard", systemImage: "chart.bar.doc.horizontal")
                }

            // Menü Tab
            MenuView()
                .tabItem {
                    Label("Menü", systemImage: "gearshape")
                }
        }
        .onAppear {
            // Rename the system "More" tab when iOS collapses extra tabs.
            customizeMoreTab(title: "Mehr")
        }
    }

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
