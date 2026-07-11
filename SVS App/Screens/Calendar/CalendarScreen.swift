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
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var currentMonth: Date = Date()
    @State private var selectedDate: Date = Date()
    @State private var monthPage: Int = 1 // 0 = prev, 1 = current, 2 = next
    @State private var pagerWidth: CGFloat = 0

    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular
    }

    var body: some View {
        Group {
            if isRegularWidth {
                iPadLayout
            } else {
                phoneLayout
            }
        }
    }

    // MARK: - Phone Layout

    private var phoneLayout: some View {
        VStack(spacing: 12) {
            calendarHeader
            legendSection
            monthPager
            dayDetailList
        }
    }

    // MARK: - iPad Layout

    private var iPadLayout: some View {
        ScrollView {
            VStack(spacing: 20) {
                calendarHeader
                legendSection
                monthPager
                dayDetailCard
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
    }

    // MARK: - Shared Sections

    private var calendarHeader: some View {
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
        .padding(.horizontal, isRegularWidth ? 0 : nil)
        .padding(.top, 4)
    }

    private var legendSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Mitarbeiter")
                .font(.subheadline)
                .padding(.horizontal, isRegularWidth ? 0 : nil)
            UserLegendView()
                .padding(.horizontal, isRegularWidth ? 0 : nil)
        }
    }

    private var monthPager: some View {
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
        .padding(.horizontal, isRegularWidth ? 0 : 20)
        .tabViewStyle(.page(indexDisplayMode: .never))
        .background(
            GeometryReader { geo in
                Color.clear
                    .preference(key: CalendarPagerWidthKey.self, value: geo.size.width)
            }
        )
        .onChange(of: monthPage) { _, newValue in
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
            height: calendarPagerHeight(
                for: max(0, pagerWidth - (isRegularWidth ? 0 : 40)),
                month: currentMonth,
                isRegularWidth: isRegularWidth
            ),
            alignment: .top
        )
    }

    private var selectedDayBirthdays: [User] {
        appState.users
            .filter { isUsersBirthday($0, on: selectedDate) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var selectedDayRequests: [LeaveRequest] {
        appState.requests(for: selectedDate).filter { r in
            if r.type == .onCallSaturday {
                return r.status != .rejected
            }
            return r.status == .approved
        }
    }

    private var dayDetailCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(formatted(selectedDate))
                .font(.title3.weight(.semibold))

            if let holiday = germanHolidayName(selectedDate) {
                Label(holiday, systemImage: "flag.fill")
                    .font(.subheadline)
                    .foregroundColor(.red)
            }

            if selectedDayBirthdays.isEmpty && selectedDayRequests.isEmpty && germanHolidayName(selectedDate) == nil {
                Text("Keine Einträge")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 220), spacing: 12)],
                    alignment: .leading,
                    spacing: 12
                ) {
                    ForEach(selectedDayBirthdays, id: \.id) { user in
                        DayDetailEntryCard(
                            title: user.name,
                            subtitle: "hat Geburtstag",
                            icon: "gift.fill",
                            color: user.color
                        )
                    }

                    ForEach(selectedDayRequests) { request in
                        let displayUser = appState.users.first(where: { $0.id == request.user.id }) ?? request.user
                        DayDetailEntryCard(
                            title: displayUser.name,
                            subtitle: request.type == .onCallSaturday ? "Bereitschaft" : request.type.rawValue,
                            icon: leaveTypeIconName(request.type),
                            color: displayUser.color
                        )
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var dayDetailList: some View {
        List {
            Section(header: Text("\(formatted(selectedDate))")) {
                if let holiday = germanHolidayName(selectedDate) {
                    Text(holiday)
                        .font(.subheadline)
                        .foregroundColor(.red)
                }

                ForEach(selectedDayBirthdays, id: \.id) { user in
                    HStack(spacing: 8) {
                        Image(systemName: "gift.fill")
                            .font(.caption)
                            .foregroundColor(.pink)
                        Text(user.name)
                            .font(.headline)
                            .foregroundColor(user.color)
                        Text("hat Geburtstag")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }

                if selectedDayRequests.isEmpty && selectedDayBirthdays.isEmpty {
                    Text("Keine Einträge")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(selectedDayRequests) { r in
                        let displayUser = appState.users.first(where: { $0.id == r.user.id }) ?? r.user

                        VStack(alignment: .leading, spacing: 4) {
                            Text(displayUser.name)
                                .font(.headline)
                                .foregroundColor(displayUser.color)
                            HStack(spacing: 6) {
                                Image(systemName: leaveTypeIconName(r.type))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                Text(r.type == .onCallSaturday ? "Bereitschaft" : r.type.rawValue)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    func formatted(_ date: Date) -> String {
        mediumDateString(date)
    }

    func dateRange(_ start: Date, _ end: Date) -> String {
        dateRangeString(start, end)
    }

    private func leaveTypeIconName(_ type: LeaveType) -> String {
        switch type {
        case .vacation:
            return "beach.umbrella"
        case .sick:
            return "cross.case"
        case .onCallSaturday:
            return "person.badge.clock"
        }
    }

    private func isUsersBirthday(_ user: User, on date: Date) -> Bool {
        guard let birthday = user.birthday else { return false }
        let cal = Calendar.current
        let bComps = cal.dateComponents([.month, .day], from: birthday)
        let dComps = cal.dateComponents([.month, .day], from: date)
        return bComps.month == dComps.month && bComps.day == dComps.day
    }

    private func shiftMonth(by delta: Int) {
        var cal = Calendar.current
        cal.firstWeekday = 2 // Montag

        guard let newMonth = cal.date(byAdding: .month, value: delta, to: currentMonth) else { return }

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

    private func calendarPagerHeight(for width: CGFloat, month: Date, isRegularWidth: Bool) -> CGFloat {
        guard width > 0 else { return 340 }

        let weeks = CalendarGrid.weeksInGrid(for: month)
        let cell = CalendarGrid.cellSize(for: width, isRegularWidth: isRegularWidth)
        let headerHeight: CGFloat = 18
        let headerBottomGap: CGFloat = 6
        let gridHeight = (CGFloat(weeks) * cell) + (CGFloat(max(weeks - 1, 0)) * CalendarGrid.rowSpacing)
        let verticalPadding: CGFloat = 6

        return headerHeight + headerBottomGap + gridHeight + verticalPadding * 2
    }
}

private struct DayDetailEntryCard: View {
    let title: String
    let subtitle: String
    let icon: String
    let color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.body)
                .foregroundColor(color)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(color)
                Text(subtitle)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
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
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        if horizontalSizeClass == .regular {
            legendGrid
        } else {
            legendScroll
        }
    }

    private var legendScroll: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 12) {
                ForEach(appState.users, id: \.id) { user in
                    legendChip(for: user)
                }
            }
            .padding(.vertical, 4)
        }
    }

    private var legendGrid: some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 120), spacing: 8)],
            alignment: .leading,
            spacing: 8
        ) {
            ForEach(appState.users, id: \.id) { user in
                legendChip(for: user)
            }
        }
        .padding(.vertical, 4)
    }

    private func legendChip(for user: User) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(user.color)
                .frame(width: 10, height: 10)
            Text(user.name)
                .font(.caption)
                .lineLimit(1)
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .background(Color(.secondarySystemBackground))
        .cornerRadius(8)
    }
}

