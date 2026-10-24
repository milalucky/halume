import Foundation
import HaluMeCore
import Observation

enum Sheet: Identifiable, Hashable {
    case pay, balance, plan
    case debt(Debt)
    case payoff(UUID)
    case subscription(Subscription)
    case withdraw(UUID)

    var id: String {
        switch self {
        case .pay: "pay"
        case .balance: "balance"
        case .plan: "plan"
        case .debt(let d): "debt-\(d.id)"
        case .payoff(let id): "payoff-\(id)"
        case .subscription(let s): "subscription-\(s.id)"
        case .withdraw(let id): "withdraw-\(id)"
        }
    }

    /// For `--sheet <name>` in demo mode.
    static func named(_ name: String, in budget: Budget?) -> Sheet? {
        switch name {
        case "pay": .pay
        case "balance": .balance
        case "plan": .plan
        case "debt": budget?.debts.first.map { .debt($0) }
        case "payoff": budget?.debts.first.map { .payoff($0.id) }
        case "subscription": budget?.subscriptions.first.map { .subscription($0) }
        case "withdraw": budget?.envelopes.first.map { .withdraw($0.id) }
        default: nil
        }
    }
}

enum Section: String, CaseIterable, Identifiable {
    case today, savings, debts, subscriptions, stats
    var id: Self { self }
}

/// The budget on disk: Application Support/HaluMe/budget.json.
@MainActor @Observable
final class BudgetStore {
    var budget: Budget? {
        didSet { save() }
    }

    var sheet: Sheet?
    var section = Section.today
    var confirmingStartOver = false

    /// `--demo` fills a sample budget in memory and never touches the file.
    let isDemo = CommandLine.arguments.contains("--demo")

    private let url: URL

    init() {
        let dir = URL.applicationSupportDirectory.appending(path: "HaluMe", directoryHint: .isDirectory)
        url = dir.appending(path: "budget.json")
        if isDemo {
            // `--demo --step N` shows onboarding step N with demo answers.
            budget = CommandLine.arguments.contains("--step") ? nil : Demo.budget()
            sheet = CommandLine.arguments.firstIndex(of: "--sheet").flatMap { Sheet.named(CommandLine.arguments[$0 + 1], in: budget) }
            section = CommandLine.arguments.firstIndex(of: "--section").flatMap { Section(rawValue: CommandLine.arguments[$0 + 1]) } ?? .today
            return
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let data = try? Data(contentsOf: url) else { return }
        do {
            budget = try JSONDecoder().decode(Budget.self, from: data)
        } catch {
            // Keep an unreadable file aside instead of overwriting it with a new budget.
            let aside = dir.appending(path: "budget-unreadable-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.moveItem(at: url, to: aside)
        }
    }

    var planner: Planner? { budget.map { Planner($0) } }

    /// The UI has one member for now; the model already supports more.
    var me: UUID? { budget?.members.first?.id }

    /// Marks a transfer or bill of the payday on `date` as done (or not).
    func toggle(_ target: Target, payday date: Date) {
        guard var budget, let me else { return }
        let planner = Planner(budget)
        var record = planner.payday(of: me, on: date) ?? planner.confirm(planner.plan(for: me, on: date), actual: nil)
        guard let i = record.allocations.firstIndex(where: { $0.target == target }) else { return }
        record.allocations[i].isDone.toggle()
        budget.upsert(record)
        self.budget = budget
    }

    /// The real amount of the payday on `date`; the plan is redone for it, done marks kept.
    func setPay(_ amount: Decimal, leftover: Decimal?, payday date: Date) {
        guard var budget, let me else { return }
        var record = Planner(budget).payday(of: me, on: date) ?? Payday(member: me, date: date, actual: nil, allocations: [])
        record.actual = amount
        record.leftover = leftover
        budget.upsert(record)
        let planner = Planner(budget)
        var confirmed = planner.confirm(planner.plan(for: me, on: date), actual: amount)
        confirmed.leftover = leftover
        budget.upsert(confirmed)
        self.budget = budget
    }

    func checkBalance(_ amount: Decimal) {
        guard let me else { return }
        budget?.checks.append(BalanceCheck(member: me, date: Date(), amount: amount))
    }

    func save(_ debt: Debt) {
        guard var budget else { return }
        if let i = budget.debts.firstIndex(where: { $0.id == debt.id }) { budget.debts[i] = debt } else { budget.debts.append(debt) }
        self.budget = budget
    }

    func deleteDebt(_ id: UUID) {
        budget?.debts.removeAll { $0.id == id }
    }

    func save(_ subscription: Subscription) {
        guard var budget else { return }
        if let i = budget.subscriptions.firstIndex(where: { $0.id == subscription.id }) {
            budget.subscriptions[i] = subscription
        } else {
            budget.subscriptions.append(subscription)
        }
        self.budget = budget
    }

    func withdraw(_ amount: Decimal, from envelope: UUID, note: String) {
        budget?.withdrawals.append(Withdrawal(envelope: envelope, amount: amount, note: note))
    }

    func deleteSubscription(_ id: UUID) {
        budget?.subscriptions.removeAll { $0.id == id }
    }

    func startOver() {
        budget = nil
        if !isDemo { try? FileManager.default.removeItem(at: url) }
    }

    private func save() {
        guard let budget, !isDemo else { return }
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            try encoder.encode(budget).write(to: url, options: .atomic)
        } catch {
            NSLog("HaluMe: could not save the budget: \(error)")
        }
    }
}

extension Budget {
    func name(of target: Target) -> String? {
        switch target {
        case .bill(let id): bills.first { $0.id == id }?.name
        case .envelope(let id): envelopes.first { $0.id == id }?.name
        case .debt(let id): debts.first { $0.id == id }?.name
        case .subscription(let id): subscriptions.first { $0.id == id }?.name
        case .free: nil
        }
    }

