import HaluMeCore
import SwiftUI

struct SavingsPage: View {
    @Environment(BudgetStore.self) private var store

    var body: some View {
        Page(title: "Savings") {
            IconButton(icon: "slider.horizontal.3", label: "Edit savings") { store.sheet = .plan }
        } content: {
            if let planner = store.planner {
                if planner.budget.envelopes.isEmpty {
                    EmptyState(icon: "tray", title: "No savings yet",
                               text: "Add a goal, an emergency fund or a yearly expense, and part of each pay goes there first.")
                } else {
                    SavingsSummary(planner: planner, today: Date())
                    SavingsGrid(planner: planner, today: Date())
                    SavingsTips(planner: planner, today: Date())
                }
            }
        }
    }
}

private func tomorrow(_ date: Date) -> Date { Calendar.current.date(byAdding: .day, value: 1, to: date)! }

private struct SavingsSummary: View {
    let planner: Planner
    let today: Date

    var body: some View {
        let budget = planner.budget
        let total = budget.envelopes.reduce(Decimal(0)) { $0 + planner.balance(of: $1, before: tomorrow(today)) }
        let monthly = budget.envelopes.compactMap { planner.nextInterest(of: $0, from: today)?.amount }.reduce(0, +)
        HStack(alignment: .top, spacing: 32) {
            Stat(label: "Saved", value: total.money(budget.currency), big: true)
            if monthly > 0 {
                Stat(label: "Interest a month", value: "+" + monthly.money(budget.currency))
                Stat(label: "A year", value: "+" + (monthly * 12).money(budget.currency))
            }
        }
    }
}

struct SavingsGrid: View {
    @Environment(BudgetStore.self) private var store
    let planner: Planner
    let today: Date

    var body: some View {
        let budget = planner.budget
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 12)], spacing: 12) {
            ForEach(budget.envelopes.sorted { $0.priority < $1.priority }) { envelope in
                let balance = planner.balance(of: envelope, before: tomorrow(today))
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        Text(envelope.name).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                        Spacer()
                        Image(systemName: envelope.holding.icon).font(.caption).foregroundStyle(.tertiary)
                            .help(Text(envelope.holding.title))
                    }
                    Text(balance.money(budget.currency))
                        .font(.system(size: 26, weight: .medium, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    if case .target(let goal, _) = envelope.goal, goal > 0 {
                        Bar(value: (balance / goal).double)
                    }
                    Text(caption(envelope, currency: budget.currency)).font(.caption).foregroundStyle(.secondary)
                    if let interest = planner.nextInterest(of: envelope, from: today) {
                        Text("\(envelope.rate.formatted())% · +\(interest.amount.money(budget.currency)) \(interest.date.relativeDay)")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Palette.green)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .top)
                .card()
                .contextMenu {
                    Button("Take Money Out…") { store.sheet = .withdraw(envelope.id) }
                    Button("Edit…") { store.sheet = .plan }
                }
            }
        }
    }

    private func caption(_ envelope: Envelope, currency: String) -> String {
        switch envelope.goal {
        case .target(let goal, let by): String(localized: "of \(goal.money(currency)) by \(by.formatted(.dateTime.month(.wide).year()))")
        case .percent(let p): String(localized: "\(p.formatted())% of each pay")
        case .perPayday(let a): String(localized: "\(a.money(currency)) each payday")
        case .yearly(let a): String(localized: "\(a.money(currency)) a year")
        case .open: String(localized: "From leftovers")
        }
    }
}

/// Plain arithmetic on the user's own rates: no products, no advice.
private struct SavingsTips: View {
    let planner: Planner
    let today: Date

    var body: some View {
        let budget = planner.budget
        let best = budget.envelopes.filter { $0.holding.earnsInterest }.map(\.rate).max() ?? 0
        let idle = budget.envelopes.filter { !$0.holding.earnsInterest && $0.holding != .investments }
            .reduce(Decimal(0)) { $0 + planner.balance(of: $1, before: tomorrow(today)) }
        let tips: [String] = [
            best > 0 && idle > 0
                ? String(localized: "\(idle.money(budget.currency)) sits on cards or in cash. At \(best.formatted())%, like your best account, it would bring about \((Planner.yearlyInterest(on: idle, rate: best) / 12).rounded().money(budget.currency)) a month.")
                : nil,
            best > 0
                ? String(localized: "Every extra \(Decimal(50_000).money(budget.currency)) at \(best.formatted())% adds about \((Planner.yearlyInterest(on: 50_000, rate: best) / 12).rounded().money(budget.currency)) a month.")
                : nil,
        ].compactMap { $0 }
        if !tips.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(tips, id: \.self) { tip in
                    Label(tip, systemImage: "lightbulb").font(.callout).foregroundStyle(.secondary)
                }
            }
            .card()
        }
    }
}

extension Holding {
    var title: LocalizedStringKey {
        switch self {
        case .card: "On a card"
        case .cash: "Cash"
        case .savingsAccount: "Savings account"
        case .deposit: "Deposit"
        case .investments: "Investments"
        }
    }

    var icon: String {
        switch self {
        case .card: "creditcard"
        case .cash: "banknote"
        case .savingsAccount: "percent"
        case .deposit: "lock"
        case .investments: "chart.line.uptrend.xyaxis"
        }
    }
}

/// Where an envelope's money lives, and its interest.
struct HoldingFields: View {
    @Binding var envelope: Envelope

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Field("Kept") {
                Picker("Kept", selection: $envelope.holding) {
                    ForEach(Holding.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                .labelsHidden()
            }
            .frame(width: 170)
            if envelope.holding.earnsInterest {
                Field("Rate, % a year") { TextField("12", value: $envelope.rate, format: .number) }.frame(width: 100)
                Field("Paid on day") { DayPicker(day: $envelope.interestDay) }.frame(width: 90)
                if envelope.holding == .deposit {
                    Field("Ends") {
                        DatePicker("Ends", selection: Binding(get: { envelope.maturity ?? Date() }, set: { envelope.maturity = $0 }),
                                   in: Date()..., displayedComponents: .date)
                            .labelsHidden()
                    }
                }
            }
            Spacer(minLength: 0)
        }
        if envelope.holding.earnsInterest {
            Toggle("Interest is paid to my card", isOn: $envelope.interestToCard)
                .help("Otherwise it stays in the account and grows the balance")
        }
    }
}

struct WithdrawSheet: View {
    @Environment(BudgetStore.self) private var store
    let envelopeID: UUID
    @State private var amount: Decimal = 0
    @State private var note = ""

    var body: some View {
        let envelope = store.budget?.envelopes.first { $0.id == envelopeID }
        let balance = envelope.flatMap { e in store.planner?.balance(of: e, before: tomorrow(Date())) } ?? 0
        let currency = store.budget?.currency ?? "USD"
        SheetFrame(title: "Take money out",
                   subtitle: "From \(envelope?.name ?? ""), \(balance.money(currency)) now. It shows up in your stats, and goals with a date catch up.",
                   action: "Take Out", canSave: amount > 0 && amount <= balance,
                   save: { store.withdraw(amount, from: envelopeID, note: note) }) {
            Field("Amount") { AmountField(amount: $amount, currency: currency) }
            Field("What for", hint: "Optional") { TextField("e.g. Car repair", text: $note) }
        }
    }
}
