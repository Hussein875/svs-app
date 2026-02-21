//
//  AdminUserManagementViews.swift
//  SVS App
//
//  Extracted from AdminConsoleView.swift for readability.
//

import Foundation
import SwiftUI
import UIKit

enum AdminUserRoleFilter: String, CaseIterable, Identifiable {
    case all = "Alle"
    case admins = "Admins"
    case employees = "Mitarbeiter"
    case experts = "SV"
    var id: String { rawValue }
}

enum AdminUserSortMode: String, CaseIterable, Identifiable {
    case name = "Name"
    var id: String { rawValue }
}

// MARK: - Admin Users Screen

struct AdminUsersScreen: View {
    @EnvironmentObject var appState: AppState
    @State private var roleFilter: AdminUserRoleFilter = .all
    @State private var sortMode: AdminUserSortMode = .name

    private func matchesRole(_ user: User) -> Bool {
        switch roleFilter {
        case .all: return true
        case .admins: return user.role == .admin
        case .employees: return user.role == .employee
        case .experts: return user.role == .expert
        }
    }

    private var filteredUsers: [User] {
        let base = appState.users
            .filter { matchesRole($0) }

        switch sortMode {
        case .name:
            return base.sorted { $0.name.lowercased() < $1.name.lowercased() }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Rolle", selection: $roleFilter) {
                        ForEach(AdminUserRoleFilter.allCases) { f in
                            Text(f.rawValue).tag(f)
                        }
                    }
                    .pickerStyle(.segmented)
                    }
                .padding(.horizontal, 18)

                List {
                    Section(header: Text("Mitarbeiter")) {
                        ForEach(filteredUsers) { user in
                            NavigationLink {
                                EditUserView(user: user).environmentObject(appState)
                            } label: {
                                AdminUserCard(user: user).environmentObject(appState)
                            }
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(Color(.systemGroupedBackground))
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Nutzerverwaltung")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        AddUserView()
                            .environmentObject(appState)
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
        }
    }
    
    private struct AdminUserCard: View {
        let user: User
        @EnvironmentObject var appState: AppState

        private var used: Int { appState.usedVacationDays(for: user) }
        private var remaining: Int { appState.remainingLeaveDays(for: user) }
        private var warning: Bool { remaining <= 5 }

        private var sickCount: Int {
            appState.leaveRequests
                .filter { $0.user.id == user.id }
                .filter { $0.type == .sick }
                .filter { $0.status == .approved }
                .count
        }

        private var onCallCountThisYear: Int {
            let cal = Calendar.current
            let year = cal.component(.year, from: Date())
            return appState.leaveRequests
                .filter { $0.user.id == user.id }
                .filter { $0.type == .onCallSaturday }
                .filter { $0.status != .rejected }
                .filter { cal.component(.year, from: $0.startDate) == year }
                .count
        }

        var body: some View {
            HStack(spacing: 12) {
                Circle().fill(user.color).frame(width: 12, height: 12)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(user.name)
                            .font(.headline)
                            .foregroundColor(user.color)

                        Spacer()

                        Text(roleText(for: user.role))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 10) {
                            Text("Urlaub: \(user.annualLeaveDays)")
                                .font(.caption2)
                                .foregroundColor(.secondary)

                            Text("Genutzt: \(used)")
                                .font(.caption2)
                                .foregroundColor(.secondary)

                            Text("Rest: \(remaining)")
                                .font(.caption2.weight(.semibold))
                                .foregroundColor(warning ? .red : .secondary)

                            if warning {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.caption2)
                                    .foregroundColor(.red)
                            }

                            Spacer()
                        }

                        HStack(spacing: 10) {
                            Text("Krank: \(sickCount)")
                                .font(.caption2)
                                .foregroundColor(.secondary)

                            if user.role == .admin || user.role == .expert {
                                Text("Bereitschaft: \(onCallCountThisYear)")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()
                        }
                    }
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke((warning ? Color.red : user.color).opacity(0.12), lineWidth: 1)
            )
        }

        private func roleText(for role: UserRole) -> String {
            switch role {
            case .admin: return "Admin"
            case .employee: return "Mitarbeiter"
            case .expert: return "Sachverständiger"
            }
        }
    }
}

// MARK: - Color Name Translation Helper
//private func germanColorName(_ key: String) -> String {
//    Color.svsGermanColorName(from: key)
//}

