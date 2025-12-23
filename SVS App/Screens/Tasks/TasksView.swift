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
    @State private var showNewTask = false
    @State private var editingTask: Task? = nil

    private var currentUser: User? { appState.currentUser }

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
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Aufgaben")
                        .font(.largeTitle.weight(.bold))

                    Spacer()

                    Button {
                        showNewTask = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(Color(.secondarySystemBackground)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Neue Aufgabe")
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)

                Group {
                    // Leer, wenn wirklich gar keine Aufgaben existieren
                    if myOpenTasks.isEmpty && otherOpenTasks.isEmpty && myDoneTasks.isEmpty && otherDoneTasks.isEmpty {
                        VStack(spacing: 12) {
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
                            if let user = currentUser, user.role == .admin {
                                // Admin: Meine offenen Aufgaben
                                if !myOpenTasks.isEmpty {
                                    Section(header: Text("Meine Aufgaben – Offen")) {
                                        ForEach(myOpenTasks) { task in
                                            TaskRow(
                                                task: task,
                                                isAdmin: true,
                                                assignedUserName: appState.userName(for: task.assignedUserId),
                                                onEdit: { editingTask = task },
                                                onToggleStatus: { appState.toggleTaskStatus(for: task) },
                                                onDelete: { appState.deleteTask(task) }
                                            )
                                        }
                                    }
                                }

                                // Admin: Offene Aufgaben anderer
                                if !otherOpenTasks.isEmpty {
                                    Section(header: Text("Andere Aufgaben – Offen")) {
                                        ForEach(otherOpenTasks) { task in
                                            TaskRow(
                                                task: task,
                                                isAdmin: true,
                                                assignedUserName: appState.userName(for: task.assignedUserId),
                                                onEdit: { editingTask = task },
                                                onToggleStatus: { appState.toggleTaskStatus(for: task) },
                                                onDelete: { appState.deleteTask(task) }
                                            )
                                        }
                                    }
                                }

                                // Link zu erledigten Aufgaben (nur wenn es welche gibt)
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
                                // Mitarbeiter / Sachverständige: nur eigene offene Aufgaben
                                if !myOpenTasks.isEmpty {
                                    Section(header: Text("Offen")) {
                                        ForEach(myOpenTasks) { task in
                                            TaskRow(
                                                task: task,
                                                isAdmin: false,
                                                assignedUserName: appState.userName(for: task.assignedUserId),
                                                onEdit: { editingTask = task },
                                                onToggleStatus: { appState.toggleTaskStatus(for: task) },
                                                onDelete: { appState.deleteTask(task) }
                                            )
                                        }
                                    }
                                }

                                // Link zu eigenen erledigten Aufgaben
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
                        .listStyle(.insetGrouped)
                        .scrollContentBackground(.hidden)
                        .background(Color(.systemGroupedBackground))
                    }
                }
            }
            .background(Color(.systemGroupedBackground))
            .sheet(isPresented: $showNewTask) {
                NewTaskView(mode: .new, task: nil)
                    .environmentObject(appState)
            }
            .sheet(item: $editingTask) { task in
                NewTaskView(mode: .edit, task: task)
                    .environmentObject(appState)
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
                    Section(header: Text("Meine erledigten Aufgaben")) {
                        ForEach(myDoneTasks) { task in
                            TaskRow(
                                task: task,
                                isAdmin: true,
                                assignedUserName: appState.userName(for: task.assignedUserId),
                                onEdit: { editingTask = task },
                                onToggleStatus: { appState.toggleTaskStatus(for: task) },
                                onDelete: { appState.deleteTask(task) }
                            )
                        }
                    }
                }

                if !otherDoneTasks.isEmpty {
                    Section(header: Text("Erledigte Aufgaben anderer")) {
                        ForEach(otherDoneTasks) { task in
                            TaskRow(
                                task: task,
                                isAdmin: true,
                                assignedUserName: appState.userName(for: task.assignedUserId),
                                onEdit: { editingTask = task },
                                onToggleStatus: { appState.toggleTaskStatus(for: task) },
                                onDelete: { appState.deleteTask(task) }
                            )
                        }
                    }
                }

                if myDoneTasks.isEmpty && otherDoneTasks.isEmpty {
                    Text("Keine erledigten Aufgaben vorhanden")
                        .foregroundColor(.secondary)
                }
            } else {
                if !myDoneTasks.isEmpty {
                    Section(header: Text("Erledigte Aufgaben")) {
                        ForEach(myDoneTasks) { task in
                            TaskRow(
                                task: task,
                                isAdmin: false,
                                assignedUserName: appState.userName(for: task.assignedUserId),
                                onEdit: { editingTask = task },
                                onToggleStatus: { appState.toggleTaskStatus(for: task) },
                                onDelete: { appState.deleteTask(task) }
                            )
                        }
                    }
                } else {
                    Text("Keine erledigten Aufgaben vorhanden")
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("Erledigte Aufgaben")
        .sheet(item: $editingTask) { task in
            NewTaskView(mode: .edit, task: task)
                .environmentObject(appState)
        }
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
        HStack {
            Button(action: onToggleStatus) {
                Image(systemName: task.status == .done ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(task.status == .done ? .green : .gray)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                Text(task.title)
                    .font(.body)
                    .strikethrough(task.status == .done, color: .secondary)

                if !task.details.isEmpty {
                    Text(task.details)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }

                HStack(spacing: 8) {
                    if let due = task.dueDate {
                        Text("Fällig: \(formattedShort(due))")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    if isAdmin {
                        Text("für \(assignedUserName)")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }

            Spacer()

            Menu {
                Button("Bearbeiten", action: onEdit)
                Button("Löschen", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundColor(.secondary)
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
        NavigationView {
            Form {
                Section(header: Text("Aufgabe")) {
                    TextField("Titel", text: $title)

                    TextField("Details (optional)", text: $details, axis: .vertical)
                        .lineLimit(1...4)
                }

                Section(header: Text("Fälligkeit")) {
                    Toggle("Fälligkeitsdatum setzen", isOn: $hasDueDate)
                    if hasDueDate {
                        DatePicker("Fällig am", selection: $dueDate, displayedComponents: .date)
                    }
                }

                if let current = appState.currentUser {
                    Section(header: Text("Zuständig")) {
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
                            Text(current.name)
                            Text("Aufgaben, die Sie erstellen, werden automatisch Ihnen zugewiesen.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                if isEditing {
                    Section(header: Text("Status")) {
                        Picker("Status", selection: $status) {
                            Text("Offen").tag(TaskStatus.open)
                            Text("Erledigt").tag(TaskStatus.done)
                        }
                        .pickerStyle(.segmented)
                    }
                }
            }
            .navigationTitle(isEditing ? "Aufgabe bearbeiten" : "Neue Aufgabe")
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Abbrechen") {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Speichern") {
                        save()
                    }
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty || appState.currentUser == nil)
                }
            }
            .onAppear {
                configureInitialState()
            }
        }
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
