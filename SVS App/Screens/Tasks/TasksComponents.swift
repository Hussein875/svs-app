//
//  TasksComponents.swift
//  SVS App
//
//  Extracted from TasksView.swift for readability.
//

import Foundation
import SwiftUI
import FirebaseFirestore
import UIKit

// MARK: - Task Row

struct TaskRow: View {
    @EnvironmentObject var appState: AppState
    let task: Task
    let assignedUserName: String
    let creatorName: String
    let onEdit: () -> Void
    let onToggleStatus: () -> Void
    let onDelete: () -> Void

    private func normalizedIdentity(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isAssignedToCurrentUser: Bool {
        guard let currentId = appState.currentUser?.id else { return false }
        return normalizedIdentity(task.assignedUserId) == normalizedIdentity(currentId)
    }

    private var isCreatedByCurrentUser: Bool {
        guard let current = appState.currentUser else { return false }
        let creator = normalizedIdentity(task.creatorUserId)
        if creator == normalizedIdentity(current.id) { return true }
        let email = normalizedIdentity(current.email).lowercased()
        if email.isEmpty { return false }
        return creator.lowercased() == email || creator.lowercased() == "invite:\(email)"
    }

    private var creatorDisplayName: String {
        isCreatedByCurrentUser ? "Ich" : creatorName
    }

    private var assigneeDisplayName: String {
        isAssignedToCurrentUser ? "Ich" : assignedUserName
    }

    var body: some View {
        let accent: Color = {
            if task.status == .done { return .green }
            if let due = task.dueDate, due < Date() { return .red }
            return task.kind == .order ? .orange : .blue
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
            .accessibilityLabel(task.status == .done ? "Erledigt" : "Offen")

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(task.title)
                        .font(.body.weight(.semibold))
                        .foregroundColor(.primary)
                        .strikethrough(task.status == .done, color: .secondary)

                    if task.kind == .order {
                        Text("Bestellung")
                            .font(.caption2.weight(.bold))
                            .foregroundColor(.orange)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.orange.opacity(0.14))
                            )
                    }
                }

