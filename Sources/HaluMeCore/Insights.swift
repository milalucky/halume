import Foundation

/// How long savings would last without any pay.
public struct Runway: Sendable, Hashable {
    /// Everything in the member's savings (their share of shared ones).
    public var savings: Decimal
    /// Part of it in deposits that can't be taken out early.
    public var locked: Decimal
    /// Bills, debt payments, subscriptions and the usual spending money, a month.
    public var monthlyNeed: Decimal

    public var months: Decimal { monthlyNeed > 0 ? savings / monthlyNeed : 0 }
    public var days: Int { monthlyNeed > 0 ? NSDecimalNumber(decimal: down(savings / monthlyNeed * 365 / 12)).intValue : 0 }
}

/// Savings and things owned less debts, at one moment.
public struct Worth: Sendable, Hashable {
    public var date: Date
    public var savings: Decimal
    public var assets: Decimal
    public var debts: Decimal
    public var total: Decimal { savings + assets - debts }
}

/// What one person sends another (or the shared account) for shared costs in a month.
public struct Owed: Sendable, Hashable {
    public struct Item: Sendable, Hashable {
        public var name: String
        public var amount: Decimal
    }
    public var from: UUID
    /// nil: into a shared account.
    public var to: UUID?
    public var amount: Decimal
    public var items: [Item]
    /// Already sent this month.
    public var settled: Decimal
    public var left: Decimal { max(0, amount - settled) }
}

/// What one pay period did, for the recap when the next pay arrives.
public struct Recap: Sendable, Hashable {
    public struct Goal: Sendable, Hashable {
        public var name: String
        public var before: Decimal
        public var after: Decimal
        /// The target, when the saving has one.
        public var target: Decimal?
    }
    public var start: Date
    public var end: Date
    public var pay: Decimal
    public var saved: Decimal
    public var savingPlanned: Decimal
    /// Bills, subscriptions and debt payments marked paid.
    public var paid: Decimal
    public var extra: Decimal
    public var unplanned: Decimal
    public var takenOut: Decimal
    public var leftover: Decimal?
    public var goals: [Goal]
}

extension Planner {
    // MARK: Runway

    /// Savings over what a month costs: bills, debts and subscriptions (the member's share) plus the usual spending money.
    public func runway(of member: UUID, on date: Date) -> Runway {
        let date = day(date), tomorrow = add(1, to: date)!
        var savings: Decimal = 0, locked: Decimal = 0
        // Only money that is kept: savings for a planned cost (insurance, a trip) are already spoken for.
        for envelope in budget.envelopes where envelope.role == .keep {
            let s = share(of: member, owner: envelope.owner, split: envelope.split, on: date)
            guard s > 0 else { continue }
            let amount = balance(of: envelope, before: tomorrow) * s
            savings += amount
            let account = envelope.account.flatMap { id in budget.accounts.first { $0.id == id } }
            if account.map({ !$0.canWithdraw }) ?? (envelope.holding == .deposit) { locked += amount }
        }
        return Runway(savings: down(savings), locked: down(locked), monthlyNeed: down(monthlyCosts(of: member, on: date) + monthlySpending(of: member, on: date)))
    }

    /// Bills, debt payments and subscriptions a month, the member's share, in the budget's currency.
    public func monthlyCosts(of member: UUID, on date: Date) -> Decimal {
        var total: Decimal = 0
        for bill in budget.bills {
            total += budget.convert(bill.amount, from: bill.currency) * share(of: member, owner: bill.owner, split: bill.split, on: date)
        }
        for debt in budget.debts where remaining(of: debt, before: date) > 0 {
            let monthly = debt.biweeklyFrom == nil ? debt.payment : debt.payment * 26 / 12
            total += budget.convert(monthly, from: debt.currency) * share(of: member, owner: debt.owner, split: debt.split, on: date)
        }
        for sub in budget.subscriptions where sub.isActive {
            total += budget.convert(Self.monthlyCost(of: sub), from: sub.currency) * share(of: member, owner: sub.owner, split: sub.split, on: date)
        }
        return total
    }

    /// The usual free money of a month: this period's free money stretched to 30.4 days.
    func monthlySpending(of member: UUID, on date: Date) -> Decimal {
        guard let start = current(on: date, of: member) else { return 0 }
        let plan = plan(for: member, on: start)
        let length = max(1, days(start, plan.next))
        return plan.free * Decimal(365) / 12 / Decimal(length)
    }

