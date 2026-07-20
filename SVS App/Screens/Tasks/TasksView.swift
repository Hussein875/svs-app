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
         startInAssignedByMe: Bool = false,
         startInDoneFilter: Bool = false) {
        self.isPresentedModally = isPresentedModally
        _scope = State(initialValue: startInAssignedByMe ? .assignedByMe : .assignedToMe)
        _statusFilter = State(initialValue: startInDoneFilter ? .done : .open)
    }

    @State private var showNewTaskNav = false
    @State private var newTaskKind: TaskKind = .general
    @State private var editingTask: Task? = nil

    private var isEmployee: Bool {
        appState.currentUser?.role == .employee
    }

    private enum TaskScope: String, CaseIterable {
        case assignedToMe = "Für mich"
        case assignedByMe = "Von mir"
    }

    private enum TaskStatusFilter: String, CaseIterable {
        case open = "Offen"
        case done = "Erledigt"
    }

    @State private var scope: TaskScope
    @State private var statusFilter: TaskStatusFilter


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
        let base: [Task] = (scope == .assignedToMe) ? assignedToMe : assignedByMeToOthers
        switch statusFilter {
        case .open: return base.filter { $0.status == .open }
        case .done: return base.filter { $0.status == .done }
        }
    }

    private var segmentTitle: String {
        switch scope {
        case .assignedToMe: return "Für mich"
        case .assignedByMe: return "Von mir"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            VStack(spacing: 10) {
                Picker("Scope", selection: $scope) {
                    ForEach(TaskScope.allCases, id: \.self) { s in
                        Text(s.rawValue).tag(s)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)

            if visibleTasks.isEmpty {
                ScrollView {
                    VStack(spacing: 14) {
                        Text("Keine Einträge")
                            .font(.title3)
                            .fontWeight(.semibold)

                        Text(statusFilter == .open
                             ? (isEmployee
                                ? "Erstelle eine Bestellung mit dem Plus-Button oben rechts – z. B. Visitenkarten oder Büromaterial."
                                : "Erstelle eine Aufgabe oder Bestellung mit dem Plus-Button oben rechts.")
                             : "Es gibt aktuell keine erledigten Einträge in diesem Bereich.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 80)
                }
                .refreshable {
                    await appState.refreshTasksFromServer()
                }
                .background(Color(.systemGroupedBackground))
            } else {
                List {
                    Section(header: Text("\(segmentTitle) – \(statusFilter.rawValue) (\(visibleTasks.count))").textCase(nil)) {
                        ForEach(visibleTasks) { task in
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
        .gesture(
            DragGesture(minimumDistance: 20, coordinateSpace: .local)
                .onEnded { value in
                    // Horizontal swipe detection
                    if abs(value.translation.width) > abs(value.translation.height) {
                        if value.translation.width < 0 {
                            // Swipe left
                            if scope == .assignedToMe {
                                scope = .assignedByMe
                            }
                        } else {
                            // Swipe right
                            if scope == .assignedByMe {
                                scope = .assignedToMe
                            }
                        }
                    }
                }
        )
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
