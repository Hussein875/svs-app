//
//  AdminConsoleView.swift
//  SVS App
//
//  Created by Hussein Souleiman on 23.12.25.
//
import Foundation
import SwiftUI

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
                            accent: .secondary
                        )

                        AdminStatCard(
                            title: "Heute abwesend",
                            value: "\(todayAbsentCount)",
                            systemImage: "calendar.badge.clock",
                            accent: .secondary
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
                                AdminNavRow(title: "Anträge verwalten",
                                            subtitle: "Genehmigen, ablehnen und filtern",
                                            systemImage: "doc.text.magnifyingglass")
                            }

                            NavigationLink {
                                AdminUsersScreen()
                                    .environmentObject(appState)
                            } label: {
                                AdminNavRow(title: "Mitarbeiter",
                                            subtitle: "Urlaub, Rollen und Login verwalten",
                                            systemImage: "person.2")
                            }

                            NavigationLink {
                                AdminOnCallSaturdaysScreen()
                                    .environmentObject(appState)
                            } label: {
                                AdminNavRow(title: "Samstags-Bereitschaft",
                                            subtitle: "Samstage zuweisen",
                                            systemImage: "person.badge.clock")
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
                    Image(systemName: systemImage).foregroundColor(.secondary)
                    Spacer()
                }
                Text(value).font(.title2.weight(.bold))
                Text(title).font(.caption).foregroundColor(.secondary)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16).fill(Color(.secondarySystemBackground)))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.secondary.opacity(0.18), lineWidth: 1))
        }
    }

    private struct AdminNavRow: View {
        let title: String
        let subtitle: String
        let systemImage: String

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
                    Text(title).font(.subheadline.weight(.semibold))
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
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Anträge")
                        .font(.largeTitle.weight(.bold))

                    Spacer()

                    Button {
                        showEditScreen = true
                        editingRequest = nil
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(Color(.secondarySystemBackground)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Neuen Antrag erstellen")

                    Menu {
                        Picker("Filter", selection: $filterMode) {
                            ForEach(AdminQuickFilter.allCases) { mode in
                                Text(mode.rawValue).tag(mode)
                            }
                        }
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(Color(.secondarySystemBackground)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Filter")
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)

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
            }
            .background(Color(.systemGroupedBackground))
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
        request.type == .sick ? Color.gray : colorForLeaveStatus(request.status)
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

                        // Krankheit: kein Status-Badge
                        if request.type != .sick {
                            statusBadgeView(request.status)
                        }
                    }

                    Text(dateRangeString(request.startDate, request.endDate))
                        .font(.subheadline)

                    HStack(spacing: 8) {
                        Image(systemName: request.type == .sick ? "cross.case" : "beach.umbrella")
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

            // AUDIT (einklappbar)
            let createdBy = appState.userName(for: request.createdByUserId)
            let updatedBy = request.updatedByUserId.map { appState.userName(for: $0) }
            let hasUpdate = (request.updatedAt != nil && updatedBy != nil)

            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    showAudit.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: showAudit ? "chevron.down" : "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.secondary)

                    Text(showAudit ? "Audit ausblenden" : "Audit anzeigen")
                        .font(.caption2.weight(.semibold))
                        .foregroundColor(.secondary)

                    Spacer()

                    // Optional: kleine Kurzinfo, damit man ohne Aufklappen Kontext hat
                    Text(shortDateString(request.createdAt))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .padding(.top, 2)

            if showAudit {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Erstellt von: \(createdBy) • \(shortDateString(request.createdAt))")
                    if let uAt = request.updatedAt, let uBy = updatedBy {
                        Text("Geändert: \(uBy) • \(shortDateString(uAt))")
                    } else if !hasUpdate {
                        Text("Noch nicht geändert")
                    }
                }
                .font(.caption2)
                .foregroundColor(.secondary)
                .transition(.opacity.combined(with: .move(edge: .top)))
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
    case remainingAsc = "Resturlaub ↑"
    case remainingDesc = "Resturlaub ↓"
    var id: String { rawValue }
}

// MARK: - Admin Users Screen

struct AdminUsersScreen: View {
    @EnvironmentObject var appState: AppState
    @State private var showAddUser = false
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
        case .remainingAsc:
            return base.sorted { appState.remainingLeaveDays(for: $0) < appState.remainingLeaveDays(for: $1) }
        case .remainingDesc:
            return base.sorted { appState.remainingLeaveDays(for: $0) > appState.remainingLeaveDays(for: $1) }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Mitarbeiter")
                        .font(.largeTitle.weight(.bold))

                    Spacer()

                    Button {
                        showAddUser = true
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

                    HStack(spacing: 10) {
                        Menu {
                            Picker("Sortierung", selection: $sortMode) {
                                ForEach(AdminUserSortMode.allCases) { m in
                                    Text(m.rawValue).tag(m)
                                }
                            }
                        } label: {
                            Label("Sortieren", systemImage: "arrow.up.arrow.down")
                                .font(.subheadline.weight(.semibold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground)))
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        Text("\(filteredUsers.count) Mitarbeiter")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 18)

                List {
                    Section(header: Text("Mitarbeiter & Resturlaub")) {
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
            .sheet(isPresented: $showAddUser) {
                NavigationStack {
                    AddUserView()
                        .environmentObject(appState)
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

    private let availableColors: [String] = ["blue", "green", "orange", "purple", "red", "pink", "teal", "indigo", "yellow", "gray"]

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

            if appState.currentUser?.role == .admin {
                Section(header: Text("Aktionen")) {
                    Button {
                        showNewRequest = true
                    } label: {
                        Label("Antrag für diesen Mitarbeiter erstellen", systemImage: "plus.circle")
                    }
                }
            }

            Section {
                Button("Änderungen speichern") {
                    appState.updateUser(user)
                    dismiss()
                }

                Button("Mitarbeiter löschen", role: .destructive) {
                    appState.deleteUser(user)
                    dismiss()
                }
            }
        }
        .navigationTitle("Mitarbeiter bearbeiten")
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
    @State private var annualLeaveDays: Int = 30
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
        .sheet(isPresented: $showNew) {
            NavigationStack {
                NewOnCallSaturdayView()
                    .environmentObject(appState)
            }
        }
        .sheet(item: $editingRequest) { req in
            NavigationStack {
                EditOnCallSaturdayView(existingRequest: req)
                    .environmentObject(appState)
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
