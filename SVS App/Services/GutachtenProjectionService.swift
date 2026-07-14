//
//  GutachtenProjectionService.swift
//  SVS App
//

import Foundation

enum GutachtenProjectionTrend: String, Hashable {
    case growing
    case shrinking
    case stable

    var label: String {
        switch self {
        case .growing: return "steigend"
        case .shrinking: return "rückläufig"
        case .stable: return "stabil"
        }
    }

    var systemImage: String {
        switch self {
        case .growing: return "arrow.up.right"
        case .shrinking: return "arrow.down.right"
        case .stable: return "arrow.right"
        }
    }
}

enum GutachtenProjectionService {
    private static let yearWeeklyBlendWeight = 0.70
    private static let recentWeeklyBlendWeight = 0.30
    private static let recentWeeksSampleSize = 8
    private static let minVolatility = 0.05
    private static let maxVolatility = 0.10

    private static var calendar: Calendar {
        var cal = Calendar(identifier: .iso8601)
        cal.locale = Locale(identifier: "de_DE")
        cal.firstWeekday = 2
        return cal
    }

    /// Letzte bekannte Gutachten-Nummer (aus neuester Kalenderwoche).
    static func currentGutachtenNumber(from weeks: [WeeklyStatsRow]) -> Int? {
        guard let latest = weeks.max(by: { $0.calendarWeek < $1.calendarWeek }) else {
            return nil
        }
        if latest.count <= 0 {
            return max(0, latest.weekStartNumber - 1)
        }
        return latest.weekStartNumber + latest.count - 1
    }

    static func project(
        from weeks: [WeeklyStatsRow],
        at date: Date = Date()
    ) -> GutachtenYearProjection {
        let year = calendar.component(.yearForWeekOfYear, from: date)
        let weekOfYear = calendar.component(.weekOfYear, from: date)
        let dayOfYear = calendar.ordinality(of: .day, in: .year, for: date) ?? 1
        let daysInYear = calendar.range(of: .day, in: .year, for: date)?.count ?? 365
        let daysRemaining = max(0, daysInYear - dayOfYear)
        let weeksRemaining = max(0, 52 - weekOfYear)

        let sortedAsc = weeks.sorted { $0.calendarWeek < $1.calendarWeek }
        let sortedDesc = weeks.sorted { $0.calendarWeek > $1.calendarWeek }
        let latestWeek = sortedDesc.first
        let completedDesc = completedWeeksDescending(from: weeks, at: date)

        let currentNumber = currentGutachtenNumber(from: weeks) ?? 0
        let yearStartNumber = sortedAsc.first?.weekStartNumber ?? currentNumber
        let progressFromYearStart = max(0, currentNumber - yearStartNumber)

        // Jahres-Ø: einfacher Mittelwert aller abgeschlossenen Wochen (ohne Gewichtung).
        let recentSample = Array(completedDesc.prefix(recentWeeksSampleSize))
        let yearToDateWeeklyAverage = simpleWeeklyAverage(from: completedDesc)
        let recentWeightedWeeklyAverage = exponentialWeightedWeeklyAverage(from: recentSample)

        // Prognose-Tempo: 70 % Jahres-Ø + 30 % gewichtete letzte Wochen (Wachstum).
        let blendedWeeklyPace =
            yearWeeklyBlendWeight * yearToDateWeeklyAverage
            + recentWeeklyBlendWeight * recentWeightedWeeklyAverage

        let trendRatio = weeklyTrend(from: completedDesc)
        let (recentFourWeekAverage, priorFourWeekAverage) = weeklyTrendAverages(from: completedDesc)
        let trend = trendDirection(for: trendRatio)
        let trendSwingFactor = trendSwingFactor(for: trendRatio, trend: trend)
        let adjustedWeeklyPace = blendedWeeklyPace * trendSwingFactor

        let remainingProduction = adjustedWeeklyPace * Double(weeksRemaining)
        let baseRemainingProduction = blendedWeeklyPace * Double(weeksRemaining)
        let projectedYearEnd = max(currentNumber, currentNumber + Int(remainingProduction.rounded()))
        let projectedYearEndLow = max(
            currentNumber,
            currentNumber + Int((baseRemainingProduction * (1 - maxVolatility)).rounded())
        )
        let projectedYearEndHigh = max(
            currentNumber,
            currentNumber + Int((baseRemainingProduction * (1 + maxVolatility)).rounded())
        )

        let methodSummary = projectionMethodSummary(
            completedWeeks: completedDesc.count,
            recentWeeks: recentSample.count,
            trend: trend,
            trendSwingPercent: Int((abs(trendSwingFactor - 1) * 100).rounded())
        )

        return GutachtenYearProjection(
            year: year,
            currentGutachtenNumber: currentNumber,
            projectedYearEndGutachtenNumber: projectedYearEnd,
            projectedYearEndLow: projectedYearEndLow,
            projectedYearEndHigh: projectedYearEndHigh,
            yearStartNumber: yearStartNumber,
            producedThisYear: progressFromYearStart,
            yearToDateWeeklyAverage: yearToDateWeeklyAverage,
            recentWeightedWeeklyAverage: recentWeightedWeeklyAverage,
            blendedWeeklyPace: blendedWeeklyPace,
            adjustedWeeklyPace: adjustedWeeklyPace,
            yearBlendWeight: yearWeeklyBlendWeight,
            recentBlendWeight: recentWeeklyBlendWeight,
            trendSwingFactor: trendSwingFactor,
            trend: trend,
            trendRatio: trendRatio,
            recentFourWeekAverage: recentFourWeekAverage,
            priorFourWeekAverage: priorFourWeekAverage,
            weeksElapsed: weekOfYear,
            weeksRemaining: weeksRemaining,
            daysRemaining: daysRemaining,
            completedWeeksSampled: completedDesc.count,
            recentWeeksSampled: recentSample.count,
            latestCalendarWeek: latestWeek?.calendarWeek,
            methodSummary: methodSummary
        )
    }

