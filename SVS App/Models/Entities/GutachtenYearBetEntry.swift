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
    let yearStartNumber: Int
    let producedThisYear: Int
    let averagePerWeek: Double
    let adjustedWeeklyPace: Double
    let dailyPace: Double
    let linearProjection: Int
    let momentumProjection: Int
    let linearBlendWeight: Double
    let trend: GutachtenProjectionTrend
    let trendFactor: Double
    let trendRatio: Double
    let recentFourWeekAverage: Double
    let priorFourWeekAverage: Double
    let weeksElapsed: Int
    let weeksRemaining: Int
    let daysRemaining: Int
    let completedWeeksSampled: Int
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
}
