//
//  DashboardView.swift
//  SVS App
//
//  Created by Hussein Souleiman on 23.12.25.
//

import Combine
import Foundation
import SwiftUI

struct DashboardView: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = DashboardViewModel()
    @State private var now = Date()

    private let secondTimer = Timer.publish(
        every: 1,
        on: .main,
        in: .common
    ).autoconnect()

    private var accent: Color {
        appState.currentUser?.color ?? Color(red: 0.09, green: 0.40, blue: 0.75)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                heroSection
                legendSection

                if !viewModel.lastFetchError.isEmpty {
                    errorBanner
                }

                boardSection
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 28)
        }
        .background(
            LinearGradient(
                colors: [
                    Color(.systemGroupedBackground),
                    Color(.secondarySystemBackground)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .navigationTitle("Dashboard")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(content: {
            ToolbarItem(placement: .topBarTrailing) {
                if viewModel.isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Button {
                        _Concurrency.Task { await viewModel.refresh(force: true) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        })
        .task {
            await viewModel.refresh(force: true)
        }
        .refreshable {
            await viewModel.refresh(force: true)
        }
        .onReceive(secondTimer) { date in
            now = date
            guard viewModel.shouldAutoRefresh(at: date) else { return }
            _Concurrency.Task { await viewModel.refresh() }
        }
    }

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Dashboard")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(.primary)
                }

                Spacer(minLength: 12)

                HStack(spacing: 8) {
                    Circle()
                        .fill(viewModel.lastFetchError.isEmpty ? accent : .red)
                        .frame(width: 10, height: 10)
                    Text(viewModel.lastFetchError.isEmpty ? "Live" : "Fehler")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(viewModel.lastFetchError.isEmpty ? accent : .red)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(
                    Capsule(style: .continuous)
                        .fill(Color.white.opacity(0.86))
                )
            }

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "number.circle.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)

                    Text("Aktuelle Nummer: \(viewModel.nextNumberText)")
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    accent,
                                    accent.opacity(0.72)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                )

                HStack(spacing: 12) {
                    metricCard(
                        title: "Offene Akten",
                        value: "\(viewModel.openCount)",
                        subtitle: viewModel.loadStateTitle,
                        tint: viewModel.loadStateColor
                    )

                    metricCard(
                        title: "Refresh",
                        value: viewModel.countdownText(now: now),
                        subtitle: viewModel.lastFetchText,
                        tint: accent
                    )
                }
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(accent.opacity(0.16), lineWidth: 1)
        )
    }

    private func metricCard(
        title: String,
        value: String,
        subtitle: String,
        tint: Color
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.caption2.weight(.bold))
                .foregroundStyle(.secondary)

            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.systemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(tint.opacity(0.20), lineWidth: 1)
        )
    }

    private var legendSection: some View {
        HStack(spacing: 10) {
            legendChip(title: "Unvollständig", color: DashboardCaseStatus.incomplete.color)
            legendChip(title: "Zu prüfen", color: DashboardCaseStatus.review.color)
            legendChip(title: "Geprüft", color: DashboardCaseStatus.checked.color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func legendChip(title: String, color: Color) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(color)
                .frame(width: 10, height: 10)

            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            Capsule(style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var errorBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.white)
                .padding(8)
                .background(Circle().fill(Color.red))

            VStack(alignment: .leading, spacing: 4) {
                Text("Letzter Abruf fehlgeschlagen")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(viewModel.lastFetchError)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.red.opacity(0.24), lineWidth: 1)
        )
    }

    private var boardSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Board")
                    .font(.headline.weight(.bold))
                Spacer()
                Text("\(viewModel.totalVisibleCards) Karten")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            if viewModel.isLoading && viewModel.totalVisibleCards == 0 {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Dashboard wird geladen…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
                .background(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(Color(.secondarySystemBackground))
                )
            } else {
                ScrollView(.horizontal, showsIndicators: true) {
                    HStack(alignment: .top, spacing: 14) {
                        ForEach(viewModel.columns) { column in
                            DashboardColumnCard(column: column)
                        }
                    }
                    .padding(.vertical, 2)
                    .padding(.trailing, 18)
                }
                .frame(maxWidth: .infinity, minHeight: 220, alignment: .leading)
                .contentShape(Rectangle())
            }
        }
    }
}

private struct DashboardColumnCard: View {
    let column: DashboardKanbanColumn

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(column.title)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.primary)

                Spacer(minLength: 8)

                Text("\(column.items.count)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color(.systemBackground))
                    )
            }

            if column.items.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "tray")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Text("Keine Akten")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
            } else {
                VStack(spacing: 10) {
                    ForEach(column.items) { item in
                        DashboardCaseCard(item: item)
                    }
                }
            }
        }
        .padding(14)
        .frame(width: 220, alignment: .topLeading)
        .frame(minHeight: 460, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(column.tint.opacity(0.16), lineWidth: 1)
        )
    }
}

