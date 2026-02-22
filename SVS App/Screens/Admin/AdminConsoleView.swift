//
//  AdminConsoleView.swift
//  SVS App
//
//  Created by Hussein Souleiman on 23.12.25.
//
import Foundation
import SwiftUI
import FirebaseFirestore

struct AdminPushDestination: Identifiable, Hashable {
    enum Kind: Hashable {
        case requests
        case onCallSaturdays
        case commissions
    }

    let id = UUID()
    let kind: Kind
    let entityId: UUID?
}

struct AdminConsoleView: View {
    @EnvironmentObject var appState: AppState
    @Binding private var pushDestination: AdminPushDestination?

    init(pushDestination: Binding<AdminPushDestination?> = .constant(nil)) {
        _pushDestination = pushDestination
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {

                    HStack(alignment: .firstTextBaseline) {
                        Text("Admin-Konsole")
                            .font(.largeTitle.weight(.bold))

                        Spacer()
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 8)

                    // KPI Cards (2)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        AdminStatCard(
                            title: "Offene Anträge",
                            value: "\(openVacationRequestsCount)",
                            systemImage: "doc.text",
                            accent: appState.currentUser?.color ?? .secondary
                        )

                        AdminStatCard(
                            title: "Offene Provisionen",
                            value: "\(openCommissionsCount)",
                            systemImage: "eurosign.circle",
                            accent: appState.currentUser?.color ?? .secondary
                        )
                    }
                    .padding(.horizontal, 18)


                    VStack(alignment: .leading, spacing: 10) {
                        Text("Übersicht")
                            .font(.headline)
                            .padding(.horizontal, 18)

                        VStack(spacing: 10) {
                            NavigationLink {
                                AdminRequestsScreen()
                                    .environmentObject(appState)
                            } label: {
                                AdminNavRow(
                                    title: "Anträge verwalten",
                                    subtitle: "Urlaub und Krankheit",
                                    systemImage: "doc.text.magnifyingglass",
                                    accent: appState.currentUser?.color ?? .secondary
                                )
                            }

                            NavigationLink {
                                AdminUsersScreen()
                                    .environmentObject(appState)
                            } label: {
                                AdminNavRow(title: "Nutzerverwaltung",
                                            subtitle: "Nutzer, Rollen und Login verwalten",
                                            systemImage: "person.2", accent: appState.currentUser?.color ?? .secondary
)
                            }

                            NavigationLink {
                                AdminOnCallSaturdaysScreen()
                                    .environmentObject(appState)
                            } label: {
                                AdminNavRow(title: "Samstags-Bereitschaft",
                                            subtitle: "Samstage zuweisen",
                                            systemImage: "person.badge.clock", accent: appState.currentUser?.color ?? .secondary)
                            }

                            NavigationLink {
                                AdminCommissionsScreen()
                                    .environmentObject(appState)
                            } label: {
                                AdminNavRow(
                                    title: "Provisionen",
                                    subtitle: "Offen, auszahlen und löschen",
                                    systemImage: "eurosign",
                                    accent: appState.currentUser?.color ?? .secondary
                                )
                            }

                            NavigationLink {
                                AdminAutomationsScreen(automationId: "auto_gutachten_ablage")
                                    .environmentObject(appState)
                            } label: {
                                AdminNavRow(title: "Automatisierungen",
                                            subtitle: "Make-Status und letzte Läufe",
                                            systemImage: "bolt.badge.clock", accent: appState.currentUser?.color ?? .secondary)
                            }

                        }
                        .padding(.horizontal, 18)
                    }

                    Spacer(minLength: 18)
                }
                .padding(.top, 2)
            }
            .navigationDestination(item: $pushDestination) { destination in
                switch destination.kind {
                case .requests:
                    AdminRequestsScreen()
                        .environmentObject(appState)
                case .onCallSaturdays:
                    AdminOnCallSaturdaysScreen()
                        .environmentObject(appState)
                case .commissions:
                    AdminCommissionsScreen()
                        .environmentObject(appState)
                }
            }
            .background(Color(.systemGroupedBackground))
        }
    }
    
    private struct AdminStatCard: View {
        let title: String
        let value: String
        let systemImage: String
        let accent: Color

        var body: some View {
            VStack(alignment: .center, spacing: 8) {
                Image(systemName: systemImage)
                    .foregroundColor(accent)

                Text(value)
                    .font(.title2.weight(.bold))
                    .multilineTextAlignment(.center)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                Text(title)
                    .font(.caption)
                    .foregroundColor(accent.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 88, maxHeight: 88, alignment: .center)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(accent.opacity(0.22), lineWidth: 1))
        }
    }

    private struct AdminNavRow: View {
        let title: String
        let subtitle: String
        let systemImage: String
        let accent: Color

        var body: some View {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Color(.secondarySystemBackground))
                    Image(systemName: systemImage)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(accent)
                    Text(subtitle).font(.caption).foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
                    .font(.caption.weight(.semibold))
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
            .contentShape(Rectangle())
        }
    }

    private var openVacationRequestsCount: Int {
        appState.leaveRequests.filter { $0.type == .vacation && $0.status == .pending }.count
    }

    private var todayAbsentCount: Int {
        let today = Calendar.current.startOfDay(for: Date())

        // "Abwesend" means Urlaub oder Krankheit.
        // Samstags-Bereitschaft ist KEINE Abwesenheit und darf hier nicht mitgezählt werden.
        let todays = appState.requests(for: today)
            .filter { $0.status == .approved }
            .filter { $0.type == .vacation || $0.type == .sick }

        return Set(todays.map { $0.user.id }).count
    }

    private var upcomingOnCallCount: Int {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return appState.leaveRequests
            .filter {
                $0.type == .onCallSaturday && $0.status != .rejected
            }
            .filter { cal.startOfDay(for: $0.startDate) >= today }
            .count
    }

    private var openCommissionsCount: Int {
        // Treat anything that is not paid as open.
        appState.commissions.filter { $0.status != .paid }.count
    }
}


struct AdminCommissionsScreen: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ProvisionenView()
            .environmentObject(appState)
            .navigationTitle("Provisionen")
            .navigationBarTitleDisplayMode(.inline)
    }
}
