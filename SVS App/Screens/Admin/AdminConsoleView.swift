//
//  AdminConsoleView.swift
//  SVS App
//
//  Created by Hussein Souleiman on 23.12.25.
//
import Foundation
import SwiftUI
import FirebaseFirestore

struct AdminConsoleView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {

                    HStack(alignment: .firstTextBaseline) {
                        Text("Admin")
                            .font(.largeTitle.weight(.bold))

                        Spacer()
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 8)

                    // KPI Cards (3, including Bereitschaft)
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                        AdminStatCard(
                            title: "Offene Anträge",
                            value: "\(openVacationRequestsCount)",
                            systemImage: "doc.text",
                            accent: appState.currentUser?.color ?? .secondary
                        )

                        AdminStatCard(
                            title: "Heute abwesend",
                            value: "\(todayAbsentCount)",
                            systemImage: "calendar.badge.clock",
                            accent: appState.currentUser?.color ?? .secondary
                        )
                    }
                    .padding(.horizontal, 18)


                    VStack(alignment: .leading, spacing: 10) {
                        Text("Übersicht")
                            .font(.headline)
                            .padding(.horizontal, 18)

                        VStack(spacing: 10) {
                            NavigationLink {
                                AdminRequestsScreen()
                                    .environmentObject(appState)
                            } label: {
                                AdminNavRow(
                                    title: "Anträge verwalten",
                                    subtitle: "Genehmigen, ablehnen und filtern",
                                    systemImage: "doc.text.magnifyingglass",
                                    accent: appState.currentUser?.color ?? .secondary
                                )
                            }

                            NavigationLink {
                                AdminUsersScreen()
                                    .environmentObject(appState)
                            } label: {
                                AdminNavRow(title: "Mitarbeiter",
                                            subtitle: "Daten, Rollen und Login verwalten",
                                            systemImage: "person.2", accent: appState.currentUser?.color ?? .secondary
)
                            }

                            NavigationLink {
                                AdminOnCallSaturdaysScreen()
                                    .environmentObject(appState)
                            } label: {
                                AdminNavRow(title: "Samstags-Bereitschaft",
                                            subtitle: "Samstage zuweisen",
                                            systemImage: "person.badge.clock", accent: appState.currentUser?.color ?? .secondary)
                            }
                            
                            NavigationLink {
                                AdminAutomationsScreen(automationId: "auto_gutachten_ablage")
                                    .environmentObject(appState)
                            } label: {
                                AdminNavRow(title: "Automatisierungen",
                                            subtitle: "Make-Status und letzte Läufe",
                                            systemImage: "bolt.badge.clock", accent: appState.currentUser?.color ?? .secondary)
                            }
                            
                        }
                        .padding(.horizontal, 18)
                    }

                    Spacer(minLength: 18)
                }
                .padding(.top, 2)
            }
            .background(Color(.systemGroupedBackground))
        }
    }
    
    private struct AdminStatCard: View {
        let title: String
        let value: String
        let systemImage: String
        let accent: Color

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: systemImage).foregroundColor(accent)
                    Spacer()
                }
                Text(value).font(.title2.weight(.bold))
                Text(title).font(.caption).foregroundColor(accent.opacity(0.8))
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(accent.opacity(0.22), lineWidth: 1))
        }
    }

    private struct AdminNavRow: View {
        let title: String
        let subtitle: String
        let systemImage: String
        let accent: Color

        var body: some View {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(Color(.secondarySystemBackground))
                    Image(systemName: systemImage)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.secondary)
                }
                .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(accent)
                    Text(subtitle).font(.caption).foregroundColor(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
                    .font(.caption.weight(.semibold))
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
            .contentShape(Rectangle())
        }
    }

    private var openVacationRequestsCount: Int {
        appState.leaveRequests.filter { $0.type == .vacation && $0.status == .pending }.count
    }

    private var todayAbsentCount: Int {
        let today = Calendar.current.startOfDay(for: Date())

        // "Abwesend" means Urlaub oder Krankheit.
        // Samstags-Bereitschaft ist KEINE Abwesenheit und darf hier nicht mitgezählt werden.
        let todays = appState.requests(for: today)
            .filter { $0.status == .approved }
            .filter { $0.type == .vacation || $0.type == .sick }

        return Set(todays.map { $0.user.id }).count
    }

    private var upcomingOnCallCount: Int {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return appState.leaveRequests
            .filter { $0.type == .onCallSaturday && $0.status == .approved }
            .filter { cal.startOfDay(for: $0.startDate) >= today }
            .count
    }
}




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
        .navigationTitle("Anträge")
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

