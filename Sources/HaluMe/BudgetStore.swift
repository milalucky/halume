import Foundation
import HaluMeCore
import Observation

enum Sheet: Identifiable, Hashable {
    case pay, balance, plan
    case debt(Debt)
    case payoff(UUID)
    case subscription(Subscription)
    case withdraw(UUID)
    case timeOff
    case wish(Wish)
    case newProject
    case task(project: UUID, stage: UUID, task: ProjectTask)
    case rates(UUID)
    case account(Account)

    var id: String {
        switch self {
        case .pay: "pay"
        case .balance: "balance"
        case .plan: "plan"
        case .debt(let d): "debt-\(d.id)"
        case .payoff(let id): "payoff-\(id)"
        case .subscription(let s): "subscription-\(s.id)"
        case .withdraw(let id): "withdraw-\(id)"
        case .timeOff: "time-off"
        case .wish(let w): "wish-\(w.id)"
        case .newProject: "new-project"
        case .task(_, _, let t): "task-\(t.id)"
        case .rates(let id): "rates-\(id)"
        case .account(let a): "account-\(a.id)"
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
        case "timeoff": .timeOff
        case "wish": budget?.wishes.first.map { .wish($0) }
        case "project": .newProject
        default: nil
        }
    }
}

enum Section: String, CaseIterable, Identifiable {
    case today, savings, debts, subscriptions, projects, wishlist, stats
    var id: Self { self }
}

/// The budget on disk: Application Support/HaluMe/budget.json.
@MainActor @Observable
final class BudgetStore {
    var budget: Budget? {
        didSet {
            save()
            syncReminders()
        }
    }

    var sheet: Sheet?
    var section = Section.today
    /// The project shown in Projects, if one is open.
    var openProject: UUID?
    var confirmingStartOver = false
    /// Bumped when display settings change so the windows redraw.
    var look = 0

    /// `--demo` fills a sample budget in memory and never touches the file.
    let isDemo = CommandLine.arguments.contains("--demo")

    private let url: URL

