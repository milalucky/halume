import Foundation

/// Which days are working days: weekends plus a country's holidays and moved days.
public struct WorkCalendar: Codable, Sendable, Hashable {
    /// ISO country code ("RU"); empty for weekends only.
    public var country: String
    /// Weekdays that are days off (holidays, moved days off), "yyyy-MM-dd".
    public var daysOff: Set<String>
    /// Saturdays or Sundays that are working days, "yyyy-MM-dd".
    public var workingWeekends: Set<String>
    /// Public holidays ("MM-dd") that don't count as vacation days.
    public var vacationHolidays: Set<String>
    /// Years the lists cover.
    public var years: [Int]

    public init(country: String, daysOff: Set<String> = [], workingWeekends: Set<String> = [],
                vacationHolidays: Set<String> = [], years: [Int] = []) {
        self.country = country; self.daysOff = daysOff; self.workingWeekends = workingWeekends
        self.vacationHolidays = vacationHolidays; self.years = years
    }

    func key(_ date: Date, _ calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    public func isWorkday(_ date: Date, calendar: Calendar) -> Bool {
        let key = key(date, calendar)
        return calendar.isDateInWeekend(date) ? workingWeekends.contains(key) : !daysOff.contains(key)
    }

    public func isVacationHoliday(_ date: Date, calendar: Calendar) -> Bool {
        vacationHolidays.contains(String(key(date, calendar).dropFirst(5)))
    }

    /// Russia's production calendar (xmlcalendar.ru, government decrees on moved days off).
    /// Holidays on weekdays and working weekends only: weekends are known anyway.
    public static let russia = WorkCalendar(
        country: "RU",
        daysOff: [
            "2025-01-01", "2025-01-02", "2025-01-03", "2025-01-06", "2025-01-07", "2025-01-08", "2025-05-01", "2025-05-02",
            "2025-05-08", "2025-05-09", "2025-06-12", "2025-06-13", "2025-11-03", "2025-11-04", "2025-12-31",
            "2026-01-01", "2026-01-02", "2026-01-05", "2026-01-06", "2026-01-07", "2026-01-08", "2026-01-09", "2026-02-23",
            "2026-03-09", "2026-05-01", "2026-05-11", "2026-06-12", "2026-11-04", "2026-12-31",
            "2027-01-01", "2027-01-04", "2027-01-05", "2027-01-06", "2027-01-07", "2027-01-08", "2027-02-22", "2027-02-23",
            "2027-03-08", "2027-05-03", "2027-05-10", "2027-06-14", "2027-11-04", "2027-11-05", "2027-12-31",
        ],
        workingWeekends: ["2025-11-01", "2027-02-20"],
        // Labour Code art. 112: non-working public holidays, not counted in vacation days.
        vacationHolidays: ["01-01", "01-02", "01-03", "01-04", "01-05", "01-06", "01-07", "01-08",
                           "02-23", "03-08", "05-01", "05-09", "06-12", "11-04"],
        years: [2025, 2026, 2027]
    )
}