enum AdminUserRoleFilter: String, CaseIterable, Identifiable {
    case all = "Alle"
    case admins = "Admins"
    case employees = "Mitarbeiter"
    case experts = "Sachverständige"
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
                HStack(alignment: .firstTextBaseline) {
                    Text("Mitarbeiter")
                        .font(.largeTitle.weight(.bold))

                    Spacer()

                    NavigationLink {
                        AddUserView()
                            .environmentObject(appState)
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(Color(.secondarySystemBackground)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Neuen Mitarbeiter erstellen")
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)

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
        }
    }
    
    private struct AdminUserCard: View {
        let user: User
        @EnvironmentObject var appState: AppState

        private var used: Int { appState.usedVacationDays(for: user) }
        private var remaining: Int { appState.remainingLeaveDays(for: user) }
        private var warning: Bool { remaining <= 5 }

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
private func germanColorName(_ key: String) -> String {
    switch key {
    case "blue": return "Blau"
    case "green": return "Grün"
    case "orange": return "Orange"
    case "purple": return "Lila"
    case "red": return "Rot"
    case "pink": return "Pink"
    case "teal": return "Türkis"
    case "indigo": return "Indigo"
    case "yellow": return "Gelb"
    case "gray": return "Grau"
    default: return key.capitalized
    }
}

struct EditUserView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    @State var user: User

    @State private var showNewRequest: Bool = false
    @State private var showPinResetAlert: Bool = false
    @State private var showLoginAlert: Bool = false

    @State private var showUnsavedConfirm: Bool = false
    @State private var initialSnapshot: UserEditSnapshot? = nil

    private let availableColors: [String] = ["blue", "green", "orange", "purple", "red", "pink", "teal", "indigo", "yellow", "gray"]

    private struct UserEditSnapshot: Equatable {
        let name: String
        let role: UserRole
        let annualLeaveDays: Int
        let colorName: String
    }

    private var hasUnsavedChanges: Bool {
        guard let s = initialSnapshot else { return false }
        return s != UserEditSnapshot(
            name: user.name,
            role: user.role,
            annualLeaveDays: user.annualLeaveDays,
            colorName: user.colorName
        )
    }

    var body: some View {
        Form {
            Section(header: Text("Allgemein")) {
                TextField("Name", text: binding(for: \.name))
                Picker("Rolle", selection: binding(for: \.role)) {
                    Text("Admin").tag(UserRole.admin)
                    Text("Mitarbeiter").tag(UserRole.employee)
                    Text("Sachverständiger").tag(UserRole.expert)
                }
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
                        Text(germanColorName(color)).tag(color)
                    }
                }
            }