                HStack(spacing: 8) {
                    partyChip(prefix: "Von", name: creatorDisplayName)
                    Image(systemName: "arrow.right")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.tertiary)
                    partyChip(prefix: "An", name: assigneeDisplayName)
                }
                .padding(.top, 2)

                let detailsText = task.details
                if !detailsText.isEmpty {
                    Text(detailsText)
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 130), spacing: 8, alignment: .top)],
                    alignment: .leading,
                    spacing: 8
                ) {
                    if let due = task.dueDate {
                        metaBadge(icon: "calendar", text: "Fällig: \(formattedShort(due))")
                    }
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

    private func partyChip(prefix: String, name: String) -> some View {
        HStack(spacing: 4) {
            Text("\(prefix):")
                .foregroundStyle(.secondary)
            Text(name)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(.tertiarySystemBackground))
        )
    }

    private func formattedShort(_ date: Date) -> String {
        let df = DateFormatter()
        df.dateStyle = .short
        return df.string(from: date)
    }

    private func metaBadge(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: icon)
                .font(.caption2)
                .frame(width: 12, alignment: .leading)
                .padding(.top, 2)

            Text(text)
                .font(.caption2.weight(.semibold))
                .lineLimit(2)
                .minimumScaleFactor(0.9)
                .multilineTextAlignment(.leading)
        }
        .foregroundColor(.secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(.tertiarySystemBackground))
        )
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
    let kind: TaskKind

    @State private var title: String = ""
    @State private var details: String = ""
    @State private var dueDate: Date = Date()
    @State private var hasDueDate: Bool = false
    @State private var assignedUserId: String = ""
    @State private var status: TaskStatus = .open
    @State private var missingOfficerWarning: Bool = false

    private enum Field: Hashable {
        case title
        case details
    }

    @FocusState private var focusedField: Field?

    private var isEditing: Bool { task != nil }
    private var isOrder: Bool { (task?.kind ?? kind) == .order }
    private var isEmployee: Bool { appState.currentUser?.role == .employee }

    private var isFormValid: Bool {
        !title.trimmingCharacters(in: .whitespaces).isEmpty && appState.currentUser != nil
    }

    private var assignableUsers: [User] {
        var list = appState.users
        if let current = appState.currentUser, !list.contains(where: { $0.id == current.id }) {
            list.insert(current, at: 0)
        }
        return list
    }

    private var procurementOfficerName: String {
        if let officer = appState.procurementOfficerUser() {
            return officer.name
        }
        return "Bestellungen"
    }

    var body: some View {
        Form {
            if isOrder {
                Section {
                    Text("Beschreibe, was benötigt wird – z. B. Visitenkarten, Büromaterial oder Drucksachen. \(procurementOfficerName) kümmert sich um die Bestellung.")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }

            Section {
                TextField(isOrder ? "Was wird benötigt?" : "Titel", text: $title)
                    .textInputAutocapitalization(.sentences)
                    .submitLabel(.next)
                    .focused($focusedField, equals: .title)
                    .onSubmit { focusedField = .details }
                TextField(
                    isOrder ? "Details (Menge, Format, Hinweise …)" : "Details (optional)",
                    text: $details,
                    axis: .vertical
                )
                .lineLimit(2...6)
                .textInputAutocapitalization(.sentences)
                .focused($focusedField, equals: .details)
            } header: {
                Label(isOrder ? "Bestellung" : "Aufgabe", systemImage: isOrder ? "cart" : "text.badge.checkmark")
            }

            if !isOrder {
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
                         ? "Wird in der Liste als Fälligkeitsdatum angezeigt."
                         : "Ohne Fälligkeitsdatum erscheint die Aufgabe nur als offen/erledigt.")
                }
            }

            if let current = appState.currentUser {
                Section {
                    if isOrder && (isEmployee || mode == .new) {
                        LabeledContent("Zuständig", value: procurementOfficerName)
                        if appState.procurementOfficerUser() == nil {
                            Text("Keine Bestellungs-Verantwortliche gefunden. Bitte Admin informieren.")
                                .font(.caption)
                                .foregroundColor(.orange)
                        }
                    } else {
                        Picker("Zuständig", selection: $assignedUserId) {
                            ForEach(assignableUsers) { user in
                                Text(user.name).tag(user.id)
                            }
                        }
                        .pickerStyle(.menu)

                        if assignedUserId != current.id,
                           let name = assignableUsers.first(where: { $0.id == assignedUserId })?.name {
                            Text(isOrder
                                 ? "Die Bestellung geht an \(name)."
                                 : "Die Aufgabe wird \(name) zugeteilt.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        } else {
                            Text("Die Aufgabe wird Ihnen selbst zugeteilt.")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Label("Zuständigkeit", systemImage: "person")
                }
            }

            if isEditing {
                Section {
                    Picker("Status", selection: $status) {
                        Text(isOrder ? "Offen" : "Offen").tag(TaskStatus.open)
                        Text(isOrder ? "Bestellt / erledigt" : "Erledigt").tag(TaskStatus.done)
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Label("Status", systemImage: "checkmark.seal")
                }
            }

            if !isEditing {
                Section {
                    Button {
                        save()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: isOrder ? "cart.badge.plus" : "plus.circle.fill")
                            Text(isOrder ? "Bestellung aufgeben" : "Aufgabe anlegen")
                                .font(.subheadline.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .buttonBorderShape(.capsule)
                    .disabled(!isFormValid || (isOrder && appState.procurementOfficerUser() == nil))
                }
            }
        }
        .navigationTitle(navigationTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isEditing {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Speichern") { save() }
                        .disabled(!isFormValid)
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .contentShape(Rectangle())
        .onTapGesture {
            dismissKeyboard()
        }
        .onAppear { configureInitialState() }
        .onChange(of: assignableUsers.count) { _, _ in
            applyDefaultAssigneeIfNeeded()
        }
        .alert("Zuständige Person fehlt", isPresented: $missingOfficerWarning) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Es ist keine Person für Bestellungen hinterlegt. Bitte den Admin bitten, Yasmin als zuständig zu markieren.")
        }
    }

    private var navigationTitle: String {
        if isEditing {
            return isOrder ? "Bestellung bearbeiten" : "Aufgabe bearbeiten"
        }
        return isOrder ? "Neue Bestellung" : "Neue Aufgabe"
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
            assignedUserId = task.assignedUserId
            status = task.status
        } else {
            title = ""
            details = ""
            hasDueDate = false
            dueDate = Date()
            status = .open
            applyDefaultAssigneeIfNeeded()
        }
    }

    private func applyDefaultAssigneeIfNeeded() {
        guard let current = appState.currentUser else { return }
        guard task == nil else { return }

        if isOrder {
            if let officer = appState.procurementOfficerUser() {
                assignedUserId = officer.id
            } else {
                assignedUserId = current.id
            }
        } else if assignedUserId.isEmpty || !assignableUsers.contains(where: { $0.id == assignedUserId }) {
            assignedUserId = current.id
        }
    }

    private func save() {
        dismissKeyboard()
        guard let current = appState.currentUser else { return }

        let taskKind = task?.kind ?? kind
        let assigned: User

        if taskKind == .order {
            guard let officer = appState.procurementOfficerUser() else {
                missingOfficerWarning = true
                return
            }
            assigned = officer
        } else {
            assigned = assignableUsers.first(where: { $0.id == assignedUserId }) ?? current
        }

        let due: Date? = (taskKind == .order || !hasDueDate) ? nil : dueDate

        switch mode {
        case .new:
            appState.createTask(
                title: title,
                details: details,
                dueDate: due,
                assignedUser: assigned,
                creator: current,
                kind: taskKind
            )
            if assigned.id != current.id {
                let db = Firestore.firestore()
                let pushTitle = taskKind == .order ? "Neue Bestellung" : "Neue Aufgabe"
                let pushBody = taskKind == .order
                    ? "\(current.name) hat eine Bestellung aufgegeben: \(title)"
                    : "\(current.name) hat dir eine Aufgabe zugeteilt: \(title)"
                db.collection("pushQueue").addDocument(data: [
                    "type": "task_assigned",
                    "toUserId": assigned.id,
                    "fromUserId": current.id,
                    "title": pushTitle,
                    "body": pushBody,
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

    private func dismissKeyboard() {
        focusedField = nil
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder),
            to: nil,
            from: nil,
            for: nil
        )
    }
}
