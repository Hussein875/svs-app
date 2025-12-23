//
//  MainView.swift
//  SVS App
//
//  Created by Hussein Souleiman on 23.12.25.
//
import Foundation
import SwiftUI

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

            // Für alle sichtbar
            TasksView()
                .tabItem {
                    Label("Aufgaben", systemImage: "checklist")
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
    }
}