    // MARK: Net worth

    /// Savings plus assets less debts on `date`; the member's share, or the whole household when `member` is nil.
    public func worth(of member: UUID?, on date: Date) -> Worth {
        let date = day(date), tomorrow = add(1, to: date)!
        func part(_ owner: Owner, _ split: Split) -> Decimal {
            guard let member else { return 1 }
            return share(of: member, owner: owner, split: split, on: date)
        }
        let savings = budget.envelopes.reduce(Decimal(0)) { $0 + balance(of: $1, before: tomorrow) * part($1.owner, $1.split) }
        let assets = budget.assets.reduce(Decimal(0)) { $0 + budget.convert($1.value, from: $1.currency) * part($1.owner, .equal) }
        let debts = budget.debts.reduce(Decimal(0)) {
            $0 + budget.convert(remaining(of: $1, before: tomorrow), from: $1.currency) * part($1.owner, $1.split)
        }
        return Worth(date: date, savings: down(savings), assets: down(assets), debts: up(debts))
    }

    /// Net worth at the start of each of the last `months` months and today, oldest first.
    /// shortcut: assets keep today's value in the past; a value history would need dated entries.
    public func worthHistory(of member: UUID?, months: Int, to date: Date) -> [Worth] {
        let start = calendar.dateInterval(of: .month, for: day(date))!.start
        let points = (1...months).reversed().map { calendar.date(byAdding: .month, value: -$0 + 1, to: start)! }
        return points.map { worth(of: member, on: add(-1, to: $0)!) }.map { var w = $0; w.date = add(1, to: w.date)!; return w }
            + [worth(of: member, on: date)]
    }

    // MARK: Who owes whom

    /// Shared bills, debts and subscriptions due in the month of `date`, paid from one person's account:
    /// the others send their shares to that person. Paid from a shared account: everyone sends their share there.
    public func owed(inMonthOf date: Date) -> [Owed] {
        let (start, end) = monthBounds(date)
        var sums: [String: Owed] = [:]
        func add(_ name: String, _ amount: Decimal, owner: Owner, split: Split, payFrom: UUID?, on due: Date) {
            guard owner == .shared, let account = payFrom.flatMap({ id in budget.accounts.first { $0.id == id } }) else { return }
            for member in budget.members {
                let s = share(of: member.id, owner: owner, split: split, on: due)
                guard s > 0 else { continue }
                let to: UUID?
                switch account.owner {
                case .member(let payer): guard payer != member.id else { continue }; to = payer
                case .shared: to = nil
                }
                let key = "\(member.id)-\(to?.uuidString ?? "shared")"
                var o = sums[key] ?? Owed(from: member.id, to: to, amount: 0, items: [], settled: 0)
                o.amount += up(amount * s)
                o.items.append(.init(name: name, amount: up(amount * s)))
                sums[key] = o
            }
        }
        for bill in budget.bills {
            for due in monthDays([bill.day], from: start, to: end) {
                add(bill.name, budget.convert(bill.amount, from: bill.currency), owner: bill.owner, split: bill.split, payFrom: bill.payFrom, on: due)
            }
        }
        for debt in budget.debts where remaining(of: debt, before: start) > 0 {
            for due in dueDates(of: debt, from: start, to: end) {
                add(debt.name, budget.convert(debt.payment, from: debt.currency), owner: debt.owner, split: debt.split, payFrom: debt.payFrom, on: due)
            }
        }
        for sub in budget.subscriptions {
            for due in charges(of: sub, from: start, to: end) {
                add(sub.name, budget.convert(sub.amount, from: sub.currency), owner: sub.owner, split: sub.split, payFrom: sub.payFrom, on: due)
            }
        }
        // Two people paying each other: only the difference moves.
        for (key, o) in sums {
            guard let to = o.to, let back = sums["\(to)-\(o.from)"], sums[key] != nil else { continue }
            if o.amount >= back.amount {
                sums[key]!.amount -= back.amount
                sums["\(to)-\(o.from)"] = nil
            }
        }
        let sent = budget.settlements.filter { day($0.date) >= start && day($0.date) <= end }
        return sums.values.filter { $0.amount > 0 }.map { o in
            var o = o
            o.settled = sent.filter { $0.from == o.from && $0.to == o.to }.reduce(0) { $0 + $1.amount }
            return o
        }
        .sorted { $0.amount > $1.amount }
    }

