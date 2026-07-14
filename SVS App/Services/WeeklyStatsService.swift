//
//  WeeklyStatsService.swift
//  SVS App
//

import Combine
import Foundation

struct WeeklyStatsRow: Identifiable, Hashable {
    let calendarWeek: Int
    let weekStartNumber: Int
    let count: Int

    var id: Int { calendarWeek }
}

@MainActor
final class WeeklyStatsViewModel: ObservableObject {
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
            guard !WeeklyStatsError.isIgnorableCancellation(error) else { return }
            lastFetchError = WeeklyStatsError.message(for: error, timeout: fetchTimeout)
        }
    }
}

enum WeeklyStatsParser {
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

enum WeeklyStatsError: LocalizedError {
    case invalidEncoding
    case invalidPayload
    case invalidResponse

    static func message(for error: Error, timeout: TimeInterval) -> String {
        if isIgnorableCancellation(error) {
            return ""
        }

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

    static func isIgnorableCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if _Concurrency.Task.isCancelled { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }

        let nsError = error as NSError
        return nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled
    }
}

enum WeeklyStatsFormatters {
    static let time: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.dateFormat = "HH:mm:ss"
        return formatter
    }()
}
