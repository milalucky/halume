import Foundation
import HaluMeCore

/// Downloads holidays: production calendars with moved days off (xmlcalendar.ru) for Russia and neighbours,
/// national public holidays (date.nager.at) for the rest. Public data only; nothing about the user is sent.
enum CalendarLoader {
    /// Countries with a full production calendar (moved days off, shortened days).
    static let production = ["RU", "BY", "KZ", "UZ"]

    struct Country: Hashable, Identifiable {
        let code: String
        var id: String { code }
        var name: String { Locale.current.localizedString(forRegionCode: code) ?? code }
    }

    static func countries() async -> [Country] {
        struct Item: Decodable { let countryCode: String }
        var codes = Set(production)
        if let url = URL(string: "https://date.nager.at/api/v3/AvailableCountries"),
           let (data, _) = try? await URLSession.shared.data(from: url),
           let items = try? JSONDecoder().decode([Item].self, from: data) {
            codes.formUnion(items.map(\.countryCode))
        }
        let local = Locale.current.region?.identifier
        return codes.map(Country.init).sorted {
            ($0.code == local ? 0 : 1, $0.name) < ($1.code == local ? 0 : 1, $1.name)
        }
    }

    static func load(_ country: String, years: [Int]) async throws -> WorkCalendar {
        var result = country == "RU" ? WorkCalendar.russia : WorkCalendar(country: country)
        for year in years where !result.years.contains(year) {
            let part = production.contains(country) ? try await production(country, year) : try await publicHolidays(country, year)
            result.daysOff.formUnion(part.daysOff)
            result.workingWeekends.formUnion(part.workingWeekends)
            result.vacationHolidays.formUnion(part.vacationHolidays)
            result.years.append(year)
        }
        result.years.sort()
        return result
    }

    private static func production(_ country: String, _ year: Int) async throws -> WorkCalendar {
        struct File: Decodable {
            struct Month: Decodable { let month: Int; let days: String }
            let months: [Month]
        }
        let url = URL(string: "https://xmlcalendar.ru/data/\(country.lowercased())/\(year)/calendar.json")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let file = try JSONDecoder().decode(File.self, from: data)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        // Listed days are days off; "*" marks a shortened working day, "+" a moved day off.
        var off = Set<String>(), listed = Set<String>()
        for month in file.months {
            for token in month.days.split(separator: ",") {
                guard let day = Int(token.filter(\.isNumber)) else { continue }
                let key = String(format: "%04d-%02d-%02d", year, month.month, day)
                if token.hasSuffix("*") { continue }
                listed.insert(key)
                let date = calendar.date(from: DateComponents(year: year, month: month.month, day: day))!
                if !calendar.isDateInWeekend(date) { off.insert(key) }
            }
        }
        var working = Set<String>()
        var date = calendar.date(from: DateComponents(year: year, month: 1, day: 1))!
        while calendar.component(.year, from: date) == year {
            let c = calendar.dateComponents([.month, .day], from: date)
            let key = String(format: "%04d-%02d-%02d", year, c.month!, c.day!)
            if calendar.isDateInWeekend(date), !listed.contains(key) { working.insert(key) }
            date = calendar.date(byAdding: .day, value: 1, to: date)!
        }
        return WorkCalendar(country: country, daysOff: off, workingWeekends: working)
    }

    private static func publicHolidays(_ country: String, _ year: Int) async throws -> WorkCalendar {
        struct Holiday: Decodable { let date: String; let global: Bool; let types: [String] }
        let url = URL(string: "https://date.nager.at/api/v3/PublicHolidays/\(year)/\(country)")!
        let (data, _) = try await URLSession.shared.data(from: url)
        let holidays = try JSONDecoder().decode([Holiday].self, from: data).filter { $0.global && $0.types.contains("Public") }
        return WorkCalendar(country: country, daysOff: Set(holidays.map(\.date)),
                            vacationHolidays: Set(holidays.map { String($0.date.dropFirst(5)) }))
    }
}
