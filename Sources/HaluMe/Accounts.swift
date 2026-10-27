import HaluMeCore
import SwiftUI

extension BudgetStore {
    func save(_ account: Account) {
        guard var budget else { return }
        if let i = budget.accounts.firstIndex(where: { $0.id == account.id }) { budget.accounts[i] = account } else { budget.accounts.append(account) }
        self.budget = budget
    }

    /// Deletes an account; envelopes and bills that used it keep their money but lose the link.
    func deleteAccount(_ id: UUID) {
        guard var budget else { return }
        budget.accounts.removeAll { $0.id == id }
        for i in budget.accounts.indices where budget.accounts[i].interestTo == id { budget.accounts[i].interestTo = nil }
        for i in budget.envelopes.indices where budget.envelopes[i].account == id { budget.envelopes[i].account = nil }
        for i in budget.bills.indices where budget.bills[i].payFrom == id { budget.bills[i].payFrom = nil }
        for i in budget.debts.indices where budget.debts[i].payFrom == id { budget.debts[i].payFrom = nil }
        for i in budget.subscriptions.indices where budget.subscriptions[i].payFrom == id { budget.subscriptions[i].payFrom = nil }
        self.budget = budget
    }
}

extension AccountKind {
    var title: LocalizedStringKey {
        switch self {
        case .card: "Card"
        case .savings: "Savings account"
        case .deposit: "Deposit"
        case .cash: "Cash"
        case .investments: "Investments"
        }
    }

    var icon: String {
        switch self {
        case .card: "creditcard"
        case .savings: "percent"
        case .deposit: "lock"
        case .cash: "banknote"
        case .investments: "chart.line.uptrend.xyaxis"
        }
    }
}

/// Savings page: the accounts, what's in each and what they earn.
struct AccountsSection: View {
    @Environment(BudgetStore.self) private var store
    let planner: Planner

    var body: some View {
        let budget = planner.budget
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Accounts").font(.headline)
                Spacer()
                Button { store.sheet = .account(Account(name: "", kind: .savings, owner: .member(store.me ?? UUID()))) } label: {
                    Label("Add account", systemImage: "plus")
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            if budget.accounts.isEmpty {
                Text("Add the places your money lives: a card, a savings account, a deposit. Several savings can share one account; interest follows its terms.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 210), spacing: 12)], spacing: 12) {
                    ForEach(budget.accounts) { account in
                        let inside = budget.envelopes.filter { $0.account == account.id }
                        let total = inside.reduce(Decimal(0)) { $0 + planner.balance(of: $1, before: tomorrow) }
                        let interest = inside.compactMap { planner.nextInterest(of: $0, from: Date())?.amount }.reduce(0, +)
                        Button { store.sheet = .account(account) } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: account.kind.icon).foregroundStyle(Palette.orange)
                                    Text(account.name).font(.body.weight(.semibold)).lineLimit(1)
                                    Spacer()
                                    OwnerBadge(owner: account.owner).font(.caption).foregroundStyle(.secondary)
                                }
                                Text(total.money(budget.currency)).font(.system(size: 22, weight: .medium, design: .rounded)).monospacedDigit()
                                Text(inside.isEmpty ? String(localized: "No savings here yet")
                                                    : inside.map(\.name).joined(separator: ", "))
                                    .font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                if account.kind.earnsInterest, account.rate > 0 {
                                    Text("\(account.rate.formatted())% · +\(interest.money(budget.currency)) a month")
                                        .font(.caption.weight(.medium)).foregroundStyle(Palette.green)
                                }
                                if !account.canWithdraw {
                                    Label("Can't take money out early", systemImage: "lock").font(.caption).foregroundStyle(.secondary)
                                }
                                // Room for the check link drawn over the card (a button can't sit inside another).
                                if !inside.isEmpty { Color.clear.frame(height: 16) }
                            }
                            .card()
                            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .overlay(alignment: .bottomLeading) {
                            if !inside.isEmpty {
                                let stale = account.checked.map { Date().timeIntervalSince($0) > 30 * 86_400 } ?? true
                                Button { store.sheet = .accountCheck(account.id) } label: {
                                    Label(account.checked.map { String(localized: "Checked \($0.formatted(.relative(presentation: .named)))") }
                                          ?? String(localized: "Check the balance"),
                                          systemImage: stale ? "exclamationmark.circle" : "checkmark.seal")
                                        .font(.caption)
                                        .foregroundStyle(stale ? Palette.orange : .secondary)
                                }
                                .buttonStyle(.plain)
                                .padding(18)
                                .help("Once a month: compare what the bank shows with what HaluMe expects")
                            }
                        }
                    }
                }
            }
        }
    }
}

struct AccountEditor: View {
    @Environment(BudgetStore.self) private var store
    @State var account: Account
    @State private var balance: Decimal = 0
    @State private var before: Decimal = 0

