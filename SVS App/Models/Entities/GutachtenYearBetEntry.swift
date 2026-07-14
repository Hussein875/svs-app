//
//  GutachtenYearBetEntry.swift
//  SVS App
//

import Foundation

struct GutachtenYearBetEntry: Identifiable, Hashable, Codable {
    let id: String
    var displayName: String
    var predictedTotal: Int
    var userId: String?

    init(
        id: String = UUID().uuidString,
        displayName: String,
        predictedTotal: Int,
        userId: String? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.predictedTotal = predictedTotal
        self.userId = userId
    }
}

struct GutachtenYearProjection: Hashable {
    let year: Int
    let currentGutachtenNumber: Int
    let projectedYearEndGutachtenNumber: Int
    let projectedYearEndLow: Int
    let projectedYearEndHigh: Int
    let yearStartNumber: Int
    let producedThisYear: Int
    let yearToDateWeeklyAverage: Double
    let recentWeightedWeeklyAverage: Double
    let blendedWeeklyPace: Double
    let adjustedWeeklyPace: Double
    let yearBlendWeight: Double
    let recentBlendWeight: Double
    let trendSwingFactor: Double
    let trend: GutachtenProjectionTrend
    let trendRatio: Double
    let recentFourWeekAverage: Double
    let priorFourWeekAverage: Double
    let weeksElapsed: Int
    let weeksRemaining: Int
    let daysRemaining: Int
    let completedWeeksSampled: Int
    let recentWeeksSampled: Int
    let latestCalendarWeek: Int?
    let methodSummary: String
}

struct GutachtenBetStanding: Identifiable, Hashable {
    var id: String { entry.id }
    let entry: GutachtenYearBetEntry
    let distanceFromProjection: Int
    let rank: Int
    let winProbabilityPercent: Double
}

extension GutachtenYearProjection {
    var trendDetailLabel: String {
        let recent = String(format: "%.0f", recentFourWeekAverage)
        let prior = String(format: "%.0f", priorFourWeekAverage)
        return "Ø \(recent) vs. \(prior)"
    }

    var projectionRangeLabel: String {
        "\(GutachtenYearBetFormatters.gutachtenNumber(projectedYearEndLow)) – \(GutachtenYearBetFormatters.gutachtenNumber(projectedYearEndHigh))"
    }

    var yearAverageLabel: String {
        String(format: "%.1f / Woche", yearToDateWeeklyAverage)
    }

    var recentPaceLabel: String {
        String(format: "%.1f / Woche", recentWeightedWeeklyAverage)
    }
}
