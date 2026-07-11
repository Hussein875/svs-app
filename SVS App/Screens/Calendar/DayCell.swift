//
//  DayCell.swift
//  SVS App
//
//  Created by Hussein Souleiman on 23.12.25.
//
import Foundation
import SwiftUI

struct DayCellMarker: Identifiable, Hashable {
    let id: String
    let initials: String
    let color: Color
}

struct DayCell: View {
    let date: Date
    let isCurrentMonth: Bool
    let isSelected: Bool
    let isToday: Bool
    let hasBirthday: Bool
    let markers: [DayCellMarker]
    let isHoliday: Bool
    var cellSize: CGFloat = 44

    private var dayFontSize: CGFloat {
        max(12, min(20, cellSize * 0.34))
    }

    private var indicatorHeight: CGFloat {
        max(3, min(7, cellSize * 0.1))
    }

    private var showInitials: Bool {
        cellSize >= 42
    }

    private var markerAreaHeight: CGFloat {
        showInitials ? max(14, cellSize * 0.32) : indicatorHeight
    }

    var body: some View {
        // Tage außerhalb des aktuellen Monats: bewusst „leer“ darstellen
        if !isCurrentMonth {
            return AnyView(
                Color.clear
                    .frame(width: cellSize, height: cellSize)
            )
        }

        let day = Calendar.current.component(.day, from: date)

        return AnyView(
            VStack(spacing: 2) {
                Text("\(day)")
                    .font(.system(size: dayFontSize, weight: dayNumberWeight))
                    .frame(maxWidth: .infinity)
                    .foregroundColor(dayNumberColor)
                    .padding(.top, 1)

                if showInitials {
                    initialsMarkers
                } else {
                    colorBarIndicators
                }
            }
            .frame(maxWidth: .infinity, minHeight: cellSize, maxHeight: cellSize)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.clear)
            )
            .animation(.easeInOut(duration: 0.15), value: isSelected)
        )
    }

    private var colorBarIndicators: some View {
        let unique = orderedUniqueMarkers(markers)
        let maxBars = 3
        let shown = Array(unique.prefix(maxBars))
        let hasMore = unique.count > maxBars
        let dotSize = max(3, indicatorHeight * 0.85)

        return HStack(spacing: 3) {
            ForEach(shown) { marker in
                Capsule()
                    .fill(marker.color.opacity(isCurrentMonth ? 0.95 : 0.35))
                    .frame(height: indicatorHeight)
            }

            if hasMore {
                Circle()
                    .fill(Color.secondary.opacity(0.7))
                    .frame(width: dotSize, height: dotSize)
            }

            if shown.isEmpty && !hasMore {
                Capsule().fill(Color.clear).frame(height: indicatorHeight)
            }
        }
        .frame(height: markerAreaHeight)
        .padding(.horizontal, max(4, cellSize * 0.12))
    }

    private var initialsMarkers: some View {
        let unique = orderedUniqueMarkers(markers)
        let maxShown = 2
        let shown = Array(unique.prefix(maxShown))
        let hasMore = unique.count > maxShown
        let fontSize = max(8, min(11, cellSize * 0.18))

        return HStack(spacing: 2) {
            ForEach(shown) { marker in
                Text(marker.initials)
                    .font(.system(size: fontSize, weight: .semibold))
                    .foregroundColor(marker.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .padding(.horizontal, 2)
                    .padding(.vertical, 1)
                    .background(marker.color.opacity(0.18))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }

            if hasMore {
                Text("+\(unique.count - maxShown)")
                    .font(.system(size: fontSize, weight: .medium))
                    .foregroundColor(.secondary)
            }

            if shown.isEmpty && !hasMore {
                Spacer(minLength: 0)
            }
        }
        .frame(height: markerAreaHeight)
        .padding(.horizontal, max(2, cellSize * 0.06))
    }

    private var dayNumberColor: Color {
        if isToday || isHoliday { return .red }
        if hasBirthday { return .yellow }
        return .primary
    }

    private var dayNumberWeight: Font.Weight {
        if isToday || isHoliday || hasBirthday {
            return .semibold
        }
        return .regular
    }

    private func orderedUniqueMarkers(_ markers: [DayCellMarker]) -> [DayCellMarker] {
        var result: [DayCellMarker] = []
        for marker in markers {
            if !result.contains(where: { $0.id == marker.id }) {
                result.append(marker)
            }
        }
        return result
    }
}
