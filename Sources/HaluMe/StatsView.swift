import AppKit
import Charts
import HaluMeCore
import SwiftUI

struct StatsPage: View {
    private enum Range: String, CaseIterable, Identifiable {
        case month, halfYear, year, fiveYears
        var id: Self { self }

        var title: LocalizedStringKey {
            switch self {
            case .month: "Month"
            case .halfYear: "6 months"
            case .year: "Year"
            case .fiveYears: "5 years"
            }
        }

        var months: Int {
            switch self {
            case .month: 1
            case .halfYear: 6
            case .year: 12
            case .fiveYears: 60
            }
        }

        var grouping: Grouping {
            switch self {
            case .month: .payday
            case .halfYear, .year: .month
            case .fiveYears: .quarter
            }
        }
    }

    @Environment(BudgetStore.self) private var store
    @State private var range = Range.year

    var body: some View {
        let today = Date()
        let from = Calendar.current.date(byAdding: .month, value: -range.months, to: today)!
        let periods = store.planner.flatMap { p in store.me.map { p.history(of: $0, from: from, to: today) } } ?? []
        Page(title: "Stats") {
            IconButton(icon: "square.and.arrow.up", label: "Export to CSV") { export(periods) }
        } content: {
            Picker("Range", selection: $range) {
                ForEach(Range.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 420)
            .frame(maxWidth: .infinity, alignment: .leading)

            if let planner = store.planner, !periods.isEmpty {
                let buckets = planner.group(periods, by: range.grouping)
                let total = periods.dropFirst().reduce(periods[0], +)
                let currency = planner.budget.currency
                Totals(total: total, currency: currency)
                ChartCard(title: "Income", subtitle: "Dashed line: what you expected") {
                    IncomeChart(buckets: buckets, grouping: range.grouping)
                }
                ChartCard(title: "Pay against plan", subtitle: LocalizedStringKey(payTrend(periods, currency: currency))) {
                    PayDiffChart(buckets: buckets, grouping: range.grouping)
                }
                ChartCard(title: "Where pay went", subtitle: nil) {
                    SplitChart(buckets: buckets, grouping: range.grouping)
                }
                ChartCard(title: "Saved and taken out", subtitle: nil) {
                    SavedChart(buckets: buckets, grouping: range.grouping)
                }
                Moments(periods: periods, planner: planner)
            } else {
                EmptyState(icon: "chart.bar", title: "Nothing to show yet",
                           text: "Stats build up from your paydays: what came in, what you moved, what was left.")
            }
        }
    }

    /// "On average 4% above plan; less than planned 3 times of 12."
    private func payTrend(_ periods: [PeriodStats], currency: String) -> String {
        let expected = periods.reduce(Decimal(0)) { $0 + $1.expected }
        guard expected > 0 else { return String(localized: "Green: more than planned, orange: less.") }
        let diff = periods.reduce(Decimal(0)) { $0 + $1.pay - $1.expected }
        let percent = Int((diff / expected * 100).rounded().double)
        let short = periods.filter { $0.pay < $0.expected }.count
        let average = percent == 0 ? String(localized: "On average as planned")
            : percent > 0 ? String(localized: "On average \(percent)% above plan") : String(localized: "On average \(-percent)% below plan")
        return String(localized: "\(average); less than planned \(short) times of \(periods.count).")
    }

    private func export(_ periods: [PeriodStats]) {
        guard let planner = store.planner else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "HaluMe \(Date().formatted(.iso8601.year().month().day())).csv"
        panel.allowedContentTypes = [.commaSeparatedText]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try planner.csv(periods).write(to: url, atomically: true, encoding: .utf8)
        } catch {
            NSAlert(error: error).runModal()
        }
    }
}

private struct Totals: View {
    let total: PeriodStats
    let currency: String

    var body: some View {
        let planned = total.savingPlanned + total.debtPlanned
        let done = total.saved + total.debtPaid
        StatRow {
            Stat(label: "Earned", value: total.income.money(currency), big: true)
            Stat(label: "Saved", value: (total.saved - total.withdrawn).money(currency))
            Stat(label: "Debts paid", value: total.debtPaid.money(currency))
            if planned > 0 {
                Stat(label: "On plan", value: (done / planned).double.formatted(.percent.precision(.fractionLength(0))))
            }
        }
    }
}

private struct ChartCard<Content: View>: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                if let subtitle { Text(subtitle).font(.caption).foregroundStyle(.secondary) }
            }
            content.frame(height: 180)
        }
        .card(padding: 20)
    }
}

private func unit(_ grouping: Grouping) -> Calendar.Component {
    switch grouping {
    case .payday: .day
    case .month: .month
    case .quarter: .quarter
    }
}

private struct IncomeChart: View {
    let buckets: [PeriodStats]
    let grouping: Grouping

    var body: some View {
        Chart(buckets) { b in
            BarMark(x: .value("Date", b.date, unit: unit(grouping)), y: .value("Income", b.income.double))
                .foregroundStyle(b.income < b.expected * 95 / 100 ? Palette.orange.opacity(0.45) : Palette.orange)
                .cornerRadius(4)
            LineMark(x: .value("Date", b.date, unit: unit(grouping)), y: .value("Expected", b.expected.double))
                .foregroundStyle(Color.primary.opacity(0.45))
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
                .interpolationMethod(.stepCenter)
        }
        .chartYAxis { AxisMarks(position: .leading) { _ in AxisGridLine().foregroundStyle(.quaternary); AxisValueLabel() } }
        .chartXAxis { AxisMarks { _ in AxisValueLabel(format: grouping == .payday ? .dateTime.day().month(.abbreviated) : .dateTime.month(.abbreviated)) } }
    }
}

