import HaluMeCore
import SwiftUI

extension BudgetStore {
    func save(_ inflow: Inflow) {
        guard var budget else { return }
        if let i = budget.inflows.firstIndex(where: { $0.id == inflow.id }) { budget.inflows[i] = inflow } else { budget.inflows.append(inflow) }
        self.budget = budget
    }

    var newInflow: Sheet { .inflow(Inflow(member: me ?? UUID(), amount: 0)) }

    func deleteInflow(_ id: UUID) { budget?.inflows.removeAll { $0.id == id } }

    /// Unplanned spending: out of a saving (a withdrawal) or out of the spending money. Editing keeps the id,
    /// even when the money now comes from the other place.
    func spend(_ amount: Decimal, currency: String?, note: String, from envelope: UUID?, date: Date = Date(), id: UUID = UUID()) {
        guard var budget, let me else { return }
        let member = budget.outflows.first { $0.id == id }?.member ?? me
        budget.outflows.removeAll { $0.id == id }
        budget.withdrawals.removeAll { $0.id == id }
        if let envelope {
            budget.withdrawals.append(Withdrawal(id: id, envelope: envelope, date: date, amount: budget.convert(amount, from: currency).rounded(.up), note: note))
        } else {
            budget.outflows.append(Outflow(id: id, member: member, date: date, amount: amount, currency: currency, note: note))
        }
        self.budget = budget
    }

    /// The leftover recorded with the payday on `date`, if it was kept or put into an envelope.
    func leftoverInflow(payday date: Date) -> Inflow? {
        budget?.inflows.first { $0.kind == .leftover && $0.member == me && Calendar.current.isDate($0.date, inSameDayAs: date) }
    }

    /// What was left from the last pay: noted only, kept to spend, or put into an envelope (an id).
    func useLeftover(_ amount: Decimal, to use: String, payday date: Date) {
        guard var budget, let me else { return }
        let old = leftoverInflow(payday: date)
        budget.inflows.removeAll { $0.id == old?.id }
        if amount > 0, use != "note" {
            var inflow = Inflow(id: old?.id ?? UUID(), member: me, date: Calendar.current.startOfDay(for: date), amount: amount,
                                note: String(localized: "Left from the last pay"))
            inflow.kind = .leftover
            if let id = UUID(uuidString: use) { inflow.allocations = [Allocation(target: .envelope(id), amount: amount, isDone: true)] }
            budget.inflows.append(inflow)
        }
        self.budget = budget
    }

    /// What the card should hold right now if spending went by the plan: what's still to pay or put aside
    /// plus the day's amount for the days left (today included).
    func expectedBalance(on date: Date = Date()) -> Decimal? {
        guard let planner, let me, let start = planner.current(on: date, of: me),
              let allowance = planner.allowance(for: me, on: date) else { return nil }
        let allocations = planner.payday(of: me, on: start)?.allocations ?? planner.confirm(planner.plan(for: me, on: start), actual: nil).allocations
        let unpaid = allocations.filter { !$0.isDone && $0.target != .free }.reduce(Decimal(0)) { $0 + $1.amount }
        return unpaid + allowance.perDay * Decimal(allowance.daysLeft)
    }

    /// Money moved from a saving into the spending money, just after the balance check that showed the gap.
    func cover(_ amount: Decimal, from envelope: UUID) {
        guard let me else { return }
        var inflow = Inflow(member: me, date: Date().addingTimeInterval(1), amount: amount,
                            note: String(localized: "Covered from \(budget?.envelopes.first { $0.id == envelope }?.name ?? "")"))
        inflow.kind = .fromSaving
        inflow.fromEnvelope = envelope
        budget?.inflows.append(inflow)
    }

    func deleteSpending(_ id: UUID) {
        budget?.outflows.removeAll { $0.id == id }
        budget?.withdrawals.removeAll { $0.id == id }
    }

    func save(_ transfer: Transfer) {
        guard var budget else { return }
        if let i = budget.transfers.firstIndex(where: { $0.id == transfer.id }) { budget.transfers[i] = transfer } else { budget.transfers.append(transfer) }
        self.budget = budget
    }

    func deleteTransfer(_ id: UUID) { budget?.transfers.removeAll { $0.id == id } }

    /// A withdrawal that pays a project task belongs to the task: change it there.
    func isProjectPayment(_ withdrawal: UUID) -> Bool {
        budget?.projects.contains { $0.tasks.contains { $0.payment == withdrawal } } ?? false
    }
}

