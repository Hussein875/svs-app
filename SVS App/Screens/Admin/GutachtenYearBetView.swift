//
//  GutachtenYearBetView.swift
//  SVS App
//

import Charts
import SwiftUI

struct GutachtenYearBetView: View {
    @EnvironmentObject private var appState: AppState
    @ObservedObject var weeklyViewModel: WeeklyStatsViewModel
    @ObservedObject var betViewModel: GutachtenYearBetViewModel

    let accent: Color

    @State private var showEditor = false
    @State private var editingEntry: GutachtenYearBetEntry?

    private var projection: GutachtenYearProjection {
        GutachtenProjectionService.project(from: weeklyViewModel.weeks)
    }

    private var standings: [GutachtenBetStanding] {
        GutachtenProjectionService.standings(
            entries: betViewModel.entries,
            projection: projection
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if !weeklyViewModel.lastFetchError.isEmpty {
                    errorBanner(weeklyViewModel.lastFetchError)
                }

                if !betViewModel.errorMessage.isEmpty {
                    errorBanner(betViewModel.errorMessage)
                }

                if !betViewModel.infoMessage.isEmpty {
                    infoBanner(betViewModel.infoMessage)
                }

                projectionCard
                chartSection
                leaderboardSection
                adminSection
            }
            .padding(.horizontal, 18)
            .padding(.top, 4)
            .padding(.bottom, 28)
        }
        .refreshable {
            await weeklyViewModel.refresh(force: true)
        }
        .sheet(isPresented: $showEditor) {
            GutachtenYearBetEditorSheet(
                year: betViewModel.activeYear,
                entry: editingEntry,
                users: appState.users,
                accent: accent
            ) { entry in
                _Concurrency.Task {
                    try? await betViewModel.saveEntry(entry)
                }
            }
        }
    }

    private func infoBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
            Text(message)
                .font(.subheadline)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.green.opacity(0.12))
        )
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(message)
                .font(.subheadline)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.orange.opacity(0.12))
        )
    }

    private var projectionCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Jahreswette \(GutachtenYearBetFormatters.year(betViewModel.activeYear))")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    if let kw = projection.latestCalendarWeek {
                        Text("Stand KW \(kw)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
                Spacer(minLength: 8)
                trendBadge
            }

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                metricBlock(
                    title: "Aktuelle Gutachten-Nr.",
                    value: formatGutachtenNumber(projection.currentGutachtenNumber),
                    tint: accent
                )

                Image(systemName: "arrow.right")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 22)

                metricBlock(
                    title: "Prognose Jahresende",
                    value: formatGutachtenNumber(projection.projectedYearEndGutachtenNumber),
                    tint: .primary
                )
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                detailRow(
                    title: "Gutachten in \(GutachtenYearBetFormatters.year(betViewModel.activeYear))",
                    value: formatGutachtenNumber(projection.producedThisYear)
                )
                detailRow(
                    title: "Ø \(projection.completedWeeksSampled) Wochen (70/30)",
                    value: String(format: "%.1f / Woche", projection.averagePerWeek)
                )
                detailRow(
                    title: "Trend",
                    value: projection.trendDetailLabel,
                    icon: projection.trend.systemImage
                )
                detailRow(
                    title: "Noch",
                    value: "\(projection.weeksRemaining) Wochen · \(projection.daysRemaining) Tage"
                )
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Text(projection.methodSummary)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(accent.opacity(0.18), lineWidth: 1)
        )
    }

    private var trendBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: projection.trend.systemImage)
            Text(projection.trend.label)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(trendColor)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Capsule().fill(trendColor.opacity(0.12)))
    }

    private var trendColor: Color {
        switch projection.trend {
        case .growing: return .green
        case .shrinking: return .orange
        case .stable: return .secondary
        }
    }

    private func detailRow(title: String, value: String, icon: String? = nil) -> some View {
        HStack {
            Text(title)
            Spacer(minLength: 8)
            if let icon {
                Image(systemName: icon)
            }
            Text(value)
                .fontWeight(.medium)
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
        }
    }

    private func formatGutachtenNumber(_ value: Int) -> String {
        GutachtenYearBetFormatters.gutachtenNumber(value)
    }

    private func metricBlock(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
            Text(value)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var chartSection: some View {
        if standings.isEmpty {
            emptyHint("Noch keine Tipps hinterlegt — unten Mitarbeiter und Zahlen eintragen.")
        } else {
            VStack(alignment: .leading, spacing: 10) {
                Text("Tipps vs. Prognose")
                    .font(.headline)

                Chart {
                    RuleMark(x: .value("Prognose", projection.projectedYearEndGutachtenNumber))
                        .foregroundStyle(accent.opacity(0.7))
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [6, 4]))
                        .annotation(position: .top, alignment: .leading) {
                            Text("Prognose \(formatGutachtenNumber(projection.projectedYearEndGutachtenNumber))")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(accent)
                        }

                    ForEach(standings) { standing in
                        BarMark(
                            x: .value("Tipp", standing.entry.predictedTotal),
                            y: .value("Name", standing.entry.displayName)
                        )
                        .foregroundStyle(
                            standing.rank == 1
                                ? accent.gradient
                                : Color.secondary.opacity(0.55).gradient
                        )
                        .annotation(position: .trailing) {
                            Text(formatGutachtenNumber(standing.entry.predictedTotal))
                                .font(.caption2.weight(.medium))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .chartXAxis {
                    AxisMarks(position: .bottom)
                }
                .frame(height: max(180, CGFloat(standings.count) * 36))
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )
            }
        }
    }

    @ViewBuilder
    private var leaderboardSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Rangliste")
                .font(.headline)

            if standings.isEmpty {
                emptyHint("Sobald Tipps vorliegen, erscheint hier wer der Prognose am nächsten ist.")
            } else {
                VStack(spacing: 0) {
                    HStack {
                        Text("Platz")
                            .frame(width: 44, alignment: .leading)
                        Text("Mitarbeiter")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("Tipp")
                            .frame(width: 64, alignment: .trailing)
                        Text("Δ")
                            .frame(width: 44, alignment: .trailing)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color(.tertiarySystemBackground))

                    ForEach(standings) { standing in
                        HStack {
                            Text("\(standing.rank)")
                                .font(.subheadline.weight(standing.rank == 1 ? .bold : .regular))
                                .frame(width: 44, alignment: .leading)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(standing.entry.displayName)
                                    .font(.subheadline.weight(standing.rank == 1 ? .semibold : .regular))
                                if standing.rank == 1 {
                                    Text(String(format: "%.0f %% Führung", standing.winProbabilityPercent))
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(accent)
                                } else {
                                    Text(String(format: "%.0f %%", standing.winProbabilityPercent))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)

                            Text(formatGutachtenNumber(standing.entry.predictedTotal))
                                .font(.subheadline.weight(.semibold))
                                .frame(width: 64, alignment: .trailing)

                            Text("\(standing.distanceFromProjection)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(width: 44, alignment: .trailing)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(
                            standing.rank == 1
                                ? accent.opacity(0.08)
                                : Color(.secondarySystemBackground)
                        )

                        if standing.id != standings.last?.id {
                            Divider().padding(.leading, 14)
                        }
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
                )
            }
        }
    }

    private var adminSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if GutachtenYearBetConfig.canSelectMultipleYears {
                yearPickerSection
            }

            HStack {
                Text("Tipps verwalten")
                    .font(.headline)
                Spacer()
                Button {
                    editingEntry = nil
                    showEditor = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                }
                .accessibilityLabel("Tipp hinzufügen")
            }

            if betViewModel.entries.isEmpty {
                emptyHint("Noch keine Tipps — oben rechts + tippen zum Hinzufügen.")
            } else {
                List {
                    ForEach(betViewModel.entries) { entry in
                        Button {
                            editingEntry = entry
                            showEditor = true
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(entry.displayName)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(.primary)
                                    Text("Tipp: \(formatGutachtenNumber(entry.predictedTotal))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: "chevron.right")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                _Concurrency.Task {
                                    try? await betViewModel.deleteEntry(entry)
                                }
                            } label: {
                                Label("Löschen", systemImage: "trash")
                            }
                        }
                        .listRowInsets(EdgeInsets(top: 10, leading: 14, bottom: 10, trailing: 14))
                        .listRowSeparator(.hidden)
                        .listRowBackground(
                            Color(.secondarySystemBackground)
                        )
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .scrollDisabled(true)
                .frame(height: CGFloat(betViewModel.entries.count) * 58)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
                )
            }
        }
    }

    private var yearPickerSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Wette-Jahr")
                .font(.headline)
            HStack {
                Button {
                    _Concurrency.Task {
                        await betViewModel.updateActiveYear(betViewModel.activeYear - 1)
                    }
                } label: {
                    Image(systemName: "minus.circle.fill")
                }
                .disabled(
                    betViewModel.isSavingYear
                        || betViewModel.activeYear <= GutachtenYearBetConfig.minimumSelectableYear
                )

                Text(GutachtenYearBetFormatters.year(betViewModel.activeYear))
                    .font(.title2.weight(.bold))
                    .frame(minWidth: 64)

                Button {
                    _Concurrency.Task {
                        await betViewModel.updateActiveYear(betViewModel.activeYear + 1)
                    }
                } label: {
                    Image(systemName: "plus.circle.fill")
                }
                .disabled(
                    betViewModel.isSavingYear
                        || betViewModel.activeYear >= GutachtenYearBetConfig.maximumSelectableYear
                )

                Spacer()

                if betViewModel.isSavingYear {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private func emptyHint(_ text: String) -> some View {
        Text(text)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.vertical, 8)
    }
}

