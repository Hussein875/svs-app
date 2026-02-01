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
    @State private var monthPage: Int = 1 // 0 = prev, 1 = current, 2 = next
    @State private var pagerWidth: CGFloat = 0

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

            TabView(selection: $monthPage) {
                CalendarGrid(currentMonth: monthByAdding(-1, to: currentMonth),
                             selectedDate: $selectedDate)
                    .tag(0)

                CalendarGrid(currentMonth: currentMonth,
                             selectedDate: $selectedDate)
                    .tag(1)

                CalendarGrid(currentMonth: monthByAdding(1, to: currentMonth),
                             selectedDate: $selectedDate)
                    .tag(2)
            }
            .padding(.horizontal, 20) // make calendar a bit narrower
            .tabViewStyle(.page(indexDisplayMode: .never))
            .background(
                GeometryReader { geo in
                    Color.clear
                        .preference(key: CalendarPagerWidthKey.self, value: geo.size.width)
                }
            )
            .onChange(of: monthPage) { newValue in
                if newValue == 0 {
                    shiftMonth(by: -1)
                    monthPage = 1
                } else if newValue == 2 {
                    shiftMonth(by: 1)
                    monthPage = 1
                }
            }
            .onAppear {
                monthPage = 1
            }
            .onPreferenceChange(CalendarPagerWidthKey.self) { w in
                pagerWidth = w
            }
            .frame(
                height: calendarPagerHeight(for: max(0, pagerWidth - 40), month: currentMonth),
                alignment: .top
            )

            List {
                Section(header: Text("\(formatted(selectedDate))")) {
                    if let holiday = germanHolidayName(selectedDate) {
                        Text(holiday)
                            .font(.subheadline)
                            .foregroundColor(.red)
                    }

                    let requests = appState.requests(for: selectedDate).filter { r in
                        // Abwesenheiten: nur genehmigte anzeigen
                        // Samstagsbereitschaft: auch "submitted" anzeigen (alles außer abgelehnt)
                        if r.type == .onCallSaturday {
                            return r.status != .rejected
                        }
                        return r.status == .approved
                    }
                    if requests.isEmpty {
                        Text("Keine Einträge")
                            .foregroundColor(.secondary)
                    } else {
                        ForEach(requests) { r in
                            // Wenn LeaveRequest noch einen Fallback-User enthält (z.B. Name==E-Mail),
                            // versuchen wir für die Anzeige immer den aktuellen User aus `appState.users` zu nehmen.
                            let displayUser = appState.users.first(where: { $0.id == r.user.id }) ?? r.user

                            VStack(alignment: .leading, spacing: 4) {
                                Text(displayUser.name)
                                    .font(.headline)
                                    .foregroundColor(displayUser.color)
                                Text(r.type == .onCallSaturday ? "Bereitschaft" : r.type.rawValue)
                                    .font(.caption)
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
    
    private func shiftMonth(by delta: Int) {
        var cal = Calendar.current
        cal.firstWeekday = 2 // Montag

        guard let newMonth = cal.date(byAdding: .month, value: delta, to: currentMonth) else { return }

        // Keep the selected day-of-month if possible; clamp to last day of target month
        let day = cal.component(.day, from: selectedDate)
        guard let monthInterval = cal.dateInterval(of: .month, for: newMonth) else {
            withAnimation(.easeInOut(duration: 0.25)) { currentMonth = newMonth }
            return
        }
        let startOfNewMonth = cal.startOfDay(for: monthInterval.start)
        let endOfNewMonth = cal.date(byAdding: .day, value: -1, to: monthInterval.end).map { cal.startOfDay(for: $0) } ?? startOfNewMonth
        let lastDay = cal.component(.day, from: endOfNewMonth)

        let clampedDay = min(day, lastDay)
        let targetDate = cal.date(bySetting: .day, value: clampedDay, of: startOfNewMonth) ?? startOfNewMonth

        withAnimation(.easeInOut(duration: 0.25)) {
            currentMonth = newMonth
            selectedDate = targetDate
        }
    }
    
    private func monthByAdding(_ delta: Int, to base: Date) -> Date {
        var cal = Calendar.current
        cal.firstWeekday = 2
        return cal.date(byAdding: .month, value: delta, to: base) ?? base
    }
    
    private func calendarPagerHeight(for width: CGFloat, month: Date) -> CGFloat {
        // Fallback to a reasonable height before we have a measured width.
        guard width > 0 else { return 340 }

        let weeks = CalendarGrid.weeksInGrid(for: month)
        let horizontalPadding: CGFloat = 0 // width already includes TabView padding measurement
        let available = max(0, width - horizontalPadding * 2)

        // Match grid spacing in CalendarGrid
        let rowSpacing: CGFloat = 8
        let colSpacing: CGFloat = 0 // GridItem(.flexible()) has implicit spacing handled by LazyVGrid spacing

        // Cell size derived from width: 7 columns
        let cell = floor((available - (rowSpacing * 6)) / 7)

        // Weekday header height + spacing under header
        let headerHeight: CGFloat = 18
        let headerBottomGap: CGFloat = 6

        // Total grid height (rows + spacing)
        let gridHeight = (CGFloat(weeks) * cell) + (CGFloat(max(weeks - 1, 0)) * rowSpacing)

        // Small internal top/bottom padding for breathing room
        let verticalPadding: CGFloat = 6

        return headerHeight + headerBottomGap + gridHeight + verticalPadding * 2
    }
}

private struct CalendarPagerWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        let n = nextValue()
        if n > 0 { value = n }
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

    static func weeksInGrid(for month: Date) -> Int {
        var cal = Calendar.current
        cal.firstWeekday = 2

        guard let monthInterval = cal.dateInterval(of: .month, for: month) else { return 6 }
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
        let weeks = Int(ceil(Double(totalDays) / 7.0))
        return max(4, min(6, weeks))
    }

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

        VStack(spacing: 6) {
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
                        ? appState.requests(for: date).filter { r in
                            if r.type == .onCallSaturday {
                                return r.status != .rejected
                            }
                            return r.status == .approved
                        }
                        : []

                    let markerColors: [Color] = approvedRequests.map { req in
                        if let u = appState.users.first(where: { $0.id == req.user.id }) {
                            return u.color
                        }
                        return req.user.color
                    }
                    let isHoliday = isCurrentMonth ? isPublicHolidayBremen(date) : false

                    DayCell(
                        date: date,
                        isCurrentMonth: isCurrentMonth,
                        isSelected: isCurrentMonth && Calendar.current.isDate(date, inSameDayAs: selectedDate),
                        approvedColors: markerColors,
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
        .padding(.vertical, 6)
    }
}
