//
//  TasksView.swift
//  SVS App
//
//  Created by Hussein Souleiman on 23.12.25.
//

import Foundation
import SwiftUI
import FirebaseAuth

struct TasksView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    // Wird nur gesetzt, wenn dieser Screen als Sheet/Modal angezeigt wird.
    // Beim Push innerhalb einer NavigationStack soll der System-Back-Button genutzt werden.
    let isPresentedModally: Bool

    init(isPresentedModally: Bool = false,
         startInDoneFilter: Bool = false) {
        self.isPresentedModally = isPresentedModally
        _statusFilter = State(initialValue: startInDoneFilter ? .done : .open)
    }

    @State private var showNewTaskNav = false
    @State private var newTaskKind: TaskKind = .general
    @State private var editingTask: Task? = nil

    private var isEmployee: Bool {
        appState.currentUser?.role == .employee
    }

    private enum TaskStatusFilter: String, CaseIterable {
        case open = "Offen"
        case done = "Erledigt"
    }

    @State private var statusFilter: TaskStatusFilter

    private var accent: Color {
        appState.currentUser?.color ?? Color(red: 0.09, green: 0.40, blue: 0.75)
    }

    private var visibleOrders: [Task] {
        visibleTasks.filter { $0.kind == .order }
    }

    private var visibleGeneralTasks: [Task] {
        visibleTasks.filter { $0.kind == .general }
    }

    private var showsOrderQuickAction: Bool {
        statusFilter == .open
    }

    private var showsProcurementInbox: Bool {
        guard let user = appState.currentUser else { return false }
        return user.isProcurementOfficer && user.role != .admin
    }

    private var openProcurementInboxCount: Int {
        guard let uid = appState.currentUser?.id else { return 0 }
        let normalizedUid = uid.trimmingCharacters(in: .whitespacesAndNewlines)
        return appState.tasks.filter {
            $0.kind == .order
                && $0.status == .open
                && $0.assignedUserId.trimmingCharacters(in: .whitespacesAndNewlines) == normalizedUid
        }.count
    }


    private var currentUser: User? { appState.currentUser }
    
    private func normalizedIdentity(_ value: String?) -> String {
        (value ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var currentIdentitySet: Set<String> {
        var ids = Set<String>()

        let authUid = normalizedIdentity(appState.auth.user?.uid)
        if !authUid.isEmpty { ids.insert(authUid) }

        let profileId = normalizedIdentity(currentUser?.id)
        if !profileId.isEmpty { ids.insert(profileId) }

        return ids
    }

    private var legacyIdentitySet: Set<String> {
        guard let emailRaw = currentUser?.email else { return [] }
        let email = normalizedIdentity(emailRaw).lowercased()
        if email.isEmpty { return [] }
        return [email, "invite:\(email)"]
    }

    // Sichtbarkeit: jeder sieht (a) Aufgaben, die ihm zugeteilt sind und (b) Aufgaben, die er anderen zugeteilt hat.
    private var assignedToMe: [Task] {
        guard !currentIdentitySet.isEmpty else { return [] }
        return appState.tasks
            .filter { task in
                currentIdentitySet.contains(normalizedIdentity(task.assignedUserId))
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var assignedByMeToOthers: [Task] {
        guard !currentIdentitySet.isEmpty else { return [] }
        return appState.tasks
            .filter { task in
                let creator = normalizedIdentity(task.creatorUserId)
                let assigned = normalizedIdentity(task.assignedUserId)
                let isCreatedByMe =
                    currentIdentitySet.contains(creator) ||
                    legacyIdentitySet.contains(creator.lowercased())
                let isAssignedToMe = currentIdentitySet.contains(assigned)
                return isCreatedByMe && !isAssignedToMe
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var visibleTasks: [Task] {
        guard !currentIdentitySet.isEmpty else { return [] }

        let relevant = (assignedToMe + assignedByMeToOthers)
            .reduce(into: [UUID: Task]()) { partial, task in
                partial[task.id] = task
            }
            .values
            .sorted { $0.createdAt > $1.createdAt }

        switch statusFilter {
        case .open: return relevant.filter { $0.status == .open }
        case .done: return relevant.filter { $0.status == .done }
        }
    }

    private var orderQuickActionCard: some View {
        Button {
            newTaskKind = .order
            showNewTaskNav = true
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "cart.badge.plus")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.orange)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(Color.orange.opacity(0.14))
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text("Bestellung aufgeben")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text("Büromaterial, Visitenkarten, Drucksachen …")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Color.orange.opacity(0.22), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Bestellung aufgeben")
    }

    private var procurementInboxCard: some View {
        NavigationLink {
            AdminOpenOrdersScreen(scope: .assignedToCurrentUser)
                .environmentObject(appState)
        } label: {
            HStack(spacing: 14) {
                Image(systemName: "tray.full.fill")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(accent)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(accent.opacity(0.14))
                    )

                VStack(alignment: .leading, spacing: 3) {
                    Text("Offene Bestellungen")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    Text(openProcurementInboxCount == 0
                         ? "Keine offenen Aufträge"
                         : "\(openProcurementInboxCount) offen – jetzt bearbeiten")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                Image(systemName: "chevron.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(accent.opacity(0.22), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Offene Bestellungen")
    }

    private func ordersSectionHeader(count: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "cart.fill")
            Text("Bestellungen")
            Text("(\(count))")
                .foregroundStyle(.secondary)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(.orange)
        .textCase(nil)
    }

    private func tasksSectionHeader(count: Int) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "checklist")
            Text("Aufgaben")
            Text("(\(count))")
                .foregroundStyle(.secondary)
        }
        .font(.subheadline.weight(.semibold))
        .foregroundStyle(accent)
        .textCase(nil)
    }

    @ViewBuilder
    private func taskRow(for task: Task) -> some View {
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
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showsProcurementInbox && statusFilter == .open {
                procurementInboxCard
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
            }

            if showsOrderQuickAction {
                orderQuickActionCard
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
            }

            if visibleTasks.isEmpty {
                ScrollView {
                    VStack(spacing: 14) {
                        Text("Keine Einträge")
                            .font(.title3)
                            .fontWeight(.semibold)

                        Text(statusFilter == .open
                             ? (isEmployee
                                ? "Tippe oben auf „Bestellung aufgeben“ – z. B. für Visitenkarten oder Büromaterial."
                                : "Lege oben eine Bestellung an oder eine Aufgabe mit dem Plus-Button.")
                             : "Es gibt aktuell keine erledigten Einträge in diesem Bereich.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
                }
                .refreshable {
                    await appState.refreshTasksFromServer()
                }
                .background(Color(.systemGroupedBackground))
            } else {
                List {
                    if !visibleOrders.isEmpty {
                        Section(header: ordersSectionHeader(count: visibleOrders.count)) {
                            ForEach(visibleOrders) { task in
                                taskRow(for: task)
                            }
                        }
                    }

                    if !visibleGeneralTasks.isEmpty {
                        Section(header: tasksSectionHeader(count: visibleGeneralTasks.count)) {
                            ForEach(visibleGeneralTasks) { task in
                                taskRow(for: task)
                            }
                        }
                    }
                }
                .listRowSeparator(.hidden)
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(Color(.systemGroupedBackground))
                .refreshable {
                    await appState.refreshTasksFromServer()
                }
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationDestination(isPresented: $showNewTaskNav) {
            NewTaskView(mode: .new, task: nil, kind: newTaskKind)
                .environmentObject(appState)
        }
        .navigationDestination(item: $editingTask) { task in
            NewTaskView(mode: .edit, task: task, kind: task.kind)
                .environmentObject(appState)
        }
        .navigationTitle("Aufgaben")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isPresentedModally {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Schließen") { dismiss() }
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    Picker("Status", selection: $statusFilter) {
                        ForEach(TaskStatusFilter.allCases, id: \.self) { s in
                            Text(s.rawValue).tag(s)
                        }
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                        .accessibilityLabel("Filter")
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                if isEmployee {
                    Button {
                        newTaskKind = .order
                        showNewTaskNav = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Neue Bestellung")
                } else {
                    Menu {
                        Button {
                            newTaskKind = .order
                            showNewTaskNav = true
                        } label: {
                            Label("Bestellung aufgeben", systemImage: "cart.badge.plus")
                        }

                        Button {
                            newTaskKind = .general
                            showNewTaskNav = true
                        } label: {
                            Label("Aufgabe anlegen", systemImage: "checklist")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("Neu")
                }
            }
        }
    }
}
