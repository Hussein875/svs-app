//
//  MyRequestsComponents.swift
//  SVS App
//
//  Extracted from MyRequestsScreen.swift for readability.
//

import Foundation
import SwiftUI

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
                                // Past requests are read-only (no edit / no delete)
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

struct MyLeaveRequestCard: View {
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
                        if request.type != .sick { Text(request.status.rawValue)
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

    // Simple Apple calendar popovers (auto-dismiss on selection)
    @State private var showStartCalendar = false
    @State private var showEndCalendar = false

    @State private var selectedType: LeaveType = .vacation
    @State private var selectedUserId: String? = nil

    @State private var inlineError: String? = nil
    @State private var didLoadInitialValues: Bool = false

    private var buttonTitle: String {
        switch selectedType {
        case .vacation:
            return "Abwesenheit einreichen"
        case .sick:
            return "Krankheit melden"
        case .onCallSaturday:
            return "Abwesenheit einreichen" // unreachable here
        }
    }

    private var typeHint: String {
        switch selectedType {
        case .vacation:
            return "Abwesenheiten müssen genehmigt werden."
        case .sick:
            return "Krankheit wird direkt eingetragen."
        case .onCallSaturday:
            return "" // unreachable
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
            ZStack {
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
                                Text(selectedType == .sick ? "meldet eine Krankheit." : "reicht eine Abwesenheit ein.")
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
                    Picker("Art", selection: $selectedType) {
                        Text(LeaveType.vacation.rawValue).tag(LeaveType.vacation)
                        Text(LeaveType.sick.rawValue).tag(LeaveType.sick)
                    }
                    .pickerStyle(.segmented)

                    if !typeHint.isEmpty {
                        Text(typeHint)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                // Admin: Mitarbeiter-Auswahl
                if isAdmin {
                    Section(header: Text("Mitarbeiter")) {
                        Picker("Für", selection: Binding<String?>(
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
                    Button {
                        showStartCalendar = true
                    } label: {
                        HStack {
                            Text("Von")
                                .foregroundColor(.primary)
                            Spacer()
                            Text(startDate.formatted(date: .abbreviated, time: .omitted))
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .sheet(isPresented: $showStartCalendar) {
                        VStack(spacing: 12) {
                            DatePicker(
                                "",
                                selection: $startDate,
                                displayedComponents: .date
                            )
                            .datePickerStyle(.graphical)
                            .labelsHidden()
                            .padding(.horizontal, 12)

                            Spacer(minLength: 0)
                        }
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
                        .onChange(of: startDate) {
                            // 1-tap auto-dismiss
                            showStartCalendar = false
                        }
                    }

                    Button {
                        showEndCalendar = true
                    } label: {
                        HStack {
                            Text("Bis")
                                .foregroundColor(.primary)
                            Spacer()
                            Text(endDate.formatted(date: .abbreviated, time: .omitted))
                                .foregroundColor(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                    .sheet(isPresented: $showEndCalendar) {
                        VStack(spacing: 12) {
                            DatePicker(
                                "",
                                selection: $endDate,
                                in: startDate...Date.distantFuture,
                                displayedComponents: .date
                            )
                            .datePickerStyle(.graphical)
                            .labelsHidden()
                            .padding(.horizontal, 12)

                            Spacer(minLength: 0)
                        }
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.visible)
                        .onChange(of: endDate) {
                            // 1-tap auto-dismiss
                            showEndCalendar = false
                        }
                    }
                }

                // Aktion
                Section {
                    Button {
                        guard let targetUser = selectedUser else {
                            inlineError = "Bitte einen Mitarbeiter auswählen."
                            return
                        }
                        let ok = appState.createLeaveRequest(
                            start: startDate,
                            end: endDate,
                            type: selectedType,
                            for: targetUser
                        )
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
                // popup overlay inserted below
                .onChange(of: inlineError) {
                    guard inlineError != nil else { return }
                    withAnimation(.easeInOut) {
                        proxy.scrollTo("errorBanner", anchor: .top)
                    }
                }
                .onChange(of: selectedType) {
                    inlineError = nil
                    appState.uiErrorMessage = nil
                }
                .onChange(of: startDate) {
                    // Normalize + keep end >= start
                    startDate = Calendar.current.startOfDay(for: startDate)
                    if endDate < startDate { endDate = startDate }
                    inlineError = nil
                    appState.uiErrorMessage = nil
                }
                .onChange(of: endDate) {
                    endDate = Calendar.current.startOfDay(for: endDate)
                    inlineError = nil
                    appState.uiErrorMessage = nil
                }
                // End of ZStack/Form
            }
        }
        .navigationTitle("Neue Abwesenheit")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            // With `.pickerStyle(.navigationLink)` SwiftUI may re-trigger `onAppear`
            // when returning from the picker screen. Guard to avoid resetting selections.
            guard !didLoadInitialValues else { return }
            didLoadInitialValues = true

            if selectedUserId == nil {
                selectedUserId = preselectedUserId ?? appState.currentUser?.id
            }
            // Normalize initial dates
            startDate = Calendar.current.startOfDay(for: startDate)
            endDate = Calendar.current.startOfDay(for: endDate)
        }
    }
}
