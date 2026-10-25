import HaluMeCore
import SwiftUI

struct DebtsPage: View {
    @Environment(BudgetStore.self) private var store

    var body: some View {
        Page(title: "Debts") {
            Button { store.sheet = .debt(newDebt()) } label: { Label("Add debt", systemImage: "plus") }
                .buttonStyle(SecondaryButtonStyle())
        } content: {
            if let planner = store.planner {
                let budget = planner.budget
                let today = Date()
                let open = budget.debts.filter { planner.remaining(of: $0, before: tomorrow(today)) > 0 }
                let closed = budget.debts.filter { planner.remaining(of: $0, before: tomorrow(today)) <= 0 }
                if budget.debts.isEmpty {
                    EmptyState(icon: "checkmark.seal", title: "No debts",
                               text: "Add an instalment plan, a loan, a mortgage or money you owe someone. Payments go into each paycheck plan.")
                } else {
                    Summary(planner: planner, debts: open, today: today)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 12)], spacing: 12) {
                        ForEach(open) { DebtCard(debt: $0, planner: planner, today: today) }
                    }
                    if !closed.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Paid off").font(.headline)
                            ForEach(closed) { debt in
                                HStack {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.green)
                                    Text(debt.name)
                                    Spacer()
                                    Text(debt.original.money(budget.currency)).foregroundStyle(.secondary).monospacedDigit()
                                }
                                .contextMenu { Button("Delete", role: .destructive) { store.deleteDebt(debt.id) } }
                            }
                        }
                        .card()
                    }
                }
            }
        }
    }

    private func newDebt() -> Debt {
        Debt(owner: .member(store.me ?? UUID()), name: "", kind: .installment, balance: 0, payment: 0, day: 1)
    }
}

private func tomorrow(_ date: Date) -> Date { Calendar.current.date(byAdding: .day, value: 1, to: date)! }

private struct Summary: View {
    let planner: Planner
    let debts: [Debt]
    let today: Date

    var body: some View {
        let currency = planner.budget.currency
        let left = debts.reduce(Decimal(0)) { $0 + planner.remaining(of: $1, before: tomorrow(today)) }
        let monthly = debts.reduce(Decimal(0)) { $0 + $1.payment }
        let free = debts.compactMap { planner.payoff(balance: planner.remaining(of: $0, before: tomorrow(today)), rate: $0.rate, payment: $0.payment, from: planner.nextDue(of: $0, from: today))?.date }.max()
        StatRow {
            Stat(label: "Left to pay", value: left.money(currency), big: true)
            Stat(label: "Each month", value: monthly.money(currency))
            if let free {
                Stat(label: "Debt-free", value: free.formatted(.dateTime.month(.wide).year()))
            }
        }
    }
}

struct Stat: View {
    let label: LocalizedStringKey
    let value: String
    var big = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            Text(value)
                .font(.system(size: big ? 40 : 22, weight: .medium, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.5)
        }
        .accessibilityElement(children: .combine)
    }
}

/// Big numbers in a row when they fit, otherwise two per line.
struct StatRow<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 32) { content }.fixedSize(horizontal: true, vertical: false)
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .topLeading), GridItem(.flexible(), alignment: .topLeading)],
                      alignment: .leading, spacing: 18) { content }
        }
    }
}

private struct DebtCard: View {
    @Environment(BudgetStore.self) private var store
    let debt: Debt
    let planner: Planner
    let today: Date
    @State private var hovering = false

