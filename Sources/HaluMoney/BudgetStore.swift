import Foundation
import HaluMoneyCore
import Observation

enum Sheet: String, Identifiable {
    case pay, balance, plan
    var id: Self { self }
}

/// The budget on disk: Application Support/Halu Money/budget.json.
@MainActor @Observable
final class BudgetStore {
    var budget: Budget? {
        didSet { save() }
    }

    var sheet: Sheet?
    var confirmingStartOver = false

    /// `--demo` fills a sample budget in memory and never touches the file.
    let isDemo = CommandLine.arguments.contains("--demo")

    private let url: URL

    init() {
        let dir = URL.applicationSupportDirectory.appending(path: "Halu Money", directoryHint: .isDirectory)
        url = dir.appending(path: "budget.json")
        if isDemo {
            // `--demo --step N` shows onboarding step N with demo answers.
            budget = CommandLine.arguments.contains("--step") ? nil : Demo.budget()
            sheet = CommandLine.arguments.firstIndex(of: "--sheet").flatMap { Sheet(rawValue: CommandLine.arguments[$0 + 1]) }
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
            NSLog("Halu Money: could not save the budget: \(error)")
        }
    }
}

extension Budget {
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
        let income = Income(member: me.id, name: "Salary", schedule: .monthly(days: [10, 25]), expected: 92_000)
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
            ]
        )
        let planner = Planner(budget)
        if let start = planner.current(on: today, of: me.id) {
            var record = planner.confirm(planner.plan(for: me.id, on: start), actual: 92_000)
            for i in record.allocations.indices where i < 2 { record.allocations[i].isDone = true }
            budget.upsert(record)
        }
        return budget
    }
}