    mutating func upsert(_ payday: Payday) {
        if let i = paydays.firstIndex(where: { $0.id == payday.id }) {
            paydays[i] = payday
        } else {
            paydays.append(payday)
        }
    }
}

/// A believable sample for screenshots and design checks.
enum Demo {
    /// 14 months of confirmed paydays: a sick-leave month, a bonus, skipped transfers, one withdrawal.
    static func addHistory(to budget: inout Budget, member: UUID, before today: Date) {
        let calendar = Calendar.current
        var planner = Planner(budget)
        let from = calendar.date(byAdding: .month, value: -14, to: today)!
        let dates = planner.paydays(of: member, from: from, to: calendar.date(byAdding: .day, value: -1, to: today)!)
            .dropLast() // the current period gets its own record
        for (i, date) in dates.enumerated() {
            let month = calendar.component(.month, from: date)
            var pay = planner.expected(of: member, on: date)
            if month == 3 { pay = pay * 72 / 100 }            // sick leave
            if month == 12, i % 2 == 1 { pay += 60_000 }        // year-end bonus
            pay += Decimal((i * 7_919) % 9_000) - 4_000         // shifts and overtime
            budget.paydays.append(Payday(member: member, date: date, actual: pay, allocations: []))
            planner = Planner(budget)
            var record = planner.confirm(planner.plan(for: member, on: date), actual: pay)
            budget.paydays.removeLast()
            for j in record.allocations.indices {
                let skip = (i % 5 == 3 && j % 3 == 1) || (month == 3 && j > 1)
                record.allocations[j].isDone = !skip
            }
            record.leftover = Decimal((i * 3_571) % 6_000)
            budget.paydays.append(record)
            planner = Planner(budget)
        }
        if let vacation = budget.envelopes.first(where: { $0.name == String(localized: "Vacation") }) {
            budget.withdrawals.append(Withdrawal(envelope: vacation.id, date: calendar.date(byAdding: .month, value: -5, to: today)!,
                                                 amount: 25_000, note: String(localized: "Car repair")))
        }
    }

