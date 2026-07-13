//
//  DayCell.swift
//  SVS App
//
//  Created by Hussein Souleiman on 23.12.25.
//
import Foundation
import SwiftUI
import UIKit

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
        let horizontalPadding = max(2, cellSize * 0.06) * 2
        let availableWidth = cellSize - horizontalPadding
        let fittedLabels = fittedInitialsLabels(
            markers: shown,
            hasMoreCount: hasMore ? unique.count - maxShown : 0,
            fontSize: fontSize,
            availableWidth: availableWidth
        )

        return HStack(spacing: 2) {
            ForEach(fittedLabels) { label in
                Text(label.text)
                    .font(.system(size: fontSize, weight: .semibold))
                    .foregroundColor(label.marker.color)
                    .lineLimit(1)
                    .padding(.horizontal, 2)
                    .padding(.vertical, 1)
                    .background(label.marker.color.opacity(0.18))
                    .clipShape(RoundedRectangle(cornerRadius: 3))
            }

            if let moreText = fittedMoreLabel(
                count: hasMore ? unique.count - maxShown : 0,
                fontSize: fontSize,
                availableWidth: remainingWidth(
                    availableWidth: availableWidth,
                    labels: fittedLabels,
                    fontSize: fontSize
                )
            ) {
                Text(moreText)
                    .font(.system(size: fontSize, weight: .medium))
                    .foregroundColor(.secondary)
            }

            if fittedLabels.isEmpty && !hasMore {
                Spacer(minLength: 0)
            }
        }
        .frame(height: markerAreaHeight)
        .padding(.horizontal, max(2, cellSize * 0.06))
    }

    private struct FittedInitialsLabel: Identifiable {
        let id: String
        let marker: DayCellMarker
        let text: String
    }

    private func fittedInitialsLabels(
        markers: [DayCellMarker],
        hasMoreCount: Int,
        fontSize: CGFloat,
        availableWidth: CGFloat
    ) -> [FittedInitialsLabel] {
        guard !markers.isEmpty else { return [] }

        let spacing: CGFloat = 2
        let badgeHorizontalPadding: CGFloat = 4
        let moreText = hasMoreCount > 0 ? "+\(hasMoreCount)" : ""
        let moreWidth = hasMoreCount > 0
            ? textWidth(for: moreText, fontSize: fontSize, weight: .medium) + spacing
            : 0
        let widthForBadges = max(0, availableWidth - moreWidth - CGFloat(max(0, markers.count - 1)) * spacing)
        let widthPerBadge = widthForBadges / CGFloat(markers.count)
        let maxTextWidthPerBadge = max(0, widthPerBadge - badgeHorizontalPadding)

        return markers.map { marker in
            let fits = textWidth(for: marker.initials, fontSize: fontSize, weight: .semibold) <= maxTextWidthPerBadge
            return FittedInitialsLabel(
                id: marker.id,
                marker: marker,
                text: fits ? marker.initials : ""
            )
        }
    }

    private func remainingWidth(
        availableWidth: CGFloat,
        labels: [FittedInitialsLabel],
        fontSize: CGFloat
    ) -> CGFloat {
        let spacing: CGFloat = 2
        let badgeHorizontalPadding: CGFloat = 4
        let used = labels.reduce(CGFloat(0)) { partial, label in
            let textWidth = textWidth(for: label.text, fontSize: fontSize, weight: .semibold)
            let badgeWidth = max(textWidth + badgeHorizontalPadding, badgeHorizontalPadding)
            return partial + badgeWidth
        }
        let spacingWidth = CGFloat(max(0, labels.count - 1)) * spacing
        return max(0, availableWidth - used - spacingWidth)
    }

    private func fittedMoreLabel(count: Int, fontSize: CGFloat, availableWidth: CGFloat) -> String? {
        guard count > 0 else { return nil }
        let text = "+\(count)"
        guard textWidth(for: text, fontSize: fontSize, weight: .medium) <= availableWidth else {
            return nil
        }
        return text
    }

    private func textWidth(for text: String, fontSize: CGFloat, weight: UIFont.Weight) -> CGFloat {
        guard !text.isEmpty else { return 0 }
        let font = UIFont.systemFont(ofSize: fontSize, weight: weight)
        return ceil((text as NSString).size(withAttributes: [.font: font]).width)
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
