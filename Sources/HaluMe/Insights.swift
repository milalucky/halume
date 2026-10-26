import HaluMeCore
import SwiftUI

/// "What if": try a pay change, a new monthly cost or saving, or months without pay — nothing is saved.
struct WhatIfSheet: View {
    @Environment(BudgetStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var payChange: Double = 0
    @State private var cost: Decimal = 0
    @State private var saving: Decimal = 0
    @State private var monthsWithout = 0

    var body: some View {
        if let planner = store.planner, let me = store.me {
            let currency = planner.budget.currency
            let scenario = planner.scenario(member: me, payChange: Decimal(payChange.rounded()), newMonthlyCost: cost, newMonthlySaving: saving)
            let now = numbers(planner, me), then = numbers(scenario, me)
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("What if…").font(.title2.weight(.semibold))
                    Text("Try a change and see what it does to your plan. Nothing is saved.").foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Pay changes by")
                            Spacer()
                            Text("\(payChange > 0 ? "+" : "")\(Int(payChange.rounded()))%").monospacedDigit().font(.body.weight(.medium))
                        }
                        Slider(value: $payChange, in: -50...50, step: 5)
                            .accessibilityLabel(Text("Pay change, percent"))
                    }
                    HStack(alignment: .top, spacing: 12) {
                        Field("New cost a month", hint: "Rent, a loan, a car") { AmountField(amount: $cost, currency: currency) }
                        Field("New saving a month", hint: "A goal, a bigger cushion") { AmountField(amount: $saving, currency: currency) }
                    }
                    Stepper(value: $monthsWithout, in: 0...12) {
                        Text(monthsWithout == 0 ? String(localized: "Months without pay: none")
                                                : String(localized: "Months without pay: \(monthsWithout)"))
                    }
                }
                .card(padding: 18)

                VStack(spacing: 10) {
                    Compare(label: "A day to spend", now: now.perDay.money(currency), then: then.perDay.money(currency), better: then.perDay >= now.perDay)
                    Compare(label: "Free money a month", now: now.monthly.money(currency), then: then.monthly.money(currency), better: then.monthly >= now.monthly)
                    Compare(label: "Savings would last", now: months(now.runway), then: months(then.runway), better: then.runway >= now.runway)
                    if monthsWithout > 0 {
                        let runway = scenario.runway(of: me, on: Date())
                        let left = runway.savings - runway.monthlyNeed * Decimal(monthsWithout)
                        Label(left >= 0
                              ? String(localized: "After \(monthsWithout) months without pay you'd still have about \(left.money(currency)).")
                              : String(localized: "Savings run out before then: about \((-left).money(currency)) short."),
                              systemImage: left >= 0 ? "checkmark.circle" : "exclamationmark.triangle")
                            .foregroundStyle(left >= 0 ? Palette.green : Palette.red)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if then.perDay <= 0 {
                        Label("The pay wouldn't cover the plan: something has to give.", systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Palette.red).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .card(padding: 18)

                HStack {
                    Spacer()
                    Button("Done") { dismiss() }.buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction)
                }
            }
            .padding(28)
            .frame(width: 560)
        }
    }

    private func numbers(_ planner: Planner, _ me: UUID) -> (perDay: Decimal, monthly: Decimal, runway: Decimal) {
        let today = Date()
        guard let start = planner.current(on: today, of: me) else { return (0, 0, 0) }
        let plan = planner.plan(for: me, on: start)
        let days = max(1, Calendar.current.dateComponents([.day], from: start, to: plan.next).day ?? 1)
        let perDay = (plan.free / Decimal(days)).rounded(.down)
        return (perDay, (plan.free * 365 / 12 / Decimal(days)).rounded(.down), planner.runway(of: me, on: today).months)
    }

    private func months(_ value: Decimal) -> String {
        String(localized: "\(value.double.formatted(.number.precision(.fractionLength(1)))) months")
    }

    private struct Compare: View {
        let label: LocalizedStringKey
        let now: String
        let then: String
        let better: Bool

        var body: some View {
            HStack {
                Text(label).foregroundStyle(.secondary)
                Spacer()
                Text(now).monospacedDigit().foregroundStyle(.secondary)
                Image(systemName: "arrow.right").font(.caption).foregroundStyle(.tertiary)
                Text(then).monospacedDigit().font(.body.weight(.semibold))
                    .foregroundStyle(now == then ? AnyShapeStyle(.primary) : better ? AnyShapeStyle(Palette.green) : AnyShapeStyle(Palette.red))
                    .frame(minWidth: 110, alignment: .trailing)
            }
        }
    }
}

