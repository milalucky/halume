import HaluMeCore
import SwiftUI

/// The country's production calendar with paydays, holidays and time off; pick days to plan a vacation or sick leave.
struct CalendarPage: View {
    @Environment(BudgetStore.self) private var store
    @State private var month = Calendar.current.dateInterval(of: .month, for: Date())!.start
    @State private var first: Date?
    @State private var last: Date?

    private let calendar = Calendar.current

    var body: some View {
        Page(title: "Calendar") {
            Button { store.sheet = .timeOff(nil) } label: { Label("Time off", systemImage: "plus") }
                .buttonStyle(SecondaryButtonStyle())
                .help("Plan a vacation, sick leave or unpaid days")
        } content: {
            if let budget = store.budget, let planner = store.planner, let me = store.me {
                VStack(alignment: .leading, spacing: 14) {
                    header(budget)
                    MonthGrid(month: month, planner: planner, me: me, first: first, last: last) { tap($0) }
                    legend
                    if let first {
                        selection(first: first, last: last ?? first, planner: planner)
                    } else {
                        summary(planner: planner, me: me, currency: budget.currency)
                    }
                }
                .card()
                Upcoming(planner: planner)
                TimeOffList(planner: planner, me: me)
            }
        }
        .task(id: store.budget?.workCalendar?.country) { await refreshNames() }
    }

    private func header(_ budget: Budget) -> some View {
        HStack {
            Text(month.formatted(.dateTime.month(.wide).year())).font(.title3.weight(.semibold))
            Spacer()
            Text(budget.workCalendar.flatMap { Locale.current.localizedString(forRegionCode: $0.country) }
                 ?? String(localized: "Weekends only"))
                .font(.caption).foregroundStyle(.secondary)
                .help("The country's working days and holidays. Change it in Settings → Work calendar.")
            IconButton(icon: "chevron.left", label: "Previous month") { shift(-1) }
            Button("Today") { month = calendar.dateInterval(of: .month, for: Date())!.start }
                .buttonStyle(.borderless)
            IconButton(icon: "chevron.right", label: "Next month") { shift(1) }
        }
    }

    private var legend: some View {
        FlowLayout(spacing: 14) {
            LegendDot(color: Palette.red.opacity(0.7), text: "Day off")
            LegendDot(color: Palette.orange, text: "Holiday")
            LegendDot(color: Palette.green, text: "Payday")
            LegendDot(color: .blue, text: "Vacation")
            LegendDot(color: .purple, text: "Sick leave")
        }
        .font(.caption).foregroundStyle(.secondary)
    }

    private func summary(planner: Planner, me: UUID, currency: String) -> some View {
        let start = month, end = calendar.date(byAdding: DateComponents(month: 1, day: -1), to: month)!
        let working = planner.workdayCount(start, end)
        let total = calendar.range(of: .day, in: .month, for: month)!.count
        let paydays = planner.paydays(of: me, from: start, to: end)
        let pay = paydays.reduce(Decimal(0)) { $0 + (planner.payday(of: me, on: $1)?.actual ?? planner.expected(of: me, on: $1)) }
            + planner.extras(of: me, from: start, to: end).reduce(0) { $0 + $1.amount }
        return VStack(alignment: .leading, spacing: 10) {
            StatRow {
                Stat(label: "Working days", value: "\(working)")
                Stat(label: "Days off", value: "\(total - working)")
                Stat(label: "Pay this month", value: pay.money(currency))
            }
            Text("Click a day, then another, to plan time off.").font(.caption).foregroundStyle(.tertiary)
        }
    }

    private func selection(first: Date, last: Date, planner: Planner) -> some View {
        let days = (calendar.dateComponents([.day], from: first, to: last).day ?? 0) + 1
        let working = planner.workdayCount(first, last)
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(first.formatted(.dateTime.day().month(.abbreviated))) – \(last.formatted(.dateTime.day().month(.abbreviated)))")
                    .font(.body.weight(.semibold))
                Text("\(days) days, \(working) working").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Clear") { self.first = nil; self.last = nil }.buttonStyle(.borderless)
            Button("Sick Leave…") { plan(.sickLeave, first, last) }.buttonStyle(SecondaryButtonStyle())
            Button("Vacation…") { plan(.vacation, first, last) }.buttonStyle(PrimaryButtonStyle())
        }
    }

    private func plan(_ kind: AbsenceKind, _ from: Date, _ to: Date) {
        store.sheet = .timeOff(TimeOffDraft(kind: kind, from: from, to: to))
        first = nil
        last = nil
    }

    /// First click starts a range, the second ends it (in either order), a third starts over.
    private func tap(_ day: Date) {
        if let first, last == nil {
            self.first = min(first, day)
            last = max(first, day)
        } else {
            first = day
            last = nil
        }
    }

    private func shift(_ months: Int) {
        month = calendar.date(byAdding: .month, value: months, to: month)!
    }

    /// Calendars downloaded before names were kept: fetch again once to get them.
    private func refreshNames() async {
        guard let current = store.budget?.workCalendar, current.country != "RU", current.names == nil, !current.country.isEmpty,
              let fresh = try? await CalendarLoader.load(current.country, years: current.years) else { return }
        store.budget?.workCalendar = fresh
    }
}