    var body: some View {
        let budget = store.budget!
        let isNew = !budget.accounts.contains { $0.id == account.id }
        let inside = budget.envelopes.filter { $0.account == account.id }
        SheetFrame(title: LocalizedStringKey(isNew ? "New account" : "Edit account"),
                   subtitle: "Just a name to tell your accounts apart. HaluMe never asks for account numbers.",
                   action: LocalizedStringKey(isNew ? "Add" : "Save"),
                   canSave: !account.name.trimmingCharacters(in: .whitespaces).isEmpty,
                   save: { save(inside: inside) }) {
            AccountFields(account: $account)
            if inside.count <= 1 {
                Field("On it now", hint: LocalizedStringKey(inside.isEmpty
                        ? "Becomes a saving with the account's name, one you keep. Change it on the Savings page."
                        : "A change goes into or out of the saving kept here.")) {
                    AmountField(amount: $balance, currency: budget.currency)
                }
                .frame(maxWidth: 260, alignment: .leading)
            } else {
                HStack {
                    Text("On it now: \(before.money(budget.currency)), split between its savings.").foregroundStyle(.secondary)
                    Spacer()
                    Button("Check the Balance…") { store.sheet = .accountCheck(account.id) }.buttonStyle(SecondaryButtonStyle())
                }
            }
            if !isNew {
                Button("Delete Account", role: .destructive) {
                    store.deleteAccount(account.id)
                    store.sheet = nil
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Palette.red)
            }
        }
        .onAppear {
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
            before = inside.reduce(Decimal(0)) { $0 + (store.planner?.balance(of: $1, before: tomorrow) ?? 0) }
            balance = before
        }
    }

    private func save(inside: [Envelope]) {
        store.save(account)
        guard balance != before, inside.count <= 1 else { return }
        if let envelope = inside.first {
            store.reconcile(account.id, difference: balance - before, envelope: envelope.id)
        } else if balance > 0, var budget = store.budget {
            var envelope = Envelope(owner: account.owner, name: account.name, goal: .open, priority: budget.envelopes.count,
                                    opening: balance, holding: account.kind.holding, account: account.id)
            envelope.purpose = .keep
            budget.envelopes.append(envelope)
            store.budget = budget
        }
    }
}

/// Name, type, owner and terms of an account (also used inline when creating one from a saving).
struct AccountFields: View {
    @Environment(BudgetStore.self) private var store
    @Binding var account: Account

    var body: some View {
        let budget = store.budget!
        Field("Name") { BoxTextField("e.g. Ozon, savings", text: $account.name) }
        HStack(alignment: .top, spacing: 12) {
            Field("Type") {
                Picker("Type", selection: $account.kind) {
                    ForEach(AccountKind.allCases, id: \.self) { Label($0.title, systemImage: $0.icon).tag($0) }
                }
                .labelsHidden()
            }
            if let me = store.me, !store.partners.isEmpty {
                Field("Whose") {
                    Picker("Whose", selection: $account.owner) {
                        Text("Mine").tag(Owner.member(me))
                        Text("Shared").tag(Owner.shared)
                        ForEach(store.partners) { Text($0.name).tag(Owner.member($0.id)) }
                    }
                    .labelsHidden()
                }
            }
        }
        if account.kind.earnsInterest {
            HStack(alignment: .top, spacing: 12) {
                Field("Rate, % a year") { PercentField(value: $account.rate) }.frame(width: 130, alignment: .leading)
                Field("Paid on day") { DayPicker(day: $account.interestDay) }.frame(width: 100, alignment: .leading)
                Field("Interest goes") {
                    Picker("Interest goes", selection: $account.interestTo) {
                        Text("Stays here").tag(UUID?.none)
                        ForEach(budget.accounts.filter { $0.id != account.id }) { Text($0.name).tag(UUID?.some($0.id)) }
                    }
                    .labelsHidden()
                }
            }
            Toggle("Money can be taken out any time", isOn: $account.canWithdraw)
            if account.kind == .deposit {
                Field("Ends") {
                    DateField(date: Binding(get: { account.maturity ?? Date() }, set: { account.maturity = $0 }), range: Date() ... .distantFuture)
                }
                .frame(maxWidth: 240, alignment: .leading)
            }
        }
    }
}

/// Where a saving lives: one of the accounts, or a new one made right here.
struct AccountPicker: View {
    @Environment(BudgetStore.self) private var store
    @Binding var envelope: Envelope
    @State private var creating = false
    @State private var draft = Account(name: "", kind: .savings, owner: .shared)