/// What the last pay period did, shown once a new pay arrives.
struct RecapSheet: View {
    @Environment(BudgetStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        if let planner = store.planner, let me = store.me, let recap = planner.recap(of: me, before: Date()) {
            let currency = planner.budget.currency
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Your last pay").font(.title2.weight(.semibold))
                    Text("\(recap.start.formatted(.dateTime.day().month(.wide))) – \(Calendar.current.date(byAdding: .day, value: -1, to: recap.end)!.formatted(.dateTime.day().month(.wide)))")
                        .foregroundStyle(.secondary)
                }
                RecapNumbers(recap: recap, currency: currency)
                if !recap.goals.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Savings that grew").font(.headline)
                        ForEach(recap.goals.prefix(5), id: \.name) { goal in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(goal.name)
                                    Spacer()
                                    Text("\(goal.after - goal.before >= 0 ? "+" : "")\((goal.after - goal.before).money(currency))")
                                        .monospacedDigit().foregroundStyle(goal.after >= goal.before ? Palette.green : Palette.red)
                                }
                                if let target = goal.target, target > 0 {
                                    Bar(value: min(1, (goal.after / target).double))
                                    Text("\(goal.after.money(currency)) of \(target.money(currency))").font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .card(padding: 18)
                }
                HStack {
                    Spacer()
                    Button("Done") { dismiss() }.buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction)
                }
            }
            .padding(28)
            .frame(width: 520)
        }
    }
}

struct RecapNumbers: View {
    let recap: Recap
    let currency: String

    var body: some View {
        StatRow {
            Stat(label: "Put aside", value: recap.saved.money(currency))
            Stat(label: "Bills paid", value: recap.paid.money(currency))
            if let leftover = recap.leftover { Stat(label: "Left over", value: leftover.money(currency)) }
        }
        if recap.savingPlanned > recap.saved || recap.unplanned > 0 || recap.extra > 0 || recap.takenOut > 0 {
            VStack(alignment: .leading, spacing: 4) {
                if recap.savingPlanned > recap.saved {
                    Text("\((recap.savingPlanned - recap.saved).money(currency)) of planned savings not moved").foregroundStyle(.secondary)
                }
                if recap.extra > 0 { Text("+\(recap.extra.money(currency)) came in outside pay").foregroundStyle(Palette.green) }
                if recap.unplanned > 0 { Text("\(recap.unplanned.money(currency)) of unplanned expenses").foregroundStyle(.secondary) }
                if recap.takenOut > 0 { Text("\(recap.takenOut.money(currency)) taken out of savings").foregroundStyle(.secondary) }
            }
            .font(.callout)
        }
    }
}

/// On Today, once per new pay: a short look back at the last one.
struct RecapCard: View {
    @Environment(BudgetStore.self) private var store
    let recap: Recap
    let currency: String
    let dismissed: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("How your last pay went", systemImage: "sparkles").font(.headline)
                Spacer()
                IconButton(icon: "xmark", label: "Hide until the next pay") { dismissed() }
            }
            RecapNumbers(recap: recap, currency: currency)
            if let best = recap.goals.first, best.after > best.before {
                Text("\(best.name) grew by \((best.after - best.before).money(currency)).").font(.callout)
            }
            Button("See Details…") { store.sheet = .recap }.buttonStyle(.borderless)
        }
        .card()
    }
}
