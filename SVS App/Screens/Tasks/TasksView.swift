//
//  TasksView.swift
//  SVS App
//
//  Created by Hussein Souleiman on 23.12.25.
//

import Foundation
import SwiftUI
import FirebaseFirestore

#if canImport(UIKit)
extension View {
    func svsDismissKeyboardOnTap() -> some View {
        self.simultaneousGesture(
            TapGesture().onEnded {
                UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder),
                                                to: nil, from: nil, for: nil)
            }
        )
    }
}
#endif

struct TasksView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    // Wird nur gesetzt, wenn dieser Screen als Sheet/Modal angezeigt wird.
    // Beim Push innerhalb einer NavigationStack soll der System-Back-Button genutzt werden.
    let isPresentedModally: Bool

    init(isPresentedModally: Bool = false) {
        self.isPresentedModally = isPresentedModally
    }

    @State private var showNewTaskNav = false
    @State private var editingTask: Task? = nil

    private enum TaskScope: String, CaseIterable {
        case assignedToMe = "Für mich"
        case assignedByMe = "Von mir"
    }

    private enum TaskStatusFilter: String, CaseIterable {
        case open = "Offen"
        case done = "Erledigt"
    }

    @State private var scope: TaskScope = .assignedToMe
    @State private var statusFilter: TaskStatusFilter = .open


    private var currentUser: User? { appState.currentUser }

    // Sichtbarkeit: jeder sieht (a) Aufgaben, die ihm zugeteilt sind und (b) Aufgaben, die er anderen zugeteilt hat.
    private var assignedToMe: [Task] {
        guard let user = currentUser else { return [] }
        return appState.tasks
            .filter { $0.assignedUserId == user.id }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var assignedByMeToOthers: [Task] {
        guard let user = currentUser else { return [] }
        return appState.tasks
            .filter { $0.creatorUserId == user.id && $0.assignedUserId != user.id }
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
                VStack(spacing: 14) {
                    Text("Keine Aufgaben")
                        .font(.title3)
                        .fontWeight(.semibold)

                    Text(statusFilter == .open
                         ? "Erstelle eine neue Aufgabe mit dem Plus-Button oben rechts."
                         : "Es gibt aktuell keine erledigten Aufgaben in diesem Bereich.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            }
        }
        .svsDismissKeyboardOnTap()
        .background(Color(.systemGroupedBackground))
        .navigationDestination(isPresented: $showNewTaskNav) {
            NewTaskView(mode: .new, task: nil)
                .environmentObject(appState)
        }
        .navigationDestination(item: $editingTask) { task in
            NewTaskView(mode: .edit, task: task)
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
                Button {
                    showNewTaskNav = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Neue Aufgabe")
            }
        }
    }
}


// MARK: - Task Row

struct TaskRow: View {
    @EnvironmentObject var appState: AppState
    let task: Task
    let assignedUserName: String
    let creatorName: String
    let onEdit: () -> Void
    let onToggleStatus: () -> Void
    let onDelete: () -> Void

    var body: some View {
        let accent: Color = {
            if task.status == .done { return .green }
            if let due = task.dueDate, due < Date() { return .red }
            return .blue
        }()

        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(accent.opacity(0.9))
                .frame(width: 4)
                .padding(.top, 2)

            Button(action: onToggleStatus) {
                Image(systemName: task.status == .done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(task.status == .done ? .green : .gray)
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .padding(.top, 2)

            VStack(alignment: .leading, spacing: 6) {
                Text(task.title)
                    .font(.body.weight(.semibold))
                    .foregroundColor(.primary)
                    .strikethrough(task.status == .done, color: .secondary)

                let detailsText = task.details ?? ""
                if !detailsText.isEmpty {
                    Text(detailsText)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: 8) {
                    if let due = task.dueDate {
                        HStack(spacing: 6) {
                            Image(systemName: "calendar")
                                .font(.caption2)
                            Text("Fällig: \(formattedShort(due))")
                                .font(.caption2.weight(.semibold))
                        }
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color(.secondarySystemBackground)))
                    }

                    HStack(spacing: 6) {
                        Image(systemName: "person.crop.circle")
                            .font(.caption2)
                        Text("Von: \(creatorName)")
                            .font(.caption2.weight(.semibold))
                    }
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color(.secondarySystemBackground)))

                    if let current = appState.currentUser, task.assignedUserId != current.id {
                        HStack(spacing: 6) {
                            Image(systemName: "person")
                                .font(.caption2)
                            Text("An: \(assignedUserName)")
                                .font(.caption2.weight(.semibold))
                        }
                        .foregroundColor(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color(.secondarySystemBackground)))
                    }

                    Spacer(minLength: 0)
                }
                .padding(.top, 2)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(accent.opacity(0.18), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.05), radius: 10, x: 0, y: 6)
        .contentShape(Rectangle())
        .onTapGesture {
            onEdit()
        }
        .listRowInsets(EdgeInsets(top: 6, leading: 18, bottom: 6, trailing: 18))
        .listRowBackground(Color.clear)
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button {
                onEdit()
            } label: {
                Label("Bearbeiten", systemImage: "pencil")
            }
            .tint(.blue)

            Button(role: .destructive) {
                onDelete()
            } label: {
                Label("Löschen", systemImage: "trash")
            }
        }
    }

    private func formattedShort(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateStyle = .short
        return df.string(from: date)
    }
}

