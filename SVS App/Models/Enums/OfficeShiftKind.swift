//
//  OfficeShiftKind.swift
//  SVS App
//

import Foundation

enum OfficeShiftKind: String, Codable, CaseIterable, Identifiable {
    case early = "Früh"
    case late = "Spät"

    var id: String { rawValue }

    var storageKey: String {
        switch self {
        case .early: return "frueh"
        case .late: return "spaet"
        }
    }

    var hoursLabel: String {
        switch self {
        case .early: return "10–18 Uhr"
        case .late: return "12–20 Uhr"
        }
    }

    var shortHoursLabel: String {
        switch self {
        case .early: return "10–18"
        case .late: return "12–20"
        }
    }
}

enum OfficeShiftCalendar {
    static let locationName = "Bremen"
    static let maxAssigneesPerSlot = 2

    static var berlin: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.locale = Locale(identifier: "de_DE")
        cal.timeZone = TimeZone(identifier: "Europe/Berlin") ?? .current
        cal.firstWeekday = 2
        return cal
    }

    static func startOfDay(_ date: Date) -> Date {
        berlin.startOfDay(for: date)
    }

    static func mondayOfWeek(containing date: Date) -> Date {
        let cal = berlin
        let day = cal.startOfDay(for: date)
        let weekday = cal.component(.weekday, from: day)
        let daysFromMonday = (weekday - cal.firstWeekday + 7) % 7
        return cal.date(byAdding: .day, value: -daysFromMonday, to: day) ?? day
    }

    static func weekdaysInWeek(starting monday: Date) -> [Date] {
        let start = berlin.startOfDay(for: monday)
        return (0..<5).compactMap { berlin.date(byAdding: .day, value: $0, to: start) }
    }

    static func dayKey(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = berlin
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = berlin.timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: berlin.startOfDay(for: date))
    }

    static func documentId(day: Date, shift: OfficeShiftKind) -> String {
        "\(dayKey(for: day))_\(shift.storageKey)"
    }

    static func weekNumber(for monday: Date) -> Int {
        berlin.component(.weekOfYear, from: monday)
    }

    static func weekRangeLabel(monday: Date) -> String {
        let days = weekdaysInWeek(starting: monday)
        guard let first = days.first, let last = days.last else { return "" }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "de_DE")
        formatter.timeZone = berlin.timeZone
        formatter.dateFormat = "dd.MM."

        return "\(formatter.string(from: first)) – \(formatter.string(from: last))"
    }

    /// Alle Montage nach der Vorlagenwoche bis Jahresende (max. 52 Wochen).
    static func futureWeekMondays(afterTemplateMonday monday: Date) -> [Date] {
        let cal = berlin
        let templateMonday = cal.startOfDay(for: monday)
        guard var cursor = cal.date(byAdding: .day, value: 7, to: templateMonday) else { return [] }

        let year = cal.component(.year, from: Date())
        guard let periodEnd = cal.date(from: DateComponents(year: year, month: 12, day: 31)) else {
            return []
        }

        var result: [Date] = []
        while cursor <= periodEnd && result.count < 52 {
            result.append(cursor)
            guard let next = cal.date(byAdding: .day, value: 7, to: cursor) else { break }
            cursor = next
        }
        return result
    }
}

struct OfficeShiftSlot: Identifiable, Hashable {
    let dayKey: String
    let day: Date
    let shift: OfficeShiftKind
    var userIds: [String]
    var updatedAt: Date?
    var updatedByUid: String?

    var id: String {
        OfficeShiftCalendar.documentId(day: day, shift: shift)
    }
}