private struct GutachtenYearBetEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let year: Int
    let entry: GutachtenYearBetEntry?
    let users: [User]
    let accent: Color
    let onSave: (GutachtenYearBetEntry) -> Void

    @State private var displayName: String = ""
    @State private var predictedTotalText: String = ""
    @State private var selectedUserId: String?

    private var predictedTotal: Int? {
        Int(predictedTotalText.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Mitarbeiter") {
                    if users.isEmpty {
                        TextField("Name", text: $displayName)
                            .textInputAutocapitalization(.words)
                    } else {
                        Picker("Aus Team", selection: $selectedUserId) {
                            Text("Manuell eingeben").tag(Optional<String>.none)
                            ForEach(users.sorted { $0.name < $1.name }) { user in
                                Text(user.name).tag(Optional(user.id))
                            }
                        }
                        .onChange(of: selectedUserId) { _, newValue in
                            if let id = newValue,
                               let user = users.first(where: { $0.id == id }) {
                                displayName = user.name
                            }
                        }

                        if selectedUserId == nil {
                            TextField("Name", text: $displayName)
                                .textInputAutocapitalization(.words)
                        } else {
                            Text(displayName)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Jahreswette \(GutachtenYearBetFormatters.year(year))") {
                    TextField("Gutachten bis Jahresende", text: $predictedTotalText)
                        .keyboardType(.numberPad)
                }
            }
            .navigationTitle(entry == nil ? "Tipp hinzufügen" : "Tipp bearbeiten")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Abbrechen") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Speichern") {
                        guard let total = predictedTotal, !displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                            return
                        }
                        let saved = GutachtenYearBetEntry(
                            id: entry?.id ?? UUID().uuidString,
                            displayName: displayName.trimmingCharacters(in: .whitespacesAndNewlines),
                            predictedTotal: total,
                            userId: selectedUserId ?? entry?.userId
                        )
                        onSave(saved)
                        dismiss()
                    }
                    .disabled(predictedTotal == nil || displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear {
                if let entry {
                    displayName = entry.displayName
                    predictedTotalText = "\(entry.predictedTotal)"
                    selectedUserId = entry.userId
                }
            }
        }
        .tint(accent)
    }
}

#Preview {
    GutachtenYearBetView(
        weeklyViewModel: WeeklyStatsViewModel(),
        betViewModel: GutachtenYearBetViewModel(),
        accent: .blue
    )
    .environmentObject(AppState())
}