// MARK: - Calendar Grid

struct CalendarGrid: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    let currentMonth: Date
    @Binding var selectedDate: Date

    static let maxCellSizePhone: CGFloat = 52
    static let rowSpacing: CGFloat = 8

    static func cellSize(for width: CGFloat, isRegularWidth: Bool) -> CGFloat {
        let available = max(0, width)
        let natural = floor((available - (rowSpacing * 6)) / 7)
        if isRegularWidth {
            return max(natural, 44)
        }
        return min(natural, maxCellSizePhone)
    }

    static func gridWidth(for width: CGFloat, isRegularWidth: Bool) -> CGFloat {
        let cell = cellSize(for: width, isRegularWidth: isRegularWidth)
        return (cell * 7) + (rowSpacing * 6)
    }

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
        GeometryReader { geo in
            let width = geo.size.width
            let isRegular = horizontalSizeClass == .regular
            let cell = Self.cellSize(for: width, isRegularWidth: isRegular)
            let columns = Array(repeating: GridItem(.fixed(cell), spacing: Self.rowSpacing), count: 7)
            let weekdayFontSize = max(11, min(16, cell * 0.22))

            Group {
                if isRegular {
                    VStack(spacing: 6) {
                        weekdayHeader(cellSize: cell, fontSize: weekdayFontSize)
                        dayGrid(columns: columns, cellSize: cell)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                } else {
                    HStack {
                        Spacer(minLength: 0)
                        VStack(spacing: 6) {
                            weekdayHeader(cellSize: cell, fontSize: weekdayFontSize)
                            dayGrid(columns: columns, cellSize: cell)
                                .frame(width: Self.gridWidth(for: width, isRegularWidth: false))
                        }
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                }
            }
        }
        .padding(.vertical, 6)
    }

    private func weekdayHeader(cellSize: CGFloat, fontSize: CGFloat) -> some View {
        HStack {
            ForEach(["Mo", "Di", "Mi", "Do", "Fr", "Sa", "So"], id: \.self) { d in
                Text(d)
                    .font(.system(size: fontSize))
                    .frame(maxWidth: .infinity)
                    .frame(width: horizontalSizeClass == .regular ? nil : cellSize)
            }
        }
    }

    private func dayGrid(columns: [GridItem], cellSize: CGFloat) -> some View {
        LazyVGrid(columns: columns, spacing: Self.rowSpacing) {
            ForEach(Array(days.enumerated()), id: \.offset) { _, date in
                let isCurrentMonth = Calendar.current.isDate(date, equalTo: currentMonth, toGranularity: .month)

                let approvedRequests = isCurrentMonth
                    ? appState.requests(for: date).filter { r in
                        if r.type == .onCallSaturday {
                            return r.status != .rejected
                        }
                        return r.status == .approved
                    }
                    : []

                let dayMarkers: [DayCellMarker] = approvedRequests.map { req in
                    let user = appState.users.first(where: { $0.id == req.user.id }) ?? req.user
                    return DayCellMarker(
                        id: user.id,
                        initials: user.displayInitials,
                        color: user.color
                    )
                }
                let hasBirthdayEntry = isCurrentMonth && hasBirthday(on: date)
                let isHoliday = isCurrentMonth ? isPublicHolidayBremen(date) : false
                let isToday = isCurrentMonth && Calendar.current.isDateInToday(date)

                DayCell(
                    date: date,
                    isCurrentMonth: isCurrentMonth,
                    isSelected: isCurrentMonth && Calendar.current.isDate(date, inSameDayAs: selectedDate),
                    isToday: isToday,
                    hasBirthday: hasBirthdayEntry,
                    markers: dayMarkers,
                    isHoliday: isHoliday,
                    cellSize: cellSize
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

    private func hasBirthday(on date: Date) -> Bool {
        let cal = Calendar.current
        let day = cal.dateComponents([.month, .day], from: date)
        return appState.users.contains { user in
            guard let birthday = user.birthday else { return false }
            let birthdayDay = cal.dateComponents([.month, .day], from: birthday)
            return birthdayDay.month == day.month && birthdayDay.day == day.day
        }
    }
}