struct EditUserView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    @State var user: User

    @State private var showNewRequest: Bool = false
    @State private var showPinResetAlert: Bool = false
    @State private var showLoginAlert: Bool = false
    @State private var showDeleteConfirm: Bool = false
    @State private var showDeleteSuccess: Bool = false
    @State private var isDeletingUser: Bool = false
    @State private var deleteErrorMessage: String? = nil

    @State private var showUnsavedConfirm: Bool = false
    @State private var initialSnapshot: UserEditSnapshot? = nil

    private let availableColors = UserColor.allCases
    
    private struct UserEditSnapshot: Equatable {
        let name: String
        let role: UserRole
        let annualLeaveDays: Int
        let colorName: String
        let birthday: Date?
    }

    private func normalizedBirthday(_ date: Date?) -> Date? {
        guard let date else { return nil }
        return Calendar.current.startOfDay(for: date)
    }

    private var hasUnsavedChanges: Bool {
        guard let s = initialSnapshot else { return false }
        return s != UserEditSnapshot(
            name: user.name,
            role: user.role,
            annualLeaveDays: user.annualLeaveDays,
            colorName: user.colorName,
            birthday: normalizedBirthday(user.birthday)
        )
    }

    var body: some View {
        Form {
            Section(header: Text("Allgemein")) {
                TextField("Name", text: binding(for: \.name))
                Picker("Rolle", selection: binding(for: \.role)) {
                    Text("Admin").tag(UserRole.admin)
                    Text("Mitarbeiter").tag(UserRole.employee)
                    Text("SV").tag(UserRole.expert)
                }
                .pickerStyle(.segmented)
            }

            Section(header: Text("Login"), footer: Text("Passwörter werden über Firebase Auth verwaltet.")) {
                Text(user.email)
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                Button {
                    appState.sendPasswordReset(to: user.email)
                    showLoginAlert = true
                } label: {
                    Label("Passwort-Reset senden", systemImage: "envelope")
                }
            }

            Section(header: Text("Urlaub")) {
                Stepper(value: binding(for: \.annualLeaveDays), in: 0...365) {
                    Text("Jahresurlaub: \(user.annualLeaveDays) Tage")
                }
            }

            Section(header: Text("Farbe")) {
                Picker("Farbe", selection: binding(for: \.colorName)) {
                    ForEach(availableColors, id: \.self) { color in
                        Text(color.germanName)
                            .tag(color.rawValue)
                    }
                }
            }

            Section(header: Text("Geburtstag")) {
                DatePicker(
                    "Geburtstag",
                    selection: Binding(
                        get: { user.birthday ?? (Calendar.current.date(from: DateComponents(year: 2000, month: 1, day: 1)) ?? Date()) },
                        set: { user.birthday = Calendar.current.startOfDay(for: $0) }
                    ),
                    displayedComponents: .date
                )
                .datePickerStyle(.compact)
            }

            Section {
                Button("Mitarbeiter löschen", role: .destructive) {
                    showDeleteConfirm = true
                }
                .disabled(isDeletingUser)
            }
        }
        .navigationTitle("Mitarbeiter bearbeiten")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Speichern") {
                    appState.updateUser(user)
                    // Update snapshot so we don't re-prompt if the user stays on screen
                    initialSnapshot = UserEditSnapshot(
                        name: user.name,
                        role: user.role,
                        annualLeaveDays: user.annualLeaveDays,
                        colorName: user.colorName,
                        birthday: normalizedBirthday(user.birthday)
                    )
                    dismiss()
                }
                .font(.subheadline.weight(.semibold))
                .disabled(!hasUnsavedChanges || isDeletingUser)
            }
        }
        .alert("Mitarbeiter löschen?", isPresented: $showDeleteConfirm) {
            Button("Löschen", role: .destructive) {
                performDeleteUser()
            }
            Button("Abbrechen", role: .cancel) { }
        } message: {
            Text("Dieser Vorgang kann nicht rückgängig gemacht werden.")
        }
        .alert("Ungespeicherte Änderungen", isPresented: $showUnsavedConfirm) {
            Button("Speichern") {
                appState.updateUser(user)
                dismiss()
            }

            Button("Verwerfen", role: .destructive) {
                dismiss()
            }

            Button("Abbrechen", role: .cancel) { }
        } message: {
            Text("Speichern?")
        }
        .sheet(isPresented: $showNewRequest) {
            NavigationStack {
                NewLeaveRequestView(preselectedUserId: user.id)
                    .environmentObject(appState)
            }
        }
        .alert("Passwort-Reset", isPresented: $showLoginAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Wenn der Account existiert, wurde eine Passwort-Reset E-Mail an \(user.email) gesendet.")
        }
        .alert("Mitarbeiter gelöscht", isPresented: $showDeleteSuccess) {
            Button("OK", role: .cancel) {
                dismiss()
            }
        } message: {
            Text("\(user.name) wurde erfolgreich gelöscht.")
        }
        .alert(
            "Löschen fehlgeschlagen",
            isPresented: Binding(
                get: { deleteErrorMessage != nil },
                set: { _ in deleteErrorMessage = nil }
            )
        ) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(deleteErrorMessage ?? "Unbekannter Fehler.")
        }
        .overlay {
            if isDeletingUser {
                ZStack {
                    Color.black.opacity(0.12).ignoresSafeArea()
                    ProgressView("Mitarbeiter wird gelöscht…")
                        .padding(18)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color(.secondarySystemBackground))
                        )
                }
            }
        }
        .onAppear {
            if initialSnapshot == nil {
                initialSnapshot = UserEditSnapshot(
                    name: user.name,
                    role: user.role,
                    annualLeaveDays: user.annualLeaveDays,
                    colorName: user.colorName,
                    birthday: normalizedBirthday(user.birthday)
                )
            }
        }
    }

    private func binding<Value>(for keyPath: WritableKeyPath<User, Value>) -> Binding<Value> {
        Binding(
            get: { user[keyPath: keyPath] },
            set: { user[keyPath: keyPath] = $0 }
        )
    }

    private func performDeleteUser() {
        guard !isDeletingUser else { return }
        isDeletingUser = true

        _Concurrency.Task {
            let success = await appState.deleteUser(user)
            await MainActor.run {
                isDeletingUser = false
                if success {
                    showDeleteSuccess = true
                } else {
                    deleteErrorMessage = appState.uiErrorMessage ?? "Profil konnte nicht gelöscht werden."
                }
            }
        }
    }

}

