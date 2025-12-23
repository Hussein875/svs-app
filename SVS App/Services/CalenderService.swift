//
//  CalenderServices.swift
//  SVS App
//
//  Created by Hussein Souleiman on 23.12.25.
//
import SwiftUI
import Foundation
    
    func germanHolidayName(_ date: Date) -> String? {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: date)
        
        func makeDate(_ month: Int, _ day: Int) -> Date? {
            var components = DateComponents()
            components.year = year
            components.month = month
            components.day = day
            return calendar.date(from: components)
        }
        
        func sameDay(_ d1: Date?, _ d2: Date) -> Bool {
            guard let d1 = d1 else { return false }
            return calendar.isDate(d1, inSameDayAs: d2)
        }
        
        // Feste Feiertage (bundesweit)
        let newYear        = makeDate(1, 1)
        let labourDay      = makeDate(5, 1)
        let germanUnity    = makeDate(10, 3)
        let reformationDay = makeDate(10, 31)
        let christmasDay   = makeDate(12, 25)
        let boxingDay      = makeDate(12, 26)
        
        if sameDay(newYear, date)        { return "Neujahr" }
        if sameDay(labourDay, date)      { return "Tag der Arbeit" }
        if sameDay(germanUnity, date)    { return "Tag der Deutschen Einheit" }
        if sameDay(reformationDay, date) { return "Reformationstag" }
        if sameDay(christmasDay, date)   { return "1. Weihnachtstag" }
        if sameDay(boxingDay, date)      { return "2. Weihnachtstag" }
        
        // Bewegliche Feiertage rund um Ostern
        guard let easter = easterSunday(year: year) else { return nil }
        let goodFriday   = calendar.date(byAdding: .day, value: -2, to: easter)
        let easterMonday = calendar.date(byAdding: .day, value:  1, to: easter)
        let ascension    = calendar.date(byAdding: .day, value: 39, to: easter)
        let whitMonday   = calendar.date(byAdding: .day, value: 50, to: easter)
        
        if sameDay(goodFriday, date)     { return "Karfreitag" }
        if sameDay(easter, date)         { return "Ostersonntag" }
        if sameDay(easterMonday, date)   { return "Ostermontag" }
        if sameDay(ascension, date)      { return "Christi Himmelfahrt" }
        if sameDay(whitMonday, date)     { return "Pfingstmontag" }
        
        return nil
    }
    
    func isPublicHolidayBremen(_ date: Date) -> Bool {
        return germanHolidayName(date) != nil
    }
    
    func easterSunday(year: Int) -> Date? {
        // Meeus/Jones/Butcher Algorithmus
        let a = year % 19
        let b = year / 100
        let c = year % 100
        let d = b / 4
        let e = b % 4
        let f = (b + 8) / 25
        let g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4
        let k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let month = (h + l - 7 * m + 114) / 31
        let day = ((h + l - 7 * m + 114) % 31) + 1
        
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        return Calendar.current.date(from: components)
    }

 func workingDays(from start: Date, to end: Date) -> Int {
    let cal = Calendar.current
    var date = cal.startOfDay(for: start)
    let endDate = cal.startOfDay(for: end)
    var count = 0

    while date <= endDate {
        let weekday = cal.component(.weekday, from: date)
        let isWeekday = weekday >= 2 && weekday <= 6

        if isWeekday && !isPublicHolidayBremen(date) {
            count += 1
        }
        date = cal.date(byAdding: .day, value: 1, to: date)!
    }
    return count
}