    // MARK: Subscriptions

    /// Not confirmed as used for three months: worth asking about.
    public func needsReview(_ sub: Subscription, on date: Date) -> Bool {
        guard sub.isActive, sub.trialEnds.map({ day($0) <= day(date) }) ?? true else { return false }
        let since = sub.reviewed ?? sub.anchor
        return calendar.date(byAdding: .month, value: 3, to: day(since))! <= day(date)
    }

    // MARK: Recap

    /// The period before the one running on `date`, from its payday record.
    public func recap(of member: UUID, before date: Date) -> Recap? {
        guard let current = current(on: date, of: member), let start = self.current(on: add(-1, to: current)!, of: member),
              let record = payday(of: member, on: start) else { return nil }
        let inside = { (d: Date) in self.day(d) >= start && self.day(d) < current }
        let isEnvelope: (Target) -> Bool = { if case .envelope = $0 { true } else { false } }
        let isPaid: (Target) -> Bool = {
            switch $0 { case .bill, .subscription, .debt: true; default: false }
        }
        let saved = record.allocations.filter { isEnvelope($0.target) && $0.isDone }.reduce(0) { $0 + $1.amount }
        let planned = record.allocations.filter { isEnvelope($0.target) }.reduce(0) { $0 + $1.amount }
        let paid = record.allocations.filter { isPaid($0.target) && $0.isDone }.reduce(0) { $0 + $1.amount }
        let extra = budget.inflows.filter { $0.member == member && $0.isNewMoney && inside($0.date) }
            .reduce(Decimal(0)) { $0 + budget.convert($1.amount, from: $1.currency) }
        let unplanned = budget.outflows.filter { $0.member == member && inside($0.date) }
            .reduce(Decimal(0)) { $0 + budget.convert($1.amount, from: $1.currency) }
        let mine = budget.envelopes.filter { share(of: member, owner: $0.owner, split: $0.split, on: start) > 0 }
        let takenOut = budget.withdrawals.filter { w in inside(w.date) && mine.contains { $0.id == w.envelope } }.reduce(0) { $0 + $1.amount }
            + budget.inflows.filter { i in i.kind == .fromSaving && inside(i.date) && mine.contains { $0.id == i.fromEnvelope } }
            .reduce(Decimal(0)) { $0 + budget.convert($1.amount, from: $1.currency) }
        let goals = mine.compactMap { envelope -> Recap.Goal? in
            let before = balance(of: envelope, before: start), after = balance(of: envelope, before: current)
            guard after != before else { return nil }
            let target: Decimal? = switch envelope.goal {
            case .target(let amount, _), .annual(let amount, _): amount
            default: nil
            }
            return Recap.Goal(name: envelope.name, before: down(before), after: down(after), target: target)
        }
        .sorted { $0.after - $0.before > $1.after - $1.before }
        return Recap(start: start, end: current, pay: record.actual ?? expected(of: member, on: start), saved: saved, savingPlanned: planned,
                     paid: paid, extra: extra, unplanned: unplanned, takenOut: takenOut,
                     leftover: payday(of: member, on: current)?.leftover, goals: goals)
    }

    // MARK: What if

    /// A changed copy of the budget for "what if" questions; nothing is saved.
    public func scenario(member: UUID, payChange: Decimal = 0, newMonthlyCost: Decimal = 0, newMonthlySaving: Decimal = 0) -> Planner {
        var b = budget
        for i in b.incomes.indices where b.incomes[i].member == member {
            b.incomes[i].expected = down(b.incomes[i].expected * (100 + payChange) / 100)
        }
        // A whole-budget-month cost or saving, paid from the member's first payday each month.
        let first = slotDays(of: member).map { _ in PaySlot.payday(0) }
        if newMonthlyCost > 0 {
            var bill = Bill(owner: .member(member), name: "What if", amount: newMonthlyCost, day: 1)
            bill.slot = first
            b.bills.append(bill)
        }
        if newMonthlySaving > 0 {
            let perPayday = newMonthlySaving / Decimal(max(1, paydays(of: member, from: Date(), to: add(29, to: day(Date()))!).count))
            b.envelopes.append(Envelope(owner: .member(member), name: "What if", goal: .perPayday(up(perPayday)), priority: -1))
        }
        return Planner(b, calendar: calendar)
    }
}