private struct DashboardCaseCard: View {
    let item: DashboardCaseItem

    private var foregroundColor: Color {
        item.status == .neutral ? .primary : .white
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.number)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(foregroundColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(item.backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(item.borderColor, lineWidth: item.externalBadge == nil ? 0 : 1.2)
            )

            if let badge = item.externalBadge {
                Text(badge.label)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(
                        Capsule(style: .continuous)
                            .fill(badge.color)
                    )
                    .padding(8)
            }
        }
    }
}

@MainActor
private final class DashboardViewModel: ObservableObject {
    @Published private(set) var columns: [DashboardKanbanColumn] =
        DashboardColumnType.allCases.map { DashboardKanbanColumn(type: $0, items: []) }
    @Published private(set) var openCount: Int = 0
    @Published private(set) var nextNumber: Int? = nil
    @Published private(set) var lastFetchAt: Date? = nil
    @Published private(set) var nextFetchAt: Date? = nil
    @Published private(set) var lastFetchError: String = ""
    @Published private(set) var isLoading: Bool = false

    private let fetchInterval: TimeInterval = 60
    private let fetchTimeout: TimeInterval = 25
    private let sheetURL = URL(
        string: "https://docs.google.com/spreadsheets/d/10mfm9SVVDiWcxnfK2QuUCj3msaVFBQIQx34NnPlUEo4/gviz/tq?tqx=out:json"
    )!

    var nextNumberText: String {
        nextNumber.map(String.init) ?? "–"
    }

    var lastFetchText: String {
        guard let lastFetchAt else { return "Noch kein Abruf" }
        return "Stand \(DashboardFormatters.time.string(from: lastFetchAt))"
    }

    var totalVisibleCards: Int {
        columns.reduce(0) { $0 + $1.items.count }
    }

    var loadStateTitle: String {
        switch openCount {
        case 30...:
            return "Brennt"
        case 20...:
            return "Kritisch"
        case 10...:
            return "Aufmerksam"
        default:
            return "Stabil"
        }
    }

    var loadStateColor: Color {
        switch openCount {
        case 30...:
            return Color(red: 0.69, green: 0.00, blue: 0.13)
        case 20...:
            return Color(red: 0.98, green: 0.55, blue: 0.00)
        case 10...:
            return Color(red: 0.96, green: 0.71, blue: 0.00)
        default:
            return Color(red: 0.12, green: 0.56, blue: 0.24)
        }
    }

    func countdownText(now: Date) -> String {
        guard let nextFetchAt else { return "lädt…" }
        let remaining = max(0, Int(nextFetchAt.timeIntervalSince(now)))
        let minutes = remaining / 60
        let seconds = remaining % 60
        return "\(minutes)m \(seconds)s"
    }

    func shouldAutoRefresh(at date: Date) -> Bool {
        guard !isLoading else { return false }
        guard let nextFetchAt else { return lastFetchAt == nil }
        return date >= nextFetchAt
    }

    func refresh(force: Bool = false) async {
        if isLoading { return }
        if !force, let nextFetchAt, Date() < nextFetchAt { return }

        isLoading = true
        defer {
            isLoading = false
            nextFetchAt = Date().addingTimeInterval(fetchInterval)
        }

        do {
            var request = URLRequest(url: sheetURL)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = fetchTimeout

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
                throw DashboardError.invalidResponse
            }

            let rows = try DashboardParser.parseRows(from: data)
            apply(rows: rows)
            lastFetchAt = Date()
            lastFetchError = ""
        } catch {
            lastFetchError = DashboardError.message(for: error, timeout: fetchTimeout)
        }
    }

    private func apply(rows: [DashboardSheetRow]) {
        let cleanedRows = rows.filter { !$0.status.hasPrefix("versendet") }
        openCount = cleanedRows.count

        let numbers = cleanedRows.compactMap(\.sortNumber)
        nextNumber = numbers.max().map { $0 + 1 }

        var bucketed = Dictionary(
            uniqueKeysWithValues: DashboardColumnType.allCases.map { ($0, [DashboardCaseItem]()) }
        )

        for row in cleanedRows {
            let item = DashboardCaseItem(
                number: row.entry,
                status: DashboardCaseStatus(rawStatus: row.status),
                worker: row.worker,
                externalBadge: DashboardExternalBadge.resolve(from: row.worker)
            )

            if DashboardCaseStatus.isChecked(rawStatus: row.status) {
                bucketed[.checked, default: []].append(item)
            } else if row.status == "vollständig" {
                bucketed[.osama, default: []].append(item)
            } else if let column = DashboardColumnType.resolveWorkerColumn(for: row.worker) {
                bucketed[column, default: []].append(item)
            } else {
                bucketed[.eingang, default: []].append(item)
            }
        }

        columns = DashboardColumnType.allCases.map { type in
            let sorted = (bucketed[type] ?? []).sorted { lhs, rhs in
                lhs.sortNumber < rhs.sortNumber
            }
            return DashboardKanbanColumn(type: type, items: sorted)
        }
    }
}

