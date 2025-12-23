//
//  DayCell.swift
//  SVS App
//
//  Created by Hussein Souleiman on 23.12.25.
//
import Foundation
import SwiftUI

struct DayCell: View {
    let date: Date
    let isCurrentMonth: Bool
    let isSelected: Bool
    let approvedColors: [Color]
    let isHoliday: Bool
    
    var body: some View {
        // Tage außerhalb des aktuellen Monats: bewusst „leer“ darstellen
        if !isCurrentMonth {
            return AnyView(
                Color.clear
                    .frame(maxWidth: .infinity, minHeight: 36)
            )
        }
        
        let day = Calendar.current.component(.day, from: date)
        
        return AnyView(
            VStack(spacing: 3) {
                Text("\(day)")
                    .font(.caption)
                    .frame(maxWidth: .infinity)
                    .foregroundColor(isHoliday ? .red : .primary)
                    .padding(.top, 1)
                
                // Indicator-Bars (Apple-like)
                indicators
                    .frame(height: 5) // kleiner als vorher
            }
                .frame(maxWidth: .infinity, minHeight: 36)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(isSelected ? Color.accentColor.opacity(0.14) : Color.clear)
                )
                .animation(.easeInOut(duration: 0.15), value: isSelected)
        )
    }
    
    
    private var indicators: some View {
        let unique = Array(orderedUniqueColors(approvedColors))
        let maxBars = 3
        let shown = Array(unique.prefix(maxBars))
        let hasMore = unique.count > maxBars
        
        return HStack(spacing: 3) {
            ForEach(Array(shown.enumerated()), id: \.offset) { _, c in
                Capsule()
                    .fill(c.opacity(isCurrentMonth ? 0.95 : 0.35))
                    .frame(height: 3)
            }
            
            if hasMore {
                Circle()
                    .fill(Color.secondary.opacity(0.7))
                    .frame(width: 3, height: 3)
            }
            
            // Wenn keine Anträge: unsichtbar, aber gleicher Platz
            if shown.isEmpty && !hasMore {
                Capsule().fill(Color.clear).frame(height: 3)
            }
        }
        .padding(.horizontal, 6)
    }
    
    private func orderedUniqueColors(_ colors: [Color]) -> [Color] {
        var result: [Color] = []
        for c in colors {
            if !result.contains(where: { $0.description == c.description }) {
                result.append(c)
            }
        }
        return result
    }
}
