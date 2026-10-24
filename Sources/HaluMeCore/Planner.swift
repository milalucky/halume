import Foundation

/// One payday's plan for one member.
public struct Plan: Sendable, Hashable {
    public struct Line: Sendable, Hashable {
        public var target: Target
        public var name: String
        /// What the plan asks for.
        public var planned: Decimal
        /// What the pay actually covers.
        public var amount: Decimal

        public init(target: Target, name: String, planned: Decimal, amount: Decimal) {
            self.target = target; self.name = name; self.planned = planned; self.amount = amount
        }
    }

    public var member: UUID
    public var date: Date
    public var next: Date
    public var pay: Decimal
    public var lines: [Line]
    public var free: Decimal
    public var shortfall: Decimal { lines.reduce(0) { $0 + $1.planned - $1.amount } }
}

public struct Payoff: Sendable, Hashable {
    public var months: Int
    public var interest: Decimal
    /// The month of the last payment.
    public var date: Date

    /// Month by month: interest added, then the payment; nil when the payment doesn't cover the interest.
    static func compute(balance: Decimal, rate: Decimal, payment: Decimal) -> (months: Int, interest: Decimal)? {
        var left = balance, months = 0, interest: Decimal = 0
        let monthly = rate / 1200
        while left > 0 {
            let charge = left * monthly
            guard payment > charge, months < 1200 else { return nil }
            left += charge
            interest += charge
            left -= min(payment, left)
            months += 1
        }
        return (months, up(interest))
    }
}

public struct Allowance: Sendable, Hashable {
    public var perDay: Decimal
    public var daysLeft: Int
    public var next: Date
}

/// Pure calculations over a budget. Dates are whole days in `calendar`.
public struct Planner: Sendable {
    public var budget: Budget
    public var calendar: Calendar

    public init(_ budget: Budget, calendar: Calendar = .current) {
        self.budget = budget
        self.calendar = calendar
    }

    // MARK: Pay dates

    /// Pay dates of one income in [from, to], weekends moved per its rule.
    public func dates(of income: Income, from: Date, to: Date) -> [Date] {
        let from = day(from), to = day(to)
        let raw: [Date]
        switch income.schedule {
        case .monthly(let days):
            // Widened: a weekend shift moves a date up to two days either way.
            raw = monthDays(days, from: add(-3, to: from)!, to: add(3, to: to)!)
        case .everyWeeks(let weeks, let anchor):
            let step = max(1, weeks) * 7, anchor = day(anchor)
            var k = max(0, self.days(anchor, from) / step - 1)
            var out: [Date] = []
            while let d = add(k * step, to: anchor), d <= add(3, to: to)! {
                out.append(d)
                k += 1
            }
            raw = out
        }
        return raw.map { shifted($0, income.shift) }.filter { $0 >= from && $0 <= to }
    }

    /// All pay dates of a member in [from, to], one per day.
    public func paydays(of member: UUID, from: Date, to: Date) -> [Date] {
        let all = budget.incomes.filter { $0.member == member }.flatMap { dates(of: $0, from: from, to: to) }
        return Set(all).sorted()
    }

    public func next(after date: Date, of member: UUID) -> Date? {
        paydays(of: member, from: add(1, to: date)!, to: add(400, to: date)!).first
    }

    /// The member's last payday on or before `date`.
    public func current(on date: Date, of member: UUID) -> Date? {
        paydays(of: member, from: add(-400, to: date)!, to: date).last
    }

    /// Sum of the member's incomes paid on that day.
    public func expected(of member: UUID, on date: Date) -> Decimal {
        budget.incomes.filter { $0.member == member && !dates(of: $0, from: date, to: date).isEmpty }
            .reduce(0) { $0 + $1.expected }
    }

    // MARK: Shares and balances

    public func share(of member: UUID, owner: Owner, split: Split, on date: Date) -> Decimal {
        if case .member(let id) = owner { return id == member ? 1 : 0 }
        let all = budget.members.map(\.id)
        guard all.contains(member) else { return 0 }
        switch split {
        case .equal:
            return 1 / Decimal(all.count)
        case .payer(let id):
            return id == member ? 1 : 0
        case .weights(let weights):
            let total = weights.values.reduce(0, +)
            return total > 0 ? (weights[member] ?? 0) / total : 1 / Decimal(all.count)
        case .byIncome:
            let yearly = { (m: UUID) in self.yearlyIncome(of: m, from: date) }
            let total = all.map(yearly).reduce(0, +)
            return total > 0 ? yearly(member) / total : 1 / Decimal(all.count)
        }
    }

    func yearlyIncome(of member: UUID, from date: Date) -> Decimal {
        paydays(of: member, from: date, to: yearLater(date)).reduce(0) { $0 + expected(of: member, on: $1) }
    }

    /// Opening money plus transfers marked done on paydays before `date`.
    public func balance(of envelope: Envelope, before date: Date) -> Decimal {
        let date = day(date)
        return budget.paydays.filter { day($0.date) < date }
            .flatMap(\.allocations)
            .filter { $0.isDone && $0.target == .envelope(envelope.id) }
            .reduce(envelope.opening) { $0 + $1.amount }
    }

