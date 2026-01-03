//
//  MyRequestsScreen.swift
//  SVS App
//
//  Created by Hussein Souleiman on 23.12.25.
//
import Foundation
import SwiftUI

struct MyRequestsScreen: View {
    @EnvironmentObject var appState: AppState
    @State private var editingRequest: LeaveRequest?

    private var myRequests: [LeaveRequest] {
        appState.myRequests()
    }

    private var todayStart: Date {
        Calendar.current.startOfDay(for: Date())
    }

    private var currentRequests: [LeaveRequest] {
        myRequests
            .filter { Calendar.current.startOfDay(for: $0.endDate) >= todayStart }
            .sorted { $0.startDate < $1.startDate }
    }

    private var pastRequests: [LeaveRequest] {
        myRequests
            .filter { Calendar.current.startOfDay(for: $0.endDate) < todayStart }
            .sorted { $0.startDate > $1.startDate }
    }

    private var counts: (pending: Int, approved: Int, rejected: Int) {
        let vacationRequests = currentRequests.filter { $0.type != .sick }
        let pending = vacationRequests.filter { $0.status == .pending }.count
        let approved = vacationRequests.filter { $0.status == .approved }.count
        let rejected = vacationRequests.filter { $0.status == .rejected }.count
        return (pending, approved, rejected)
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                // Header (match Kalender style)
                HStack(alignment: .firstTextBaseline) {
                    Text("Meine Anträge")
                        .font(.largeTitle.weight(.bold))

                    Spacer()

                    NavigationLink(destination: NewLeaveRequestView()) {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .semibold))
                            .frame(width: 40, height: 40)
                            .background(Circle().fill(Color(.secondarySystemBackground)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Neuen Antrag erstellen")
                }
                .padding(.horizontal, 18)
                .padding(.top, 8)

                Group {
                    if myRequests.isEmpty {
                        // Clean empty state (no List top inset / no huge header gap)
                        VStack(alignment: .leading, spacing: 14) {
                            Text("Noch keine Anträge")
                                .font(.headline)
                                .foregroundColor(.secondary)

                            RoundedRectangle(cornerRadius: 18)
                                .fill(Color(.secondarySystemBackground))
                                .frame(height: 68)
                                .overlay(
                                    HStack {
                                        Text("Noch keine Anträge")
                                            .foregroundColor(.secondary)
                                        Spacer()
                                    }
                                    .padding(.horizontal, 18)
                                )

                            Spacer()
                        }
                        .padding(.horizontal, 18)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                        .background(Color(.systemGroupedBackground))
                    } else {
                        List {
                            // Aktuell / kommende Anträge
                            Section {
                                if currentRequests.isEmpty {
                                    HStack {
                                        Text("Keine aktuellen Anträge")
                                            .foregroundColor(.secondary)
                                        Spacer()
                                    }
                                    .listRowBackground(Color.clear)
                                    .listRowSeparator(.hidden)
                                } else {
                                    ForEach(currentRequests) { r in
                                        MyLeaveRequestCard(request: r) {
                                            if appState.canEditOrDelete(r, by: appState.currentUser) {
                                                editingRequest = r
                                            }
                                        }
                                        .swipeActions {
                                            if appState.canEditOrDelete(r, by: appState.currentUser) {
                                                Button {
                                                    editingRequest = r
                                                } label: {
                                                    Label("Bearbeiten", systemImage: "pencil")
                                                }

                                                Button(role: .destructive) {
                                                    appState.deleteLeaveRequest(r)
                                                } label: {
                                                    Label("Löschen", systemImage: "trash")
                                                }
                                            }
                                        }
                                        .listRowSeparator(.hidden)
                                        .listRowBackground(Color.clear)
                                        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                                    }
                                }
                            } header: {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Aktuelle Anträge")
                                    if counts.pending + counts.approved + counts.rejected > 0 {
                                        HStack(spacing: 8) {
                                            if counts.pending > 0 { Text("Offen: \(counts.pending)") }
                                            if counts.approved > 0 { Text("Genehmigt: \(counts.approved)") }
                                            if counts.rejected > 0 { Text("Abgelehnt: \(counts.rejected)") }
                                        }
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                    }
                                }
                                .textCase(nil)
                            }

                            // Vergangene Anträge (separater Screen)
                            if !pastRequests.isEmpty {
                                Section {
                                    NavigationLink {
                                        PastRequestsScreen(requests: pastRequests)
                                            .environmentObject(appState)
                                    } label: {
                                        HStack {
                                            Text("Vergangene Anträge")
                                            Spacer()
                                            Text("\(pastRequests.count)")
                                                .font(.caption.weight(.semibold))
                                                .foregroundColor(.secondary)
                                                .padding(.horizontal, 10)
                                                .padding(.vertical, 4)
                                                .background(
                                                    Capsule().fill(Color(.secondarySystemBackground))
                                                )
                                        }
                                        .padding(.vertical, 6)
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
            .sheet(item: $editingRequest) { request in
                NavigationStack {
                    EditLeaveRequestView(request: request)
                }
            }
        }
    }
}

struct PastRequestsScreen: View {
    @EnvironmentObject var appState: AppState
    let requests: [LeaveRequest]

    @State private var editingRequest: LeaveRequest?

    private enum TypeFilter: String, CaseIterable, Identifiable {
        case all = "Alle"
        case vacation = "Urlaub"
        case sick = "Krankheit"
        var id: String { rawValue }
    }

    private enum StatusFilter: String, CaseIterable, Identifiable {
        case all = "Alle"
        case pending = "Offen"
        case approved = "Genehmigt"
        case rejected = "Abgelehnt"
        var id: String { rawValue }
    }

    @State private var typeFilter: TypeFilter = .all
    @State private var statusFilter: StatusFilter = .all

    private var filteredRequests: [LeaveRequest] {
        requests
            .filter { r in
                switch typeFilter {
                case .all:
                    return true
                case .vacation:
                    return r.type == .vacation
                case .sick:
                    return r.type == .sick
                }
            }
            .filter { r in
                // Status filter only applies to vacation requests.
                guard r.type == .vacation else { return true }
                switch statusFilter {
                case .all:
                    return true
                case .pending:
                    return r.status == .pending
                case .approved:
                    return r.status == .approved
                case .rejected:
                    return r.status == .rejected
                }
            }
    }

    var body: some View {
        VStack(spacing: 10) {
            // Filterleiste
            VStack(spacing: 8) {
                Picker("Art", selection: $typeFilter) {
                    ForEach(TypeFilter.allCases) { f in
                        Text(f.rawValue).tag(f)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding(.horizontal, 18)
            .padding(.top, 8)

            Group {
                if filteredRequests.isEmpty {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Keine Anträge für den Filter")
                            .font(.headline)
                            .foregroundColor(.secondary)
                            .padding(.top, 16)
                        Spacer()
                    }
                    .padding(.horizontal, 18)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    .background(Color(.systemGroupedBackground))
                } else {
                    List {
                        ForEach(filteredRequests) { r in
                            MyLeaveRequestCard(request: r) {
                                if appState.canEditOrDelete(r, by: appState.currentUser) {
                                    editingRequest = r
                                }
                            }
                            .swipeActions {
                                if appState.canEditOrDelete(r, by: appState.currentUser) {
                                    Button {
                                        editingRequest = r
                                    } label: {
                                        Label("Bearbeiten", systemImage: "pencil")
                                    }

                                    Button(role: .destructive) {
                                        appState.deleteLeaveRequest(r)
                                    } label: {
                                        Label("Löschen", systemImage: "trash")
                                    }
                                }
                            }
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                    .background(Color(.systemGroupedBackground))
                }
            }
        }
        .navigationTitle("Vergangene Anträge")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editingRequest) { request in
            NavigationStack {
                EditLeaveRequestView(request: request)
            }
        }
    }
}

private struct MyRequestsHeaderView: View {
    let counts: (pending: Int, approved: Int, rejected: Int)

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Meine Anträge")
                .font(.headline)

            HStack(spacing: 8) {
                if counts.pending > 0 { Text("Offen: \(counts.pending)") }
                if counts.approved > 0 { Text("Genehmigt: \(counts.approved)") }
                if counts.rejected > 0 { Text("Abgelehnt: \(counts.rejected)") }
            }
            .font(.caption)
            .foregroundColor(.secondary)
        }
    }
}

private struct MyLeaveRequestCard: View {
    let request: LeaveRequest
    let onTap: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                // Farb-Leiste links
                RoundedRectangle(cornerRadius: 3)
                    .fill(request.type == .sick ? Color.gray.opacity(0.35) : colorForLeaveStatus(request.status).opacity(0.9))
                    .frame(width: 6)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(dateRangeString(request.startDate, request.endDate))
                            .font(.headline)

                        Spacer()

                        // Status nur bei Urlaub anzeigen
                        if request.type != .sick {
                            statusBadgeView(request.status)
                        }
                    }

                    HStack(spacing: 8) {
                        Image(systemName: request.type == .sick ? "cross.case" : "beach.umbrella")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        Text(request.type.rawValue)
                            .font(.subheadline)
                            .foregroundColor(.primary)

                        Spacer()
                    }
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
                .stroke(
                    (request.type == .sick ? Color.gray : colorForLeaveStatus(request.status)).opacity(0.18),
                    lineWidth: 1
                )
        )
        .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 6)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

// MARK: - New Leave Request Form

struct NewLeaveRequestView: View {

    private let preselectedUserId: UUID?

    init(preselectedUserId: UUID? = nil) {
        self.preselectedUserId = preselectedUserId
        _selectedUserId = State(initialValue: preselectedUserId)
    }

    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    @State private var startDate = Date()
    @State private var endDate = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    @State private var selectedType: LeaveType = .vacation
    @State private var selectedUserId: UUID? = nil
    @State private var approveImmediately: Bool = true
    @State private var inlineError: String? = nil

    private var buttonTitle: String {
        switch selectedType {
        case .vacation:
            return "Urlaub beantragen"
        case .sick:
            return "Krankheit melden"
        case .onCallSaturday:
            return "Samstag beantragen"
        }
    }

    private var typeHint: String {
        switch selectedType {
        case .vacation:
            return "Urlaubsanträge müssen genehmigt werden."
        case .sick:
            return "Krankheit wird direkt eingetragen."
        case .onCallSaturday:
            return "Samstaganträge werden nicht genehmigt."
        }
    }

    private var dayCount: Int {
        let days = workingDays(from: startDate, to: endDate)
        return max(days, 1)
    }


    private var isAdmin: Bool {
        appState.currentUser?.role == .admin
    }

    private var selectedUser: User? {
        if let id = selectedUserId {
            return appState.users.first(where: { $0.id == id })
        }
        // Default: aktueller User
        return appState.currentUser
    }

    var body: some View {
        ScrollViewReader { proxy in
            Form {
                // Fehlerhinweis immer oben anzeigen
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
                        .listRowSeparator(.hidden)
                    }
                    .id("errorBanner")
                }

                // Überblick
                Section(header: Text("Überblick")) {
                    if let user = selectedUser {
                        HStack(spacing: 12) {
                            InitialsAvatarView(name: user.name, color: user.color)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(user.name)
                                    .font(.subheadline.weight(.semibold))
                                Text("stellt einen neuen Abwesenheitsantrag.")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                    }

                    HStack(spacing: 12) {
                        Image(systemName: "calendar")
                            .foregroundColor(.accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(dayCount) Tag\(dayCount == 1 ? "" : "e")")
                                .font(.subheadline.weight(.semibold))
                            Text("von \(startDate.formatted(date: .abbreviated, time: .omitted)) bis \(endDate.formatted(date: .abbreviated, time: .omitted))")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                    }
                }

                // Admin: Mitarbeiter-Auswahl
                if isAdmin {
                    Section(header: Text("Mitarbeiter")) {
                        Picker("Für", selection: Binding(
                            get: { selectedUserId ?? appState.currentUser?.id },
                            set: { selectedUserId = $0 }
                        )) {
                            ForEach(appState.users) { u in
                                Text(u.name).tag(Optional(u.id))
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }

    // Zeitraum
    Section(header: Text("Zeitraum")) {
        DatePicker("Von", selection: $startDate, displayedComponents: .date)
            .datePickerStyle(.compact)
            .onChange(of: startDate) { newStart in
                if endDate < newStart {
                    endDate = newStart
                }
            }

        DatePicker("Bis", selection: $endDate, in: startDate...Date.distantFuture, displayedComponents: .date)
            .datePickerStyle(.compact)
    }

                // Art der Abwesenheit
                Section(header: Text("Art der Abwesenheit")) {
                    // Nur Urlaub und Krankheit zur Auswahl anbieten
                    let allowedTypes: [LeaveType] = [.vacation, .sick]

                    Picker("Art", selection: $selectedType) {
                        ForEach(allowedTypes, id: \.self) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)

                    if !typeHint.isEmpty {
                        Text(typeHint)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if isAdmin && selectedType == .vacation {
                        Toggle("Direkt genehmigen", isOn: $approveImmediately)
                    }
                }

                // Aktion
                Section {
                    Button {
                        guard let targetUser = selectedUser else {
                            inlineError = "Bitte einen Mitarbeiter auswählen."
                            return
                        }

                        let ok = appState.createLeaveRequest(start: startDate,
                                                             end: endDate,
                                                             type: selectedType,
                                                             for: targetUser,
                                                             approveImmediately: (selectedType == .vacation) ? (isAdmin && approveImmediately) : false)
                        if ok {
                            inlineError = nil
                            dismiss()
                        } else {
                            inlineError = appState.uiErrorMessage
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: selectedType == .vacation ? "paperplane.fill" : "cross.case.fill")
                                .font(.system(size: 14, weight: .semibold))
                            Text(buttonTitle)
                                .font(.subheadline.weight(.semibold))
                        }
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .buttonBorderShape(.capsule)
                }
            }
            .onChange(of: inlineError) { value in
                guard value != nil else { return }
                withAnimation(.easeInOut) {
                    proxy.scrollTo("errorBanner", anchor: .top)
                }
            }
            .onChange(of: startDate) { _ in
                inlineError = nil
                appState.uiErrorMessage = nil
            }
            .onChange(of: endDate) { _ in
                inlineError = nil
                appState.uiErrorMessage = nil
            }
            .onChange(of: selectedType) { _ in
                inlineError = nil
                appState.uiErrorMessage = nil
                if selectedType == .sick {
                    approveImmediately = false
                }
            }
        }
        .navigationTitle("Neuer Antrag")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if selectedUserId == nil {
                selectedUserId = preselectedUserId ?? appState.currentUser?.id
            }
            // Bei Krankheit macht "Direkt genehmigen" keinen Sinn
            if selectedType == .sick {
                approveImmediately = false
            }
        }
    }
}
