//
//  CalendarScreen.swift
//  SVS App
//
//  Created by Hussein Souleiman on 23.12.25.
//
import Foundation
import SwiftUI

struct CalendarScreen: View {
    @EnvironmentObject var appState: AppState
    @State private var currentMonth: Date = Date()
    @State private var selectedDate: Date = Date()

    var body: some View {
        VStack(spacing: 12) {
            // Clean Header
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Kalender")
                        .font(.largeTitle.weight(.bold))

                    Spacer()

                    Button {
                        let now = Date()
                        withAnimation(.easeInOut(duration: 0.25)) {
                            currentMonth = now
                        }
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedDate = now
                        }
                    } label: {
                        Text("Heute")
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .tint(.secondary)
                }

                MonthHeader(currentMonth: $currentMonth)
            }
            .padding(.horizontal)
            .padding(.top, 4)

            VStack(alignment: .leading, spacing: 4) {
                Text("Mitarbeiter")
                    .font(.subheadline)
                    .padding(.horizontal)
                UserLegendView()
                    .padding(.horizontal)
            }

            CalendarGrid(currentMonth: currentMonth,
                         selectedDate: $selectedDate)
                .padding(.horizontal)
                .animation(.easeInOut(duration: 0.25), value: currentMonth)

            List {
                Section(header: Text("\(formatted(selectedDate))")) {
                    if let holiday = germanHolidayName(selectedDate) {
                        Text(holiday)
                            .font(.subheadline)
                            .foregroundColor(.red)
                    }

                    let requests = appState.requests(for: selectedDate).filter { $0.status == .approved }
                    if requests.isEmpty {
                        Text("Keine Anträge")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(requests) { r in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(r.user.name)
                                    .font(.headline)
                                    .foregroundColor(r.user.color)
                                Text("\(dateRange(r.startDate, r.endDate))")
                                    .font(.subheadline)
                                Text(r.type.rawValue)
                                    .font(.caption)
                                // Bei Krankheit keinen Status-Text anzeigen
                                if r.type != .sick {
                                    Text(r.status.rawValue)
                                        .font(.caption2)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    func formatted(_ date: Date) -> String {
        mediumDateString(date)
    }

    func dateRange(_ start: Date, _ end: Date) -> String {
        dateRangeString(start, end)
    }
}



// MARK: - User Legend

struct UserLegendView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(appState.users, id: \.id) { user in
                    HStack(spacing: 6) {
                        Circle()
                            .fill(user.color)
                            .frame(width: 10, height: 10)
                        Text(user.name)
                            .font(.caption)
                    }
                    .padding(.vertical, 4)
                    .padding(.horizontal, 8)
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(8)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

// MARK: - Calendar Grid

struct CalendarGrid: View {
    @EnvironmentObject var appState: AppState
    let currentMonth: Date
    @Binding var selectedDate: Date

    private var days: [Date] {
        var cal = Calendar.current
        cal.firstWeekday = 2 // Montag

        guard let monthInterval = cal.dateInterval(of: .month, for: currentMonth) else {
            return []
        }

        let startOfMonth = cal.startOfDay(for: monthInterval.start)
        let endOfMonth = cal.date(byAdding: .day, value: -1, to: monthInterval.end).map { cal.startOfDay(for: $0) } ?? startOfMonth

        func startOfWeek(_ date: Date) -> Date {
            let weekday = cal.component(.weekday, from: date)
            let diff = (weekday - cal.firstWeekday + 7) % 7
            return cal.date(byAdding: .day, value: -diff, to: date).map { cal.startOfDay(for: $0) } ?? date
        }

        func endOfWeek(_ date: Date) -> Date {
            let weekday = cal.component(.weekday, from: date)
            let diff = (cal.firstWeekday + 6 - weekday + 7) % 7
            return cal.date(byAdding: .day, value: diff, to: date).map { cal.startOfDay(for: $0) } ?? date
        }

        let gridStart = startOfWeek(startOfMonth)
        let gridEnd = endOfWeek(endOfMonth)

        let totalDays = (cal.dateComponents([.day], from: gridStart, to: gridEnd).day ?? 0) + 1
        let weeks = max(4, min(6, Int(ceil(Double(totalDays) / 7.0))))

        return (0..<(weeks * 7)).compactMap { offset in
            cal.date(byAdding: .day, value: offset, to: gridStart)
        }
    }

    var body: some View {
        let columns = Array(repeating: GridItem(.flexible()), count: 7)

        VStack {
            HStack {
                ForEach(["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"], id: \.self) { d in
                    Text(d)
                        .font(.caption)
                        .frame(maxWidth: .infinity)
                }
            }
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(days, id: \.self) { date in
                    let isCurrentMonth = Calendar.current.isDate(date, equalTo: currentMonth, toGranularity: .month)

                    let approvedRequests = isCurrentMonth
                        ? appState.requests(for: date).filter { $0.status == .approved }
                        : []

                    let approvedColors = approvedRequests.map { $0.user.color }
                    let isHoliday = isCurrentMonth ? isPublicHolidayBremen(date) : false

                    DayCell(
                        date: date,
                        isCurrentMonth: isCurrentMonth,
                        isSelected: isCurrentMonth && Calendar.current.isDate(date, inSameDayAs: selectedDate),
                        approvedColors: approvedColors,
                        isHoliday: isHoliday
                    )
                    .contentShape(Rectangle())
                    .allowsHitTesting(isCurrentMonth)
                    .onTapGesture {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            selectedDate = date
                        }
                    }
                }
            }
        }
    }
}


    
    