/// How much each pay was above or below what was planned.
private struct PayDiffChart: View {
    let buckets: [PeriodStats]
    let grouping: Grouping

    var body: some View {
        Chart(buckets) { b in
            let diff = (b.pay - b.expected).double
            BarMark(x: .value("Date", b.date, unit: unit(grouping)), y: .value("Difference", diff))
                .foregroundStyle(diff >= 0 ? Palette.green : Palette.orange)
                .cornerRadius(4)
            RuleMark(y: .value("Plan", 0)).foregroundStyle(Color.primary.opacity(0.3))
        }
        .chartYAxis { AxisMarks(position: .leading) { _ in AxisGridLine().foregroundStyle(.quaternary); AxisValueLabel() } }
        .chartXAxis { AxisMarks { _ in AxisValueLabel(format: grouping == .payday ? .dateTime.day().month(.abbreviated) : .dateTime.month(.abbreviated)) } }
        .accessibilityLabel(Text("Pay above or below plan"))
    }
}

private struct SplitChart: View {
    let buckets: [PeriodStats]
    let grouping: Grouping

    var body: some View {
        let rows: [(Date, String, Double)] = buckets.flatMap { b in [
            (b.date, String(localized: "Bills"), b.bills.double),
            (b.date, String(localized: "Debts"), b.debtPlanned.double),
            (b.date, String(localized: "Savings"), b.savingPlanned.double),
            (b.date, String(localized: "Free"), b.free.double),
        ] }
        Chart(rows, id: \.1) { date, kind, value in
            BarMark(x: .value("Date", date, unit: unit(grouping)), y: .value("Amount", value))
                .foregroundStyle(by: .value("Kind", kind))
        }
        .chartForegroundStyleScale([
            String(localized: "Bills"): Color.gray.opacity(0.55),
            String(localized: "Debts"): Palette.red.opacity(0.75),
            String(localized: "Savings"): Palette.green,
            String(localized: "Free"): Palette.orange,
        ])
        .chartLegend(position: .top, alignment: .leading)
        .chartYAxis { AxisMarks(position: .leading) { _ in AxisGridLine().foregroundStyle(.quaternary); AxisValueLabel() } }
    }
}

private struct SavedChart: View {
    let buckets: [PeriodStats]
    let grouping: Grouping

    var body: some View {
        Chart(buckets) { b in
            BarMark(x: .value("Date", b.date, unit: unit(grouping)), y: .value("Saved", b.saved.double))
                .foregroundStyle(Palette.green)
                .cornerRadius(4)
            if b.withdrawn > 0 {
                BarMark(x: .value("Date", b.date, unit: unit(grouping)), y: .value("Taken out", -b.withdrawn.double))
                    .foregroundStyle(Palette.red)
                    .cornerRadius(4)
            }
            RuleMark(y: .value("Zero", 0)).foregroundStyle(.tertiary)
        }
        .chartYAxis { AxisMarks(position: .leading) { _ in AxisGridLine().foregroundStyle(.quaternary); AxisValueLabel() } }
    }
}

/// The few things worth noticing, newest first.
private struct Moments: View {
    let periods: [PeriodStats]
    let planner: Planner

    var body: some View {
        let currency = planner.budget.currency
        let usual = median(periods.map(\.income))
        var items: [(Date, String, String, Color)] = []
        for p in periods {
            let date = p.date.formatted(.dateTime.day().month(.wide))
            if usual > 0, p.income < usual * 90 / 100 {
                let drop = Int(((usual - p.income) / usual * 100).double.rounded())
                items.append((p.date, "arrow.down.right", String(localized: "\(date): pay was \(drop)% lower than usual"), Palette.orange))
            } else if usual > 0, p.income > usual * 115 / 100 {
                items.append((p.date, "arrow.up.right", String(localized: "\(date): \((p.income - usual).money(currency)) more than usual"), Palette.green))
            }
            if p.missed > 0 {
                items.append((p.date, "exclamationmark.circle", String(localized: "\(date): \(p.missed.money(currency)) planned for savings or debts wasn't moved"), Palette.red))
            }
        }
        for w in planner.budget.withdrawals {
            let name = planner.budget.envelopes.first { $0.id == w.envelope }?.name ?? ""
            let what = w.note.isEmpty ? "" : " — \(w.note)"
            items.append((w.date, "arrow.uturn.backward", String(localized: "\(w.date.formatted(.dateTime.day().month(.wide))): took \(w.amount.money(currency)) from \(name)\(what)"), Palette.red))
        }
        let start = periods.first?.date ?? .distantPast
        let shown = items.filter { $0.0 >= start }.sorted { $0.0 > $1.0 }.prefix(8)
        return Group {
            if !shown.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Worth noticing").font(.headline)
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(Array(shown.enumerated()), id: \.offset) { _, item in
                            Label { Text(item.2) } icon: { Image(systemName: item.1).foregroundStyle(item.3) }
                        }
                    }
                    .card()
                }
            }
        }
    }

    private func median(_ values: [Decimal]) -> Decimal {
        let sorted = values.sorted()
        return sorted.isEmpty ? 0 : sorted[sorted.count / 2]
    }
}