private enum DashboardColumnType: String, CaseIterable, Identifiable {
    case eingang = "Eingang"
    case hadi = "Hadi"
    case ramazan = "Ramazan"
    case robar = "Robar"
    case osama = "Osama"
    case checked = "Geprüft"

    var id: String { rawValue }

    var tint: Color {
        switch self {
        case .eingang:
            return Color(red: 0.36, green: 0.43, blue: 0.52)
        case .hadi:
            return Color(red: 0.33, green: 0.47, blue: 0.84)
        case .ramazan:
            return Color(red: 0.64, green: 0.35, blue: 0.81)
        case .robar:
            return Color(red: 0.08, green: 0.56, blue: 0.49)
        case .osama:
            return Color(red: 0.96, green: 0.45, blue: 0.00)
        case .checked:
            return Color(red: 0.10, green: 0.68, blue: 0.22)
        }
    }

    static func resolveWorkerColumn(for rawWorker: String) -> DashboardColumnType? {
        let normalized = DashboardParser.normalizeWorkerName(rawWorker)
        guard !normalized.isEmpty else { return nil }

        let aliases: [String: DashboardColumnType] = [
            "hadi": .hadi,
            "hadi issa": .hadi,
            "ramazan": .ramazan,
            "ramazan dag": .ramazan,
            "robar": .robar,
            "robar kassem": .robar,
            "osama": .osama,
            "osama sleiman": .osama,
            "osama souleiman": .osama,
        ]

        if let direct = aliases[normalized] {
            return direct
        }

        let firstName = normalized.split(separator: " ").first.map(String.init) ?? ""
        return aliases[firstName]
    }
}

private struct DashboardKanbanColumn: Identifiable {
    let type: DashboardColumnType
    let items: [DashboardCaseItem]

    var id: String { type.id }
    var title: String { type.rawValue }
    var tint: Color { type.tint }
}

private struct DashboardCaseItem: Identifiable {
    let id: String
    let number: String
    let status: DashboardCaseStatus
    let worker: String
    let externalBadge: DashboardExternalBadge?

    init(
        number: String,
        status: DashboardCaseStatus,
        worker: String,
        externalBadge: DashboardExternalBadge?
    ) {
        self.id = "\(number)|\(status.label)|\(worker)"
        self.number = number
        self.status = status
        self.worker = worker
        self.externalBadge = externalBadge
    }

    var sortNumber: Int {
        Int(number.replacingOccurrences(
            of: ".*?(\\d+).*",
            with: "$1",
            options: .regularExpression
        )) ?? 0
    }

    var backgroundColor: Color {
        switch status {
        case .checked:
            return status.color
        case .incomplete:
            return status.color
        case .review:
            return status.color
        case .neutral:
            return Color(.systemBackground)
        }
    }

    var borderColor: Color {
        externalBadge?.color.opacity(0.75) ?? Color.secondary.opacity(0.10)
    }
}

private enum DashboardCaseStatus {
    case incomplete
    case review
    case checked
    case neutral

    init(rawStatus: String) {
        if Self.isChecked(rawStatus: rawStatus) {
            self = .checked
        } else if rawStatus.contains("unvollständig") {
            self = .incomplete
        } else if rawStatus.contains("vollständig") {
            self = .review
        } else {
            self = .neutral
        }
    }

    static func isChecked(rawStatus: String) -> Bool {
        rawStatus.range(
            of: #"^geprüft\s*(o|1|2|hj|hk)$"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    var label: String {
        switch self {
        case .incomplete:
            return "Unvollständig"
        case .review:
            return "Zu prüfen"
        case .checked:
            return "Geprüft"
        case .neutral:
            return "Offen"
        }
    }

    var color: Color {
        switch self {
        case .incomplete:
            return Color(red: 0.89, green: 0.07, blue: 0.07)
        case .review:
            return Color(red: 1.00, green: 0.45, blue: 0.00)
        case .checked:
            return Color(red: 0.07, green: 0.89, blue: 0.22)
        case .neutral:
            return Color(red: 0.91, green: 0.93, blue: 0.95)
        }
    }
}

private struct DashboardExternalBadge {
    let label: String
    let color: Color

