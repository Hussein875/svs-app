//
//  TasksView.swift
//  SVS App
//
//  Created by Hussein Souleiman on 23.12.25.
//
import Foundation
import SwiftUI

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

    enum AdminTaskScope: String, CaseIterable {
        case mine = "Meine"
        case team = "Team"
    }

    @State private var adminScope: AdminTaskScope = .mine

    private var currentUser: User? { appState.currentUser }

    private var adminScopeTint: Color {
        switch adminScope {
        case .mine: return .blue
        case .team: return .indigo
        }
    }

    // Aufgaben-Sichten für Admin / Mitarbeiter
    private var myOpenTasks: [Task] {
        guard let user = currentUser else { return [] }
        return appState.tasks
            .filter { $0.assignedUserId == user.id && $0.status == .open }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var myDoneTasks: [Task] {
        guard let user = currentUser else { return [] }
        return appState.tasks
            .filter { $0.assignedUserId == user.id && $0.status == .done }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var otherOpenTasks: [Task] {
        guard let user = currentUser, user.role == .admin else { return [] }
        return appState.tasks
            .filter { $0.assignedUserId != user.id && $0.status == .open }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var otherDoneTasks: [Task] {
        guard let user = currentUser, user.role == .admin else { return [] }
        return appState.tasks
            .filter { $0.assignedUserId != user.id && $0.status == .done }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                // Leer, wenn wirklich gar keine Aufgaben existieren
                if myOpenTasks.isEmpty && otherOpenTasks.isEmpty && myDoneTasks.isEmpty && otherDoneTasks.isEmpty {
                    VStack(spacing: 16) {
                        Text("Noch keine Aufgaben")
                            .font(.title3)
                            .fontWeight(.semibold)
                        Text("Erstellen Sie eine neue Aufgabe mit dem Plus-Button oben rechts.")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemGroupedBackground))
                } else {
                    List {
                        // Admin: Sticky Segment-Header unter dem Navigation-Header
                        if let user = currentUser, user.role == .admin {
                            Section {
                                EmptyView()
                            } header: {
                                Picker("Ansicht", selection: $adminScope) {
                                    ForEach(AdminTaskScope.allCases, id: \.self) { scope in
                                        Text(scope.rawValue).tag(scope)
                                    }
                                }
                                .pickerStyle(.segmented)
                                .tint(adminScopeTint)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 2)
                                .background(Color(.systemGroupedBackground))
                            }
                            .textCase(nil)
                            .headerProminence(.increased)
                        }

                        if let user = currentUser, user.role == .admin {
                            switch adminScope {
                            case .mine:
                                if !myOpenTasks.isEmpty {
                                    Section(header: Text("Meine Aufgaben – Offen (\(myOpenTasks.count))").textCase(nil)) {
                                        ForEach(myOpenTasks) { task in
                                            TaskRow(
                                                task: task,
                                                isAdmin: true,
                                                assignedUserName: appState.userName(for: task.assignedUserId),
                                                onEdit: { editingTask = task },
                                                onToggleStatus: { appState.toggleTaskStatus(for: task) },
                                                onDelete: { appState.deleteTask(task) }
                                            )
                                            .listRowSeparator(.hidden)
                                        }
                                    }
                                }
                            case .team:
                                if !otherOpenTasks.isEmpty {
                                    Section(header: Text("Team – Offene Aufgaben").textCase(nil)) {
                                        ForEach(otherOpenTasks) { task in
                                            TaskRow(
                                                task: task,
                                                isAdmin: true,
                                                assignedUserName: appState.userName(for: task.assignedUserId),
                                                onEdit: { editingTask = task },
                                                onToggleStatus: { appState.toggleTaskStatus(for: task) },
                                                onDelete: { appState.deleteTask(task) }
                                            )
                                            .listRowSeparator(.hidden)
                                        }
                                    }
                                }
                            }

                            if !myDoneTasks.isEmpty || !otherDoneTasks.isEmpty {
                                Section {
                                    NavigationLink {
                                        CompletedTasksView()
                                            .environmentObject(appState)
                                    } label: {
                                        HStack {
                                            Image(systemName: "checkmark.circle")
                                            Text("Erledigte Aufgaben anzeigen")
                                        }
                                    }
                                }
                            }
                        } else {
                            if !myOpenTasks.isEmpty {
                                Section(header: Text("Offen").textCase(nil)) {
                                    ForEach(myOpenTasks) { task in
                                        TaskRow(
                                            task: task,
                                            isAdmin: false,
                                            assignedUserName: appState.userName(for: task.assignedUserId),
                                            onEdit: { editingTask = task },
                                            onToggleStatus: { appState.toggleTaskStatus(for: task) },
                                            onDelete: { appState.deleteTask(task) }
                                        )
                                        .listRowSeparator(.hidden)
                                    }
                                }
                            }

                            if !myDoneTasks.isEmpty {
                                Section {
                                    NavigationLink {
                                        CompletedTasksView()
                                            .environmentObject(appState)
                                    } label: {
                                        HStack {
                                            Image(systemName: "checkmark.circle")
                                            Text("Erledigte Aufgaben anzeigen")
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(.top, 2)
                    .listRowSeparator(.hidden)
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                    .background(Color(.systemGroupedBackground))
                }
            }
        }
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
            // Nur im Sheet/Modal anzeigen – beim Push nutzen wir den System-Back-Button.
            if isPresentedModally {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Schließen") {
                        dismiss()
                    }
                }
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 10) {
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
}

// MARK: - Completed Tasks View

struct CompletedTasksView: View {
    @EnvironmentObject var appState: AppState
    @State private var editingTask: Task? = nil

    private var currentUser: User? { appState.currentUser }

    private var myDoneTasks: [Task] {
        guard let user = currentUser else { return [] }
        return appState.tasks
            .filter { $0.assignedUserId == user.id && $0.status == .done }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var otherDoneTasks: [Task] {
        guard let user = currentUser, user.role == .admin else { return [] }
        return appState.tasks
            .filter { $0.assignedUserId != user.id && $0.status == .done }
            .sorted { $0.createdAt > $1.createdAt }
    }

    var body: some View {
        List {
            if let user = currentUser, user.role == .admin {
                if !myDoneTasks.isEmpty {
                    Section(header: Text("Meine erledigten Aufgaben").textCase(nil)) {
                        ForEach(myDoneTasks) { task in
                            TaskRow(
                                task: task,
                                isAdmin: true,
                                assignedUserName: appState.userName(for: task.assignedUserId),
                                onEdit: { editingTask = task },
                                onToggleStatus: { appState.toggleTaskStatus(for: task) },
                                onDelete: { appState.deleteTask(task) }
                            )
                            .listRowSeparator(.hidden)
                        }
                    }
                }

                if !otherDoneTasks.isEmpty {
                    Section(header: Text("Erledigte Aufgaben anderer").textCase(nil)) {
                        ForEach(otherDoneTasks) { task in
                            TaskRow(
                                task: task,
                                isAdmin: true,
                                assignedUserName: appState.userName(for: task.assignedUserId),
                                onEdit: { editingTask = task },
                                onToggleStatus: { appState.toggleTaskStatus(for: task) },
                                onDelete: { appState.deleteTask(task) }
                            )
                            .listRowSeparator(.hidden)
                        }
                    }
                }

                if myDoneTasks.isEmpty && otherDoneTasks.isEmpty {
                    Text("Keine erledigten Aufgaben vorhanden")
                        .foregroundColor(.secondary)
                }
            } else {
                if !myDoneTasks.isEmpty {
                    Section(header: Text("Erledigte Aufgaben").textCase(nil)) {
                        ForEach(myDoneTasks) { task in
                            TaskRow(
                                task: task,
                                isAdmin: false,
                                assignedUserName: appState.userName(for: task.assignedUserId),
                                onEdit: { editingTask = task },
                                onToggleStatus: { appState.toggleTaskStatus(for: task) },
                                onDelete: { appState.deleteTask(task) }
                            )
                            .listRowSeparator(.hidden)
                        }
                    }
                } else {
                    Text("Keine erledigten Aufgaben vorhanden")
                        .foregroundColor(.secondary)
                }
            }
        }
                    .listRowSeparator(.hidden)
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
        .sheet(item: $editingTask) { task in
            NewTaskView(mode: .edit, task: task)
                .environmentObject(appState)
        }
        .navigationTitle("Erledigte Aufgaben")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Task Row

struct TaskRow: View {
    let task: Task
    let isAdmin: Bool
    let assignedUserName: String
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

                if !task.details.isEmpty {
                    Text(task.details)
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

                    if isAdmin {
                        HStack(spacing: 6) {
                            Image(systemName: "person")
                                .font(.caption2)
                            Text(assignedUserName)
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
    @State private var assignedUser: User?
    @State private var status: TaskStatus = .open

    private var isEditing: Bool { task != nil }

    var body: some View {
        Form {
            Section {
                TextField("Titel", text: $title)
                    .textInputAutocapitalization(.sentences)
                    .submitLabel(.next)

                TextField("Details (optional)", text: $details, axis: .vertical)
                    .lineLimit(2...6)
                    .textInputAutocapitalization(.sentences)
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
                    if current.role == .admin {
                        Picker("Mitarbeiter", selection: Binding(
                            get: { assignedUser?.id ?? current.id },
                            set: { id in
                                assignedUser = appState.users.first(where: { $0.id == id }) ?? current
                            })
                        ) {
                            ForEach(appState.users) { user in
                                Text(user.name).tag(user.id)
                            }
                        }
                    } else {
                        HStack {
                            Text("Zuständig")
                            Spacer()
                            Text(current.name)
                                .foregroundColor(.secondary)
                        }

                        Text("Aufgaben, die Sie erstellen, werden automatisch Ihnen zugewiesen.")
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
    }

    private func configureInitialState() {
        guard let current = appState.currentUser else { return }

        if let task = task {
            title = task.title
            details = task.details
            if let due = task.dueDate {
                dueDate = due
                hasDueDate = true
            } else {
                hasDueDate = false
            }
            assignedUser = appState.users.first(where: { $0.id == task.assignedUserId }) ?? current
            status = task.status
        } else {
            // Neue Aufgabe
            title = ""
            details = ""
            hasDueDate = false
            dueDate = Date()
            assignedUser = current
            status = .open
        }
    }

    private func save() {
        guard let current = appState.currentUser else { return }
        let assigned = assignedUser ?? current
        let due: Date? = hasDueDate ? dueDate : nil

        switch mode {
        case .new:
            appState.createTask(title: title,
                                details: details,
                                dueDate: due,
                                assignedUser: assigned,
                                creator: current)
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