    static func budget() -> Budget {
        let me = Member(name: "Milana")
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: today)! }
        let started = calendar.date(byAdding: .month, value: -14, to: today)!
        let income = Income(member: me.id, name: String(localized: "Salary"), schedule: .monthly(days: [10, 25]), expected: 115_000)
        var budget = Budget(
            name: "Milana", currency: "RUB", members: [me], incomes: [income],
            bills: [
                Bill(owner: .member(me.id), name: String(localized: "Rent"), amount: 55_000, day: 5),
                Bill(owner: .member(me.id), name: String(localized: "Utilities"), amount: 6_500, day: 20),
                Bill(owner: .member(me.id), name: String(localized: "Phone & internet"), amount: 1_400, day: 15),
            ],
            envelopes: [
                Envelope(owner: .member(me.id), name: String(localized: "Vacation"), goal: .target(180_000, by: calendar.date(byAdding: .month, value: 8, to: today)!),
                         priority: 0, openedAt: started),
                Envelope(owner: .member(me.id), name: String(localized: "Emergency fund"), goal: .percent(10), priority: 1, opening: 40_000, openedAt: started,
                         holding: .savingsAccount, rate: 12, interestDay: 1),
                Envelope(owner: .member(me.id), name: String(localized: "Gifts"), goal: .yearly(36_000), priority: 2, openedAt: started),
                Envelope(owner: .member(me.id), name: String(localized: "Deposit"), goal: .open, priority: 3, opening: 300_000, openedAt: started,
                         holding: .deposit, rate: 16, interestDay: 15, interestToCard: true,
                         maturity: calendar.date(byAdding: .month, value: 4, to: today)!),
            ],
            debts: [
                Debt(owner: .member(me.id), name: "Yandex Split", kind: .installment, original: 24_000, balance: 12_000,
                     payment: 6_000, day: 28),
                Debt(owner: .member(me.id), name: String(localized: "Car loan"), kind: .loan, original: 900_000, balance: 412_000,
                     rate: 14.5, payment: 21_000, day: 15),
                Debt(owner: .member(me.id), name: String(localized: "Anna"), kind: .personal, balance: 8_000, payment: 8_000, day: 1),
            ],
            subscriptions: [
                Subscription(owner: .member(me.id), name: "Yandex Plus", amount: 399, anchor: day(3), category: "Video"),
                Subscription(owner: .member(me.id), name: "Spotify", amount: 169, anchor: day(-5), category: "Music"),
                Subscription(owner: .member(me.id), name: "iCloud+", amount: 149, anchor: day(12), category: "Cloud"),
                Subscription(owner: .member(me.id), name: "ChatGPT Plus", amount: 1_990, anchor: day(19), category: "Software"),
                Subscription(owner: .member(me.id), name: "Kinopoisk", amount: 299, anchor: day(-20), trialEnds: day(2),
                             category: "Video"),
                Subscription(owner: .member(me.id), name: "Telegram Premium", amount: 2_990, cycle: .yearly, anchor: day(140),
                             category: "Software"),
                Subscription(owner: .member(me.id), name: String(localized: "Gym"), amount: 3_500, anchor: day(8), isActive: false, category: "Other"),
            ]
        )
        addHistory(to: &budget, member: me.id, before: today)
        let planner = Planner(budget)
        if let start = planner.current(on: today, of: me.id) {
            var record = planner.confirm(planner.plan(for: me.id, on: start), actual: 115_000)
            for i in record.allocations.indices where [String(localized: "Rent"), String(localized: "Vacation"), "Yandex Split"].contains(budget.name(of: record.allocations[i].target)) {
                record.allocations[i].isDone = true
            }
            budget.upsert(record)
        }
        return budget
    }
}
