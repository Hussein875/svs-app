//
//  AdminOpenOrdersScreen.swift
//  SVS App
//

import SwiftUI
import FirebaseAuth

/// Übersicht offener Bestellungen — für Admin (alle) oder Bestellungs-Verantwortliche (eigene).
struct AdminOpenOrdersScreen: View {
    enum Scope {
        case all
        case assignedToCurrentUser
    }

    @EnvironmentObject var appState: AppState

    var scope: Scope = .all

    @State private var editingTask: Task?

    private var openOrders: [Task] {
        appState.tasks
            .filter { task in
                guard task.kind == .order, task.status == .open else { return false }
                switch scope {
                case .all:
                    return true
                case .assignedToCurrentUser:
                    return taskAssignedToCurrentUser(task)
                }
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        Group {
            if openOrders.isEmpty {
                ScrollView {
                    VStack(spacing: 14) {
                        Image(systemName: "cart")
                            .font(.system(size: 40))
                            .foregroundColor(.secondary)
                        Text("Keine offenen Bestellungen")
                            .font(.title3.weight(.semibold))
                        Text(scope == .all
                             ? "Alle Bestellanfragen sind erledigt."
                             : "Dir sind aktuell keine offenen Bestellungen zugewiesen.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 24)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 80)
                }
                .refreshable {
                    await appState.refreshTasksFromServer()
                }
            } else {
                List {
                    Section {
                        summaryCard
                            .listRowInsets(EdgeInsets(top: 6, leading: 18, bottom: 6, trailing: 18))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }

                    Section(header: Text("Offen (\(openOrders.count))").textCase(nil)) {
                        ForEach(openOrders) { task in
                            TaskRow(
                                task: task,
                                assignedUserName: appState.userName(for: task.assignedUserId),
                                creatorName: appState.userName(for: task.creatorUserId),
                                onEdit: { editingTask = task },
                                onToggleStatus: { appState.toggleTaskStatus(for: task) },
                                onDelete: { appState.deleteTask(task) }
                            )
                            .environmentObject(appState)
                            .listRowSeparator(.hidden)
                            .swipeActions(edge: .leading, allowsFullSwipe: true) {
                                Button {
                                    appState.toggleTaskStatus(for: task)
                                } label: {
                                    Label("Bestellt", systemImage: "checkmark.circle")
                                }
                                .tint(.green)
                            }
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .refreshable {
                    await appState.refreshTasksFromServer()
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Offene Bestellungen")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $editingTask) { task in
            NewTaskView(mode: .edit, task: task, kind: task.kind)
                .environmentObject(appState)
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "cart.fill")
                    .foregroundColor(.orange)
                Text("\(openOrders.count) offen")
                    .font(.headline)
                Spacer()
            }
            Text("Nach links wischen oder Häkchen tippen, wenn bestellt. Antippen für Details.")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func taskAssignedToCurrentUser(_ task: Task) -> Bool {
        guard let current = appState.currentUser else { return false }

        var ids = Set<String>()
        let authUid = taskIdentity(appState.auth.user?.uid)
        if !authUid.isEmpty { ids.insert(authUid) }
        let profileId = taskIdentity(current.id)
        if !profileId.isEmpty { ids.insert(profileId) }

        return ids.contains(taskIdentity(task.assignedUserId))
    }

    private func taskIdentity(_ value: String?) -> String {
        (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
