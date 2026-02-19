//
//  AdminOnCallSaturdaysViews.swift
//  SVS App
//
//  Extracted from AdminConsoleView.swift for readability.
//

import Foundation
import SwiftUI

// MARK: - Admin On-Call Saturdays

struct AdminOnCallSaturdaysScreen: View {
    @EnvironmentObject var appState: AppState
    @State private var showNew: Bool = false
    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    @State private var editingRequest: LeaveRequest?
    @State private var showEdit: Bool = false
    @State private var prefilledNewSaturday: Date? = nil

    // 1) takenSaturdays
    private var takenSaturdays: Set<Date> {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let taken = appState.leaveRequests
            .filter { $0.type == .onCallSaturday && $0.status != .rejected }
            .map { cal.startOfDay(for: $0.startDate) }
        // Only consider dates from today onward
        return Set(taken.filter { $0 >= today })
    }

    // 2) nextFreeSaturdays
    private var nextFreeSaturdays: [Date] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var result: [Date] = []
        var d = today
        while result.count < 8 {
            if cal.component(.weekday, from: d) == 7 { // Saturday
                let day = cal.startOfDay(for: d)
                if !takenSaturdays.contains(day) {
                    result.append(day)
                }
            }
            d = cal.date(byAdding: .day, value: 1, to: d) ?? d
        }
        return result
    }

    // Keep the existing onCallCountsByUser and totalOnCallCount
    private var onCallCountsByUser: [(user: User, count: Int)] {
        let cal = Calendar.current
        let currentYear = cal.component(.year, from: Date())
        let counts: [String: Int] = appState.leaveRequests
            .filter { $0.type == .onCallSaturday && $0.status != .rejected }
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

    private var upcomingOnCalls: [LeaveRequest] {
        let cal = Calendar.current
        let currentYear = cal.component(.year, from: Date())

        return appState.leaveRequests
            .filter { $0.type == .onCallSaturday && $0.status != .rejected }
            .filter { cal.component(.year, from: $0.startDate) == currentYear }
            .sorted { $0.startDate < $1.startDate }
    }

    private var onCallsByMonth: [(monthStart: Date, items: [LeaveRequest])] {
        let cal = Calendar.current

        let grouped = Dictionary(grouping: upcomingOnCalls) { req in
            let comps = cal.dateComponents([.year, .month], from: req.startDate)
            return cal.date(from: comps) ?? cal.startOfDay(for: req.startDate)
        }

        let sortedKeys = grouped.keys.sorted(by: <)
        return sortedKeys.map { key in
            let items = (grouped[key] ?? []).sorted { $0.startDate < $1.startDate }
            return (monthStart: key, items: items)
        }
    }

    private func monthTitle(_ date: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale(identifier: "de_DE")
        df.dateFormat = "LLLL yyyy"
        return df.string(from: date).capitalized
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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
                if nextFreeSaturdays.isEmpty && onCallsByMonth.isEmpty {
                    Section {
                        Text("Noch keine Samstags-Bereitschaften eingetragen")
                            .foregroundColor(.secondary)
                    }
                } else {
                    if !nextFreeSaturdays.isEmpty {
                        Section(header: Text("Freie Samstage (nächste 8)")) {
                            ForEach(nextFreeSaturdays, id: \.self) { d in
                                HStack(spacing: 12) {
                                    Image(systemName: "calendar.badge.plus")
                                        .foregroundColor(.secondary)
                                    Text(d.formatted(date: .abbreviated, time: .omitted))
                                        .font(.subheadline.weight(.semibold))
                                    Spacer()
                                    Text("Frei")
                                        .font(.caption.weight(.semibold))
                                        .foregroundColor(.secondary)
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    prefilledNewSaturday = d
                                    showNew = true
                                }
                            }
                        }
                    }
                    if !onCallsByMonth.isEmpty {
                        ForEach(onCallsByMonth, id: \.monthStart) { group in
                            Section(header: Text(monthTitle(group.monthStart))) {
                                ForEach(group.items) { req in
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
                                        Button {
                                            editingRequest = req
                                            showEdit = true
                                        } label: {
                                            Label("Bearbeiten", systemImage: "pencil")
                                        }
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
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground))
        }
        .background(Color(.systemGroupedBackground))
        .navigationDestination(isPresented: $showNew) {
            NewOnCallSaturdayView(prefilledDate: prefilledNewSaturday)
                .environmentObject(appState)
        }
        .navigationDestination(isPresented: $showEdit) {
            if let req = editingRequest {
                EditOnCallSaturdayView(existingRequest: req)
                    .environmentObject(appState)
            } else {
                EmptyView()
            }
        }
        .onChange(of: showEdit) {
            if !showEdit {
                editingRequest = nil
            }
        }
        .onChange(of: showNew) {
            if !showNew {
                prefilledNewSaturday = nil
            }
        }
        .navigationTitle("Bereitschaft")
        .navigationBarTitleDisplayMode(.inline)
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
        if isAdmin {
            return appState.users
                .filter { $0.role == .expert || $0.role == .admin }
                .sorted { $0.name.lowercased() < $1.name.lowercased() }
        }
        guard let me = appState.currentUser else { return [] }
        return [me]
    }

    private var isAdmin: Bool {
        appState.currentUser?.role == .admin
    }
    
    private var takenSaturdaysExcludingCurrent: Set<Date> {
        let cal = Calendar.current
        let currentDay = cal.startOfDay(for: existingRequest.startDate)
        return Set(
            appState.leaveRequests
                .filter {
                    $0.type == .onCallSaturday && $0.status != .rejected
                }
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
                Picker("Datum", selection: Binding(
                    get: { Calendar.current.startOfDay(for: selectedSaturday) },
                    set: { selectedSaturday = Calendar.current.startOfDay(for: $0) }
                )) {
                    ForEach(saturdayPickerOptions.map { Calendar.current.startOfDay(for: $0) }, id: \.self) { d in
                        Text(d.formatted(date: .abbreviated, time: .omitted)).tag(d)
                    }
                }
                .pickerStyle(.navigationLink)
            }
            
            Section(header: Text("Mitarbeiter")) {
                if isAdmin {
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
                } else if let me = appState.currentUser, eligibleUsers.contains(where: { $0.id == me.id }) {
                    HStack {
                        Text("Mitarbeiter")
                        Spacer()
                        Text(me.name)
                            .foregroundColor(.secondary)
                    }
                    .onAppear {
                        selectedUserId = me.id
                    }
                } else {
                    Text("Bereitschaft kann nur für Admins oder Sachverständige eingetragen werden.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            
            Section(header: Text("Aktionen")) {
                Button {
                    guard let id = selectedUserId, let user = eligibleUsers.first(where: { $0.id == id }) else {
                        inlineError = "Bitte einen Admin oder Sachverständigen auswählen."
                        return
                    }
                    if !isAdmin, user.id != appState.currentUser?.id {
                        inlineError = "Sie können nur sich selbst für Bereitschaft eintragen."
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
                        for: user
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
                            for: oldUser
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
            }
        }
        .navigationTitle("Bereitschaft")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // Important: With `.pickerStyle(.navigationLink)` SwiftUI may re-trigger `onAppear`
            // when coming back from the picker screen. Without this guard, the selection is reset.
            guard !didLoadInitialValues else { return }
            didLoadInitialValues = true
            if isAdmin {
                selectedUserId = existingRequest.user.id
            } else {
                selectedUserId = appState.currentUser?.id
            }
            selectedSaturday = Calendar.current.startOfDay(for: existingRequest.startDate)
        }
    }
}

// MARK: - NewOnCallSaturdayView

struct NewOnCallSaturdayView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    
    let prefilledDate: Date?

    @State private var selectedUserId: String?
    @State private var selectedSaturday: Date = Calendar.current.startOfDay(for: Date())
    @State private var inlineError: String?
    @State private var didLoadInitialValues: Bool = false

    init(prefilledDate: Date? = nil) {
        self.prefilledDate = prefilledDate
    }

    private var isAdmin: Bool {
        appState.currentUser?.role == .admin
    }

    private var eligibleUsers: [User] {
        if isAdmin {
            return appState.users
                .filter { $0.role == .expert || $0.role == .admin }
                .sorted { $0.name.lowercased() < $1.name.lowercased() }
        }
        guard let me = appState.currentUser else { return [] }
        return [me]
    }

    private var takenSaturdays: Set<Date> {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return Set(
            appState.leaveRequests
                .filter { $0.type == .onCallSaturday && $0.status != .rejected }
                .map { cal.startOfDay(for: $0.startDate) }
                .filter { $0 >= today }
        )
    }

    private var upcomingFreeSaturdays: [Date] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        var result: [Date] = []
        var d = today
        while result.count < 8 {
            if cal.component(.weekday, from: d) == 7 {
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
        let normalized = cal.startOfDay(for: selectedSaturday)
        var options = upcomingFreeSaturdays
        // keep selection present if it was prefilled
        if !options.contains(normalized) {
            options.append(normalized)
        }
        // but never allow already-taken dates to appear
        options = options.filter { !takenSaturdays.contains($0) }
        return Array(Set(options)).sorted(by: <)
    }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 10) {
                    Image(systemName: "person.badge.clock")
                        .foregroundColor(.secondary)
                    Text("Samstags-Bereitschaft hinzufügen")
                        .font(.subheadline.weight(.semibold))
                }
                Text("Wähle einen freien Samstag und einen Admin oder Sachverständigen.")
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

            Section(header: Text("Samstag"), footer: Text("Nur freie Samstage auswählbar.")) {
                Picker("Datum", selection: Binding(
                    get: { Calendar.current.startOfDay(for: selectedSaturday) },
                    set: { selectedSaturday = Calendar.current.startOfDay(for: $0) }
                )) {
                    ForEach(saturdayPickerOptions, id: \.self) { d in
                        Text(d.formatted(date: .abbreviated, time: .omitted)).tag(d)
                    }
                }
                .pickerStyle(.navigationLink)
            }

            Section(header: Text("Mitarbeiter")) {
                if isAdmin {
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
                } else if let me = appState.currentUser, eligibleUsers.contains(where: { $0.id == me.id }) {
                    HStack {
                        Text("Mitarbeiter")
                        Spacer()
                        Text(me.name)
                            .foregroundColor(.secondary)
                    }
                } else {
                    Text("Bereitschaft kann nur für Admins oder Sachverständige eingetragen werden.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }

            Section(header: Text("Aktionen")) {
                Button {
                    guard let id = selectedUserId, let user = eligibleUsers.first(where: { $0.id == id }) else {
                        inlineError = "Bitte einen Admin oder Sachverständigen auswählen."
                        return
                    }
                    if !isAdmin, user.id != appState.currentUser?.id {
                        inlineError = "Sie können nur sich selbst für Bereitschaft eintragen."
                        return
                    }
                    let ok = appState.createLeaveRequest(
                        start: selectedSaturday,
                        end: selectedSaturday,
                        type: .onCallSaturday,
                        for: user
                    )

                    if ok {
                        inlineError = nil
                        dismiss()   // ✅ Fenster schließt sich sauber
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
                .disabled(selectedUserId == nil)
            }
        }
        .navigationTitle("Bereitschaft")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            guard !didLoadInitialValues else { return }
            didLoadInitialValues = true
            if !isAdmin {
                selectedUserId = appState.currentUser?.id
            }
            if let d = prefilledDate {
                selectedSaturday = Calendar.current.startOfDay(for: d)
            }
        }
    }
}