            Section {
                Button("Mitarbeiter löschen", role: .destructive) {
                    appState.deleteUser(user)
                    dismiss()
                }
            }
        }
        .navigationTitle("Mitarbeiter bearbeiten")
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    if hasUnsavedChanges {
                        showUnsavedConfirm = true
                    } else {
                        dismiss()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "chevron.left")
                        Text("Zurück")
                    }
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button("Speichern") {
                    appState.updateUser(user)
                    // Update snapshot so we don't re-prompt if the user stays on screen
                    initialSnapshot = UserEditSnapshot(
                        name: user.name,
                        role: user.role,
                        annualLeaveDays: user.annualLeaveDays,
                        colorName: user.colorName
                    )
                    dismiss()
                }
                .font(.subheadline.weight(.semibold))
                .disabled(!hasUnsavedChanges)
            }
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
        .onAppear {
            if initialSnapshot == nil {
                initialSnapshot = UserEditSnapshot(
                    name: user.name,
                    role: user.role,
                    annualLeaveDays: user.annualLeaveDays,
                    colorName: user.colorName
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
    @State private var colorName: String = "gray"
    @State private var isCreating: Bool = false

    private let availableColors: [String] = ["blue", "green", "orange", "purple", "red", "pink", "teal", "indigo", "yellow", "gray"]

    var body: some View {
        Form {
            Section(header: Text("Allgemein")) {
                TextField("Name", text: $name)
                TextField("E-Mail", text: $email)
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                Picker("Rolle", selection: $role) {
                    Text("Admin").tag(UserRole.admin)
                    Text("Mitarbeiter").tag(UserRole.employee)
                    Text("Sachverständiger").tag(UserRole.expert)
                }
            }

            Section(header: Text("Urlaub")) {
                Stepper(value: $annualLeaveDays, in: 0...365) {
                    Text("Jahresurlaub: \(annualLeaveDays) Tage")
                }
            }

            Section(header: Text("Farbe")) {
                Picker("Farbe", selection: $colorName) {
                    ForEach(availableColors, id: \.self) { color in
                        Text(germanColorName(color)).tag(color)
                    }
                }
            }

            Section {
                Button {
                    let cleanEmail = email.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    let cleanName  = name.trimmingCharacters(in: .whitespacesAndNewlines)

                    guard !isCreating else { return }
                    isCreating = true

                    _Concurrency.Task {
                        await appState.adminCreateUserViaFunction(
                            name: cleanName,
                            email: cleanEmail,
                            role: role,
                            colorName: colorName,
                            annualLeaveDays: annualLeaveDays
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
}

// MARK: - Admin On-Call Saturdays

struct AdminOnCallSaturdaysScreen: View {
    @EnvironmentObject var appState: AppState
    @State private var showNew: Bool = false
    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    @State private var editingRequest: LeaveRequest?
    @State private var showEdit: Bool = false

    private var upcomingOnCalls: [LeaveRequest] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return appState.leaveRequests
            .filter { $0.type == .onCallSaturday && $0.status == .approved }
            .filter { cal.startOfDay(for: $0.startDate) >= today }
            .sorted { $0.startDate < $1.startDate }
    }

    private var onCallCountsByUser: [(user: User, count: Int)] {
        let cal = Calendar.current
        let currentYear = cal.component(.year, from: Date())

        // Count ONLY approved on-call Saturdays in the current year
        let counts: [String: Int] = appState.leaveRequests
            .filter { $0.type == .onCallSaturday && $0.status == .approved }
            .filter { cal.component(.year, from: $0.startDate) == currentYear }
            .reduce(into: [:]) { partial, req in
                partial[req.user.id, default: 0] += 1
            }

        let eligible = appState.users
            .filter { $0.role == .admin || $0.role == .expert }

        return eligible
            .map { ($0, counts[$0.id] ?? 0) }
            .sorted { lhs, rhs in
                if lhs.1 == rhs.1 { return lhs.0.name.lowercased() < rhs.0.name.lowercased() }
                return lhs.1 > rhs.1
            }
    }

    private var totalOnCallCount: Int {
        onCallCountsByUser.reduce(0) { $0 + $1.count }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Bereitschaft")
                    .font(.largeTitle.weight(.bold))

                Spacer()

                Button {
                    showNew = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(Color(.secondarySystemBackground)))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Bereitschaft hinzufügen")
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)

            // Übersicht: Counts pro Mitarbeiter
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Übersicht")
                        .font(.headline)

                    Spacer()

                    Text("Gesamt: \(totalOnCallCount)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 18)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(onCallCountsByUser, id: \.user.id) { item in
                            HStack(spacing: 8) {
                                Circle()
                                    .fill(item.user.color)
                                    .frame(width: 10, height: 10)

                                Text(item.user.name)
                                    .font(.caption.weight(.semibold))
                                    .foregroundColor(.primary)

                                Text("\(item.count)")
                                    .font(.caption2.weight(.bold))
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(
                                        Capsule().fill(Color(.secondarySystemBackground))
                                    )
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(
                                RoundedRectangle(cornerRadius: 14)
                                    .fill(Color(.secondarySystemBackground))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
                            )
                        }
                    }
                    .padding(.horizontal, 18)
                }
            }
            .padding(.top, 4)

            List {
                if upcomingOnCalls.isEmpty {
                    Section {
                        Text("Noch keine Samstags-Bereitschaften eingetragen")
                            .foregroundColor(.secondary)
                    }
                } else {
                    Section(header: Text("Nächste Samstage")) {
                        ForEach(upcomingOnCalls) { req in
                            HStack(spacing: 12) {
                                Image(systemName: "person.badge.clock")
                                    .foregroundColor(.secondary)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(req.user.name)
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundColor(req.user.color)
                                    Text(req.startDate.formatted(date: .abbreviated, time: .omitted))
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                editingRequest = req
                                showEdit = true
                            }
                            .swipeActions {
                                Button(role: .destructive) {
                                    appState.deleteLeaveRequest(req)
                                } label: {
                                    Label("Löschen", systemImage: "trash")
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
        .background(Color(.systemGroupedBackground))
        .navigationDestination(isPresented: $showNew) {
            NewOnCallSaturdayView()
                .environmentObject(appState)
        }
        .navigationDestination(isPresented: $showEdit) {
            if let req = editingRequest {
                EditOnCallSaturdayView(existingRequest: req)
                    .environmentObject(appState)
                    .onDisappear {
                        editingRequest = nil
                    }
            } else {
                // Fallback (should not happen)
                EmptyView()
            }
        }
    }
}

struct NewOnCallSaturdayView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    @State private var selectedExpertId: String?
    @State private var selectedSaturday: Date = Calendar.current.startOfDay(for: Date())
    @State private var inlineError: String?

    private var eligibleUsers: [User] {
        appState.users
            .filter { $0.role == .expert || $0.role == .admin }
            .sorted { $0.name.lowercased() < $1.name.lowercased() }
    }

    private var takenSaturdays: Set<Date> {
        let cal = Calendar.current
        return Set(
            appState.leaveRequests
                .filter { $0.type == .onCallSaturday && $0.status == .approved }
                .map { cal.startOfDay(for: $0.startDate) }
        )
    }

    private var upcomingSaturdays: [Date] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        // Generate next 16 available Saturdays
        var result: [Date] = []
        var d = today
        while result.count < 16 {
            let weekday = cal.component(.weekday, from: d)
            if weekday == 7 { // Saturday
                let day = cal.startOfDay(for: d)
                if !takenSaturdays.contains(day) {
                    result.append(day)
                }
            }
            d = cal.date(byAdding: .day, value: 1, to: d) ?? d
        }
        return result
    }

    private var saturdayPickerOptions: [Date] {
        let cal = Calendar.current
        let normalizedSelection = cal.startOfDay(for: selectedSaturday)
        var options = upcomingSaturdays
        // Ensure current selection is always a valid tag (prevents Picker runtime warning)
        if !options.contains(normalizedSelection) {
            options.append(normalizedSelection)
        }
        return Array(Set(options)).sorted(by: <)
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 10) {
                    Image(systemName: "person.badge.clock")
                        .foregroundColor(.secondary)
                    Text("Samstags-Bereitschaft")
                        .font(.subheadline.weight(.semibold))
                }
                Text("Hier weist du für einen Samstag genau eine Person als Bereitschaft zu. Der Eintrag erscheint im Kalender.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let msg = inlineError {
                Section {
                    Label(msg, systemImage: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                        .font(.footnote)
                }
            }

            Section(header: Text("Samstag"), footer: Text("Es sind nur kommende Samstage auswählbar. Pro Samstag ist nur ein Eintrag möglich.")) {
                Picker("Datum", selection: $selectedSaturday) {
                    ForEach(saturdayPickerOptions, id: \.self) { d in
                        Text(d.formatted(date: .abbreviated, time: .omitted)).tag(d)
                    }
                }
                .pickerStyle(.navigationLink)
            }

            Section(header: Text("Mitarbeiter")) {
                Picker("Mitarbeiter", selection: Binding(get: {
                    selectedExpertId
                }, set: { newVal in
                    selectedExpertId = newVal
                })) {
                    Text("Bitte auswählen").tag(String?.none)
                    ForEach(eligibleUsers) { u in
                        Text(u.name).tag(Optional(u.id))
                    }
                }
                .pickerStyle(.navigationLink)
            }

            Section {
                Button {
                    guard let id = selectedExpertId, let user = eligibleUsers.first(where: { $0.id == id }) else {
                        inlineError = "Bitte einen Admin oder Sachverständigen auswählen."
                        return
                    }

                    let ok = appState.createLeaveRequest(
                        start: selectedSaturday,
                        end: selectedSaturday,
                        type: .onCallSaturday,
                        for: user,
                        approveImmediately: true
                    )

                    if ok {
                        inlineError = nil
                        dismiss()
                    } else {
                        inlineError = appState.uiErrorMessage
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Speichern")
                            .font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .disabled(selectedExpertId == nil)

                Button("Abbrechen", role: .cancel) {
                    dismiss()
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .navigationTitle("Bereitschaft anlegen")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Ensure the initial selection is a valid option/tag
            if let first = upcomingSaturdays.first {
                selectedSaturday = Calendar.current.startOfDay(for: first)
            } else {
                selectedSaturday = Calendar.current.startOfDay(for: selectedSaturday)
            }
        }
    }
}

struct EditOnCallSaturdayView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    
    let existingRequest: LeaveRequest
    
    @State private var selectedUserId: String?
    @State private var selectedSaturday: Date = Date()
    @State private var inlineError: String?
    @State private var didLoadInitialValues: Bool = false
    
    private var eligibleUsers: [User] {
        appState.users
            .filter { $0.role == .expert || $0.role == .admin }
            .sorted { $0.name.lowercased() < $1.name.lowercased() }
    }
    
    private var takenSaturdaysExcludingCurrent: Set<Date> {
        let cal = Calendar.current
        let currentDay = cal.startOfDay(for: existingRequest.startDate)
        return Set(
            appState.leaveRequests
                .filter { $0.type == .onCallSaturday && $0.status == .approved }
                .map { cal.startOfDay(for: $0.startDate) }
        ).subtracting([currentDay])
    }
    
    private var upcomingSaturdays: [Date] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var result: [Date] = []
        var d = today
        while result.count < 16 {
            let weekday = cal.component(.weekday, from: d)
            if weekday == 7 { // Saturday
                let day = cal.startOfDay(for: d)
                if !takenSaturdaysExcludingCurrent.contains(day) {
                    result.append(day)
                }
            }
            d = cal.date(byAdding: .day, value: 1, to: d) ?? d
        }
        return result
    }

    private var saturdayPickerOptions: [Date] {
        let cal = Calendar.current
        let normalizedSelection = cal.startOfDay(for: selectedSaturday)
        var options = upcomingSaturdays
        // Ensure current selection is always present to avoid invalid-tag warning
        if !options.contains(normalizedSelection) {
            options.append(normalizedSelection)
        }
        return Array(Set(options)).sorted(by: <)
    }
    
    var body: some View {
        Form {
            Section {
                HStack(spacing: 10) {
                    Image(systemName: "person.badge.clock")
                        .foregroundColor(.secondary)
                    Text("Samstags-Bereitschaft bearbeiten")
                        .font(.subheadline.weight(.semibold))
                }
                Text("Du kannst Datum und Person ändern. Pro Samstag ist nur ein Eintrag möglich.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if let msg = inlineError {
                Section {
                    Label(msg, systemImage: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                        .font(.footnote)
                }
            }
            
            Section(header: Text("Samstag"), footer: Text("Belegte Samstage sind nicht auswählbar.")) {
                Picker("Datum", selection: $selectedSaturday) {
                    ForEach(saturdayPickerOptions, id: \.self) { d in
                        Text(d.formatted(date: .abbreviated, time: .omitted)).tag(d)
                    }
                }
                .pickerStyle(.navigationLink)
            }
            
            Section(header: Text("Mitarbeiter")) {
                Picker("Mitarbeiter", selection: Binding(get: {
                    selectedUserId
                }, set: { newVal in
                    selectedUserId = newVal
                })) {
                    Text("Bitte auswählen").tag(String?.none)
                    ForEach(eligibleUsers) { u in
                        Text(u.name).tag(Optional(u.id))
                    }
                }
                .pickerStyle(.navigationLink)
            }
            
            Section(header: Text("Aktionen")) {
                Button {
                    guard let id = selectedUserId, let user = eligibleUsers.first(where: { $0.id == id }) else {
                        inlineError = "Bitte einen Admin oder Sachverständigen auswählen."
                        return
                    }
                    
                    // Backup old values
                    let oldUser = existingRequest.user
                    let oldDay = Calendar.current.startOfDay(for: existingRequest.startDate)
                    
                    // Swap: delete old, create new. If creation fails, restore old.
                    appState.deleteLeaveRequest(existingRequest)
                    
                    let ok = appState.createLeaveRequest(
                        start: selectedSaturday,
                        end: selectedSaturday,
                        type: .onCallSaturday,
                        for: user,
                        approveImmediately: true
                    )
                    
                    if ok {
                        inlineError = nil
                        dismiss()
                    } else {
                        // Restore the old entry
                        _ = appState.createLeaveRequest(
                            start: oldDay,
                            end: oldDay,
                            type: .onCallSaturday,
                            for: oldUser,
                            approveImmediately: true
                        )
                        inlineError = appState.uiErrorMessage
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Speichern")
                            .font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.capsule)
                .disabled(selectedUserId == nil)
                
                Button("Schließen", role: .cancel) {
                    dismiss()
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
        }
        .navigationTitle("Bereitschaft")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Important: With `.pickerStyle(.navigationLink)` SwiftUI may re-trigger `onAppear`
            // when coming back from the picker screen. Without this guard, the selection is reset.
            guard !didLoadInitialValues else { return }
            didLoadInitialValues = true

            selectedUserId = existingRequest.user.id
            selectedSaturday = Calendar.current.startOfDay(for: existingRequest.startDate)
        }
    }
}

// MARK: - Admin Automations Screen (Make Status)

private struct AutomationEvent: Identifiable {
    let id: String
    let status: String
    let message: String
    let runAt: Date?
}

private struct AutomationStatusDoc {
    var status: String
    var lastRunAt: Date?
    var lastMessage: String
    var events: [AutomationEvent]
}

struct AdminAutomationsScreen: View {
    @EnvironmentObject var appState: AppState

    let automationId: String

    @State private var doc: AutomationStatusDoc?
    @State private var isLoading: Bool = true
    @State private var listener: ListenerRegistration?
    @State private var eventsListener: ListenerRegistration?
    @State private var showRuns: Bool = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {

                HStack(alignment: .firstTextBaseline) {
                    Text("Automatisierungen")
                        .font(.largeTitle.weight(.bold))
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Make")
                        .font(.headline)
                        .padding(.horizontal, 18)

                    automationCard
                        .padding(.horizontal, 18)

                    DisclosureGroup(isExpanded: $showRuns) {
                        eventsList
                            .padding(.top, 10)
                    } label: {
                        HStack {
                            Text("Letzte 10 Läufe")
                                .font(.headline)

                            Spacer()

                            let count = doc?.events.count ?? 0
                            Text("\(count)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        .padding(.horizontal, 18)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 8)
                }

                Spacer(minLength: 18)
            }
            .padding(.bottom, 18)
        }
        .background(Color(.systemGroupedBackground))
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { startListening() }
        .onDisappear {
            listener?.remove()
            listener = nil
            eventsListener?.remove()
            eventsListener = nil
        }
        .refreshable {
            await refreshNow()
        }
    }
    
    private func shortStatusTitle(_ s: String) -> String {
        switch s {
        case "ok": return "OK"
        case "error": return "Fehler"
        default: return "Hinweis"
        }
    }

    private func fetchOnce(completion: @escaping () -> Void = {}) {
        isLoading = true

        let ref = Firestore.firestore().collection("automations").document(automationId)
        let eventsRef = ref.collection("events")
            .order(by: "runAt", descending: true)
            .limit(to: 10)

        let group = DispatchGroup()

        var status: String = "warn"
        var lastMessage: String = ""
        var lastRunAt: Date? = nil
        var events: [AutomationEvent] = []

        group.enter()
        ref.getDocument { snap, err in
            defer { group.leave() }

            if let err {
                print("[automations] fetch doc error:", err)
                return
            }

            guard let data = snap?.data() else { return }
            status = (data["status"] as? String) ?? "warn"
            lastMessage = (data["lastMessage"] as? String) ?? ""
            lastRunAt = (data["lastRunAt"] as? Timestamp)?.dateValue()
        }

        group.enter()
        eventsRef.getDocuments { snap, err in
            defer { group.leave() }

            if let err {
                print("[automations] fetch events error:", err)
                return
            }

            events = (snap?.documents ?? []).map { d in
                let data = d.data()
                let s = (data["status"] as? String) ?? "warn"
                let m = (data["message"] as? String) ?? ""
                let r = (data["runAt"] as? Timestamp)?.dateValue()
                return AutomationEvent(id: d.documentID, status: s, message: m, runAt: r)
            }
        }

        group.notify(queue: .main) {
            self.doc = AutomationStatusDoc(
                status: status,
                lastRunAt: lastRunAt,
                lastMessage: lastMessage,
                events: events
            )
            self.isLoading = false
            completion()
        }
    }

    private func refreshNow() async {
        await withCheckedContinuation { cont in
            fetchOnce {
                cont.resume()
            }
        }
    }

    private var automationCard: some View {
        Group {
            if isLoading {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Status wird geladen…")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
            } else if let doc {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 10) {
                        statusDot(doc.status)
                        Text(statusLabel(doc.status))
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                    }

                    HStack(spacing: 10) {
                        Label(lastRunText(doc.lastRunAt), systemImage: "clock")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Spacer()
                    }

                    if !doc.lastMessage.isEmpty {
                        Text(doc.lastMessage)
                            .font(.footnote)
                            .foregroundColor(.secondary)
                            .lineLimit(2)
                    }
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
                )
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Noch kein Status vorhanden")
                        .font(.subheadline.weight(.semibold))
                    Text("Sobald Make den ersten Lauf meldet, erscheint hier der Status.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
            }
        }
    }
    
    private var eventsList: some View {
        Group {
            let items = doc?.events ?? []
            if items.isEmpty {
                HStack(spacing: 10) {
                    Text("Noch keine Läufe vorhanden")
                        .font(.footnote.weight(.semibold))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
            } else {
                VStack(spacing: 10) {
                    ForEach(items) { e in
                        HStack(alignment: .top, spacing: 10) {
                            statusDot(e.status)
                                .padding(.top, 2)

                            VStack(alignment: .leading, spacing: 4) {

                                HStack(spacing: 8) {
                                    Text(shortStatusTitle(e.status))
                                        .font(.footnote.weight(.semibold))

                                    Text(e.runAt?.formatted(date: .abbreviated, time: .shortened) ?? "–")
                                        .font(.footnote.weight(.semibold))

                                    Spacer(minLength: 0)
                                }

                                if !e.message.isEmpty {
                                    Text(e.message)
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                        .lineLimit(2)
                                }
                            }

                            Spacer(minLength: 0)
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color(.secondarySystemBackground)))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(Color.secondary.opacity(0.10), lineWidth: 1)
                        )
                    }
                }
            }
        }
    }


    private func startListening() {
        isLoading = true
        listener?.remove()
        eventsListener?.remove()

        let ref = Firestore.firestore().collection("automations").document(automationId)
        listener = ref.addSnapshotListener { snap, err in
            if let err {
                print("[automations] snapshot error:", err)
                self.doc = nil
                self.isLoading = false
                return
            }

            guard let data = snap?.data() else {
                self.doc = nil
                self.isLoading = false
                return
            }

            let status = (data["status"] as? String) ?? "warn"
            let lastMessage = (data["lastMessage"] as? String) ?? ""
            let lastRunAt = (data["lastRunAt"] as? Timestamp)?.dateValue()

            self.doc = AutomationStatusDoc(
                status: status,
                lastRunAt: lastRunAt,
                lastMessage: lastMessage,
                events: self.doc?.events ?? []
            )
            self.isLoading = false
        }
        
        let eventsRef = ref.collection("events")
            .order(by: "runAt", descending: true)
            .limit(to: 10)

        eventsListener = eventsRef.addSnapshotListener { snap, err in
            if let err {
                print("[automations] events snapshot error:", err)
                return
            }

            let items: [AutomationEvent] = (snap?.documents ?? []).map { d in
                let data = d.data()
                let status = (data["status"] as? String) ?? "warn"
                let message = (data["message"] as? String) ?? ""
                let runAt = (data["runAt"] as? Timestamp)?.dateValue()
                return AutomationEvent(id: d.documentID, status: status, message: message, runAt: runAt)
            }

            if var existing = self.doc {
                existing.events = items
                self.doc = existing
            } else {
                self.doc = AutomationStatusDoc(status: "warn", lastRunAt: nil, lastMessage: "", events: items)
            }
        }
    }

    private func statusLabel(_ s: String) -> String {
        switch s {
        case "ok": return "✅ Läuft"
        case "error": return "❌ Fehler"
        default: return "⚠️ Hinweis"
        }
    }

    @ViewBuilder
    private func statusDot(_ s: String) -> some View {
        let c: Color = {
            switch s {
            case "ok": return .green
            case "error": return .red
            default: return .orange
            }
        }()
        Circle().fill(c).frame(width: 10, height: 10)
    }

    private func lastRunText(_ d: Date?) -> String {
        guard let d else { return "Letzter Lauf: –" }
        return "Letzter Lauf: \(d.formatted(date: .abbreviated, time: .shortened))"
    }
}
