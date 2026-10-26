import HaluMeCore
import SwiftUI

extension BudgetStore {
    func add(_ inflow: Inflow) { budget?.inflows.append(inflow) }

    /// Unplanned spending: out of a saving (a withdrawal) or out of the spending money.
    func spend(_ amount: Decimal, currency: String?, note: String, from envelope: UUID?) {
        guard var budget, let me else { return }
        if let envelope {
            budget.withdrawals.append(Withdrawal(envelope: envelope, amount: budget.convert(amount, from: currency).rounded(.up), note: note))
        } else {
            budget.outflows.append(Outflow(member: me, amount: amount, currency: currency, note: note))
        }
        self.budget = budget
    }

    func move(_ amount: Decimal, from: UUID, to: UUID) {
        budget?.transfers.append(Transfer(from: from, to: to, amount: amount))
    }
}

/// "Money came in": a gift, a bonus, a refund… put into envelopes, the rest is spending money.
struct InflowSheet: View {
    @Environment(BudgetStore.self) private var store
    @State private var amount: Decimal = 0
    @State private var currency: String?
    @State private var note = ""
    @State private var parts: [UUID: Decimal] = [:]

    private let kinds = ["Gift", "Bonus", "Refund", "Sold something", "Side job", "Found money"]

    var body: some View {
        let budget = store.budget!
        let total = budget.convert(amount, from: currency)
        let placed = parts.values.reduce(0, +)
        let envelopes = budget.envelopes.filter { e in
            if case .member(let id) = e.owner { id == store.me } else { true }
        }
        SheetFrame(title: "Money came in", subtitle: "Put some of it into savings; the rest adds to what you can spend until payday.",
                   action: "Save", canSave: amount > 0 && placed <= total,
                   save: {
                       guard let me = store.me else { return }
                       store.add(Inflow(member: me, amount: amount, currency: currency,
                                        note: note.isEmpty ? String(localized: "Extra money") : note,
                                        allocations: parts.filter { $0.value > 0 }.map { Allocation(target: .envelope($0.key), amount: $0.value, isDone: true) }))
                   }) {
            HStack(alignment: .top, spacing: 12) {
                Field("Amount") { AmountField(amount: $amount, code: $currency, budgetCurrency: budget.currency) }
                Field("What is it") { BoxTextField("e.g. Birthday gift", text: $note) }
            }
            FlowLayout(spacing: 6) {
                ForEach(kinds, id: \.self) { kind in
                    Button(LocalizedStringKey(kind)) { note = String(localized: String.LocalizationValue(kind)) }
                        .buttonStyle(.bordered).buttonBorderShape(.capsule).controlSize(.small)
                }
            }
            if !envelopes.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Into savings").font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                    ForEach(envelopes) { envelope in
                        HStack {
                            Text(envelope.name)
                            Spacer()
                            AmountField(optional: Binding(get: { parts[envelope.id] }, set: { parts[envelope.id] = $0 }),
                                        currency: budget.currency, placeholder: "0")
                                .frame(width: 160)
                        }
                    }
                }
                .card(padding: 14)
            }
            Label(placed <= total ? String(localized: "\((total - placed).money(budget.currency)) goes to spending money")
                                  : String(localized: "That's more than came in"),
                  systemImage: placed <= total ? "sun.max" : "exclamationmark.triangle")
                .foregroundStyle(placed <= total ? AnyShapeStyle(.secondary) : AnyShapeStyle(Palette.red))
        }
        .frame(width: 520)
    }
}

/// "Unplanned expense": treatment, a repair, a fine — from a saving or from spending money.
struct OutflowSheet: View {
    @Environment(BudgetStore.self) private var store
    @State private var amount: Decimal = 0
    @State private var currency: String?
    @State private var note = ""
    @State private var from: UUID?

    private let kinds = ["Treatment", "Repair", "Fine", "Car", "Help someone", "Other"]

    var body: some View {
        let budget = store.budget!
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        SheetFrame(title: "Unplanned expense",
                   subtitle: "Take it from a saving, or from the spending money — then the amount a day goes down.",
                   action: "Save", canSave: amount > 0,
                   save: { store.spend(amount, currency: currency, note: note.isEmpty ? String(localized: "Unplanned expense") : note, from: from) }) {
            HStack(alignment: .top, spacing: 12) {
                Field("Amount") { AmountField(amount: $amount, code: $currency, budgetCurrency: budget.currency) }
                Field("What for") { BoxTextField("e.g. Dentist", text: $note) }
            }
            FlowLayout(spacing: 6) {
                ForEach(kinds, id: \.self) { kind in
                    Button(LocalizedStringKey(kind)) { note = String(localized: String.LocalizationValue(kind)) }
                        .buttonStyle(.bordered).buttonBorderShape(.capsule).controlSize(.small)
                }
            }
            Field("Pay from") {
                Picker("Pay from", selection: $from) {
                    Text("Spending money").tag(UUID?.none)
                    ForEach(budget.envelopes) { envelope in
                        let balance = store.planner?.balance(of: envelope, before: tomorrow) ?? 0
                        Text("\(envelope.name) · \(balance.money(budget.currency))").tag(UUID?.some(envelope.id))
                    }
                }
                .labelsHidden()
            }
        }
    }
}

/// Move money from one saving to another.
struct TransferSheet: View {
    @Environment(BudgetStore.self) private var store
    @State private var from: UUID?
    @State private var to: UUID?
    @State private var amount: Decimal = 0

    var body: some View {
        let budget = store.budget!
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        let available = from.flatMap { id in budget.envelopes.first { $0.id == id } }.flatMap { store.planner?.balance(of: $0, before: tomorrow) } ?? 0
        SheetFrame(title: "Move between savings", subtitle: "The money changes envelope; the total stays the same.",
                   action: "Move", canSave: from != nil && to != nil && from != to && amount > 0 && amount <= available,
                   save: { if let from, let to { store.move(amount, from: from, to: to) } }) {
            HStack(alignment: .top, spacing: 12) {
                Field("From", hint: from == nil ? nil : "\(available.money(budget.currency)) there now") {
                    Picker("From", selection: $from) {
                        Text("Choose").tag(UUID?.none)
                        ForEach(budget.envelopes) { Text($0.name).tag(UUID?.some($0.id)) }
                    }
                    .labelsHidden()
                }
                Field("To") {
                    Picker("To", selection: $to) {
                        Text("Choose").tag(UUID?.none)
                        ForEach(budget.envelopes.filter { $0.id != from }) { Text($0.name).tag(UUID?.some($0.id)) }
                    }
                    .labelsHidden()
                }
            }
            Field("Amount") { AmountField(amount: $amount, currency: budget.currency) }.frame(width: 220, alignment: .leading)
        }
    }
}