    static func standings(
        entries: [GutachtenYearBetEntry],
        projection: GutachtenYearProjection
    ) -> [GutachtenBetStanding] {
        guard !entries.isEmpty else { return [] }

        let target = projection.projectedYearEndGutachtenNumber
        let ranked = entries
            .map { entry -> (GutachtenYearBetEntry, Int) in
                (entry, abs(entry.predictedTotal - target))
            }
            .sorted { lhs, rhs in
                if lhs.1 != rhs.1 { return lhs.1 < rhs.1 }
                return lhs.0.displayName.localizedCaseInsensitiveCompare(rhs.0.displayName) == .orderedAscending
            }

        let weights: [Double] = ranked.map { _, distance in
            1.0 / (Double(distance) + 1.0)
        }
        let weightSum = weights.reduce(0, +)

        return ranked.enumerated().map { index, item in
            let probability = weightSum > 0 ? (weights[index] / weightSum) * 100 : 0
            return GutachtenBetStanding(
                entry: item.0,
                distanceFromProjection: item.1,
                rank: index + 1,
                winProbabilityPercent: probability
            )
        }
    }

    // MARK: - Private

    /// Abgeschlossene Kalenderwochen, neueste zuerst — die laufende KW wird ausgeschlossen.
    private static func completedWeeksDescending(
        from weeks: [WeeklyStatsRow],
        at date: Date
    ) -> [WeeklyStatsRow] {
        let currentCalendarWeek = calendar.component(.weekOfYear, from: date)
        return weeks
            .sorted { $0.calendarWeek > $1.calendarWeek }
            .filter { $0.calendarWeek != currentCalendarWeek }
    }

    private static func simpleWeeklyAverage(from weeks: [WeeklyStatsRow]) -> Double {
        guard !weeks.isEmpty else { return 0 }
        let total = weeks.map(\.count).reduce(0, +)
        return Double(total) / Double(weeks.count)
    }

    private static func exponentialWeightedWeeklyAverage(from weeks: [WeeklyStatsRow]) -> Double {
        guard !weeks.isEmpty else { return 0 }
        let decay = 0.82
        var weightSum = 0.0
        var valueSum = 0.0

        for (index, week) in weeks.enumerated() {
            let weight = pow(decay, Double(index))
            weightSum += weight
            valueSum += Double(week.count) * weight
        }

        return weightSum > 0 ? valueSum / weightSum : 0
    }

    /// Verhältnis Ø der 4 neuesten abgeschlossenen Wochen zu den 4 davor.
    private static func weeklyTrend(from completedWeeksDescending: [WeeklyStatsRow]) -> Double {
        let (recent, prior) = weeklyTrendAverages(from: completedWeeksDescending)
        guard prior > 0 else { return 1 }
        return recent / prior
    }

    private static func weeklyTrendAverages(
        from completedWeeksDescending: [WeeklyStatsRow]
    ) -> (recent: Double, prior: Double) {
        let recentWeeks = Array(completedWeeksDescending.prefix(4))
        let priorWeeks = Array(completedWeeksDescending.dropFirst(4).prefix(4))
        let recent = recentWeeks.isEmpty
            ? 0
            : Double(recentWeeks.map(\.count).reduce(0, +)) / Double(recentWeeks.count)
        let prior = priorWeeks.isEmpty
            ? 0
            : Double(priorWeeks.map(\.count).reduce(0, +)) / Double(priorWeeks.count)
        return (recent, prior)
    }

    private static func trendDirection(for ratio: Double) -> GutachtenProjectionTrend {
        if ratio > 1.04 { return .growing }
        if ratio < 0.96 { return .shrinking }
        return .stable
    }

    /// Trend-Richtung in eine Schwankung von 5–10 % übersetzen.
    private static func trendSwingFactor(
        for ratio: Double,
        trend: GutachtenProjectionTrend
    ) -> Double {
        switch trend {
        case .stable:
            return 1.0
        case .growing:
            let strength = min(max(ratio - 1, minVolatility), maxVolatility)
            return 1.0 + strength
        case .shrinking:
            let strength = min(max(1 - ratio, minVolatility), maxVolatility)
            return 1.0 - strength
        }
    }

    private static func projectionMethodSummary(
        completedWeeks: Int,
        recentWeeks: Int,
        trend: GutachtenProjectionTrend,
        trendSwingPercent: Int
    ) -> String {
        let yearPercent = Int((yearWeeklyBlendWeight * 100).rounded())
        let recentPercent = Int((recentWeeklyBlendWeight * 100).rounded())
        let swingText: String
        switch trend {
        case .stable:
            swingText = "Band ±5–10 % um das Tempo"
        case .growing:
            swingText = "+\(max(trendSwingPercent, 5)) % Anpassung (Trend \(trend.label)), Band ±5–10 %"
        case .shrinking:
            swingText = "−\(max(trendSwingPercent, 5)) % Anpassung (Trend \(trend.label)), Band ±5–10 %"
        }
        return "Prognose = aktuelle Nr. + Restwochen × (\(yearPercent) % Jahres-Ø \(completedWeeks) Wochen + \(recentPercent) % letzte \(recentWeeks) gewichtet). \(swingText)."
    }
}
