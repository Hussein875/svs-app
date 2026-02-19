//
//  MyRequestsScreen.swift
//  SVS App
//
//  Created by Hussein Souleiman on 23.12.25.
//
import Foundation
import SwiftUI

struct MyRequestsScreen: View {
    @EnvironmentObject var appState: AppState
    @State private var editingRequest: LeaveRequest?

    private var myRequests: [LeaveRequest] {
        guard let me = appState.currentUser else { return [] }
        let myId = me.id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !myId.isEmpty else { return [] }

        return appState.leaveRequests.filter {
            $0.user.id == myId && $0.type != .onCallSaturday
        }
    }

    private var todayStart: Date {
        Calendar.current.startOfDay(for: Date())
    }

    private var currentRequests: [LeaveRequest] {
        myRequests
            .filter { Calendar.current.startOfDay(for: $0.endDate) >= todayStart }
            .sorted { $0.startDate < $1.startDate }
    }

    private var pastRequests: [LeaveRequest] {
        myRequests
            .filter { Calendar.current.startOfDay(for: $0.endDate) < todayStart }
            .sorted { $0.startDate > $1.startDate }
    }

    private var counts: (pending: Int, approved: Int, rejected: Int) {
        let vacationRequests = currentRequests.filter { $0.type != .sick }
        let pending = vacationRequests.filter { $0.status == .pending }.count
        let approved = vacationRequests.filter { $0.status == .approved }.count
        let rejected = vacationRequests.filter { $0.status == .rejected }.count
        return (pending, approved, rejected)
    }

    private func canEditOnCall(_ r: LeaveRequest) -> Bool {
        guard r.type == .onCallSaturday else { return false }
        guard let currentUser = appState.currentUser else { return false }
        // Only allow editing for future (or today) entries
        let day = Calendar.current.startOfDay(for: r.startDate)
        guard day >= todayStart else { return false }
        // Admin can edit all; otherwise only the owner can edit
        if currentUser.role == .admin { return true }
        return (currentUser.role == .expert) && (r.user.id == currentUser.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if myRequests.isEmpty {
                // Clean empty state (no List top inset / no huge header gap)
                VStack(alignment: .leading, spacing: 14) {
                    Text("Noch keine Anträge")
                        .font(.headline)
                        .foregroundColor(.secondary)

                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color(.secondarySystemBackground))
                        .frame(height: 68)
                        .overlay(
                            HStack {
                                Text("Noch keine Anträge")
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                            .padding(.horizontal, 18)
                        )

                    Spacer()
                }
                .padding(.horizontal, 18)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background(Color(.systemGroupedBackground))
            } else {
                List {
                    // Aktuell / kommende Anträge
                    Section {
                        if currentRequests.isEmpty {
                            HStack {
                                Text("Keine aktuellen Anträge")
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                            .listRowBackground(Color.clear)
                            .listRowSeparator(.hidden)
                        } else {
                            ForEach(currentRequests) { r in
                                MyLeaveRequestCard(request: r) {
                                    // Past requests are read-only
                                    let isPast = Calendar.current.startOfDay(for: r.endDate) < todayStart
                                    guard !isPast else { return }

                                    // Samstags-Bereitschaft soll nicht bearbeitet werden
                                    guard r.type != .onCallSaturday else { return }

                                    if appState.canEditOrDelete(r, by: appState.currentUser) {
                                        editingRequest = r
                                    }
                                }
                                .swipeActions {
                                    let isPast = Calendar.current.startOfDay(for: r.endDate) < todayStart
                                    if !isPast {
                                        // Für Samstags-Bereitschaft: nur Löschen (kein Bearbeiten)
                                        if r.type == .onCallSaturday {
                                            Button(role: .destructive) {
                                                appState.deleteLeaveRequest(r)
                                            } label: {
                                                Label("Löschen", systemImage: "trash")
                                            }
                                        } else if appState.canEditOrDelete(r, by: appState.currentUser) {
                                            Button {
                                                editingRequest = r
                                            } label: {
                                                Label("Bearbeiten", systemImage: "pencil")
                                            }

                                            Button(role: .destructive) {
                                                appState.deleteLeaveRequest(r)
                                            } label: {
                                                Label("Löschen", systemImage: "trash")
                                            }
                                        }
                                    }
                                }
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            }
                        }
                    } header: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Aktuelle Anträge")
                            if counts.pending + counts.approved + counts.rejected > 0 {
                                HStack(spacing: 8) {
                                    if counts.pending > 0 { Text("Offen: \(counts.pending)") }
                                    if counts.approved > 0 { Text("Genehmigt: \(counts.approved)") }
                                    if counts.rejected > 0 { Text("Abgelehnt: \(counts.rejected)") }
                                }
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                        }
                        .textCase(nil)
                    }

                    // Vergangene Anträge (separater Screen)
                    if !pastRequests.isEmpty {
                        Section {
                            NavigationLink {
                                PastRequestsScreen(requests: pastRequests)
                                    .environmentObject(appState)
                            } label: {
                                HStack {
                                    Text("Vergangene Anträge")
                                    Spacer()
                                    Text("\(pastRequests.count)")
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(
                                            Capsule().fill(Color(.secondarySystemBackground))
                                        )
                                }
                                .padding(.vertical, 6)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(Color(.systemGroupedBackground))
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationDestination(item: $editingRequest) { request in
            EditLeaveRequestView(request: request)
                .environmentObject(appState)
        }
        .navigationTitle("Meine Abwesenheiten")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    NewLeaveRequestView()
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Neuen Antrag erstellen")
            }
        }
    }
}
