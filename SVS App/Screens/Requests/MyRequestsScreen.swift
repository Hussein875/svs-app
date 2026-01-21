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
        guard let me = appState.currentUser else { return [] }
        let myId = me.id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !myId.isEmpty else { return [] }

        return appState.leaveRequests.filter { $0.user.id == myId }
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

    private func canEditOnCall(_ r: LeaveRequest) -> Bool {
        guard r.type == .onCallSaturday else { return false }
        guard let currentUser = appState.currentUser else { return false }
        // Only allow editing for future (or today) entries
        let day = Calendar.current.startOfDay(for: r.startDate)
        guard day >= todayStart else { return false }
        // Admin can edit all; otherwise only the owner can edit
        if currentUser.role == .admin { return true }
        return (currentUser.role == .expert) && (r.user.id == currentUser.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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
                                    // Samstags-Bereitschaft soll nicht bearbeitet werden
                                    guard r.type != .onCallSaturday else { return }
                                    if appState.canEditOrDelete(r, by: appState.currentUser) {
                                        editingRequest = r
                                    }
                                }
                                .swipeActions {
                                    // Für Samstags-Bereitschaft: nur Löschen (kein Bearbeiten)
                                    if r.type == .onCallSaturday {
                                        Button(role: .destructive) {
                                            appState.deleteLeaveRequest(r)
                                        } label: {
                                            Label("Löschen", systemImage: "trash")
                                        }
                                    } else if appState.canEditOrDelete(r, by: appState.currentUser) {
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
        .background(Color(.systemGroupedBackground))
        .navigationDestination(item: $editingRequest) { request in
            EditLeaveRequestView(request: request)
                .environmentObject(appState)
        }
        .navigationTitle("Meine Anträge")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    NewLeaveRequestView()
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityLabel("Neuen Antrag erstellen")
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
        case onCallSaturday = "Bereitschaft"
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
                case .onCallSaturday:
                    return r.type == .onCallSaturday
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
                                // Für Samstags-Bereitschaft: nur Löschen (kein Bearbeiten)
                                if r.type == .onCallSaturday {
                                    Button(role: .destructive) {
                                        appState.deleteLeaveRequest(r)
                                    } label: {
                                        Label("Löschen", systemImage: "trash")
                                    }
                                } else if appState.canEditOrDelete(r, by: appState.currentUser) {
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
        .navigationDestination(item: $editingRequest) { request in
            EditLeaveRequestView(request: request)
                .environmentObject(appState)
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
                    .fill({
                        switch request.type {
                        case .sick:
                            return Color.gray.opacity(0.35)
                        case .onCallSaturday:
                            return Color.blue.opacity(0.9)
                        case .vacation:
                            return colorForLeaveStatus(request.status).opacity(0.9)
                        }
                    }())
                    .frame(width: 6)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(dateRangeString(request.startDate, request.endDate))
                            .font(.headline)

                        Spacer()

                        // Status nur bei Urlaub anzeigen
                        if request.type != .sick && request.type != .onCallSaturday {
                            Text(request.status.rawValue)
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.primary)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(
                                    Capsule()
                                        .fill(colorForLeaveStatus(request.status).opacity(0.20))
                                )
                        }
                    }

                    HStack(spacing: 8) {
                        Image(systemName: {
                            switch request.type {
                            case .vacation: return "beach.umbrella"
                            case .sick: return "cross.case"
                            case .onCallSaturday: return "person.badge.clock"
                            }
                        }())
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
                    ({
                        switch request.type {
                        case .sick:
                            return Color.gray
                        case .onCallSaturday:
                            return Color.blue
                        case .vacation:
                            return colorForLeaveStatus(request.status)
                        }
                    }()).opacity(0.18),
                    lineWidth: 1
                )
        )
        .shadow(color: Color.black.opacity(0.06), radius: 10, x: 0, y: 6)
        .contentShape(Rectangle())
        .onTapGesture {
            // Samstags-Bereitschaft soll nicht per Tap geöffnet werden.
            // Bearbeiten/Löschen erfolgt dort ausschließlich über Wischen (Swipe Actions).
            guard request.type != .onCallSaturday else { return }
            onTap()
        }
    }
}

// MARK: - New Leave Request Form

struct NewLeaveRequestView: View {

    private let preselectedUserId: String?

