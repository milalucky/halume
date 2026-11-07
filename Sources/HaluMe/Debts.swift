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
        let budget = planner.budget
        let left = debts.reduce(Decimal(0)) { $0 + budget.convert(planner.remaining(of: $1, before: tomorrow(today)), from: $1.currency) }
        let monthly = debts.reduce(Decimal(0)) { $0 + budget.convert($1.payment, from: $1.currency) }
        let free = debts.compactMap { planner.payoff(of: $0, balance: planner.remaining(of: $0, before: tomorrow(today)), payment: $0.payment, from: planner.nextDue(of: $0, from: today))?.date }.max()
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
        let payoff = planner.payoff(of: debt, balance: left, payment: debt.payment, from: planner.nextDue(of: debt, from: today))
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
                    OwnerBadge(owner: debt.owner).font(.caption).foregroundStyle(.secondary)
                    if debt.rate > 0 {
                        Text("\(debt.rate.formatted())%").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                    }
                }
                Text(left.money(debt.currency ?? currency))
                    .font(.system(size: 28, weight: .medium, design: .rounded))
                    .monospacedDigit()
                Bar(value: debt.original > 0 ? (1 - left / debt.original).double : 0)
                HStack {
                    Text(debt.biweeklyFrom == nil ? String(localized: "\(debt.payment.money(debt.currency ?? currency)) a month")
                                                  : String(localized: "\(debt.payment.money(debt.currency ?? currency)) every two weeks")).font(.caption)
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
            OwnerFields(owner: $debt.owner, split: $debt.split)
            HStack(alignment: .top, spacing: 12) {
                if debt.biweeklyFrom == nil { PaySlotField(slot: $debt.slot) }
                PayFromField(account: $debt.payFrom)
            }
            Field("What kind") {
                Picker("Kind", selection: $debt.kind) {
                    ForEach(DebtKind.allCases, id: \.self) { Label($0.title, systemImage: $0.icon).tag($0) }
                }
                .labelsHidden()
            }
            Field(LocalizedStringKey(debt.kind == .personal ? "Who you owe" : "Name")) {
                BoxTextField(LocalizedStringKey(debt.kind == .installment ? "e.g. Split for headphones" : "Name"), text: $debt.name)
            }
            HStack(alignment: .top, spacing: 12) {
                Field("Left to pay") { AmountField(amount: $left, code: $debt.currency, budgetCurrency: currency) }
                Field(LocalizedStringKey(debt.kind == .personal ? "Paying back" : debt.biweeklyFrom == nil ? "Each month" : "Each payment")) {
                    AmountField(amount: $debt.payment, currency: debt.currency ?? currency)
                }
            }
            HStack(alignment: .top, spacing: 12) {
                Field("How often") {
                    Picker("How often", selection: Binding(get: { debt.biweeklyFrom != nil },
                                                           set: { debt.biweeklyFrom = $0 ? (debt.biweeklyFrom ?? Date()) : nil })) {
                        Text("Every month").tag(false)
                        Text("Every two weeks").tag(true)
                    }
                    .labelsHidden()
                }
                .frame(width: 180, alignment: .leading)
                if let first = debt.biweeklyFrom {
                    Field("Next payment") {
                        DateField(date: Binding(get: { first }, set: { debt.biweeklyFrom = $0 }), range: Date.distantPast ... .distantFuture)
                    }
                    .frame(width: 220, alignment: .leading)
                } else {
                    Field("Due day") { DayPicker(day: $debt.day) }.frame(width: 100, alignment: .leading)
                }
            }
            HStack(alignment: .top, spacing: 12) {
                if debt.kind.hasInterest {
                    Field("Interest a year, %") { PercentField(value: $debt.rate) }
                }
                if debt.kind != .personal {
                    Field("Borrowed", hint: "For progress") { AmountField(amount: $debt.original, currency: debt.currency ?? currency) }
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
    /// After a one-off payment banks either keep the payment and shorten the term, or keep the term and lower the payment.
    @State private var lowerPayment = false
    /// Where the one-off comes from: nil is spending money, else an envelope.
    @State private var from: UUID?

    /// Everything the sheet shows, in the debt's currency; read fresh by the Record button too.
    private struct Plan {
        var left: Decimal, once: Decimal, more: Decimal, payment: Decimal, lowers: Bool
        var now: Payoff?, then: Payoff?
    }

    private func plan(_ planner: Planner, _ debt: Debt, today: Date) -> Plan {
        let left = planner.remaining(of: debt, before: tomorrow(today))
        let due = planner.nextDue(of: debt, from: today)
        let now = planner.payoff(of: debt, balance: left, payment: debt.payment, from: due)
        let once = min(self.once, left)
        let more = Decimal(extra).rounded(to: step(debt))
        let lowers = once > 0 && once < left && lowerPayment && now != nil
        let payment = lowers ? Payoff.annuity(balance: left - once, rate: debt.rate, count: now?.months ?? 0,
                                              perYear: debt.biweeklyFrom != nil ? 26 : 12)
                             : debt.payment
        let then = planner.payoff(of: debt, balance: left - once, payment: payment + more, from: due)
        return Plan(left: left, once: once, more: more, payment: payment, lowers: lowers, now: now, then: then)
    }

    private func step(_ debt: Debt) -> Decimal {
        max(1, up(debt.payment / 10, to: debt.payment >= 5_000 ? 500 : 10))
    }

    var body: some View {
        if let planner = store.planner, let debt = planner.budget.debts.first(where: { $0.id == debtID }) {
            let currency = debt.currency ?? planner.budget.currency
            let today = Date()
            let p = plan(planner, debt, today: today)
            let biweekly = debt.biweeklyFrom != nil
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
                    Stat(label: "Left", value: p.left.money(currency), big: true)
                    if let now = p.now {
                        Stat(label: "Paid off in", value: now.date.formatted(.dateTime.month(.wide).year()))
                        if debt.rate > 0 { Stat(label: "Interest ahead", value: now.interest.money(currency)) }
                    }
                }

                VStack(alignment: .leading, spacing: 14) {
                    Text("What if you pay more?").font(.headline)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(LocalizedStringKey(biweekly ? "Each payment" : "Each month"))
                            Spacer()
                            Text("\((p.payment + p.more).money(currency))  (+\(p.more.money(currency)))").monospacedDigit()
                        }
                        Slider(value: $extra, in: 0...max(debt.payment * 2, step(debt) * 2).double)
                    }
                    HStack(alignment: .bottom, spacing: 12) {
                        Field("Or pay once now") { AmountField(amount: $once, currency: currency) }.frame(width: 160, alignment: .leading)
                        if once > 0 {
                            Field("Pay from") {
                                Picker("Pay from", selection: $from) {
                                    Text("Spending money").tag(UUID?.none)
                                    ForEach(planner.budget.envelopes) { Text($0.name).tag(UUID?.some($0.id)) }
                                }
                                .labelsHidden()
                            }
                        }
                    }
                    if once > 0, once < p.left {
                        Picker("Then", selection: $lowerPayment) {
                            Text("Shorter term").tag(false)
                            Text("Smaller payment").tag(true)
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .help("Ask your bank which one it does; for a mortgage you can usually choose")
                    }
                    if let now = p.now, let then = p.then, p.more > 0 || p.once > 0 {
                        let months = now.months - then.months
                        let saved = now.interest - then.interest
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.once >= p.left ? String(localized: "Paid off with this payment")
                                     : String(localized: "Paid off by \(then.date.formatted(.dateTime.month(.wide).year()))"))
                                    .font(.body.weight(.semibold))
                                if p.lowers {
                                    Text("The payment becomes \((p.payment + p.more).money(currency)) instead of \(debt.payment.money(currency))")
                                        .font(.body.weight(.medium))
                                    if saved > 0 { Text("\(saved.money(currency)) less interest").foregroundStyle(.secondary) }
                                } else if months > 0 {
                                    Text(biweekly ? String(localized: "\(months) payments sooner")
                                         : saved > 0 ? String(localized: "\(months) months sooner, \(saved.money(currency)) less interest")
                                         : String(localized: "\(months) months sooner"))
                                        .foregroundStyle(.secondary)
                                } else if saved > 0 {
                                    Text("\(saved.money(currency)) less interest").foregroundStyle(.secondary)
                                }
                            }
                        } icon: {
                            Image(systemName: "arrow.down.forward.circle.fill").foregroundStyle(Palette.green).font(.title2)
                        }
                    } else if p.now == nil {
                        Text("The payment doesn't cover the interest, so this debt never ends. Pay more each month.")
                            .foregroundStyle(Palette.red)
                    }
                }
                .card(padding: 20)

                HStack {
                    Spacer()
                    Button("Close") { dismiss() }.buttonStyle(SecondaryButtonStyle()).keyboardShortcut(.cancelAction)
                    if p.more > 0 || p.once > 0 {
                        Button(p.once > 0 ? String(localized: "Record the \(p.once.money(currency)) Payment")
                               : biweekly ? String(localized: "Pay \((p.payment + p.more).money(currency)) each time")
                               : String(localized: "Pay \((p.payment + p.more).money(currency)) a month")) {
                            record(debt)
                        }
                        .help(LocalizedStringKey(p.once > 0 ? "Lowers what’s left by this payment and keeps the payment you chose" : ""))
                        .buttonStyle(PrimaryButtonStyle())
                        .keyboardShortcut(.defaultAction)
                    }
                }
            }
            .padding(28)
            .frame(width: 520, alignment: .leading)
        }
    }

    /// Recomputes from the current state: Return can fire a button closure from an earlier render.
    private func record(_ debt: Debt) {
        guard let planner = store.planner else { return }
        let today = Date()
        let p = plan(planner, debt, today: today)
        var changed = debt
        changed.payment = p.payment + p.more
        if p.once > 0 {
            changed.balance = p.left - p.once
            changed.asOf = tomorrow(today)
        }
        store.save(changed)
        // The one-off leaves spending money or a saving, so "a day" and stats see it.
        if p.once > 0 { store.spend(p.once, currency: debt.currency, note: debt.name, from: from, date: today) }
        dismiss()
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

    func rounded(toPlaces places: Int) -> Decimal {
        var value = self, result = Decimal()
        NSDecimalRound(&result, &value, places, .plain)
        return result
    }
}