private func tomorrow() -> Date { Calendar.current.date(byAdding: .day, value: 1, to: Date())! }

/// "Money came in": a gift, a bonus, a refund… put into envelopes, the rest is spending money.
/// With an irregular income it can also be earnings, which become next month's budget.
struct InflowSheet: View {
    @Environment(BudgetStore.self) private var store
    /// The money that came in, new or being edited.
    @State var inflow: Inflow
    @State private var parts: [UUID: Decimal] = [:]

    private let kinds = ["Gift", "Bonus", "Refund", "Sold something", "Side job", "Found money"]

    init(inflow: Inflow) {
        _inflow = State(initialValue: inflow)
        _parts = State(initialValue: Dictionary(inflow.allocations.compactMap { a in
            if case .envelope(let id) = a.target { (id, a.amount) } else { nil }
        }, uniquingKeysWith: +))
    }

    var body: some View {
        let budget = store.budget!
        let isNew = !budget.inflows.contains { $0.id == inflow.id }
        let total = budget.convert(inflow.amount, from: inflow.currency)
        let placed = inflow.income == nil ? parts.values.reduce(0, +) : 0
        let envelopes = budget.envelopes.filter { e in
            if case .member(let id) = e.owner { id == inflow.member } else { true }
        }
        let earnings = budget.incomes.filter { $0.member == inflow.member && $0.irregular }
        SheetFrame(title: LocalizedStringKey(isNew ? "Money came in" : "Edit money that came in"),
                   subtitle: inflow.income == nil ? "Put some of it into savings; the rest adds to what you can spend until payday."
                                                  : "Earnings wait until the 1st: then they become next month's budget.",
                   action: "Save", canSave: inflow.amount > 0 && placed <= total,
                   save: save, delete: isNew ? nil : { store.deleteInflow(inflow.id) }) {
            if !earnings.isEmpty {
                Picker("What is it", selection: $inflow.income) {
                    ForEach(earnings) { Text("Earnings: \(String(localized: String.LocalizationValue($0.name)))").tag(UUID?.some($0.id)) }
                    Text("Extra money").tag(UUID?.none)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            HStack(alignment: .top, spacing: 12) {
                Field("Amount") { AmountField(amount: $inflow.amount, code: $inflow.currency, budgetCurrency: budget.currency) }
                Field("What is it") { BoxTextField(LocalizedStringKey(inflow.income == nil ? "e.g. Birthday gift" : "e.g. Logo for a client"), text: $inflow.note) }
            }
            if inflow.income == nil {
                FlowLayout(spacing: 6) {
                    ForEach(kinds, id: \.self) { kind in
                        Button(LocalizedStringKey(kind)) { inflow.note = String(localized: String.LocalizationValue(kind)) }
                            .buttonStyle(.bordered).buttonBorderShape(.capsule).controlSize(.small)
                    }
                }
            }
            Field("Date") { DateField(date: $inflow.date, range: .distantPast ... Date()) }.frame(width: 220, alignment: .leading)
            if inflow.income == nil {
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
            } else {
                let month = Calendar.current.date(byAdding: .month, value: 1, to: inflow.date)!
                let first = Calendar.current.dateInterval(of: .month, for: month)!.start
                Label("Paid out to you on \(first.formatted(.dateTime.day().month(.wide))) as next month's budget.", systemImage: "tray.and.arrow.down")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: 520)
        .onAppear { if isNew, inflow.income == nil, let first = earnings.first { inflow.income = first.id } }
    }

    private func save() {
        var inflow = inflow
        if inflow.note.isEmpty { inflow.note = inflow.income == nil ? String(localized: "Extra money") : String(localized: "Earnings") }
        inflow.allocations = inflow.income != nil ? [] : parts.filter { $0.value > 0 }.map {
            Allocation(target: .envelope($0.key), amount: $0.value, isDone: true)
        }
        store.save(inflow)
    }
}

/// What the expense sheet edits: an unplanned expense from spending money or from a saving.
struct Spending: Hashable {
    var id = UUID()
    var date = Date()
    var amount: Decimal = 0
    var currency: String?
    var note = ""
    /// nil: from the spending money.
    var envelope: UUID?

    init() {}
    init(_ outflow: Outflow) { id = outflow.id; date = outflow.date; amount = outflow.amount; currency = outflow.currency; note = outflow.note }
    init(_ withdrawal: Withdrawal) { id = withdrawal.id; date = withdrawal.date; amount = withdrawal.amount; note = withdrawal.note; envelope = withdrawal.envelope }
}

/// "Unplanned expense": treatment, a repair, a fine — from a saving or from spending money.
struct OutflowSheet: View {
    @Environment(BudgetStore.self) private var store
    @State var spending: Spending

    private let kinds = ["Treatment", "Repair", "Fine", "Car", "Help someone", "Other"]

    var body: some View {
        let budget = store.budget!
        let isNew = !budget.outflows.contains { $0.id == spending.id } && !budget.withdrawals.contains { $0.id == spending.id }
        SheetFrame(title: LocalizedStringKey(isNew ? "Unplanned expense" : "Edit expense"),
                   subtitle: "Take it from a saving, or from the spending money — then the amount a day goes down.",
                   action: "Save", canSave: spending.amount > 0,
                   save: {
                       store.spend(spending.amount, currency: spending.currency,
                                   note: spending.note.isEmpty ? String(localized: "Unplanned expense") : spending.note,
                                   from: spending.envelope, date: spending.date, id: spending.id)
                   },
                   delete: isNew ? nil : { store.deleteSpending(spending.id) }) {
            HStack(alignment: .top, spacing: 12) {
                Field("Amount") { AmountField(amount: $spending.amount, code: $spending.currency, budgetCurrency: budget.currency) }
                Field("What for") { BoxTextField("e.g. Dentist", text: $spending.note) }
            }
            FlowLayout(spacing: 6) {
                ForEach(kinds, id: \.self) { kind in
                    Button(LocalizedStringKey(kind)) { spending.note = String(localized: String.LocalizationValue(kind)) }
                        .buttonStyle(.bordered).buttonBorderShape(.capsule).controlSize(.small)
                }
            }
            HStack(alignment: .top, spacing: 12) {
                Field("Pay from") {
                    Picker("Pay from", selection: $spending.envelope) {
                        Text("Spending money").tag(UUID?.none)
                        ForEach(budget.envelopes) { envelope in
                            let balance = store.planner?.balance(of: envelope, before: tomorrow()) ?? 0
                            Text("\(envelope.name) · \(balance.money(budget.currency))").tag(UUID?.some(envelope.id))
                        }
                    }
                    .labelsHidden()
                }
                Field("Date") { DateField(date: $spending.date, range: .distantPast ... Date()) }.frame(width: 200, alignment: .leading)
            }
        }
        .frame(width: 520)
    }
}

/// Move money from one saving to another.
struct TransferSheet: View {
    @Environment(BudgetStore.self) private var store
    @State var transfer: Transfer

    var body: some View {
        let budget = store.budget!
        let isNew = !budget.transfers.contains { $0.id == transfer.id }
        let none = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        // What's there now, plus this transfer itself when editing it.
        let available = budget.envelopes.first { $0.id == transfer.from }.flatMap { store.planner?.balance(of: $0, before: tomorrow()) }
            .map { $0 + (isNew ? 0 : budget.transfers.first { $0.id == transfer.id }?.amount ?? 0) } ?? 0
        SheetFrame(title: LocalizedStringKey(isNew ? "Move between savings" : "Edit move"),
                   subtitle: "The money changes envelope; the total stays the same.",
                   action: LocalizedStringKey(isNew ? "Move" : "Save"),
                   canSave: transfer.from != none && transfer.to != none && transfer.from != transfer.to && transfer.amount > 0 && transfer.amount <= available,
                   save: { store.save(transfer) }, delete: isNew ? nil : { store.deleteTransfer(transfer.id) }) {
            HStack(alignment: .top, spacing: 12) {
                Field("From", hint: transfer.from == none ? nil : "\(available.money(budget.currency)) there now") {
                    Picker("From", selection: $transfer.from) {
                        Text("Choose").tag(none)
                        ForEach(budget.envelopes) { Text($0.name).tag($0.id) }
                    }
                    .labelsHidden()
                }
                Field("To") {
                    Picker("To", selection: $transfer.to) {
                        Text("Choose").tag(none)
                        ForEach(budget.envelopes.filter { $0.id != transfer.from }) { Text($0.name).tag($0.id) }
                    }
                    .labelsHidden()
                }
            }
            HStack(alignment: .top, spacing: 12) {
                Field("Amount") { AmountField(amount: $transfer.amount, currency: budget.currency) }
                Field("Date") { DateField(date: $transfer.date, range: .distantPast ... Date()) }
            }
        }
    }

    static func new() -> Transfer {
        let none = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
        return Transfer(from: none, to: none, amount: 0)
    }
}
