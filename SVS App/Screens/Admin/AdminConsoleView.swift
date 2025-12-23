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
    @State private var showNewRequestSheet: Bool = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {

                    HStack(alignment: .firstTextBaseline) {
                        Text("Admin")
                            .font(.largeTitle.weight(.bold))

                        Spacer()

                        Button {
                            showNewRequestSheet = true
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 16, weight: .semibold))
                                .frame(width: 40, height: 40)
                                .background(Circle().fill(Color(.secondarySystemBackground)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Antrag erstellen")
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 8)

                    // KPI Cards (2 only, neutral accent)
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
                        }
                        .padding(.horizontal, 18)
                    }

                    Spacer(minLength: 18)
                }
                .padding(.top, 2)
            }
            .background(Color(.systemGroupedBackground))
            .sheet(isPresented: $showNewRequestSheet) {
                NavigationStack {
                    NewLeaveRequestView()
                        .environmentObject(appState)
                }
            }
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
        let todays = appState.requests(for: today).filter { $0.status == .approved }
        return Set(todays.map { $0.user.id }).count
    }
}

struct EditLeaveRequestView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    @State var request: LeaveRequest
    @State private var inlineError: String? = nil

    var body: some View {
        ScrollViewReader { proxy in
            Form {
                if let inlineError {
                    Section {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text(inlineError)
                                .font(.footnote)
                                .foregroundColor(.red)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(.vertical, 4)
                    }
                    .id("errorBanner")
                }

                Section(header: Text("Zeitraum")) {
                    DatePicker("Von", selection: $request.startDate, displayedComponents: .date)
                    DatePicker("Bis", selection: $request.endDate, in: request.startDate..., displayedComponents: .date)
                }

                Section(header: Text("Art der Abwesenheit")) {
                    // Nur Urlaub und Krankheit zur Auswahl anbieten
                    let allowedTypes: [LeaveType] = [.vacation, .sick]

                    Picker("Art", selection: $request.type) {
                        ForEach(allowedTypes, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section {
                    if appState.canEditOrDelete(request, by: appState.currentUser) {
                        Button("Änderungen speichern") {
                            let ok = appState.updateLeaveRequest(request)
                            if ok {
                                inlineError = nil
                                dismiss()
                            } else {
                                inlineError = appState.uiErrorMessage
                            }
                        }

                        Button("Antrag löschen", role: .destructive) {
                            appState.deleteLeaveRequest(request)
                            dismiss()
                        }
                    } else {
                        Text("Dieser Antrag wurde bereits entschieden und kann nicht mehr bearbeitet werden.")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .onChange(of: inlineError) { value in
                guard value != nil else { return }
                withAnimation(.easeInOut) {
                    proxy.scrollTo("errorBanner", anchor: .top)
                }
            }
            .onChange(of: request.startDate) { _ in
                inlineError = nil
                appState.uiErrorMessage = nil
            }
            .onChange(of: request.endDate) { _ in
                inlineError = nil
                appState.uiErrorMessage = nil
            }
            .onChange(of: request.type) { _ in
                inlineError = nil
                appState.uiErrorMessage = nil
            }
        }
        .navigationTitle("Antrag bearbeiten")
        .onAppear {
            if request.type == .sick {
                request.status = .approved
            }
        }
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
    @State private var searchText: String = ""
    @State private var filterMode: AdminQuickFilter = .all

    private func matchesSearch(_ request: LeaveRequest) -> Bool {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return true }
        return request.user.name.lowercased().contains(q.lowercased())
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
            .filter { matchesSearch($0) && matchesQuickFilter($0) }
            .sorted { $0.startDate > $1.startDate }
    }

    // Beantwortete Anträge (inkl. Krankheit) – nach Monat gruppiert
    private var answeredRequests: [LeaveRequest] {
        appState.leaveRequests
            .filter { !($0.type == .vacation && $0.status == .pending) }
            .filter { matchesSearch($0) && matchesQuickFilter($0) }
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
                .searchable(text: $searchText, prompt: "Mitarbeiter suchen")
                .sheet(item: $editingRequest) { request in
                    NavigationStack {
                        EditLeaveRequestView(request: request)
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
            onEdit: { editingRequest = request },
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
    @State private var searchText: String = ""
    @State private var roleFilter: AdminUserRoleFilter = .all
    @State private var sortMode: AdminUserSortMode = .name
    
    private func matchesSearch(_ user: User) -> Bool {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return true }
        return user.name.lowercased().contains(q.lowercased())
    }

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
            .filter { matchesSearch($0) }

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
                .searchable(text: $searchText, prompt: "Mitarbeiter suchen")
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

struct EditUserView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    @State var user: User

    @State private var showNewRequest: Bool = false
    @State private var showPinResetAlert: Bool = false

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

            Section(header: Text("Login")) {
                TextField("PIN", text: binding(for: \.pin))
                    .keyboardType(.numberPad)

                Button {
                    user.pin = "0000"
                    showPinResetAlert = true
                } label: {
                    Label("PIN auf 0000 setzen", systemImage: "key")
                }
                .font(.subheadline)
            }

            Section(header: Text("Urlaub")) {
                Stepper(value: binding(for: \.annualLeaveDays), in: 0...365) {
                    Text("Jahresurlaub: \(user.annualLeaveDays) Tage")
                }
            }

            Section(header: Text("Farbe")) {
                Picker("Farbe", selection: binding(for: \.colorName)) {
                    ForEach(availableColors, id: \.self) { color in
                        Text(color.capitalized).tag(color)
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
        .alert("PIN geändert", isPresented: $showPinResetAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Der PIN wurde auf 0000 gesetzt. Bitte speichern.")
        }
    }

    private func binding<Value>(for keyPath: WritableKeyPath<User, Value>) -> Binding<Value> {
        Binding(
            get: { user[keyPath: keyPath] },
            set: { user[keyPath: keyPath] = $0 }
        )
    }
}

struct AddUserView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    @State private var name: String = ""
    @State private var role: UserRole = .employee
    @State private var pin: String = ""
    @State private var annualLeaveDays: Int = 30
    @State private var colorName: String = "gray"

    private let availableColors: [String] = ["blue", "green", "orange", "purple", "red", "pink", "teal", "indigo", "yellow", "gray"]

    var body: some View {
        Form {
            Section(header: Text("Allgemein")) {
                TextField("Name", text: $name)
                Picker("Rolle", selection: $role) {
                    Text("Admin").tag(UserRole.admin)
                    Text("Mitarbeiter").tag(UserRole.employee)
                    Text("Sachverständiger").tag(UserRole.expert)
                }
            }

            Section(header: Text("Login")) {
                TextField("PIN", text: $pin)
                    .keyboardType(.numberPad)
            }

            Section(header: Text("Urlaub")) {
                Stepper(value: $annualLeaveDays, in: 0...365) {
                    Text("Jahresurlaub: \(annualLeaveDays) Tage")
                }
            }

            Section(header: Text("Farbe")) {
                Picker("Farbe", selection: $colorName) {
                    ForEach(availableColors, id: \.self) { color in
                        Text(color.capitalized).tag(color)
                    }
                }
            }

            Section {
                Button("Mitarbeiter erstellen") {
                    appState.addUser(name: name,
                                     role: role,
                                     pin: pin,
                                     colorName: colorName,
                                     annualLeaveDays: annualLeaveDays)
                    dismiss()
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || pin.isEmpty)
            }
        }
        .navigationTitle("Neuer Mitarbeiter")
    }
}
