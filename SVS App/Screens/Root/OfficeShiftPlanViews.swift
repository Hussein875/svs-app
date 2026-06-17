//
//  OfficeShiftPlanViews.swift
//  SVS App
//

import SwiftUI

struct OfficeShiftWeekPlanSection: View {
    @EnvironmentObject var appState: AppState
    @State private var weekMonday: Date = OfficeShiftCalendar.mondayOfWeek(containing: Date())
    @State private var editingContext: OfficeShiftEditContext?
    @State private var showCopyConfirm = false
    @State private var isCopying = false

    private var isAdmin: Bool {
        appState.currentUser?.role == .admin
    }

    private var weekdays: [Date] {
        OfficeShiftCalendar.weekdaysInWeek(starting: weekMonday)
    }

    private var futureWeeksToCopyCount: Int {
        OfficeShiftCalendar.futureWeekMondays(afterTemplateMonday: weekMonday).count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Büroschichten \(OfficeShiftCalendar.locationName)")
                        .font(.headline)
                    Text("Mo–Fr · Früh 10–18 · Spät 12–20")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                Spacer()
            }

            HStack(spacing: 8) {
                Button {
                    shiftWeek(by: -7)
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color(.tertiarySystemBackground)))
                }
                .buttonStyle(.plain)

                VStack(spacing: 2) {
                    Text("KW \(OfficeShiftCalendar.weekNumber(for: weekMonday))")
                        .font(.subheadline.weight(.semibold))
                    Text(OfficeShiftCalendar.weekRangeLabel(monday: weekMonday))
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity)

                Button {
                    shiftWeek(by: 7)
                } label: {
                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.semibold))
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(Color(.tertiarySystemBackground)))
                }
                .buttonStyle(.plain)
            }

            OfficeShiftWeekGrid(
                weekdays: weekdays,
                appState: appState,
                containsCurrentUser: containsCurrentUser(day:shift:),
                onCellTap: { day, shift in
                    editingContext = OfficeShiftEditContext(day: day, shift: shift)
                }
            )

            if isAdmin {
                Button {
                    showCopyConfirm = true
                } label: {
                    HStack(spacing: 8) {
                        if isCopying {
                            ProgressView()
                                .controlSize(.small)
                        } else {
                            Image(systemName: "doc.on.doc.fill")
                        }
                        Text("Plan für alle zukünftigen Wochen kopieren")
                            .font(.subheadline.weight(.semibold))
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color(.tertiarySystemBackground))
                    )
                }
                .buttonStyle(.plain)
                .disabled(isCopying || futureWeeksToCopyCount == 0)
            }

            Text(isAdmin
                 ? "Tippen zum Eintragen · bis zu 2 Mitarbeiter pro Schicht"
                 : "Tippen zum Eintragen · eigene Schicht oder Admin-Zuweisung")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.secondary.opacity(0.10), lineWidth: 1)
        )
        .sheet(item: $editingContext) { context in
            OfficeShiftEditorSheet(
                day: context.day,
                shift: context.shift,
                isAdmin: isAdmin
            )
            .environmentObject(appState)
        }
        .alert("Plan kopieren?", isPresented: $showCopyConfirm) {
            Button("Kopieren") {
                copyPlanToFutureWeeks()
            }
            Button("Abbrechen", role: .cancel) { }
        } message: {
            Text(
                "Die Schichten dieser Woche (KW \(OfficeShiftCalendar.weekNumber(for: weekMonday))) werden auf \(futureWeeksToCopyCount) weitere Wochen bis Jahresende übernommen. Bestehende Einträge werden dabei überschrieben."
            )
        }
    }

    private func shiftWeek(by days: Int) {
        weekMonday = OfficeShiftCalendar.berlin.date(byAdding: .day, value: days, to: weekMonday)
            ?? weekMonday
    }

    private func containsCurrentUser(day: Date, shift: OfficeShiftKind) -> Bool {
        guard let me = appState.currentUser else { return false }
        return appState.officeShiftUsers(day: day, shift: shift).contains(where: { $0.id == me.id })
    }

    private func copyPlanToFutureWeeks() {
        guard !isCopying else { return }
        isCopying = true
        _Concurrency.Task {
            defer { isCopying = false }
            _ = await appState.copyOfficeShiftWeekToFutureWeeks(fromWeekMonday: weekMonday)
        }
    }
}

private struct OfficeShiftWeekGrid: View {
    let weekdays: [Date]
    let appState: AppState
    let containsCurrentUser: (Date, OfficeShiftKind) -> Bool
    let onCellTap: (Date, OfficeShiftKind) -> Void

    private let labelColumnWidth: CGFloat = 36