    var body: some View {
        let currency = planner.budget.currency
        let left = planner.remaining(of: debt, before: tomorrow(today))
        let payoff = planner.payoff(balance: left, rate: debt.rate, payment: debt.payment, from: planner.nextDue(of: debt, from: today))
        Button { store.sheet = .payoff(debt.id) } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: debt.kind.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Palette.orange)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Palette.orange.opacity(0.14)))
                    VStack(alignment: .leading, spacing: 0) {
                        Text(debt.name).font(.body.weight(.semibold))
                        Text(debt.kind.title).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if debt.rate > 0 {
                        Text("\(debt.rate.formatted())%").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    }
                }
                Text(left.money(currency))
                    .font(.system(size: 28, weight: .medium, design: .rounded))
                    .monospacedDigit()
                Bar(value: debt.original > 0 ? (1 - left / debt.original).double : 0)
                HStack {
                    Text("\(debt.payment.money(currency)) a month").font(.caption)
                    Spacer()
                    if let payoff {
                        Text("until \(payoff.date.formatted(.dateTime.month(.abbreviated).year()))").font(.caption)
                    } else {
                        Text("Payment doesn't cover interest").font(.caption).foregroundStyle(Palette.red)
                    }
                }
                .foregroundStyle(.secondary)
            }
            .card()
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.primary.opacity(hovering ? 0.12 : 0)))
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help("See how to pay it off sooner")
        .contextMenu {
            Button("Edit…") { store.sheet = .debt(debt) }
            Button("Delete", role: .destructive) { store.deleteDebt(debt.id) }
        }
    }
}

extension DebtKind {
    var title: LocalizedStringKey {
        switch self {
        case .installment: "Instalments"
        case .loan: "Loan"
        case .mortgage: "Mortgage"
        case .creditCard: "Credit card"
        case .personal: "Owed to a person"
        }
    }

    var icon: String {
        switch self {
        case .installment: "square.split.2x1"
        case .loan: "banknote"
        case .mortgage: "house"
        case .creditCard: "creditcard"
        case .personal: "person"
        }
    }

    var hasInterest: Bool { self == .loan || self == .mortgage || self == .creditCard }
}

// MARK: Editor

struct DebtEditor: View {
    @Environment(BudgetStore.self) private var store
    @State var debt: Debt
    @State private var left: Decimal = 0

    var body: some View {
        let currency = store.budget?.currency ?? "USD"
        let isNew = !(store.budget?.debts.contains { $0.id == debt.id } ?? false)
        SheetFrame(title: LocalizedStringKey(isNew ? "New debt" : "Edit debt"),
                   subtitle: "Payments go into the paycheck before each due day. When nothing is left, it's marked paid off.",
                   action: LocalizedStringKey(isNew ? "Add" : "Save"),
                   canSave: !debt.name.trimmingCharacters(in: .whitespaces).isEmpty && left > 0 && debt.payment > 0,
                   save: save) {
            Field("What kind") {
                Picker("Kind", selection: $debt.kind) {
                    ForEach(DebtKind.allCases, id: \.self) { Label($0.title, systemImage: $0.icon).tag($0) }
                }
                .labelsHidden()
            }
            Field(LocalizedStringKey(debt.kind == .personal ? "Who you owe" : "Name")) {
                TextField(LocalizedStringKey(debt.kind == .installment ? "e.g. Split for headphones" : "Name"), text: $debt.name)
            }
            HStack(alignment: .top, spacing: 12) {
                Field("Left to pay") { AmountField(amount: $left, currency: currency) }
                Field(LocalizedStringKey(debt.kind == .personal ? "Paying back" : "Each month")) { AmountField(amount: $debt.payment, currency: currency) }
            }
            HStack(alignment: .top, spacing: 12) {
                Field("Due day") { DayPicker(day: $debt.day) }.frame(width: 100, alignment: .leading)
                if debt.kind.hasInterest {
                    Field("Interest a year, %") { PercentField(value: $debt.rate) }
                }
                if debt.kind != .personal {
                    Field("Borrowed", hint: "For progress") { AmountField(amount: $debt.original, currency: currency) }
                }
            }
            if !isNew {
                Button("Delete Debt", role: .destructive) {
                    store.deleteDebt(debt.id)
                    store.sheet = nil
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Palette.red)
            }
        }
        .onAppear {
            left = store.planner?.remaining(of: debt, before: tomorrow(Date())) ?? debt.balance
            if debt.kind == .personal, debt.payment == 0 { debt.payment = left }
        }
        .onChange(of: debt.kind) { _, kind in if !kind.hasInterest { debt.rate = 0 } }
    }

