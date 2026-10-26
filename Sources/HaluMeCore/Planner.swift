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
    /// Everything this period: the payday, extras and what was kept from the last pay.
    public var pay: Decimal
    public var lines: [Line]
    public var free: Decimal
    /// Vacation or sick pay arriving within this period.
    public var extras: [Arrival] = []
    /// Kept from the last period for this one.
    public var carriedIn: Decimal = 0
    public var shortfall: Decimal { lines.reduce(0) { $0 + $1.planned - $1.amount } }
}

/// Money arriving apart from a payday.
public struct Arrival: Sendable, Hashable {
    public enum Kind: Sendable, Hashable { case vacationPay, sickPayEmployer, sickPayFund }
    public var date: Date
    public var kind: Kind
    public var amount: Decimal
    public var absence: UUID
}

public struct Payoff: Sendable, Hashable {
    public var months: Int
    public var interest: Decimal
    /// The month of the last payment.
    public var date: Date

    /// Payment by payment: interest added, then the payment; nil when the payment doesn't cover the interest.
    /// `months` counts payments (every two weeks for a biweekly debt).
    static func compute(balance: Decimal, rate: Decimal, payment: Decimal, perYear: Int = 12) -> (months: Int, interest: Decimal)? {
        var left = balance, months = 0, interest: Decimal = 0
        let monthly = rate / 100 / Decimal(perYear)
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
            // Widened: a shift past weekends and holidays can move a date up to two weeks.
            raw = monthDays(days, from: add(-14, to: from)!, to: add(14, to: to)!)
        case .everyWeeks(let weeks, let anchor):
            let step = max(1, weeks) * 7, anchor = day(anchor)
            // Paydays run both ways from the anchor: one known payday stands for the whole schedule.
            var k = Int((Double(self.days(anchor, from)) / Double(step)).rounded(.down)) - 1
            var out: [Date] = []
            while let d = add(k * step, to: anchor), d <= add(14, to: to)! {
                out.append(d)
                k += 1
            }
            raw = out
        case .daily:
            // Planned weekly: one "payday" each Monday.
            let back = (calendar.component(.weekday, from: from) + 5) % 7 // days since Monday
            var monday = add(-back, to: from)!
            var out: [Date] = []
            while monday <= to {
                out.append(monday)
                monday = add(7, to: monday)!
            }
            return out.filter { $0 >= from && $0 <= to }
        }
        return raw.map { shifted($0, income.shift) }.filter { $0 >= from && $0 <= to }
    }

    /// What one income is expected to bring on one of its paydays, less the working days missed.
    public func expected(of income: Income, on date: Date) -> Decimal {
        pay(of: income, on: date, absences: true)
    }

    /// The same without time off: what a usual payday brings.
    public func usual(of income: Income, on date: Date) -> Decimal {
        pay(of: income, on: date, absences: false)
    }

    /// After tax when the income is entered before tax, unless `gross`.
    func pay(of income: Income, on date: Date, absences: Bool, gross: Bool = false) -> Decimal {
        let amount = grossPay(of: income, on: date, absences: absences)
        // Gross stays in the income's currency (taxes are counted there); take-home pay comes in the budget's.
        guard !gross else { return amount }
        return budget.convert(income.tax == nil ? amount : amount - tax(of: income, gross: amount, on: date), from: income.currency)
    }

    func grossPay(of income: Income, on date: Date, absences: Bool) -> Decimal {
        let date = day(date)
        if income.irregular {
            // Last month's earnings, in the income's currency; the estimate until any are recorded.
            let earned = earnings(of: income, inMonthOf: calendar.date(byAdding: .month, value: -1, to: date)!)
            return earned > 0 ? budget.convert(earned, to: income.currency) : income.expected
        }
        // Working days in [from, to] and how many of them were worked.
        func span(_ from: Date, _ to: Date) -> (worked: Int, all: Int) {
            let all = workdayCount(from, to)
            return (absences ? all - absentWorkdays(of: income.member, from, to) : all, all)
        }
        // amount × worked / all, multiplied before dividing so whole sums stay whole.
        func part(_ amount: Decimal, _ d: (worked: Int, all: Int), over total: Int? = nil) -> Decimal {
            let den = total ?? d.all
            return den > 0 ? down(amount * Decimal(d.worked) / Decimal(den)) : amount
        }
        switch income.schedule {
        case .daily(let weekdaysOnly):
            let days = (0..<7).map { add($0, to: date)! }
                .filter { !weekdaysOnly || isWorkday($0) }
                .filter { d in !absences || !isAbsent(income.member, on: d) }
            return income.expected * Decimal(days.count)
        case .everyWeeks(let weeks, _):
            return part(income.expected, span(add(-7 * max(weeks, 1), to: date)!, add(-1, to: date)!))
        case .monthly(let days):
            guard income.isMonthly else { return income.expected }
            // Which nominal day was moved onto this date by the weekend and holiday rule.
            let nominal = monthDays(days, from: add(-14, to: date)!, to: add(14, to: date)!)
                .first { shifted($0, income.shift) == date } ?? date
            guard days.count == 2 else {
                // One payday a month pays the month before.
                let (start, end) = monthBounds(calendar.date(byAdding: .month, value: -1, to: nominal)!)
                return part(income.expected, span(start, end))
            }
            // A payday late in the month pays the first half of that month (the advance);
            // an early one pays the rest of the month before.
            let firstHalf = calendar.component(.day, from: nominal) >= 16
            let month = firstHalf ? nominal : calendar.date(byAdding: .month, value: -1, to: nominal)!
            let (start, end) = monthBounds(month)
            let mid = add(14, to: start)!
            let firstDays = span(start, mid), wholeMonth = span(start, end)
            let advance: Decimal = switch income.split {
            case .equal: part(income.expected, firstDays, over: firstDays.all * 2)
            case .advance(let amount): part(min(amount, income.expected), firstDays)
            case .byWorkdays: part(income.expected, firstDays, over: wholeMonth.all)
            }
            let earned = part(income.expected, wholeMonth)
            return firstHalf ? advance : max(0, earned - advance)
        }
    }

    /// What an irregular income brought in the calendar month of `date`, in the budget's currency.
    public func earnings(of income: Income, inMonthOf date: Date) -> Decimal {
        let (start, end) = monthBounds(date)
        return budget.inflows.filter { $0.income == income.id && day($0.date) >= start && day($0.date) <= end }
            .reduce(0) { $0 + budget.convert($1.amount, from: $1.currency) }
    }

    func monthBounds(_ date: Date) -> (Date, Date) {
        let start = calendar.dateInterval(of: .month, for: date)!.start
        return (start, add(calendar.range(of: .day, in: .month, for: start)!.count - 1, to: start)!)
    }

    // MARK: Working days and time off

    public func isWorkday(_ date: Date) -> Bool {
        budget.workCalendar?.isWorkday(date, calendar: calendar) ?? !calendar.isDateInWeekend(date)
    }

    /// Working days in [from, to], both included.
    public func workdayCount(_ from: Date, _ to: Date) -> Int {
        var n = 0, d = day(from)
        while d <= day(to) { if isWorkday(d) { n += 1 }; d = add(1, to: d)! }
        return n
    }

    func isAbsent(_ member: UUID, on date: Date) -> Bool {
        budget.absences.contains { $0.member == member && day($0.from) <= date && date <= day($0.to) }
    }

    func absentWorkdays(of member: UUID, _ from: Date, _ to: Date) -> Int {
        var n = 0, d = day(from)
        while d <= day(to) { if isWorkday(d) && isAbsent(member, on: d) { n += 1 }; d = add(1, to: d)! }
        return n
    }

    /// What a member's paydays on this date usually bring, without time off.
    public func usual(of member: UUID, on date: Date) -> Decimal {
        budget.incomes.filter { $0.member == member && !dates(of: $0, from: date, to: date).isEmpty }
            .reduce(0) { $0 + usual(of: $1, on: date) }
    }

    /// A period's money without what an earlier period kept for it: the payday plus extras before the next one.
    func incoming(of member: UUID, at date: Date, next: Date) -> Decimal {
        (payday(of: member, on: date)?.actual ?? expected(of: member, on: date))
            + extras(of: member, from: date, to: add(-1, to: next)!).reduce(0) { $0 + $1.amount }
    }

    func nextOrMonth(after date: Date, of member: UUID) -> Date {
        next(after: date, of: member) ?? calendar.date(byAdding: .month, value: 1, to: date)!
    }

    /// How much of this period's money to keep for the next paydays that come in short (up to three ahead).
    func carryOut(of member: UUID, at date: Date, next: Date, money: Decimal) -> Decimal {
        let excess = money - usual(of: member, on: date)
        guard excess > 0 else { return 0 }
        var short: Decimal = 0, payday = next
        for _ in 0..<3 {
            let after = nextOrMonth(after: payday, of: member)
            short += max(0, usual(of: member, on: payday) - incoming(of: member, at: payday, next: after))
            payday = after
        }
        // The user can also keep the extra of a bigger pay for the next one ("pay ahead").
        let chosen = min(self.payday(of: member, on: date)?.keep ?? 0, excess)
        return down(max(min(excess, short), chosen))
    }

    /// What the periods before `date` kept for it (passed on until the short payday).
    func carry(of member: UUID, into date: Date, depth: Int = 3) -> Decimal {
        guard depth > 0, let previous = current(on: add(-1, to: date)!, of: member) else { return 0 }
        let money = incoming(of: member, at: previous, next: date) + carry(of: member, into: previous, depth: depth - 1)
        return carryOut(of: member, at: previous, next: date, money: money)
    }

    /// A member's usual monthly salary (salaried incomes only).
    func monthlySalary(of member: UUID) -> Decimal {
        budget.incomes.filter { $0.member == member && $0.isMonthly }.reduce(0) { $0 + budget.convert($1.expected, from: $1.currency) }
    }

    /// Money that comes apart from paydays: vacation pay before a vacation, sick pay after sick leave.
    public func extras(of member: UUID, from: Date, to: Date) -> [Arrival] {
        let monthly = monthlySalary(of: member)
        guard monthly > 0 else { return [] }
        var out: [Arrival] = []
        for absence in budget.absences where absence.member == member {
            let first = day(absence.from), last = day(absence.to)
            switch absence.kind {
            case .vacation:
                // Paid at least 3 days ahead (Labour Code art. 136), on a working day; average day = month / 29.3.
                var payday = add(-3, to: first)!
                while !isWorkday(payday) { payday = add(-1, to: payday)! }
                var days = 0, d = first
                while d <= last {
                    if !(budget.workCalendar?.isVacationHoliday(d, calendar: calendar) ?? false) { days += 1 }
                    d = add(1, to: d)!
                }
                out.append(Arrival(date: payday, kind: .vacationPay,
                                   amount: down(monthly / Decimal(string: "29.3")! * Decimal(days) * afterTaxShare(of: member, on: payday)), absence: absence.id))
            case .sickLeave:
                // shortcut: average day from the current salary; employers use the two previous years' earnings.
                let total = days(first, last) + 1
                var average = monthly * 12 / 365
                // Russia caps the average day at the two years' contribution limits / 730 (2024 + 2025 for 2026).
                if budget.country == "RU" { average = min(average, Self.russiaSickDayCap) }
                let daily = average * Decimal(absence.sickPercent) / 100 * afterTaxShare(of: member, on: last)
                // The employer pays the first 3 days with the next payday; the Social Fund the rest about two weeks after.
                if let next = paydays(of: member, from: add(1, to: last)!, to: add(60, to: last)!).first {
                    out.append(Arrival(date: next, kind: .sickPayEmployer, amount: down(daily * Decimal(min(3, total))), absence: absence.id))
                }
                if total > 3 {
                    out.append(Arrival(date: add(14, to: last)!, kind: .sickPayFund, amount: down(daily * Decimal(total - 3)), absence: absence.id))
                }
            case .unpaid:
                break
            }
        }
        return out.filter { $0.date >= day(from) && $0.date <= day(to) }.sorted { $0.date < $1.date }
    }

    /// (2 225 000 + 2 759 000) / 730: the most a sick day can be paid for in 2026.
    static let russiaSickDayCap = Decimal(string: "6827.40")!

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
            .reduce(0) { $0 + expected(of: $1, on: date) }
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
        case .turns:
            let c = calendar.dateComponents([.year, .month], from: date)
            return all[(c.year! * 12 + c.month!) % all.count] == member ? 1 : 0
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

    /// Opening money, transfers marked done, withdrawals and interest that stays in the account, before `date`.
    public func balance(of envelope: Envelope, before date: Date) -> Decimal {
        ledger(of: envelope, before: date).balance
    }

    /// The balance before `date` and the interest accrued since the last payout: banks count it daily
    /// on the day's balance and pay it on the payout day.
    func ledger(of envelope: Envelope, before date: Date) -> (balance: Decimal, accrued: Decimal) {
        let envelope = budget.terms(of: envelope)
        let date = day(date), opened = day(envelope.openedAt)
        var events: [(date: Date, change: Decimal?)] = []
        for payday in budget.paydays where day(payday.date) < date {
            for a in payday.allocations where a.isDone && a.target == .envelope(envelope.id) {
                events.append((day(payday.date), a.amount))
            }
        }
        for w in budget.withdrawals where w.envelope == envelope.id && day(w.date) < date {
            events.append((day(w.date), -w.amount))
        }
        for inflow in budget.inflows where day(inflow.date) < date {
            for a in inflow.allocations where a.target == .envelope(envelope.id) { events.append((day(inflow.date), a.amount)) }
            // Money taken out to cover spending.
            if inflow.kind == .fromSaving, inflow.fromEnvelope == envelope.id {
                events.append((day(inflow.date), -budget.convert(inflow.amount, from: inflow.currency)))
            }
        }
        for t in budget.transfers where day(t.date) < date && (t.from == envelope.id || t.to == envelope.id) {
            events.append((day(t.date), t.from == envelope.id ? -t.amount : t.amount))
        }
        let earns = envelope.holding.earnsInterest && envelope.rate > 0 && opened > .distantPast
        // Interest stops at a deposit's end.
        let accrualEnd = envelope.maturity.map { min(add(1, to: day($0))!, date) } ?? date
        if earns, opened < accrualEnd {
            // nil change = a payout day.
            events += monthDays([envelope.interestDay], from: add(1, to: opened)!, to: add(-1, to: accrualEnd)!).map { ($0, nil) }
        }
        // Payouts first on a shared day: they pay for the days before it.
        events.sort { $0.date != $1.date ? $0.date < $1.date : ($0.change == nil && $1.change != nil) }
        let daily = envelope.rate / 36_500
        var total = envelope.opening, accrued: Decimal = 0, from = opened
        func accrue(to end: Date) {
            let end = min(end, accrualEnd)
            if earns, end > from { accrued += total * daily * Decimal(days(from, end)); from = end }
        }
        for e in events {
            accrue(to: e.date)
            if let change = e.change {
                total = max(0, total + change)
            } else {
                if !envelope.interestToCard { total += accrued }
                accrued = 0
            }
        }
        accrue(to: date)
        return (total, accrued)
    }

    /// The next interest payout of a savings account or deposit, on or after `date`.
    public func nextInterest(of envelope: Envelope, from date: Date) -> (date: Date, amount: Decimal)? {
        let envelope = budget.terms(of: envelope)
        guard envelope.holding.earnsInterest, envelope.rate > 0 else { return nil }
        let start = day(date)
        guard let payout = monthDays([envelope.interestDay], from: start, to: calendar.date(byAdding: .month, value: 1, to: start)!).first,
              envelope.maturity.map({ payout <= day($0) }) ?? true else { return nil }
        return (payout, down(ledger(of: envelope, before: payout).accrued))
    }

    /// Interest a year at the envelope's rate on `amount`.
    public static func yearlyInterest(on amount: Decimal, rate: Decimal) -> Decimal {
        down(amount * rate / 100)
    }

    // MARK: Plan

    public func plan(for member: UUID, on date: Date) -> Plan {
        let date = day(date)
        let next = self.next(after: date, of: member) ?? calendar.date(byAdding: .month, value: 1, to: date)!
        let record = payday(of: member, on: date)
        let extra = extras(of: member, from: date, to: add(-1, to: next)!)
        let carriedIn = carry(of: member, into: date)
        let pay = incoming(of: member, at: date, next: next) + carriedIn
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
        // A wide window: a bill can be paid from a payday chosen ahead of or after its due day.
        let wideFrom = add(-45, to: date)!, wideTo = add(45, to: last)!
        for bill in budget.bills {
            let s = share(of: member, owner: bill.owner, split: bill.split, on: date)
            guard s > 0 else { continue }
            let amount = budget.convert(bill.amount, from: bill.currency) * s
            due += placed(monthDays([bill.day], from: wideFrom, to: wideTo), slot: bill.slot, member: member, period: date, last: last)
                .map { (.bill(bill.id), bill.name, $0.date, up(amount * $0.part)) }
        }
        for debt in budget.debts {
            let s = share(of: member, owner: debt.owner, split: debt.split, on: date)
            let left = remaining(of: debt, before: date)
            guard s > 0, left > 0 else { continue }
            // A biweekly debt can fall twice in one period; never more than what's left.
            let parts = placed(dueDates(of: debt, from: wideFrom, to: wideTo), slot: debt.biweeklyFrom == nil ? debt.slot : nil,
                               member: member, period: date, last: last)
            if let first = parts.first {
                let owed = min(debt.payment * parts.reduce(0) { $0 + $1.part }, left)
                due.append((.debt(debt.id), debt.name, first.date, up(budget.convert(owed, from: debt.currency) * s)))
            }
        }
        for sub in budget.subscriptions {
            let s = share(of: member, owner: sub.owner, split: sub.split, on: date)
            guard s > 0 else { continue }
            let parts = placed(charges(of: sub, from: wideFrom, to: wideTo), slot: sub.slot, member: member, period: date, last: last)
            if let first = parts.first {
                due.append((.subscription(sub.id), sub.name, first.date,
                            up(budget.convert(sub.amount, from: sub.currency) * parts.reduce(0) { $0 + $1.part } * s)))
            }
        }
        for item in due.sorted(by: { $0.date < $1.date }) {
            take(item.target, item.name, item.amount)
        }

        // Smoothing: a bigger period (vacation pay came) keeps enough for a smaller next payday.
        let keep = carryOut(of: member, at: date, next: next, money: pay)
        if keep > 0 { take(.carry, "", keep) }

        for envelope in budget.envelopes.sorted(by: { $0.priority < $1.priority }) {
            let s = share(of: member, owner: envelope.owner, split: envelope.split, on: date)
            guard s > 0 else { continue }
            let planned = contribution(envelope, member: member, on: date, pay: pay, share: s)
            if planned > 0 { take(.envelope(envelope.id), envelope.name, planned) }
        }

        return Plan(member: member, date: date, next: next, pay: pay, lines: lines, free: max(left, 0),
                    extras: extra, carriedIn: carriedIn)
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
        case .annual(let amount, let on):
            // Saved by the next time the date comes round; paying it (a withdrawal) starts the next year.
            let next = nextOccurrence(of: on, from: date)
            let missing = max(0, amount - balance(of: envelope, before: date)) * share
            return up(missing / Decimal(max(paydays(of: member, from: date, to: next).count, 1)))
        case .project(let id):
            guard let project = budget.projects.first(where: { $0.id == id }) else { return 0 }
            return projectContribution(envelope, project: project, member: member, on: date, share: share)
        }
    }

    /// A payday record from a plan, keeping the existing record's id and done marks.
    public func confirm(_ plan: Plan, actual: Decimal?) -> Payday {
        let old = payday(of: plan.member, on: plan.date)
        let done = Set(old?.allocations.filter(\.isDone).map(\.target) ?? [])
        let allocations = plan.lines.map { Allocation(target: $0.target, amount: $0.amount, isDone: done.contains($0.target)) }
            + [Allocation(target: .free, amount: plan.free)]
        var record = Payday(id: old?.id ?? UUID(), member: plan.member, date: plan.date, actual: actual, allocations: allocations)
        record.leftover = old?.leftover
        record.keep = old?.keep
        return record
    }

    public func payday(of member: UUID, on date: Date) -> Payday? {
        budget.paydays.first { $0.member == member && day($0.date) == day(date) }
    }

    // MARK: Which payday pays

    /// The days of the month a member is paid on, when there are several (a two-payday salary).
    public func slotDays(of member: UUID) -> (days: [Int], shift: WeekendShift)? {
        for income in budget.incomes where income.member == member {
            if case .monthly(let days) = income.schedule, days.count >= 2 { return (days.sorted(), income.shift) }
        }
        return nil
    }

    /// Of these due dates, the ones this period pays and how much of each (half when split between paydays).
    func placed(_ dues: [Date], slot: PaySlot?, member: UUID, period: Date, last: Date) -> [(date: Date, part: Decimal)] {
        guard let slot, let paid = slotDays(of: member) else {
            return dues.filter { $0 >= period && $0 <= last }.map { ($0, 1) }
        }
        let picks: [(Int, Decimal)] = switch slot {
        case .payday(let k): [(paid.days[min(max(k, 0), paid.days.count - 1)], 1)]
        case .split: paid.days.map { ($0, 1 / Decimal(paid.days.count)) }
        }
        var out: [(Date, Decimal)] = []
        for due in dues {
            let (start, end) = monthBounds(due)
            for (dayOfMonth, part) in picks {
                guard let nominal = monthDays([dayOfMonth], from: start, to: end).first else { continue }
                if shifted(nominal, paid.shift) == period { out.append((period, part)) }
            }
        }
        return out
    }

    // MARK: Debts

    /// What is left of a debt before `date`: its balance on `asOf`, plus interest on each due date, minus payments marked done since.
    /// Interest is counted only up to the last payment marked done: after it, the app doesn't know what was paid.
    public func remaining(of debt: Debt, before date: Date) -> Decimal {
        let date = day(date), since = day(debt.asOf)
        // Payments are in the budget's currency; the balance in the debt's.
        let payments: [(date: Date, amount: Decimal)] = budget.paydays.filter { day($0.date) >= since && day($0.date) < date }
            .flatMap { p in p.allocations.filter { $0.isDone && $0.target == .debt(debt.id) }.map { (day(p.date), budget.convert($0.amount, to: debt.currency)) } }
        var events = payments.map { (date: $0.date, amount: Optional($0.amount)) }
        if debt.rate > 0, let lastPaid = payments.map(\.date).max() {
            events += dueDates(of: debt, from: add(1, to: since)!, to: lastPaid).map { (date: $0, amount: nil) }
        }
        // Interest first on a shared day: a payment covers the period's interest.
        events.sort { $0.date != $1.date ? $0.date < $1.date : ($0.amount == nil && $1.amount != nil) }
        let periodRate = debt.rate / 100 / Decimal(debt.biweeklyFrom == nil ? 12 : 26)
        return events.reduce(debt.balance) { left, e in max(0, e.amount.map { left - $0 } ?? left + left * periodRate) }
    }

    /// Months, interest and payoff date at a monthly payment; nil if the payment never covers the interest.
    public func payoff(balance: Decimal, rate: Decimal, payment: Decimal, from date: Date) -> Payoff? {
        Payoff.compute(balance: balance, rate: rate, payment: payment).map { months, interest in
            Payoff(months: months, interest: interest,
                   date: calendar.date(byAdding: .month, value: max(months - 1, 0), to: day(date))!)
        }
    }

    /// Months (payments, for a biweekly debt), interest and payoff date; nil if the payment never covers the interest.
    public func payoff(of debt: Debt, balance: Decimal, payment: Decimal, from date: Date) -> Payoff? {
        guard debt.biweeklyFrom != nil else { return self.payoff(balance: balance, rate: debt.rate, payment: payment, from: date) }
        return Payoff.compute(balance: balance, rate: debt.rate, payment: payment, perYear: 26).map { count, interest in
            Payoff(months: count, interest: interest, date: add(14 * max(count - 1, 0), to: day(date))!)
        }
    }

    /// Monthly due dates on `day` in [from, to].
    public func dueDates(day: Int, from: Date, to: Date) -> [Date] {
        monthDays([day], from: self.day(from), to: self.day(to))
    }

    /// The next due day of a debt, today included.
    public func nextDue(of debt: Debt, from date: Date) -> Date {
        dueDates(of: debt, from: date, to: calendar.date(byAdding: .month, value: 1, to: day(date))!).first ?? day(date)
    }

    /// A debt's payment dates in [from, to]: monthly on its day, or every two weeks starting on `biweeklyFrom`.
    public func dueDates(of debt: Debt, from: Date, to: Date) -> [Date] {
        let from = day(from), to = day(to)
        guard let anchor = debt.biweeklyFrom.map(day) else { return monthDays([debt.day], from: from, to: to) }
        var k = max(0, Int((Double(days(anchor, from)) / 14).rounded(.down)))
        var out: [Date] = []
        while let d = add(k * 14, to: anchor), d <= to {
            if d >= from { out.append(d) }
            k += 1
        }
        return out
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
    /// Spending money a period gained or lost outside its plan: what's left of extra money, minus unplanned spending.
    /// `after`: only what happened after that moment (a balance check already holds the rest of its day).
    public func adjustment(of member: UUID, from: Date, to: Date, after: Date? = nil) -> Decimal {
        let inside = { (d: Date) in self.day(d) >= self.day(from) && self.day(d) <= self.day(to) && after.map { d > $0 } ?? true }
        let gained = budget.inflows.filter { $0.member == member && $0.income == nil && inside($0.date) }
            .reduce(Decimal(0)) { $0 + budget.convert($1.amount, from: $1.currency) - $1.allocations.reduce(0) { $0 + $1.amount } }
        let spent = budget.outflows.filter { $0.member == member && inside($0.date) }
            .reduce(Decimal(0)) { $0 + budget.convert($1.amount, from: $1.currency) }
        return gained - spent
    }

    public func allowance(for member: UUID, on date: Date) -> Allowance? {
        let today = day(date)
        guard let start = current(on: today, of: member), let next = next(after: start, of: member) else { return nil }
        let record = payday(of: member, on: start)
        let allocations = record?.allocations ?? confirm(plan(for: member, on: start), actual: nil).allocations
        let perDay: Decimal
        if let check = budget.checks.filter({ $0.member == member && day($0.date) >= start && day($0.date) <= today })
            .max(by: { $0.date < $1.date }) {
            let unpaid = allocations.filter { !$0.isDone && $0.target != .free }.reduce(0) { $0 + $1.amount }
            // The balance already holds what came or went before it was checked.
            let since = adjustment(of: member, from: day(check.date), to: add(-1, to: next)!, after: check.date)
            perDay = max(0, check.amount - unpaid + since) / Decimal(max(1, days(day(check.date), next)))
        } else {
            let free = (allocations.first { $0.target == .free }?.amount ?? 0) + adjustment(of: member, from: start, to: add(-1, to: next)!)
            perDay = max(0, free) / Decimal(max(1, days(start, next)))
        }
        return Allowance(perDay: down(perDay), daysLeft: max(1, days(today, next)), next: next)
    }

    // MARK: Dates

    /// The next day (today included) with the same day and month as `date`.
    public func nextOccurrence(of date: Date, from start: Date) -> Date {
        let c = calendar.dateComponents([.month, .day], from: date)
        let year = calendar.component(.year, from: start)
        for y in [year, year + 1] {
            if let d = calendar.date(from: DateComponents(year: y, month: c.month, day: c.day)), day(d) >= day(start) { return day(d) }
        }
        return day(start)
    }

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

    /// A payday on a day off moves to the working day before (or after); holidays count when there is a work calendar.
    func shifted(_ date: Date, _ shift: WeekendShift) -> Date {
        guard shift != .none else { return date }
        var d = date
        for _ in 0..<14 where !isWorkday(d) { d = add(shift == .earlier ? -1 : 1, to: d)! }
        return d
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
