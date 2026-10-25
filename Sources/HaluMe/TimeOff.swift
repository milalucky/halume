import HaluMeCore
import SwiftUI

/// Which holidays count: weekends only, or a country's calendar (downloaded once, then kept).
struct WorkCalendarPicker: View {
    @Binding var calendar: WorkCalendar?
    @State private var countries: [CalendarLoader.Country] = []
    @State private var loading = false
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("Holidays", selection: Binding(get: { calendar?.country ?? "" }, set: { load($0) })) {
                Text("Weekends only").tag("")
                ForEach(list) { Text($0.name).tag($0.code) }
            }
            .labelsHidden()
            .disabled(loading)
            Group {
                if loading {
                    Text("Loading holidays…")
                } else if failed {
                    Text("Couldn't load the holidays. Check the connection and pick the country again.").foregroundStyle(Palette.red)
                } else if let calendar, !calendar.country.isEmpty {
                    Text(CalendarLoader.production.contains(calendar.country)
                         ? "Production calendar with moved days off, \(years(calendar))."
                         : "Public holidays, \(years(calendar)).")
                } else {
                    Text("Paydays move only off weekends, and holidays don't change the advance.")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .task { if countries.isEmpty { countries = await CalendarLoader.countries() } }
    }

    private var list: [CalendarLoader.Country] {
        let all = countries.isEmpty ? CalendarLoader.production.map(CalendarLoader.Country.init) : countries
        guard let code = calendar?.country, !code.isEmpty, !all.contains(where: { $0.code == code }) else { return all }
        return [CalendarLoader.Country(code: code)] + all
    }

    private func years(_ calendar: WorkCalendar) -> String {
        guard let first = calendar.years.first, let last = calendar.years.last else { return "" }
        return first == last ? "\(first)" : "\(first)–\(last)"
    }

    private func load(_ code: String) {
        guard !code.isEmpty else { calendar = nil; return }
        let year = Calendar.current.component(.year, from: Date())
        loading = true
        failed = false
        Task {
            do {
                calendar = try await CalendarLoader.load(code, years: [year, year + 1])
            } catch {
                // Russia works offline from the built-in years.
                if code == "RU" { calendar = .russia } else { failed = true }
            }
            loading = false
        }
    }
}

// MARK: Time off

/// Vacations, sick leave and unpaid days, with what they do to the next paydays.
struct TimeOffSheet: View {
    @Environment(BudgetStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var kind = AbsenceKind.vacation
    // A two-week vacation starting in two weeks: a typical first entry.
    @State private var from = Calendar.current.date(byAdding: .day, value: 14, to: Calendar.current.startOfDay(for: Date()))!
    @State private var to = Calendar.current.date(byAdding: .day, value: 27, to: Calendar.current.startOfDay(for: Date()))!
    @State private var percent = 100

    var body: some View {
        let budget = store.budget
        let me = store.me
        let currency = budget?.currency ?? "USD"
        let mine = (budget?.absences ?? []).filter { $0.member == me }.sorted { $0.from < $1.from }
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Time off").font(.title2.weight(.semibold))
                Text("Vacation pay comes early and the next paydays get smaller; sick pay comes later. HaluMe plans for both.")
                    .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }

            if !mine.isEmpty {
                VStack(spacing: 0) {
                    ForEach(mine) { absence in
                        HStack(spacing: 12) {
                            Image(systemName: absence.kind.icon).foregroundStyle(Palette.orange).frame(width: 22)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(absence.kind.title)
                                Text("\(absence.from.formatted(.dateTime.day().month(.abbreviated))) – \(absence.to.formatted(.dateTime.day().month(.abbreviated).year()))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            RemoveButton { store.budget?.absences.removeAll { $0.id == absence.id } }
                        }
                        .padding(.vertical, 6)
                    }
                }
                .card(padding: 14)
            }

            VStack(alignment: .leading, spacing: 14) {
                Picker("Kind", selection: $kind) {
                    ForEach(AbsenceKind.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                HStack(alignment: .top, spacing: 12) {
                    Field("First day") { DateField(date: $from) }
                    Field("Last day") { DateField(date: $to, range: from ... .distantFuture) }
                    if kind == .sickLeave {
                        Field("Paid", hint: "By your insurance record") {
                            Picker("Paid", selection: $percent) {
                                Text("100%").tag(100)
                                Text("80%").tag(80)
                                Text("60%").tag(60)
                            }
                            .labelsHidden()
                        }
                        .frame(width: 120, alignment: .leading)
                    }
                }
                if let preview = preview(currency: currency), !preview.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(preview, id: \.self) { line in
                            Label(line, systemImage: "arrow.right.circle").font(.callout)
                        }
                    }
                }
                if store.budget?.workCalendar == nil {
                    Text("Tip: pick your country's holidays in Settings for exact days.").font(.caption).foregroundStyle(.secondary)
                }
            }
            .card(padding: 18)

            HStack {
                Spacer()
                Button("Close") { dismiss() }.buttonStyle(SecondaryButtonStyle()).keyboardShortcut(.cancelAction)
                Button("Add") {
                    guard let me else { return }
                    store.budget?.absences.append(Absence(member: me, kind: kind, from: from, to: max(from, to), sickPercent: percent))
                }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(me == nil || to < from)
            }
        }
        .padding(28)
        .frame(width: 560)
    }

    /// What the new time off would change: money that comes apart and paydays that shrink.
    private func preview(currency: String) -> [String]? {
        guard var budget = store.budget, let me = store.me, to >= from else { return nil }
        let absence = Absence(member: me, kind: kind, from: from, to: to, sickPercent: percent)
        budget.absences.append(absence)
        let planner = Planner(budget)
        let horizon = Calendar.current.date(byAdding: .day, value: 75, to: to)!
        let start = Calendar.current.date(byAdding: .day, value: -20, to: from)!
        var lines: [String] = planner.extras(of: me, from: start, to: horizon).filter { $0.absence == absence.id }.map { arrival in
            let date = arrival.date.formatted(.dateTime.day().month(.wide))
            return switch arrival.kind {
            case .vacationPay: String(localized: "Vacation pay about \(arrival.amount.money(currency)) on \(date)")
            case .sickPayEmployer: String(localized: "First 3 days of sick pay, about \(arrival.amount.money(currency)), with the \(date) pay")
            case .sickPayFund: String(localized: "The rest of sick pay, about \(arrival.amount.money(currency)), from the Social Fund around \(date)")
            }
        }
        for payday in planner.paydays(of: me, from: from, to: horizon) {
            let usual = planner.usual(of: me, on: payday), now = planner.expected(of: me, on: payday)
            if now < usual {
                lines.append(String(localized: "Pay on \(payday.formatted(.dateTime.day().month(.wide))): about \(now.money(currency)) instead of \(usual.money(currency))"))
            }
        }
        return lines
    }
}

extension AbsenceKind {
    var title: LocalizedStringKey {
        switch self {
        case .vacation: "Vacation"
        case .sickLeave: "Sick leave"
        case .unpaid: "Unpaid leave"
        }
    }

    var icon: String {
        switch self {
        case .vacation: "airplane"
        case .sickLeave: "cross.case"
        case .unpaid: "calendar.badge.minus"
        }
    }
}

extension Arrival.Kind {
    var title: LocalizedStringKey {
        switch self {
        case .vacationPay: "Vacation pay"
        case .sickPayEmployer: "Sick pay from work"
        case .sickPayFund: "Sick pay from the Social Fund"
        }
    }
}