    // MARK: Plan

    public func plan(for member: UUID, on date: Date) -> Plan {
        let date = day(date)
        let next = self.next(after: date, of: member) ?? calendar.date(byAdding: .month, value: 1, to: date)!
        let record = payday(of: member, on: date)
        let pay = record?.actual ?? expected(of: member, on: date)
        var left = pay
        var lines: [Plan.Line] = []

        func take(_ target: Target, _ name: String, _ planned: Decimal) {
            let amount = min(planned, max(left, 0))
            left -= amount
            lines.append(.init(target: target, name: name, planned: planned, amount: amount))
        }

        // Bills, debt payments and subscription charges due before the next payday, earliest first.
        let last = add(-1, to: next)!
        var due: [(target: Target, name: String, date: Date, amount: Decimal)] = []
        for bill in budget.bills {
            let s = share(of: member, owner: bill.owner, split: bill.split, on: date)
            guard s > 0 else { continue }
            due += monthDays([bill.day], from: date, to: last).map { (.bill(bill.id), bill.name, $0, up(bill.amount * s)) }
        }
        for debt in budget.debts {
            let s = share(of: member, owner: debt.owner, split: debt.split, on: date)
            let left = remaining(of: debt, before: date)
            guard s > 0, left > 0 else { continue }
            due += monthDays([debt.day], from: date, to: last).prefix(1)
                .map { (.debt(debt.id), debt.name, $0, up(min(debt.payment, left) * s)) }
        }
        for sub in budget.subscriptions {
            let s = share(of: member, owner: sub.owner, split: sub.split, on: date)
            guard s > 0 else { continue }
            let dates = charges(of: sub, from: date, to: last)
            if let first = dates.first {
                due.append((.subscription(sub.id), sub.name, first, up(sub.amount * Decimal(dates.count) * s)))
            }
        }
        for item in due.sorted(by: { $0.date < $1.date }) {
            take(item.target, item.name, item.amount)
        }

        for envelope in budget.envelopes.sorted(by: { $0.priority < $1.priority }) {
            let s = share(of: member, owner: envelope.owner, split: envelope.split, on: date)
            guard s > 0 else { continue }
            let planned = contribution(envelope, member: member, on: date, pay: pay, share: s)
            if planned > 0 { take(.envelope(envelope.id), envelope.name, planned) }
        }

        return Plan(member: member, date: date, next: next, pay: pay, lines: lines, free: max(left, 0))
    }

    func contribution(_ envelope: Envelope, member: UUID, on date: Date, pay: Decimal, share: Decimal) -> Decimal {
        switch envelope.goal {
        case .perPayday(let amount):
            return up(amount * share)
        case .percent(let percent):
            return up(pay * percent / 100)
        case .yearly(let amount):
            let count = paydays(of: member, from: date, to: add(-1, to: yearLater(date))!).count
            return up(amount * share / Decimal(max(count, 1)))
        case .target(let amount, let by):
            let remaining = max(0, amount - balance(of: envelope, before: date)) * share
            let count = paydays(of: member, from: date, to: by).count
            return up(remaining / Decimal(max(count, 1)))
        case .open:
            return 0
        }
    }

    /// A payday record from a plan, keeping the existing record's id and done marks.
    public func confirm(_ plan: Plan, actual: Decimal?) -> Payday {
        let old = payday(of: plan.member, on: plan.date)
        let done = Set(old?.allocations.filter(\.isDone).map(\.target) ?? [])
        let allocations = plan.lines.map { Allocation(target: $0.target, amount: $0.amount, isDone: done.contains($0.target)) }
            + [Allocation(target: .free, amount: plan.free)]
        return Payday(id: old?.id ?? UUID(), member: plan.member, date: plan.date, actual: actual, allocations: allocations)
    }

    public func payday(of member: UUID, on date: Date) -> Payday? {
        budget.paydays.first { $0.member == member && day($0.date) == day(date) }
    }

    // MARK: Debts

    /// What is left of a debt before `date`: its balance on `asOf`, plus monthly interest, minus payments marked done since.
    public func remaining(of debt: Debt, before date: Date) -> Decimal {
        let date = day(date), since = day(debt.asOf)
        let payments = budget.paydays.filter { day($0.date) >= since && day($0.date) < date }
            .sorted { $0.date < $1.date }
            .flatMap(\.allocations)
            .filter { $0.isDone && $0.target == .debt(debt.id) }
        // shortcut: interest is added once per payment made, not by calendar month; close enough for a plan.
        let monthly = debt.rate / 1200
        return payments.reduce(debt.balance) { left, payment in max(0, left + left * monthly - payment.amount) }
    }

    /// Months, interest and payoff date at a monthly payment; nil if the payment never covers the interest.
    public func payoff(balance: Decimal, rate: Decimal, payment: Decimal, from date: Date) -> Payoff? {
        Payoff.compute(balance: balance, rate: rate, payment: payment).map { months, interest in
            Payoff(months: months, interest: interest,
                   date: calendar.date(byAdding: .month, value: max(months - 1, 0), to: day(date))!)
        }
    }