private struct LegendDot: View {
    let color: Color
    let text: LocalizedStringKey

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text)
        }
    }
}

/// A month of days, Monday (or the locale's first weekday) first.
private struct MonthGrid: View {
    let month: Date
    let planner: Planner
    let me: UUID
    let first: Date?
    let last: Date?
    let tap: (Date) -> Void

    private let calendar = Calendar.current

    var body: some View {
        let days = calendar.range(of: .day, in: .month, for: month)!.map { calendar.date(byAdding: .day, value: $0 - 1, to: month)! }
        let lead = (calendar.component(.weekday, from: month) - calendar.firstWeekday + 7) % 7
        let end = days.last!
        let paydays = Set(planner.paydays(of: me, from: month, to: end))
        let arrivals = planner.extras(of: me, from: month, to: end)
        let symbols = Array(calendar.shortStandaloneWeekdaySymbols[(calendar.firstWeekday - 1)...] + calendar.shortStandaloneWeekdaySymbols[..<(calendar.firstWeekday - 1)])
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)
        LazyVGrid(columns: columns, spacing: 4) {
            ForEach(symbols, id: \.self) { Text($0).font(.caption.weight(.medium)).foregroundStyle(.secondary) }
            ForEach(0..<lead, id: \.self) { _ in Color.clear.frame(height: 46) }
            ForEach(days, id: \.self) { day in
                DayCell(day: day, planner: planner, me: me,
                        payday: paydays.contains(day), arrival: arrivals.first { calendar.isDate($0.date, inSameDayAs: day) },
                        selected: inSelection(day))
                    .onTapGesture { tap(day) }
            }
        }
    }

    private func inSelection(_ day: Date) -> Bool {
        guard let first else { return false }
        return day >= first && day <= (last ?? first)
    }
}

private struct DayCell: View {
    @Environment(BudgetStore.self) private var store
    let day: Date
    let planner: Planner
    let me: UUID
    let payday: Bool
    let arrival: Arrival?
    let selected: Bool
    @State private var hovering = false

    var body: some View {
        let calendar = Calendar.current
        let workday = planner.isWorkday(day)
        let holiday = planner.budget.workCalendar?.holiday(on: day, calendar: calendar)
        let absence = planner.budget.absences.first { $0.member == me && calendar.startOfDay(for: $0.from) <= day && day <= calendar.startOfDay(for: $0.to) }
        let today = calendar.isDateInToday(day)
        VStack(spacing: 3) {
            Text("\(calendar.component(.day, from: day))")
                .font(.system(size: 14, weight: today ? .bold : .regular, design: .rounded))
                .foregroundStyle(workday ? AnyShapeStyle(.primary) : AnyShapeStyle(Palette.red.opacity(0.75)))
            HStack(spacing: 3) {
                if holiday != nil { Circle().fill(Palette.orange).frame(width: 5, height: 5) }
                if payday || arrival != nil { Circle().fill(Palette.green).frame(width: 5, height: 5) }
            }
            .frame(height: 5)
        }
        .frame(maxWidth: .infinity, minHeight: 46)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(selected ? Palette.orange.opacity(0.22) : absence.map { $0.kind.color.opacity(0.16) } ?? (hovering ? Color.primary.opacity(0.05) : .clear))
        }
        .overlay {
            if today { RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Palette.orange, lineWidth: 1.5) }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .help(help(holiday: holiday, absence: absence))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(help(holiday: holiday, absence: absence)))
        .accessibilityAddTraits(.isButton)
    }

    private func help(holiday: String?, absence: Absence?) -> String {
        let currency = planner.budget.currency
        var parts = [day.formatted(.dateTime.weekday(.wide).day().month(.wide))]
        if let holiday { parts.append(String(localized: String.LocalizationValue(holiday))) }
        if payday { parts.append(String(localized: "Payday, about \(planner.expected(of: me, on: day).money(currency))")) }
        if let arrival { parts.append("\(String(localized: arrival.kind.titleValue)): \(arrival.amount.money(currency))") }
        if let absence { parts.append(String(localized: absence.kind.titleValue)) }
        return parts.joined(separator: "\n")
    }
}

/// Holidays in the next four months.
private struct Upcoming: View {
    let planner: Planner

