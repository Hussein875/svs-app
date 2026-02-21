//
//  MainViewHome.swift
//  SVS App
//
//  Extracted from MainView.swift for readability.
//

import Foundation
import SwiftUI
import FirebaseFirestore

// MARK: - Arbeit (Home)

struct WorkHomeView: View {
    @EnvironmentObject var appState: AppState
    @Binding var pushDestination: HomePushDestination?

    private var displayName: String {
        let name = appState.currentUser?.name.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "" : name
    }

    private var userAccentColor: Color {
        Color.svsAccentColor(from: appState.currentUser?.colorName)
    }

    private var isEmployeeRole: Bool {
        appState.currentUser?.role == .employee
    }

    private var currentYearInterval: DateInterval {
        let cal = Calendar.current
        let year = cal.component(.year, from: Date())
        let start = cal.date(from: DateComponents(year: year, month: 1, day: 1)) ?? Date()
        let end = cal.date(from: DateComponents(year: year + 1, month: 1, day: 1))
            ?? Date().addingTimeInterval(60 * 60 * 24 * 365)
        return DateInterval(start: start, end: end)
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
            .filter { $0.type != .onCallSaturday }
            .count
    }

    private var myOnCallSaturdaysThisYearCount: Int {
        guard let me = appState.currentUser else { return 0 }
        return appState.leaveRequests
            .filter { $0.user.id == me.id }
            .filter { $0.type == .onCallSaturday }
            .filter { currentYearInterval.contains($0.startDate) }
            .count
    }

    private var openMeetingTopicsCount: Int {
        appState.meetingTopics.filter { $0.status == .open }.count
    }

    private var nextMeetingShortText: String {
        guard let next = appState.nextMeetingAt else { return "Nicht gesetzt" }
        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "dd.MM · HH:mm"
        return f.string(from: next)
    }

    private var nextMyOnCallSaturdayText: String {
        guard let me = appState.currentUser else { return "—" }
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())

        let next = appState.leaveRequests
            .filter { $0.user.id == me.id }
            .filter { $0.type == .onCallSaturday }
            .map { cal.startOfDay(for: $0.startDate) }
            .filter { $0 >= today }
            .sorted()
            .first

        guard let next else { return "Keine geplant" }

        let f = DateFormatter()
        f.locale = Locale(identifier: "de_DE")
        f.dateFormat = "EEE, dd.MM"
        return f.string(from: next)
    }

    private var upcomingFreeSaturdaysCount: Int {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let saturdays = allSaturdays(in: currentYearInterval)
        return saturdays
            .filter { $0 >= today }
            .filter { sat in
                !appState.leaveRequests.contains(where: {
                    $0.type == .onCallSaturday && cal.isDate($0.startDate, inSameDayAs: sat)
                })
            }
            .count
    }

    private func allSaturdays(in interval: DateInterval) -> [Date] {
        let cal = Calendar.current
        var dates: [Date] = []
        var d = cal.startOfDay(for: interval.start)

        // Advance to first Saturday.
        while cal.component(.weekday, from: d) != 7 {
            guard let next = cal.date(byAdding: .day, value: 1, to: d) else { break }
            d = next
        }

        // Collect Saturdays until end.
        while d < interval.end {
            dates.append(d)
            guard let next = cal.date(byAdding: .day, value: 7, to: d) else { break }
            d = next
        }

        return dates
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

                    if !isEmployeeRole {
                        // MARK: Quick numbers
                        VStack(spacing: 12) {
                            HStack(spacing: 12) {
                                StatTextPill(
                                    title: "Nächste Bereitschaft",
                                    valueText: nextMyOnCallSaturdayText,
                                    systemImage: "calendar.badge.clock"
                                )
                                StatTextPill(
                                    title: "Nächstes Meeting",
                                    valueText: nextMeetingShortText,
                                    systemImage: "person.3.fill"
                                )
                            }
                        }
                        .padding(.horizontal, 18)
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        Text(isEmployeeRole ? "Fokus" : "Start")
                            .font(.caption.weight(.semibold))
                            .foregroundColor(.secondary)
                            .textCase(.uppercase)
                            .padding(.horizontal, 2)

                        VStack(spacing: 12) {
                            if isEmployeeRole {
                                NavigationLink {
                                    TasksView()
                                } label: {
                                    WorkCard(
                                        title: "Aufgaben",
                                        subtitle: "Dein Tagesfokus",
                                        systemImage: "checklist",
                                        trailingValue: myOpenTasksCount
                                    )
                                }
                                .buttonStyle(.plain)

                                NavigationLink {
                                    MyRequestsScreen()
                                } label: {
                                    WorkCard(
                                        title: "Abwesenheiten",
                                        subtitle: "Urlaub und Krankheit verwalten",
                                        systemImage: "doc.text",
                                        trailingValue: myActiveRequestsCount
                                    )
                                }
                                .buttonStyle(.plain)
                            } else {
                                NavigationLink {
                                    MyRequestsScreen()
                                } label: {
                                    WorkCard(
                                        title: "Abwesenheiten",
                                        subtitle: "Urlaub, Krankheit, Bereitschaft",
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
                                        subtitle: "Offene To-dos",
                                        systemImage: "checklist",
                                        trailingValue: myOpenTasksCount
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.bottom, isEmployeeRole ? 18 : 0)

                    if !isEmployeeRole {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Weitere Bereiche")
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.secondary)
                                .textCase(.uppercase)
                                .padding(.horizontal, 2)

                            HStack(spacing: 12) {
                                NavigationLink {
                                    MyOnCallSaturdaysScreen()
                                } label: {
                                    CompactWorkCard(
                                        title: "Bereitschaft",
                                        systemImage: "calendar.badge.clock",
                                        badgeText: myOnCallSaturdaysThisYearCount > 0 ? "\(myOnCallSaturdaysThisYearCount)" : nil
                                    )
                                }
                                .buttonStyle(.plain)

                                NavigationLink {
                                    MeetingTopicsView()
                                } label: {
                                    CompactWorkCard(
                                        title: "Meeting",
                                        systemImage: "person.3.fill",
                                        badgeText: openMeetingTopicsCount > 0 ? "\(openMeetingTopicsCount)" : nil
                                    )
                                }
                                .buttonStyle(.plain)
                            }

                            HStack(spacing: 12) {
                                NavigationLink {
                                    ProvisionenView()
                                } label: {
                                    CompactWorkCard(
                                        title: "Provision",
                                        systemImage: "eurosign.circle",
                                        badgeText: nil
                                    )
                                }
                                .buttonStyle(.plain)

                                NavigationLink {
                                    DashboardView()
                                } label: {
                                    CompactWorkCard(
                                        title: "Dashboard",
                                        systemImage: "chart.bar.xaxis",
                                        badgeText: nil
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.bottom, 18)
                    }
                }
            }
            .navigationDestination(item: $pushDestination) { destination in
                switch destination.kind {
                case .tasksAssigned:
                    TasksView()
                case .tasksCompleted:
                    TasksView(
                        startInAssignedByMe: true,
                        startInDoneFilter: true
                    )
                case .myRequests:
                    MyRequestsScreen()
                }
            }
            .background(Color(.systemGroupedBackground))
            .tint(userAccentColor)
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