// MARK: - New Task View

struct NewTaskView: View {
    enum Mode {
        case new
        case edit
    }

    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let mode: Mode
    let task: Task?

    @State private var title: String = ""
    @State private var details: String = ""
    @State private var dueDate: Date = Date()
    @State private var hasDueDate: Bool = false
    @State private var assignedUserId: String = ""
    @State private var status: TaskStatus = .open
    
    private enum Field: Hashable {
        case title
        case details
    }

    @FocusState private var focusedField: Field?

    private var isEditing: Bool { task != nil }

    private var assignableUsers: [User] {
        var list = appState.users
        if let current = appState.currentUser, !list.contains(where: { $0.id == current.id }) {
            list.insert(current, at: 0)
        }
        return list
    }

    var body: some View {
        Form {
            Section {
                TextField("Titel", text: $title)
                    .textInputAutocapitalization(.sentences)
                    .submitLabel(.next)
                    .focused($focusedField, equals: .title)
                    .onSubmit { focusedField = .details }
                TextField("Details (optional)", text: $details, axis: .vertical)
                    .lineLimit(2...6)
                    .textInputAutocapitalization(.sentences)
                    .focused($focusedField, equals: .details)
            } header: {
                Label("Aufgabe", systemImage: "text.badge.checkmark")
            }

            Section {
                Toggle("Fälligkeitsdatum setzen", isOn: $hasDueDate.animation(.easeInOut(duration: 0.2)))

                if hasDueDate {
                    DatePicker("Fällig am", selection: $dueDate, displayedComponents: .date)
                        .datePickerStyle(.compact)
                }
            } header: {
                Label("Fälligkeit", systemImage: "calendar")
            } footer: {
                Text(hasDueDate
                     ? "Wird in der Aufgabenliste als Fälligkeitsdatum angezeigt."
                     : "Ohne Fälligkeitsdatum erscheint die Aufgabe nur als offen/erledigt.")
            }

            if let current = appState.currentUser {
                Section {
                    Picker("Zuständig", selection: $assignedUserId) {
                        ForEach(assignableUsers) { user in
                            Text(user.name).tag(user.id)
                        }
                    }

                    if assignedUserId != current.id,
                       let name = assignableUsers.first(where: { $0.id == assignedUserId })?.name {
                        Text("Die Aufgabe wird \(name) zugeteilt.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Die Aufgabe wird Ihnen selbst zugeteilt.")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Label("Zuständigkeit", systemImage: "person")
                }
            }

            if isEditing {
                Section {
                    Picker("Status", selection: $status) {
                        Text("Offen").tag(TaskStatus.open)
                        Text("Erledigt").tag(TaskStatus.done)
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Label("Status", systemImage: "checkmark.seal")
                }
            }
        }
        .navigationTitle(isEditing ? "Aufgabe bearbeiten" : "Neue Aufgabe")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Speichern") { save() }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || appState.currentUser == nil)
            }
        }
        .onAppear { configureInitialState() }
        .onChange(of: assignableUsers.count) { _ in
            guard let current = appState.currentUser else { return }
            if assignedUserId.isEmpty || !assignableUsers.contains(where: { $0.id == assignedUserId }) {
                assignedUserId = current.id
            }
        }
    }

    private func configureInitialState() {
        guard let current = appState.currentUser else { return }

        if let task = task {
            title = task.title
            details = task.details ?? ""
            if let due = task.dueDate {
                dueDate = due
                hasDueDate = true
            } else {
                hasDueDate = false
            }
            assignedUserId = task.assignedUserId
            status = task.status
        } else {
            // Neue Aufgabe
            title = ""
            details = ""
            hasDueDate = false
            dueDate = Date()
            assignedUserId = current.id
            status = .open
        }
    }

    private func save() {
        guard let current = appState.currentUser else { return }
        let assigned = assignableUsers.first(where: { $0.id == assignedUserId }) ?? current
        let due: Date? = hasDueDate ? dueDate : nil

        switch mode {
        case .new:
            appState.createTask(title: title,
                                details: details,
                                dueDate: due,
                                assignedUser: assigned,
                                creator: current)
            // Push-Notification (Best Effort): Cloud Function kann auf pushQueue reagieren.
            if assigned.id != current.id {
                let db = Firestore.firestore()
                db.collection("pushQueue").addDocument(data: [
                    "type": "task_assigned",
                    "toUserId": assigned.id,
                    "fromUserId": current.id,
                    "title": "Neue Aufgabe",
                    "body": "\(current.name) hat dir eine Aufgabe zugeteilt: \(title)",
                    "createdAt": FieldValue.serverTimestamp()
                ])
            }
        case .edit:
            if var existing = task {
                existing.title = title
                existing.details = details
                existing.dueDate = due
                existing.assignedUserId = assigned.id
                existing.status = status
                appState.updateTask(existing)
            }
        }

        dismiss()
    }
}