    private func save() {
        var debt = debt
        // The amount entered is what's left today; payments marked from tomorrow on come off it.
        debt.balance = left
        debt.asOf = tomorrow(Date())
        if debt.original < left { debt.original = left }
        store.save(debt)
    }
}

// MARK: Payoff

/// "What if I pay more?": months and interest saved by a bigger payment or a one-off.
struct PayoffSheet: View {
    @Environment(BudgetStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let debtID: UUID
    @State private var extra: Double = 0
    @State private var once: Decimal = 0

    var body: some View {
        if let planner = store.planner, let debt = planner.budget.debts.first(where: { $0.id == debtID }) {
            let currency = planner.budget.currency
            let today = Date()
            let left = planner.remaining(of: debt, before: tomorrow(today))
            let due = planner.nextDue(of: debt, from: today)
            let now = planner.payoff(balance: left, rate: debt.rate, payment: debt.payment, from: due)
            let step = max(Decimal(500), up(debt.payment / 10, to: 500))
            let more = Decimal(extra).rounded(to: step)
            let then = planner.payoff(balance: max(0, left - once), rate: debt.rate, payment: debt.payment + more, from: due)
            VStack(alignment: .leading, spacing: 22) {
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(debt.name).font(.title2.weight(.semibold))
                        Text(debt.kind.title).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Edit…") { store.sheet = .debt(debt) }.buttonStyle(SecondaryButtonStyle())
                }
                StatRow {
                    Stat(label: "Left", value: left.money(currency), big: true)
                    if let now {
                        Stat(label: "Paid off in", value: now.date.formatted(.dateTime.month(.wide).year()))
                        if debt.rate > 0 { Stat(label: "Interest ahead", value: now.interest.money(currency)) }
                    }
                }

                VStack(alignment: .leading, spacing: 14) {
                    Text("What if you pay more?").font(.headline)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Each month")
                            Spacer()
                            Text("\((debt.payment + more).money(currency))  (+\(more.money(currency)))").monospacedDigit()
                        }
                        Slider(value: $extra, in: 0...max(debt.payment * 2, 1_000).double)
                    }
                    Field("Or pay once now") { AmountField(amount: $once, currency: currency) }.frame(width: 200, alignment: .leading)
                    if let now, let then, more > 0 || once > 0 {
                        let months = now.months - then.months
                        let saved = now.interest - then.interest
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Paid off by \(then.date.formatted(.dateTime.month(.wide).year()))").font(.body.weight(.semibold))
                                Text(saved > 0 ? String(localized: "\(months) months sooner, \(saved.money(currency)) less interest")
                                                : String(localized: "\(months) months sooner"))
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "arrow.down.forward.circle.fill").foregroundStyle(Palette.green).font(.title2)
                        }
                    } else if now == nil {
                        Text("The payment doesn't cover the interest, so this debt never ends. Pay more each month.")
                            .foregroundStyle(Palette.red)
                    }
                }
                .card(padding: 20)

                HStack {
                    Spacer()
                    Button("Close") { dismiss() }.buttonStyle(SecondaryButtonStyle()).keyboardShortcut(.cancelAction)
                    if more > 0 {
                        Button("Pay \((debt.payment + more).money(currency)) a month") {
                            var changed = debt
                            changed.payment += more
                            store.save(changed)
                            dismiss()
                        }
                        .buttonStyle(PrimaryButtonStyle())
                        .keyboardShortcut(.defaultAction)
                    }
                }
            }
            .padding(28)
            .frame(width: 520, alignment: .leading)
        }
    }

    private func up(_ value: Decimal, to step: Decimal) -> Decimal {
        (value / step).rounded(.up) * step
    }
}

extension Decimal {
    func rounded(_ mode: NSDecimalNumber.RoundingMode = .plain) -> Decimal {
        var value = self, result = Decimal()
        NSDecimalRound(&result, &value, 0, mode)
        return result
    }

    func rounded(to step: Decimal) -> Decimal { (self / step).rounded() * step }
}
