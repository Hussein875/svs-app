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

            WorkHomeView()
                .tabItem {
                    Label("Mein Bereich", systemImage: "person.crop.circle")
                }
            
            // Admin-spezifische Tabs
            if appState.currentUser?.role == .admin {
                AdminConsoleView()
                    .tabItem {
                        Label("Admin", systemImage: "shield.lefthalf.filled")
                    }
            }

            // Menü Tab
            MenuView()
                .tabItem {
                    Label("Menü", systemImage: "gearshape")
                }
        }
        .onAppear {
            // 1) UI-Kleinkram
            customizeMoreTab(title: "Mehr")
        }
    }

}

// MARK: - Arbeit (Home)

private struct WorkHomeView: View {
    @EnvironmentObject var appState: AppState

    private var displayName: String {
        let name = appState.currentUser?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "" : name
    }

    private var userAccentColor: Color {
        let key = (appState.currentUser?.colorName ?? "").lowercased()
        switch key {
        case "blau", "blue": return .blue
        case "grün", "gruen", "green": return .green
        case "rot", "red": return .red
        case "orange": return .orange
        case "lila", "purple": return .purple
        case "pink": return .pink
        case "gelb", "yellow": return .yellow
        case "grau", "gray", "grey": return .gray
        case "mint": return .mint
        case "teal": return .teal
        case "indigo": return .indigo
        default: return .blue
        }
    }

    // Quick numbers
    private var myOpenTasksCount: Int {
        guard let me = appState.currentUser else { return 0 }
        return appState.tasks.filter { $0.assignedUserId == me.id && $0.status == .open }.count
    }

    private var myActiveRequestsCount: Int {
        guard let me = appState.currentUser else { return 0 }
        let today = Calendar.current.startOfDay(for: Date())
        return appState.leaveRequests
            .filter { $0.user.id == me.id }
            .filter { $0.endDate >= today }
            .count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // MARK: Header (clean)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 10) {
                            Image(systemName: "car.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.tint)

                            Text("Mein Bereich")
                                .font(.subheadline.weight(.semibold))
                                .foregroundColor(.secondary)

                            Spacer(minLength: 0)
                        }

                        Text(displayName.isEmpty ? "Mein Bereich" : "Hallo, \(displayName)")
                            .font(.largeTitle.bold())
                            .foregroundColor(.primary)

                        // Subtle accent underline
                        Capsule(style: .continuous)
                            .fill(.tint)
                            .frame(width: 54, height: 4)
                            .padding(.top, 4)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 8)

                    // MARK: Quick numbers
                    HStack(spacing: 12) {
                        StatPill(title: "Aktive Anträge", value: myActiveRequestsCount, systemImage: "doc.text")
                        StatPill(title: "Offene Aufgaben", value: myOpenTasksCount, systemImage: "checklist")
                    }
                    .padding(.horizontal, 18)

                    // MARK: Cards
                    VStack(spacing: 12) {
                        NavigationLink {
                            MyRequestsScreen()
                        } label: {
                            WorkCard(
                                title: "Anträge",
                                subtitle: "Urlaub, Krankheit",
                                systemImage: "doc.text",
                                trailingValue: myActiveRequestsCount
                            )
                        }
                        .buttonStyle(.plain)

                        NavigationLink {
                            TasksView()
                        } label: {
                            WorkCard(
                                title: "Aufgaben",
                                subtitle: "To-dos",
                                systemImage: "checklist",
                                trailingValue: myOpenTasksCount
                            )
                        }
                        .buttonStyle(.plain)

                        NavigationLink {
                            ProvisionenView()
                        } label: {
                            WorkCard(
                                title: "Provision",
                                subtitle: "Vermittlungsprovision",
                                systemImage: "eurosign.circle",
                                trailingValue: 0
                            )
                        }
                        .buttonStyle(.plain)

                        NavigationLink {
                            DashboardView()
                        } label: {
                            WorkCard(
                                title: "Dashboard",
                                subtitle: "Übersicht",
                                systemImage: "chart.bar.xaxis",
                                trailingValue: 0
                            )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, 18)
                }
            }
            .background(Color(.systemGroupedBackground))
            .tint(userAccentColor)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct StatPill: View {
    let title: String
    let value: Int
    let systemImage: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text("\(value)")
                    .font(.headline)
                    .foregroundColor(.primary)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.secondary.opacity(0.10), lineWidth: 1)
        )
    }
}

private struct WorkCard: View {
    let title: String
    let subtitle: String
    let systemImage: String
    let trailingValue: Int

    var body: some View {
        HStack(spacing: 14) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(.tint.opacity(0.12))
                .frame(width: 44, height: 44)
                .overlay(
                    Image(systemName: systemImage)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.tint)
                )

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.primary)

                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            if trailingValue > 0 {
                Text("\(trailingValue)")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color(.secondarySystemBackground)))
            }

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Color(UIColor.tertiaryLabel))
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.secondary.opacity(0.10), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.04), radius: 8, x: 0, y: 5)
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