    static func resolve(from rawWorker: String) -> DashboardExternalBadge? {
        let normalized = DashboardParser.normalizeWorkerName(rawWorker)
        guard !normalized.isEmpty else { return nil }

        let aliases: [String: DashboardExternalBadge] = [
            "h": DashboardExternalBadge(label: "H", color: Color(red: 0.42, green: 0.11, blue: 0.60)),
            "hj": DashboardExternalBadge(label: "H", color: Color(red: 0.42, green: 0.11, blue: 0.60)),
            "hussein jaber": DashboardExternalBadge(label: "H", color: Color(red: 0.42, green: 0.11, blue: 0.60)),
            "b": DashboardExternalBadge(label: "B", color: Color(red: 0.05, green: 0.28, blue: 0.63)),
            "hussein selman": DashboardExternalBadge(label: "B", color: Color(red: 0.05, green: 0.28, blue: 0.63)),
            "hu": DashboardExternalBadge(label: "HU", color: Color.black),
            "hussein souleiman": DashboardExternalBadge(label: "HU", color: Color.black),
        ]

        if let direct = aliases[normalized] {
            return direct
        }

        if normalized.contains("hussein") {
            if normalized.range(of: #"\bselman\b"#, options: .regularExpression) != nil {
                return aliases["b"]
            }
            if normalized.range(of: #"\b(souleiman|suleiman|sleiman)\b"#, options: .regularExpression) != nil {
                return aliases["hu"]
            }
            if normalized.range(of: #"\bjaber\b"#, options: .regularExpression) != nil {
                return aliases["h"]
            }
        }

        let firstName = normalized.split(separator: " ").first.map(String.init) ?? ""
        return aliases[firstName]
    }
}

private struct DashboardSheetRow {
    let entry: String
    let worker: String
    let status: String

    var sortNumber: Int? {
        let match = entry.range(of: #"\d+"#, options: .regularExpression)
        guard let match else { return nil }
        return Int(entry[match])
    }
}

private enum DashboardParser {
    static func parseRows(from data: Data) throws -> [DashboardSheetRow] {
        guard let text = String(data: data, encoding: .utf8) else {
            throw DashboardError.invalidEncoding
        }

        let start = text.firstIndex(of: "{")
        let end = text.lastIndex(of: "}")
        guard let start, let end, start <= end else {
            throw DashboardError.invalidPayload
        }

        let jsonText = String(text[start...end])
        let object = try JSONSerialization.jsonObject(with: Data(jsonText.utf8))
        guard
            let root = object as? [String: Any],
            let table = root["table"] as? [String: Any],
            let rows = table["rows"] as? [[String: Any]]
        else {
            throw DashboardError.invalidPayload
        }

        return rows.compactMap { row in
            let cells = row["c"] as? [Any] ?? []
            let entry = extractAktenzeichen(cellValue(at: 0, in: cells))
            let worker = cellValue(at: 1, in: cells).trimmingCharacters(in: .whitespacesAndNewlines)
            let status = cellValue(at: 2, in: cells)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()

            guard !entry.isEmpty, entry.lowercased() != "eingang" else {
                return nil
            }

            return DashboardSheetRow(entry: entry, worker: worker, status: status)
        }
    }

    static func normalizeWorkerName(_ rawValue: String) -> String {
        rawValue
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: #"^herr\s+"#, with: "", options: [.regularExpression, .caseInsensitive])
            .replacingOccurrences(of: #"^frau\s+"#, with: "", options: [.regularExpression, .caseInsensitive])
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    private static func cellValue(at index: Int, in cells: [Any]) -> String {
        guard index < cells.count else { return "" }
        guard let cell = cells[index] as? [String: Any] else { return "" }
        guard let value = cell["v"] else { return "" }
        return String(describing: value)
    }

    private static func extractAktenzeichen(_ text: String) -> String {
        let pattern = #"^(RB|KVA)?\s*\d+"#
        guard let range = text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return text[range]
            .uppercased()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }
}

private enum DashboardError: LocalizedError {
    case invalidEncoding
    case invalidPayload
    case invalidResponse

    static func message(for error: Error, timeout: TimeInterval) -> String {
        if let urlError = error as? URLError, urlError.code == .timedOut {
            return "Timeout nach \(Int(timeout))s"
        }

        if let dashboardError = error as? DashboardError {
            switch dashboardError {
            case .invalidEncoding:
                return "Antwort konnte nicht gelesen werden."
            case .invalidPayload:
                return "Dashboard-Daten konnten nicht geparst werden."
            case .invalidResponse:
                return "Serverantwort ist ungültig."
            }
        }

        return error.localizedDescription
    }
}

private enum DashboardFormatters {
    static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

#Preview {
    NavigationStack {
        DashboardView()
            .environmentObject(AppState())
    }
}

struct InitialsAvatarView: View {
    let name: String
    let color: Color

    private var initials: String {
        let components = name
            .split(separator: " ")
            .compactMap { $0.first.map(String.init) }
        let joined = components.prefix(2).joined()
        return joined.isEmpty ? "?" : joined.uppercased()
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.2))
            Text(initials)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(color)
        }
        .frame(width: 32, height: 32)
    }
}