/**
 Admin-Flow
 1.    Admin legt Mitarbeiter an
 2.    Cloud Function:
 •    erstellt Firebase-Auth-User
 •    speichert Profil in Firestore
 3.    App:
 •    sendet Passwort-Reset
 4.    Mitarbeiter:
 •    setzt eigenes Passwort
 •    loggt sich ein
 */

struct AddUserView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    @State private var name: String = ""
    @State private var email: String = ""
    @State private var role: UserRole = .employee
    @State private var annualLeaveDays: Int = 24
    @State private var birthday: Date? = nil
    @State private var isCreating: Bool = false

    private let availableColors = UserColor.allCases
    
    private enum Field: Hashable {
        case name
        case email
    }
    @FocusState private var focusedField: Field?
    
    var body: some View {
        Form {
            Section(header: Text("Allgemein")) {
                TextField("Name", text: $name)
                    .focused($focusedField, equals: .name)
                    .submitLabel(.next)
                    .onSubmit { focusedField = .email }
                TextField("E-Mail", text: $email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .focused($focusedField, equals: .email)
                    .submitLabel(.done)
                    .onSubmit { dismissKeyboard() }
                Picker("Rolle", selection: $role) {
                    Text("Admin").tag(UserRole.admin)
                    Text("Mitarbeiter").tag(UserRole.employee)
                    Text("SV").tag(UserRole.expert)
                }
                .pickerStyle(.segmented)
            }

            Section(header: Text("Urlaub")) {
                Stepper(value: $annualLeaveDays, in: 0...365) {
                    Text("Jahresurlaub: \(annualLeaveDays) Tage")
                }
            }

            Section {
                Text("Farbe wird automatisch zufällig vergeben.")
                    .font(.footnote)
                    .foregroundColor(.secondary)
            }

            Section(header: Text("Geburtstag")) {
                DatePicker(
                    "Geburtstag",
                    selection: Binding(
                        get: { birthday ?? (Calendar.current.date(from: DateComponents(year: 2000, month: 1, day: 1)) ?? Date()) },
                        set: { birthday = Calendar.current.startOfDay(for: $0) }
                    ),
                    displayedComponents: .date
                )
                .datePickerStyle(.compact)
            }

            Section {
                Button {
                    dismissKeyboard()
                    let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    let cleanName  = name.trimmingCharacters(in: .whitespacesAndNewlines)

                    guard !isCreating else { return }
                    isCreating = true

                    _Concurrency.Task {
                        let colorName = availableColors.randomElement()?.rawValue ?? "gray"
                        await appState.adminCreateUserViaFunction(
                            name: cleanName,
                            email: cleanEmail,
                            role: role,
                            colorName: colorName,
                            annualLeaveDays: annualLeaveDays,
                            birthday: birthday.map { Calendar.current.startOfDay(for: $0) }
                        )

                        isCreating = false
                        dismiss()
                    }
                } label: {
                    HStack(spacing: 10) {
                        if isCreating {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "person.badge.plus")
                        }

                        Text(isCreating ? "Wird erstellt…" : "Mitarbeiter erstellen")
                            .font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .disabled(
                    isCreating ||
                    name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ||
                    email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .overlay {
            if isCreating {
                ZStack {
                    Color.black.opacity(0.12)
                        .ignoresSafeArea()

                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Mitarbeiter wird erstellt…")
                            .font(.footnote.weight(.semibold))
                            .foregroundColor(.secondary)
                    }
                    .padding(18)
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(.secondarySystemBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
                    )
                }
            }
        }
        .navigationTitle("Neuer Mitarbeiter")
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