    var body: some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let days = (0..<120).map { calendar.date(byAdding: .day, value: $0, to: today)! }
        // One row per holiday run (the New Year holidays are one entry).
        let named = days.compactMap { day in planner.budget.workCalendar?.holiday(on: day, calendar: calendar).map { (day, $0) } }
        let runs = named.reduce(into: [(from: Date, to: Date, name: String)]()) { runs, item in
            if let last = runs.last, last.name == item.1, calendar.dateComponents([.day], from: last.to, to: item.0).day == 1 {
                runs[runs.count - 1].to = item.0
            } else {
                runs.append((item.0, item.0, item.1))
            }
        }
        if !runs.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Holidays ahead").font(.headline)
                ForEach(Array(runs.prefix(6).enumerated()), id: \.offset) { _, run in
                    HStack {
                        Circle().fill(Palette.orange).frame(width: 7, height: 7)
                        Text(LocalizedStringKey(run.name))
                        Spacer()
                        Text(run.from == run.to ? run.from.formatted(.dateTime.weekday(.abbreviated).day().month(.wide))
                             : "\(run.from.formatted(.dateTime.day().month(.abbreviated))) – \(run.to.formatted(.dateTime.day().month(.abbreviated)))")
                            .foregroundStyle(.secondary).monospacedDigit()
                    }
                }
            }
            .card()
        }
    }
}

/// Planned and past time off this year and later, with what it brings.
private struct TimeOffList: View {
    @Environment(BudgetStore.self) private var store
    let planner: Planner
    let me: UUID

    var body: some View {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: Date())
        let yearStart = calendar.date(from: DateComponents(year: year))!
        let mine = planner.budget.absences.filter { $0.member == me && $0.to >= yearStart }.sorted { $0.from < $1.from }
        let currency = planner.budget.currency
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Time off").font(.headline)
                Spacer()
                if planner.budget.country == "RU" {
                    let used = mine.filter { $0.kind == .vacation && calendar.component(.year, from: $0.from) == year }
                        .reduce(0) { $0 + vacationDays($1) }
                    Text("Vacation in \(String(year)): \(used) of 28 days").font(.callout).foregroundStyle(.secondary)
                        .help("Russian employees get 28 calendar days a year; public holidays inside a vacation don't count.")
                }
            }
            if mine.isEmpty {
                Text("Plan vacations here to see vacation pay and smaller paydays ahead of time. Click a day in the calendar, then another.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            ForEach(mine) { absence in
                let arrivals = planner.extras(of: me, from: calendar.date(byAdding: .day, value: -20, to: absence.from)!,
                                              to: calendar.date(byAdding: .day, value: 60, to: absence.to)!).filter { $0.absence == absence.id }
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: absence.kind.icon).foregroundStyle(absence.kind.color).frame(width: 22)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(absence.kind.title)
                        Text("\(absence.from.formatted(.dateTime.day().month(.abbreviated))) – \(absence.to.formatted(.dateTime.day().month(.abbreviated).year()))")
                            .font(.caption).foregroundStyle(.secondary)
                        ForEach(arrivals, id: \.self) { arrival in
                            Text("\(Text(arrival.kind.title)): \(arrival.amount.money(currency)), \(arrival.date.formatted(.dateTime.day().month(.wide)))")
                                .font(.caption).foregroundStyle(Palette.green)
                        }
                    }
                    Spacer()
                    RemoveButton { store.budget?.absences.removeAll { $0.id == absence.id } }
                }
                .padding(.vertical, 4)
            }
        }
        .card()
    }

    private func vacationDays(_ absence: Absence) -> Int {
        let calendar = Calendar.current
        var n = 0, d = calendar.startOfDay(for: absence.from)
        while d <= absence.to {
            if !(planner.budget.workCalendar?.isVacationHoliday(d, calendar: calendar) ?? false) { n += 1 }
            d = calendar.date(byAdding: .day, value: 1, to: d)!
        }
        return n
    }
}

/// Kind and dates picked in the calendar, for the time-off sheet.
struct TimeOffDraft: Hashable {
    var kind: AbsenceKind
    var from: Date
    var to: Date
}

extension AbsenceKind {
    var color: Color {
        switch self {
        case .vacation: .blue
        case .sickLeave: .purple
        case .unpaid: .gray
        }
    }

    var titleValue: String.LocalizationValue {
        switch self {
        case .vacation: "Vacation"
        case .sickLeave: "Sick leave"
        case .unpaid: "Unpaid leave"
        }
    }
}

extension Arrival.Kind {
    var titleValue: String.LocalizationValue {
        switch self {
        case .vacationPay: "Vacation pay"
        case .sickPayEmployer: "Sick pay from work"
        case .sickPayFund: "Sick pay from the Social Fund"
        }
    }
}