    init() {
        // `--data <folder>` keeps a test budget apart from the real one.
        let custom = CommandLine.arguments.firstIndex(of: "--data").map { URL(fileURLWithPath: CommandLine.arguments[$0 + 1]) }
        let dir = custom ?? URL.applicationSupportDirectory.appending(path: "HaluMe", directoryHint: .isDirectory)
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

    /// The member using this device: remembered per budget, the budget's creator by default.
    var me: UUID? {
        guard let budget else { return nil }
        if let saved = UserDefaults.standard.string(forKey: "me.\(budget.id)").flatMap(UUID.init(uuidString:)),
           budget.members.contains(where: { $0.id == saved }) {
            return saved
        }
        return budget.members.first?.id
    }

    /// Everyone else in the household.
    var partners: [Member] { budget?.members.filter { $0.id != me } ?? [] }

    /// Adds a partner; their monthly income (if given) lets shared bills split by income.
    func addPartner(name: String, monthly: Decimal) {
        guard var budget else { return }
        let member = Member(name: name)
        budget.members.append(member)
        if monthly > 0 {
            budget.incomes.append(Income(member: member.id, name: String(localized: "Salary"), schedule: .monthly(days: [1]),
                                         shift: .none, expected: monthly, isMonthly: true))
        }
        self.budget = budget
    }

    /// Removes a partner; what they owned becomes yours, shared things stay shared.
    func removeMember(_ id: UUID) {
        guard var budget, id != me, let me else { return }
        budget.members.removeAll { $0.id == id }
        budget.incomes.removeAll { $0.member == id }
        func mine(_ owner: inout Owner) { if owner == .member(id) { owner = .member(me) } }
        for i in budget.bills.indices { mine(&budget.bills[i].owner) }
        for i in budget.envelopes.indices { mine(&budget.envelopes[i].owner) }
        for i in budget.debts.indices { mine(&budget.debts[i].owner) }
        for i in budget.subscriptions.indices { mine(&budget.subscriptions[i].owner) }
        self.budget = budget
    }

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

    func save(_ wish: Wish) {
        guard var budget else { return }
        if let i = budget.wishes.firstIndex(where: { $0.id == wish.id }) { budget.wishes[i] = wish } else { budget.wishes.append(wish) }
        self.budget = budget
    }

    func deleteWish(_ id: UUID) {
        budget?.wishes.removeAll { $0.id == id }
        budget?.reservations.removeAll { $0.wish == id }
    }

    /// Creates a goal for the wish: its price in six months, first in line after existing savings.
    func startSaving(for wish: Wish) {
        guard var budget, let me, let i = budget.wishes.firstIndex(where: { $0.id == wish.id }) else { return }
        let envelope = Envelope(owner: .member(me), name: wish.name,
                                goal: .target(budget.convert(wish.price, from: wish.currency).rounded(.up),
                                              by: Calendar.current.date(byAdding: .month, value: 6, to: Date())!),
                                priority: (budget.envelopes.map(\.priority).max() ?? -1) + 1)
        budget.envelopes.append(envelope)
        budget.wishes[i].envelope = envelope.id
        self.budget = budget
    }

    func markGot(_ wish: Wish) {
        guard var budget, let i = budget.wishes.firstIndex(where: { $0.id == wish.id }) else { return }
        budget.wishes[i].isDone = true
        self.budget = budget
    }

    func toggleReservation(_ wish: Wish) {
        guard var budget, let me else { return }
        if budget.reservations.contains(where: { $0.wish == wish.id && $0.by == me }) {
            budget.reservations.removeAll { $0.wish == wish.id && $0.by == me }
        } else {
            budget.reservations.append(Reservation(wish: wish.id, by: me))
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

    func syncReminders() {
        guard !isDemo else { return }
        Reminders.sync(budget)
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
    /// Which account a plan line is paid from or goes into, by name.
    func source(of target: Target) -> String? {
        let id: UUID? = switch target {
        case .bill(let i): bills.first { $0.id == i }?.payFrom
        case .debt(let i): debts.first { $0.id == i }?.payFrom
        case .subscription(let i): subscriptions.first { $0.id == i }?.payFrom
        case .envelope(let i): envelopes.first { $0.id == i }?.account
        default: nil
        }
        return id.flatMap { a in accounts.first { $0.id == a }?.name }
    }

    /// Daily pay is planned week by week.
    var plansByWeek: Bool {
        if case .daily = incomes.first?.schedule { true } else { false }
    }

    func name(of target: Target) -> String? {
        switch target {
        case .bill(let id): bills.first { $0.id == id }?.name
        case .envelope(let id): envelopes.first { $0.id == id }?.name
        case .debt(let id): debts.first { $0.id == id }?.name
        case .subscription(let id): subscriptions.first { $0.id == id }?.name
        case .carry, .free: nil
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
        let income = Income(member: me.id, name: String(localized: "Salary"), schedule: .monthly(days: [10, 25]), expected: 230_000,
                            isMonthly: true, split: .byWorkdays)
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
        budget.wishes = [
            Wish(owner: me.id, name: "iPhone Duo", price: 149_990, link: "https://www.apple.com/iphone/", note: String(localized: "Black, 256 GB")),
            Wish(owner: me.id, name: String(localized: "Running shoes"), price: 12_900),
        ]
        budget.workCalendar = .russia
        addHistory(to: &budget, member: me.id, before: today)
        let planner = Planner(budget)
        if let start = planner.current(on: today, of: me.id) {
            var record = planner.confirm(planner.plan(for: me.id, on: start), actual: planner.expected(of: me.id, on: start))
            for i in record.allocations.indices where [String(localized: "Rent"), String(localized: "Vacation"), "Yandex Split"].contains(budget.name(of: record.allocations[i].target)) {
                record.allocations[i].isDone = true
            }
            budget.upsert(record)
        }
        return budget
    }
}