    // MARK: Subscriptions

    /// Charge dates of an active subscription in [from, to], none before the trial ends.
    public func charges(of sub: Subscription, from: Date, to: Date) -> [Date] {
        guard sub.isActive else { return [] }
        let from = day(from), to = day(to), anchor = day(sub.trialEnds ?? sub.anchor)
        let (unit, step): (Calendar.Component, Int) = switch sub.cycle {
        case .weekly: (.day, 7)
        case .monthly: (.month, 1)
        case .quarterly: (.month, 3)
        case .yearly: (.year, 1)
        }
        // From the anchor, step forward (or back for an old anchor) by whole cycles, counted from the anchor to keep month ends.
        var out: [Date] = []
        var k = 0
        if anchor < from {
            let rough = calendar.dateComponents([unit], from: anchor, to: from).value(for: unit) ?? 0
            k = max(0, rough / step - 1)
        }
        while let d = calendar.date(byAdding: unit, value: k * step, to: anchor), d <= to {
            if d >= from, sub.trialEnds.map({ d >= day($0) }) ?? true { out.append(d) }
            k += 1
        }
        return out
    }

    public func nextCharge(of sub: Subscription, after date: Date) -> Date? {
        charges(of: sub, from: date, to: calendar.date(byAdding: .year, value: 1, to: date)!).first
    }

    /// The average cost a month.
    public static func monthlyCost(of sub: Subscription) -> Decimal {
        switch sub.cycle {
        case .weekly: sub.amount * 52 / 12
        case .monthly: sub.amount
        case .quarterly: sub.amount / 3
        case .yearly: sub.amount / 12
        }
    }

    // MARK: Per-day number

    /// "About N a day until payday". With a balance check this period:
    /// (balance − allocations not yet done) / days from the check; otherwise free money / period length.
    public func allowance(for member: UUID, on date: Date) -> Allowance? {
        let today = day(date)
        guard let start = current(on: today, of: member), let next = next(after: start, of: member) else { return nil }
        let record = payday(of: member, on: start)
        let allocations = record?.allocations ?? confirm(plan(for: member, on: start), actual: nil).allocations
        let perDay: Decimal
        if let check = budget.checks.filter({ $0.member == member && day($0.date) >= start && day($0.date) <= today })
            .max(by: { $0.date < $1.date }) {
            let unpaid = allocations.filter { !$0.isDone && $0.target != .free }.reduce(0) { $0 + $1.amount }
            perDay = max(0, check.amount - unpaid) / Decimal(max(1, days(day(check.date), next)))
        } else {
            let free = allocations.first { $0.target == .free }?.amount ?? 0
            perDay = free / Decimal(max(1, days(start, next)))
        }
        return Allowance(perDay: down(perDay), daysLeft: max(1, days(today, next)), next: next)
    }

    // MARK: Dates

    func day(_ date: Date) -> Date { calendar.startOfDay(for: date) }
    func add(_ days: Int, to date: Date) -> Date? { calendar.date(byAdding: .day, value: days, to: date) }
    func days(_ from: Date, _ to: Date) -> Int { calendar.dateComponents([.day], from: from, to: to).day ?? 0 }
    func yearLater(_ date: Date) -> Date { calendar.date(byAdding: .year, value: 1, to: date)! }

    /// Given days of every month touching [from, to], clamped to the month's length, unshifted.
    func monthDays(_ days: [Int], from: Date, to: Date) -> [Date] {
        guard var month = calendar.dateInterval(of: .month, for: calendar.date(byAdding: .month, value: -1, to: from)!)?.start
        else { return [] }
        let last = calendar.date(byAdding: .month, value: 1, to: to)!
        var out: [Date] = []
        while month <= last {
            let length = calendar.range(of: .day, in: .month, for: month)?.count ?? 28
            for d in days { out.append(add(min(max(d, 1), length) - 1, to: month)!) }
            month = calendar.date(byAdding: .month, value: 1, to: month)!
        }
        return out.filter { $0 >= from && $0 <= to }
    }

    // shortcut: weekends only, no public holidays; add a per-country holiday list when localizing.
    func shifted(_ date: Date, _ shift: WeekendShift) -> Date {
        let weekday = calendar.component(.weekday, from: date) // 1 Sunday, 7 Saturday
        switch (shift, weekday) {
        case (.earlier, 7): return add(-1, to: date)!
        case (.earlier, 1): return add(-2, to: date)!
        case (.later, 7): return add(2, to: date)!
        case (.later, 1): return add(1, to: date)!
        default: return date
        }
    }
}

// shortcut: rounds to whole currency units, fine for RUB/USD planning; use the currency's minor units if cents matter.
func up(_ value: Decimal) -> Decimal { rounded(value, .up) }
func down(_ value: Decimal) -> Decimal { rounded(value, .down) }
private func rounded(_ value: Decimal, _ mode: NSDecimalNumber.RoundingMode) -> Decimal {
    var value = value, result = Decimal()
    NSDecimalRound(&result, &value, 0, mode)
    return result
}
