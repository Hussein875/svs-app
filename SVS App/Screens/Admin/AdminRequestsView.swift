//
//  AdminRequestsView.swift
//  SVS App
//
//  Extracted from AdminConsoleView.swift for readability.
//

import Foundation
import SwiftUI

// MARK: - Admin Requests Screen

enum AdminQuickFilter: String, CaseIterable, Identifiable {
    case all = "Alle"
    case today = "Heute"
    case thisWeek = "Diese Woche"

    var id: String { rawValue }
}

struct AdminRequestsScreen: View {
    @EnvironmentObject var appState: AppState
    @State private var editingRequest: LeaveRequest?
    @State private var showEditScreen: Bool = false
    @State private var filterMode: AdminQuickFilter = .all
    private var accent: Color {
        appState.currentUser?.color ?? .secondary
    }

    private func matchesQuickFilter(_ request: LeaveRequest) -> Bool {
        let cal = Calendar.current
        let start = cal.startOfDay(for: request.startDate)
        let end = cal.startOfDay(for: request.endDate)
        let today = cal.startOfDay(for: Date())

        switch filterMode {
        case .all:
            return true
        case .today:
            return start <= today && today <= end
        case .thisWeek:
            guard let week = cal.dateInterval(of: .weekOfYear, for: today) else { return true }
            let wStart = cal.startOfDay(for: week.start)
            let wEnd = cal.startOfDay(for: week.end.addingTimeInterval(-1))
            return start <= wEnd && wStart <= end
        }
    }

    private var openRequests: [LeaveRequest] {
        appState.leaveRequests
            .filter { $0.type == .vacation && $0.status == .pending }
            .filter { matchesQuickFilter($0) }
            .sorted { $0.startDate > $1.startDate }
    }

    // Beantwortete Anträge (inkl. Krankheit) – nach Monat gruppiert
    private var answeredRequests: [LeaveRequest] {
        appState.leaveRequests
            .filter { !($0.type == .vacation && $0.status == .pending) }
            .filter { matchesQuickFilter($0) }
            .sorted { $0.startDate > $1.startDate }
    }

    private var answeredRequestsByMonth: [(monthStart: Date, requests: [LeaveRequest])] {
        let cal = Calendar.current
        let grouped = Dictionary(grouping: answeredRequests) { req in
            let comps = cal.dateComponents([.year, .month], from: req.startDate)
            return cal.date(from: comps) ?? cal.startOfDay(for: req.startDate)
        }

        let sortedKeys = grouped.keys.sorted(by: >)
        return sortedKeys.map { key in
            let items = (grouped[key] ?? []).sorted { $0.startDate > $1.startDate }
            return (monthStart: key, requests: items)
        }
    }

    private func monthTitle(_ date: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "de_DE")
        df.dateFormat = "LLLL yyyy"
        return df.string(from: date).capitalized
    }

    var body: some View {
        List {
            if openRequests.isEmpty && answeredRequests.isEmpty {
                Section {
                    Text("Keine Anträge vorhanden")
                        .foregroundColor(.secondary)
                }
            } else {
                if !openRequests.isEmpty {
                    Section(header: Text("Offen")) {
                        ForEach(openRequests) { request in
                            adminRequestRow(for: request)
                        }
                    }
                }

                if !answeredRequestsByMonth.isEmpty {
                    ForEach(answeredRequestsByMonth, id: \.monthStart) { group in
                        Section(header: Text(monthTitle(group.monthStart))) {
                            ForEach(group.requests) { request in
                                adminRequestRow(for: request)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
        .navigationDestination(isPresented: $showEditScreen) {
            if let request = editingRequest {
                EditLeaveRequestView(request: request)
                    .environmentObject(appState)
                    .onDisappear { editingRequest = nil }
            } else {
                NewLeaveRequestView()
                    .environmentObject(appState)
            }
        }
        .navigationTitle("Abwesenheiten")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                HStack(spacing: 8) {
                    Button {
                        showEditScreen = true
                        editingRequest = nil
                    } label: {
                        Image(systemName: "plus")
                    }

                    Menu {
                        Picker("Filter", selection: $filterMode) {
                            ForEach(AdminQuickFilter.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func adminRequestRow(for request: LeaveRequest) -> some View {
        AdminLeaveRequestCard(
            request: request,
            onApprove: { appState.updateStatus(for: request.id, to: .approved) },
            onReject: { appState.updateStatus(for: request.id, to: .rejected) },
            onResetToOpen: { appState.updateStatus(for: request.id, to: .pending) },
            onEdit: {
                editingRequest = request
                showEditScreen = true
            },
            onDelete: { appState.deleteLeaveRequest(request) }
        )
        .environmentObject(appState)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
        .swipeActions {
            if appState.canEditOrDelete(request, by: appState.currentUser) {
                Button {
                    editingRequest = request
                    showEditScreen = true
                } label: {
                    Label("Bearbeiten", systemImage: "pencil")
                }

                Button(role: .destructive) {
                    appState.deleteLeaveRequest(request)
                } label: {
                    Label("Löschen", systemImage: "trash")
                }
            }
        }
    }
}

private struct AdminLeaveRequestCard: View {
    let request: LeaveRequest
    let onApprove: () -> Void
    let onReject: () -> Void
    let onResetToOpen: () -> Void
    let onEdit: () -> Void
    let onDelete: () -> Void

    @EnvironmentObject var appState: AppState

    private var isVacation: Bool { request.type == .vacation }
    private var accent: Color {
        if request.type == .onCallSaturday { return .blue }
        if request.type == .sick { return .gray }
        return colorForLeaveStatus(request.status)
    }
    @State private var showAudit: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(accent.opacity(0.9))
                    .frame(width: 6)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(request.user.name)
                            .font(.headline)
                            .foregroundColor(request.user.color)

                        Spacer()

                        // Krankheit + Samstags-Bereitschaft: kein Status-Badge
                        if request.type != .sick && request.type != .onCallSaturday {
                            statusBadgeView(request.status)
                        }
                    }

                    Text(dateRangeString(request.startDate, request.endDate))
                        .font(.subheadline)

                    HStack(spacing: 8) {
                        Image(systemName: {
                            if request.type == .sick { return "cross.case" }
                            if request.type == .onCallSaturday { return "person.badge.clock" }
                            return "beach.umbrella"
                        }())
                        .font(.caption)
                        .foregroundColor(.secondary)
                        Text(request.type.rawValue)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                }
            }

            // Aktionen:
            if isVacation {
                if request.status == .pending {
                    HStack(spacing: 8) {
                        Button("Genehmigen", action: onApprove)
                            .buttonStyle(.borderedProminent)
                            .tint(.green)

                        Button("Ablehnen", action: onReject)
                            .buttonStyle(.bordered)
                            .tint(.red)
                    }
                } else {
                    Button {
                        onResetToOpen()
                    } label: {
                        Label("Auf Offen setzen", systemImage: "arrow.uturn.backward")
                            .font(.caption.weight(.semibold))
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(.secondary)
                    .padding(.top, 2)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(accent.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 6)
    }
}
