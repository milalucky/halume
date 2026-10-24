import Foundation
import HaluMeCore
import Observation

enum Sheet: Identifiable, Hashable {
    case pay, balance, plan
    case debt(Debt)
    case payoff(UUID)
    case subscription(Subscription)

    var id: String {
        switch self {
        case .pay: "pay"
        case .balance: "balance"
        case .plan: "plan"
        case .debt(let d): "debt-\(d.id)"
        case .payoff(let id): "payoff-\(id)"
        case .subscription(let s): "subscription-\(s.id)"
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
        default: nil
        }
    }
}

enum Section: String, CaseIterable, Identifiable {
    case today, savings, debts, subscriptions
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
    func setPay(_ amount: Decimal, payday date: Date) {
        guard var budget, let me else { return }
        var record = Planner(budget).payday(of: me, on: date) ?? Payday(member: me, date: date, actual: nil, allocations: [])
        record.actual = amount
        budget.upsert(record)
        let planner = Planner(budget)
        budget.upsert(planner.confirm(planner.plan(for: me, on: date), actual: amount))
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
    static func budget() -> Budget {
        let me = Member(name: "Milana")
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        func day(_ offset: Int) -> Date { calendar.date(byAdding: .day, value: offset, to: today)! }
        let income = Income(member: me.id, name: "Salary", schedule: .monthly(days: [10, 25]), expected: 115_000)
        var budget = Budget(
            name: "Milana", currency: "RUB", members: [me], incomes: [income],
            bills: [
                Bill(owner: .member(me.id), name: "Rent", amount: 55_000, day: 5),
                Bill(owner: .member(me.id), name: "Utilities", amount: 6_500, day: 20),
                Bill(owner: .member(me.id), name: "Phone & internet", amount: 1_400, day: 15),
                Bill(owner: .member(me.id), name: "Subscriptions", amount: 2_100, day: 12),
            ],
            envelopes: [
                Envelope(owner: .member(me.id), name: "Vacation", goal: .target(180_000, by: calendar.date(byAdding: .month, value: 8, to: today)!),
                         priority: 0, opening: 64_000),
                Envelope(owner: .member(me.id), name: "Emergency fund", goal: .percent(10), priority: 1, opening: 120_000),
                Envelope(owner: .member(me.id), name: "Gifts", goal: .yearly(36_000), priority: 2, opening: 9_000),
            ],
            debts: [
                Debt(owner: .member(me.id), name: "Yandex Split", kind: .installment, original: 24_000, balance: 12_000,
                     payment: 6_000, day: 28),
                Debt(owner: .member(me.id), name: "Car loan", kind: .loan, original: 900_000, balance: 412_000,
                     rate: 14.5, payment: 21_000, day: 15),
                Debt(owner: .member(me.id), name: "Anna", kind: .personal, balance: 8_000, payment: 8_000, day: 1),
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
                Subscription(owner: .member(me.id), name: "Gym", amount: 3_500, anchor: day(8), isActive: false, category: "Other"),
            ]
        )
        let planner = Planner(budget)
        if let start = planner.current(on: today, of: me.id) {
            var record = planner.confirm(planner.plan(for: me.id, on: start), actual: 115_000)
            for i in record.allocations.indices where ["Rent", "Vacation", "Yandex Split"].contains(budget.name(of: record.allocations[i].target)) {
                record.allocations[i].isDone = true
            }
            budget.upsert(record)
        }
        return budget
    }
}
