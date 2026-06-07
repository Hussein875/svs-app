//
//  AdminWeeklyStatsView.swift
//  SVS App
//

import Combine
import Foundation
import SwiftUI

struct AdminWeeklyStatsScreen: View {
    @EnvironmentObject private var appState: AppState
    @StateObject private var viewModel = WeeklyStatsViewModel()

    private var accent: Color {
        appState.currentUser?.color ?? Color(red: 0.09, green: 0.40, blue: 0.75)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if !viewModel.lastFetchError.isEmpty {
                    errorBanner
                }

                if let latest = viewModel.latestWeek {
                    currentWeekCard(latest)
                }

                historySection
            }
            .padding(.horizontal, 18)
            .padding(.top, 14)
            .padding(.bottom, 28)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Wochenstatistik")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
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
        }
        .task {
            await viewModel.refresh(force: true)
        }
        .refreshable {
            await viewModel.refresh(force: true)
        }
    }

    private var errorBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(viewModel.lastFetchError)
                .font(.subheadline)
                .foregroundStyle(.primary)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.orange.opacity(0.12))
        )
    }

    private func currentWeekCard(_ week: WeeklyStatsRow) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Aktuelle KW")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    Text("KW \(week.calendarWeek)")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)

                    Text("Ab Nr. \(week.weekStartNumber)")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 4) {
                    Text("Gutachten")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .textCase(.uppercase)

                    Text("\(week.count)")
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .foregroundStyle(accent)
                }
            }

            HStack(spacing: 8) {
                Circle()
                    .fill(viewModel.lastFetchError.isEmpty ? .green : .red)
                    .frame(width: 8, height: 8)

                Text(viewModel.lastFetchText)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer(minLength: 0)

                if viewModel.isCurrentCalendarWeek(week) {
                    Text("Laufende Kalenderwoche")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(accent)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Capsule().fill(accent.opacity(0.12)))
                }
            }
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

    private var historySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Historie")
                .font(.headline)

            if viewModel.weeks.isEmpty, !viewModel.isLoading {
                Text("Noch keine Wochenwerte geladen.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                VStack(spacing: 0) {
                    HStack {
                        Text("KW")
                            .frame(width: 56, alignment: .leading)
                        Text("Ab Nr.")
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text("Anzahl")
                            .frame(width: 56, alignment: .trailing)
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color(.tertiarySystemBackground))

                    ForEach(viewModel.weeks) { week in
                        HStack {
                            Text("KW \(week.calendarWeek)")
                                .font(.subheadline.weight(week.id == viewModel.latestWeek?.id ? .semibold : .regular))
                                .frame(width: 56, alignment: .leading)

                            Text("\(week.weekStartNumber)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            Text("\(week.count)")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(week.id == viewModel.latestWeek?.id ? accent : .primary)
                                .frame(width: 56, alignment: .trailing)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 12)
                        .background(
                            week.id == viewModel.latestWeek?.id
                                ? accent.opacity(0.08)
                                : Color(.secondarySystemBackground)
                        )

                        if week.id != viewModel.weeks.last?.id {
                            Divider()
                                .padding(.leading, 14)
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
}

// MARK: - View model

private struct WeeklyStatsRow: Identifiable, Hashable {
    let calendarWeek: Int
    let weekStartNumber: Int
    let count: Int

    var id: Int { calendarWeek }
}

@MainActor
private final class WeeklyStatsViewModel: ObservableObject {
    @Published private(set) var weeks: [WeeklyStatsRow] = []
    @Published private(set) var latestWeek: WeeklyStatsRow?
    @Published private(set) var lastFetchAt: Date?
    @Published private(set) var nextFetchAt: Date?
    @Published private(set) var lastFetchError: String = ""
    @Published private(set) var isLoading: Bool = false

    private let fetchInterval: TimeInterval = 60
    private let fetchTimeout: TimeInterval = 25

    private var sheetURL: URL? {
        URL(
            string:
                "https://docs.google.com/spreadsheets/d/10mfm9SVVDiWcxnfK2QuUCj3msaVFBQIQx34NnPlUEo4/gviz/tq?tqx=out:json&gid=2065000943"
        )
    }

    var lastFetchText: String {
        guard let lastFetchAt else { return "Noch kein Abruf" }
        return "Stand \(WeeklyStatsFormatters.time.string(from: lastFetchAt))"
    }

    func isCurrentCalendarWeek(_ week: WeeklyStatsRow) -> Bool {
        week.calendarWeek == Calendar.current.component(.weekOfYear, from: Date())
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
            guard let sheetURL else {
                lastFetchError = "Tabellen-URL ist ungültig."
                return
            }

            var request = URLRequest(url: sheetURL)
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.timeoutInterval = fetchTimeout

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, 200..<300 ~= http.statusCode else {
                throw WeeklyStatsError.invalidResponse
            }

            let parsed = try WeeklyStatsParser.parseRows(from: data)
            weeks = parsed.sorted { $0.calendarWeek > $1.calendarWeek }
            latestWeek = weeks.max(by: { $0.calendarWeek < $1.calendarWeek })
            lastFetchAt = Date()
            lastFetchError = ""
        } catch {
            lastFetchError = WeeklyStatsError.message(for: error, timeout: fetchTimeout)
        }
    }
}

// MARK: - Parser

private enum WeeklyStatsParser {
    static func parseRows(from data: Data) throws -> [WeeklyStatsRow] {
        guard let text = String(data: data, encoding: .utf8) else {
            throw WeeklyStatsError.invalidEncoding
        }

        let start = text.firstIndex(of: "{")
        let end = text.lastIndex(of: "}")
        guard let start, let end, start <= end else {
            throw WeeklyStatsError.invalidPayload
        }

        let jsonText = String(text[start...end])
        let object = try JSONSerialization.jsonObject(with: Data(jsonText.utf8))
        guard
            let root = object as? [String: Any],
            let table = root["table"] as? [String: Any],
            let rows = table["rows"] as? [[String: Any]]
        else {
            throw WeeklyStatsError.invalidPayload
        }

        var results: [WeeklyStatsRow] = []

        for row in rows {
            let cells = row["c"] as? [Any] ?? []
            let kwText = cellString(at: 1, in: cells).trimmingCharacters(in: .whitespacesAndNewlines)
            let startText = cellString(at: 2, in: cells).trimmingCharacters(in: .whitespacesAndNewlines)
            let countText = cellString(at: 4, in: cells).trimmingCharacters(in: .whitespacesAndNewlines)

            if kwText.caseInsensitiveCompare("KW") == .orderedSame
                || kwText.caseInsensitiveCompare("Jahr") == .orderedSame
                || startText.caseInsensitiveCompare("Wochenstart") == .orderedSame {
                continue
            }

            guard let calendarWeek = parseInt(kwText, cell: cell(at: 1, in: cells)),
                  let weekStartNumber = parseInt(startText, cell: cell(at: 2, in: cells)),
                  let count = parseInt(countText, cell: cell(at: 4, in: cells)) else {
                continue
            }

            results.append(
                WeeklyStatsRow(
                    calendarWeek: calendarWeek,
                    weekStartNumber: weekStartNumber,
                    count: count
                )
            )
        }

        return results
    }

    private static func cell(at index: Int, in cells: [Any]) -> [String: Any]? {
        guard index < cells.count else { return nil }
        return cells[index] as? [String: Any]
    }

    private static func cellString(at index: Int, in cells: [Any]) -> String {
        guard let cell = cell(at: index, in: cells), let value = cell["v"] else { return "" }
        return String(describing: value)
    }

    private static func parseInt(_ text: String, cell: [String: Any]?) -> Int? {
        if let number = cell?["v"] as? NSNumber {
            return number.intValue
        }
        if let number = cell?["v"] as? Double {
            return Int(number)
        }
        return Int(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

private enum WeeklyStatsError: LocalizedError {
    case invalidEncoding
    case invalidPayload
    case invalidResponse

    static func message(for error: Error, timeout: TimeInterval) -> String {
        if let urlError = error as? URLError, urlError.code == .timedOut {
            return "Timeout nach \(Int(timeout))s"
        }

        if let statsError = error as? WeeklyStatsError {
            switch statsError {
            case .invalidEncoding:
                return "Antwort konnte nicht gelesen werden."
            case .invalidPayload:
                return "Wochenstatistik konnte nicht gelesen werden."
            case .invalidResponse:
                return "Serverantwort ist ungültig."
            }
        }

        return error.localizedDescription
    }
}

private enum WeeklyStatsFormatters {
    static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}

#Preview {
    NavigationStack {
        AdminWeeklyStatsScreen()
            .environmentObject(AppState())
    }
}