    init(preselectedUserId: String? = nil) {
        self.preselectedUserId = preselectedUserId
        _selectedUserId = State(initialValue: preselectedUserId)
    }

    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    @State private var startDate = Date()
    @State private var endDate = Calendar.current.date(byAdding: .day, value: 1, to: Date()) ?? Date()
    @State private var selectedType: LeaveType = .vacation
    @State private var selectedUserId: String? = nil
    @State private var approveImmediately: Bool = true
    @State private var inlineError: String? = nil
    @State private var didLoadInitialValues: Bool = false

    private var buttonTitle: String {
        switch selectedType {
        case .vacation:
            return "Urlaub beantragen"
        case .sick:
            return "Krankheit melden"
        case .onCallSaturday:
            return "Samstags-Bereitschaft eintragen"
        }
    }

    private var typeHint: String {
        switch selectedType {
        case .vacation:
            return "Urlaubsanträge müssen genehmigt werden."
        case .sick:
            return "Krankheit wird direkt eingetragen."
        case .onCallSaturday:
            return "Bereitschaft am Samstag wird direkt eingetragen."
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

    // MARK: - Samstags-Bereitschaft Helpers

    private var canRequestSaturdayOnCall: Bool {
        // Sachverständige + Admins dürfen Samstags-Bereitschaft eintragen
        guard let role = appState.currentUser?.role else { return false }
        return role == .admin || role == .expert
    }

    private var eligibleSaturdayUsers: [User] {
        // Nur Admins und Sachverständige auswählbar
        appState.users.filter { $0.role == .admin || $0.role == .expert }
    }

    private var takenOnCallSaturdays: Set<Date> {
        let cal = Calendar.current
        let all = appState.leaveRequests
            .filter { $0.type == .onCallSaturday }
            .filter { $0.status == .approved }
        return Set(all.map { cal.startOfDay(for: $0.startDate) })
    }

    private var upcomingFreeSaturdays: [Date] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var result: [Date] = []
        var d = today

        // Next 52 weeks max (enough for planning) and skip taken Saturdays
        while result.count < 52 {
            let weekday = cal.component(.weekday, from: d)
            if weekday == 7 { // Saturday (1=Sunday ... 7=Saturday)
                let day = cal.startOfDay(for: d)
                if !takenOnCallSaturdays.contains(day) {
                    result.append(day)
                }
            }
            d = cal.date(byAdding: .day, value: 1, to: d) ?? d
        }
        return result
    }

    private var saturdayPickerOptions: [Date] {
        // Prevent Picker invalid-tag warning by ensuring selection is always present
        let cal = Calendar.current
        let normalizedStart = cal.startOfDay(for: startDate)
        var options = upcomingFreeSaturdays
        if !options.contains(normalizedStart) {
            options.append(normalizedStart)
        }
        return Array(Set(options)).sorted(by: <)
    }

    private var isSelectedSaturdayFree: Bool {
        let cal = Calendar.current
        let day = cal.startOfDay(for: startDate)
        return !takenOnCallSaturdays.contains(day)
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
                                Text(selectedType == .onCallSaturday ? "trägt eine Samstags-Bereitschaft ein." : "stellt einen neuen Abwesenheitsantrag.")
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
                
                // Art der Abwesenheit
                Section(header: Text("Art")) {
                    // Standard: Urlaub + Krankheit. Zusätzlich: Samstags-Bereitschaft für Sachverständige/Admins.
                    let allowedTypes: [LeaveType] = canRequestSaturdayOnCall ? [.vacation, .sick, .onCallSaturday] : [.vacation, .sick]

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

                // Admin: Mitarbeiter-Auswahl
                if isAdmin {
                    Section(header: Text("Mitarbeiter")) {
                        Picker("Für", selection: Binding<String?>(
                            get: { selectedUserId ?? appState.currentUser?.id },
                            set: { selectedUserId = $0 }
                        )) {
                            ForEach(selectedType == .onCallSaturday ? eligibleSaturdayUsers : appState.users) { u in
                                Text(u.name).tag(Optional(u.id))
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }

                // Zeitraum / Samstag
                if selectedType == .onCallSaturday {
                    Section(header: Text("Samstag"), footer: Text("Belegte Samstage sind nicht auswählbar.")) {
                        Picker("Datum", selection: $startDate) {
                            ForEach(saturdayPickerOptions, id: \.self) { d in
                                Text(d.formatted(date: .abbreviated, time: .omitted)).tag(d)
                            }
                        }
                        .pickerStyle(.navigationLink)
                        .onAppear {
                            // Ensure selection is start-of-day so it matches the tags
                            startDate = Calendar.current.startOfDay(for: startDate)
                            endDate = Calendar.current.startOfDay(for: endDate)
                        }
                        // For on-call Saturdays we keep start=end
                        // (endDate is not used for this type but kept consistent)
                        .onChange(of: startDate) {
                            let day = Calendar.current.startOfDay(for: startDate)
                            startDate = day
                            endDate = day
                        }

                        if !isSelectedSaturdayFree {
                            Text("Dieser Samstag ist bereits vergeben.")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                } else {
                    Section(header: Text("Zeitraum")) {
                        DatePicker("Von", selection: $startDate, displayedComponents: .date)
                            .datePickerStyle(.compact)
                            .onChange(of: startDate) {
                                if endDate < startDate {
                                    endDate = startDate
                                }
                            }

                        DatePicker("Bis", selection: $endDate, in: startDate...Date.distantFuture, displayedComponents: .date)
                            .datePickerStyle(.compact)
                    }
                }

                // Aktion
                Section {
                    Button {
                        guard let targetUser = selectedUser else {
                            inlineError = "Bitte einen Mitarbeiter auswählen."
                            return
                        }

                        if selectedType == .onCallSaturday {
                            // Normalize to start-of-day and ensure the Saturday is free
                            let day = Calendar.current.startOfDay(for: startDate)
                            startDate = day
                            endDate = day

                            guard isSelectedSaturdayFree else {
                                inlineError = "Dieser Samstag ist bereits vergeben. Bitte einen anderen Samstag wählen."
                                return
                            }

                            // Optional: enforce eligibility at runtime
                            guard targetUser.role == .admin || targetUser.role == .expert else {
                                inlineError = "Für Samstags-Bereitschaft können nur Admins oder Sachverständige ausgewählt werden."
                                return
                            }
                        }

                        let ok = appState.createLeaveRequest(
                            start: startDate,
                            end: endDate,
                            type: selectedType,
                            for: targetUser,
                            approveImmediately: (selectedType == .vacation)
                                ? (isAdmin && approveImmediately)
                                : (selectedType == .onCallSaturday ? true : false)
                        )
                        if ok {
                            inlineError = nil
                            dismiss()
                        } else {
                            inlineError = appState.uiErrorMessage
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: selectedType == .vacation ? "paperplane.fill" : (selectedType == .sick ? "cross.case.fill" : "person.badge.clock"))
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
            .onChange(of: inlineError) {
                guard inlineError != nil else { return }
                withAnimation(.easeInOut) {
                    proxy.scrollTo("errorBanner", anchor: .top)
                }
            }
            .onChange(of: startDate) {
                inlineError = nil
                appState.uiErrorMessage = nil
            }
            .onChange(of: endDate) {
                inlineError = nil
                appState.uiErrorMessage = nil
            }
            .onChange(of: selectedType) {
                inlineError = nil
                appState.uiErrorMessage = nil
                if selectedType == .sick {
                    approveImmediately = false
                }
                if selectedType == .onCallSaturday {
                    // Pick the first free Saturday by default
                    if let first = upcomingFreeSaturdays.first {
                        let day = Calendar.current.startOfDay(for: first)
                        startDate = day
                        endDate = day
                    } else {
                        // Fallback: normalize current
                        let day = Calendar.current.startOfDay(for: startDate)
                        startDate = day
                        endDate = day
                    }
                    approveImmediately = false
                }
            }
        }
        .navigationTitle("Neuer Antrag")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // With `.pickerStyle(.navigationLink)` SwiftUI may re-trigger `onAppear`
            // when returning from the picker screen. Guard to avoid resetting selections.
            guard !didLoadInitialValues else { return }
            didLoadInitialValues = true

            if selectedUserId == nil {
                selectedUserId = preselectedUserId ?? appState.currentUser?.id
            }
            // Bei Krankheit macht "Direkt genehmigen" keinen Sinn
            if selectedType == .sick {
                approveImmediately = false
            }
            // Normalize initial dates
            startDate = Calendar.current.startOfDay(for: startDate)
            endDate = Calendar.current.startOfDay(for: endDate)

            // If the UI starts on on-call, ensure we start with a free Saturday.
            if selectedType == .onCallSaturday, let first = upcomingFreeSaturdays.first {
                startDate = Calendar.current.startOfDay(for: first)
                endDate = startDate
            }
        }
    }
}