    var body: some View {
        Grid(horizontalSpacing: 3, verticalSpacing: 6) {
            GridRow {
                Color.clear
                    .frame(width: labelColumnWidth, height: 1)
                    .gridCellColumns(1)

                ForEach(weekdays, id: \.self) { day in
                    OfficeShiftDayHeader(day: day)
                        .frame(maxWidth: .infinity)
                }
            }

            ForEach(OfficeShiftKind.allCases) { shift in
                GridRow {
                    OfficeShiftRowLabel(shift: shift)
                        .frame(width: labelColumnWidth, alignment: .leading)

                    ForEach(weekdays, id: \.self) { day in
                        OfficeShiftPlanCell(
                            users: appState.officeShiftUsers(day: day, shift: shift),
                            isMine: containsCurrentUser(day, shift)
                        ) {
                            onCellTap(day, shift)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

private struct OfficeShiftEditContext: Identifiable {
    let day: Date
    let shift: OfficeShiftKind

    var id: String {
        OfficeShiftCalendar.documentId(day: day, shift: shift)
    }
}

private struct OfficeShiftRowLabel: View {
    let shift: OfficeShiftKind

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(shift.rawValue)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(shift.shortHoursLabel)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }
}

private struct OfficeShiftDayHeader: View {
    let day: Date

    private var weekdayLabel: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.timeZone = OfficeShiftCalendar.berlin.timeZone
        formatter.dateFormat = "EE"
        return formatter.string(from: day).capitalized
    }

    private var dateLabel: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.timeZone = OfficeShiftCalendar.berlin.timeZone
        formatter.dateFormat = "d.M."
        return formatter.string(from: day)
    }

    var body: some View {
        VStack(spacing: 1) {
            Text(weekdayLabel)
                .font(.system(size: 10, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(dateLabel)
                .font(.system(size: 9))
                .foregroundColor(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct OfficeShiftPlanCell: View {
    let users: [User]
    let isMine: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .center, spacing: 2) {
                if users.isEmpty {
                    Text("—")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 28)
                } else {
                    ForEach(users) { user in
                        Text(compactName(user.name))
                            .font(.system(size: 10, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                            .allowsTightening(true)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .padding(.horizontal, 3)
            .padding(.vertical, 5)
            .frame(maxWidth: .infinity, minHeight: 36)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isMine ? Color.green.opacity(0.16) : Color(.tertiarySystemBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(Color.secondary.opacity(0.10), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func compactName(_ name: String) -> String {
        let parts = name.split(separator: " ").map(String.init)
        guard let first = parts.first else { return name }
        if parts.count == 1 { return first }
        let lastInitial = parts.last.map { String($0.prefix(1)) } ?? ""
        return "\(first) \(lastInitial)."
    }
}

struct OfficeShiftEditorSheet: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let day: Date
    let shift: OfficeShiftKind
    let isAdmin: Bool

    @State private var selectedUserIds: Set<String> = []
    @State private var inlineError: String?

    private var eligibleUsers: [User] {
        appState.officeShiftEligibleUsers(isAdmin: isAdmin)
    }

    private var dayTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.timeZone = OfficeShiftCalendar.berlin.timeZone
        formatter.dateFormat = "EEEE, dd.MM.yyyy"
        return formatter.string(from: day)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Tag", value: dayTitle)
                    LabeledContent("Schicht", value: "\(shift.rawValue) · \(shift.hoursLabel)")
                    LabeledContent("Ort", value: OfficeShiftCalendar.locationName)
                }

                Section(header: Text("Eingetragen (\(selectedUserIds.count)/\(OfficeShiftCalendar.maxAssigneesPerSlot))")) {
                    if eligibleUsers.isEmpty {
                        Text("Keine berechtigten Mitarbeiter verfügbar.")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(eligibleUsers) { user in
                            let isSelected = selectedUserIds.contains(user.id)
                            Button {
                                toggleUser(user)
                            } label: {
                                HStack(spacing: 12) {
                                    Circle()
                                        .fill(user.color)
                                        .frame(width: 10, height: 10)

                                    Text(user.name)
                                        .foregroundColor(.primary)

                                    Spacer()

                                    if isSelected {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.tint)
                                    } else {
                                        Image(systemName: "circle")
                                            .foregroundColor(.secondary)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .disabled(!isSelected && selectedUserIds.count >= OfficeShiftCalendar.maxAssigneesPerSlot)
                        }
                    }

                    if let inlineError {
                        Text(inlineError)
                            .font(.footnote)
                            .foregroundColor(.red)
                    }
                }

                if isAdmin {
                    Section {
                        Button(role: .destructive) {
                            selectedUserIds = []
                            save()
                        } label: {
                            Text("Schicht leeren")
                        }
                    }
                }
            }
            .navigationTitle("Schicht planen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") { save() }
                }
            }
            .onAppear {
                selectedUserIds = Set(appState.officeShiftUsers(day: day, shift: shift).map(\.id))
            }
        }
    }

    private func toggleUser(_ user: User) {
        inlineError = nil
        if selectedUserIds.contains(user.id) {
            selectedUserIds.remove(user.id)
            return
        }
        guard selectedUserIds.count < OfficeShiftCalendar.maxAssigneesPerSlot else {
            inlineError = "Maximal \(OfficeShiftCalendar.maxAssigneesPerSlot) Mitarbeiter pro Schicht."
            return
        }
        selectedUserIds.insert(user.id)
    }

    private func save() {
        let ok = appState.setOfficeShiftUsers(
            day: day,
            shift: shift,
            userIds: Array(selectedUserIds)
        )
        if ok {
            dismiss()
        } else {
            inlineError = appState.uiErrorMessage
        }
    }
}