    var body: some View {
        let accounts = store.budget?.accounts ?? []
        Field("Where it lives") {
            Picker("Where it lives", selection: Binding(get: { creating ? UUID?.some(Self.new) : envelope.account },
                                                        set: { if $0 == Self.new { creating = true } else { creating = false; envelope.account = $0 } })) {
                Text("Not set").tag(UUID?.none)
                ForEach(accounts) { Label($0.name, systemImage: $0.kind.icon).tag(UUID?.some($0.id)) }
                Divider()
                Text("New account…").tag(UUID?.some(Self.new))
            }
            .labelsHidden()
        }
        .frame(maxWidth: 280, alignment: .leading)
        if creating {
            VStack(alignment: .leading, spacing: 12) {
                AccountFields(account: $draft)
                HStack {
                    Spacer()
                    Button("Cancel") { creating = false }.buttonStyle(SecondaryButtonStyle())
                    Button("Create Account") {
                        store.save(draft)
                        envelope.account = draft.id
                        creating = false
                        draft = Account(name: "", kind: .savings, owner: envelope.owner)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.primary.opacity(0.04)))
            .onAppear { draft.owner = envelope.owner }
        }
    }

    private static let new = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!
}

/// Which card or account pays a bill; hidden until there are accounts.
struct PayFromField: View {
    @Environment(BudgetStore.self) private var store
    @Binding var account: UUID?

    var body: some View {
        let accounts = (store.budget?.accounts ?? []).filter { $0.kind == .card || $0.kind == .cash || $0.kind == .savings }
        if !accounts.isEmpty {
            Field("Paid from") {
                Picker("Paid from", selection: $account) {
                    Text("Not set").tag(UUID?.none)
                    ForEach(accounts) { Text($0.name).tag(UUID?.some($0.id)) }
                }
                .labelsHidden()
            }
            .frame(maxWidth: 220, alignment: .leading)
        }
    }
}

/// Which payday pays it, when pay comes twice a month: the one before it's due, a chosen one, or half from each.
struct PaySlotField: View {
    @Environment(BudgetStore.self) private var store
    @Binding var slot: PaySlot?

    var body: some View {
        if let me = store.me, let days = store.planner?.slotDays(of: me)?.days {
            Field("From which pay") {
                Picker("From which pay", selection: $slot) {
                    Text("The one before it's due").tag(PaySlot?.none)
                    ForEach(Array(days.enumerated()), id: \.offset) { i, day in
                        Text("From the pay on day \(day)").tag(PaySlot?.some(.payday(i)))
                    }
                    Text("Half from each").tag(PaySlot?.some(.split))
                }
                .labelsHidden()
            }
            .frame(maxWidth: 240, alignment: .leading)
        }
    }
}

/// Once a month: does the bank show what the envelopes say? A difference goes into (or out of) one of them.
struct AccountCheckSheet: View {
    @Environment(BudgetStore.self) private var store
    let accountID: UUID
    @State private var actual: Decimal?
    @State private var envelope: UUID?

    var body: some View {
        if let planner = store.planner, let account = planner.budget.accounts.first(where: { $0.id == accountID }) {
            let currency = planner.budget.currency
            let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: Date())!
            let inside = planner.budget.envelopes.filter { $0.account == account.id }
            let expected = inside.reduce(Decimal(0)) { $0 + planner.balance(of: $1, before: tomorrow) }.rounded()
            let diff = (actual ?? expected) - expected
            SheetFrame(title: "Check \(account.name)", subtitle: "Open your bank and enter what this account holds now.",
                       action: "Save", canSave: actual != nil && (diff == 0 || envelope != nil),
                       save: { store.reconcile(account.id, difference: diff, envelope: envelope) }) {
                StatRow {
                    Stat(label: "HaluMe expects", value: expected.money(currency))
                    Stat(label: "Difference", value: actual == nil ? "—" : (diff > 0 ? "+" : "") + diff.money(currency))
                }
                Field("In the bank now") { AmountField(optional: $actual, currency: currency, placeholder: "0") }.frame(maxWidth: 220, alignment: .leading)
                if actual != nil {
                    if diff == 0 {
                        Label("It matches.", systemImage: "checkmark.circle").foregroundStyle(Palette.green)
                    } else {
                        Field(LocalizedStringKey(diff > 0 ? "Add the extra to" : "Take the missing part from"),
                              hint: LocalizedStringKey(diff > 0 ? "Often it's interest, or money you put in and didn't record." : "Often it's money taken out and not recorded.")) {
                            Picker("Envelope", selection: $envelope) {
                                Text("Choose").tag(UUID?.none)
                                ForEach(inside) { Text($0.name).tag(UUID?.some($0.id)) }
                            }
                            .labelsHidden()
                        }
                    }
                }
            }
            .onAppear { envelope = inside.count == 1 ? inside[0].id : nil }
        }
    }
}

extension BudgetStore {
    /// Books an account check: more than expected goes into an envelope, less comes out of it.
    func reconcile(_ account: UUID, difference: Decimal, envelope: UUID?) {
        guard var budget, let me else { return }
        if let envelope, difference != 0 {
            if difference > 0 {
                var inflow = Inflow(member: me, amount: difference, note: String(localized: "Account check"),
                                    allocations: [Allocation(target: .envelope(envelope), amount: difference, isDone: true)])
                inflow.kind = .reconcile
                budget.inflows.append(inflow)
            } else {
                budget.withdrawals.append(Withdrawal(envelope: envelope, amount: -difference, note: String(localized: "Account check")))
            }
        }
        if let i = budget.accounts.firstIndex(where: { $0.id == account }) { budget.accounts[i].checked = Date() }
        self.budget = budget
    }
}
