//
//  File.swift
//  SVS App
//
//  Created by Hussein Souleiman on 23.12.25.
//
import Foundation
import SwiftUI

func roleLabel(for role: UserRole) -> String {
    switch role {
    case .admin:
        return "Admin"
    case .employee:
        return "Mitarbeiter"
    case .expert:
        return "Sachverständiger"
    }
}

struct PrimaryCapsuleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .frame(maxWidth: .infinity, minHeight: 44)
            .padding(.horizontal, 4)
            .background(Color.accentColor)
            .foregroundColor(.white)
            .clipShape(Capsule())
            .opacity(configuration.isPressed ? 0.92 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.99 : 1.0)
    }
}

struct SecondaryTextActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.subheadline.weight(.semibold))
            .frame(minHeight: 44)
            .padding(.horizontal, 8)
            .foregroundColor(.secondary)
            .opacity(configuration.isPressed ? 0.7 : 1.0)
    }
}

func shortDateString(_ date: Date) -> String {
    let df = DateFormatter()
    df.dateStyle = .short
    return df.string(from: date)
}

func mediumDateString(_ date: Date) -> String {
    let df = DateFormatter()
    df.dateStyle = .medium
    return df.string(from: date)
}

func dateRangeString(_ start: Date, _ end: Date) -> String {
    if Calendar.current.isDate(start, inSameDayAs: end) {
        return shortDateString(start)
    } else {
        return "\(shortDateString(start)) – \(shortDateString(end))"
    }
}

func colorForLeaveStatus(_ status: LeaveStatus) -> Color {
    switch status {
    case .approved: return .green
    case .pending:  return .orange
    case .rejected: return .red
    }
}

func statusBadgeView(_ status: LeaveStatus) -> some View {
    Text(status.rawValue)
        .font(.caption2)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule().fill(colorForLeaveStatus(status).opacity(0.15))
        )
        .foregroundColor(colorForLeaveStatus(status))
}
