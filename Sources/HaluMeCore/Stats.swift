import Foundation

/// What happened in one pay period, from its confirmed payday record.
public struct PeriodStats: Sendable, Hashable, Identifiable {
    public var id: Date { date }
    public var date: Date
    public var expected: Decimal
    public var income: Decimal
    /// Bills and subscriptions.
    public var bills: Decimal
    public var debtPlanned: Decimal
    public var debtPaid: Decimal
    public var savingPlanned: Decimal
    public var saved: Decimal
    public var withdrawn: Decimal
    public var interest: Decimal
    public var free: Decimal
    /// Left from this pay when the next one came, if the user said.
    public var leftover: Decimal?

    /// Planned transfers that were not made.
    public var missed: Decimal { max(0, savingPlanned - saved) + max(0, debtPlanned - debtPaid) }

    /// Spent beyond the free money: transfers skipped and savings taken out, less what was left over.
    public var overspent: Decimal { max(0, missed + withdrawn - (leftover ?? 0)) }

    public static func + (a: Self, b: Self) -> Self {
        var sum = a
        sum.expected += b.expected; sum.income += b.income; sum.bills += b.bills
        sum.debtPlanned += b.debtPlanned; sum.debtPaid += b.debtPaid
        sum.savingPlanned += b.savingPlanned; sum.saved += b.saved
        sum.withdrawn += b.withdrawn; sum.interest += b.interest; sum.free += b.free
        sum.leftover = (a.leftover ?? 0) + (b.leftover ?? 0)
        return sum
    }

    static func empty(_ date: Date) -> Self {
        Self(date: date, expected: 0, income: 0, bills: 0, debtPlanned: 0, debtPaid: 0, savingPlanned: 0, saved: 0,
             withdrawn: 0, interest: 0, free: 0, leftover: nil)
    }
}

public enum Grouping: Sendable {
    case payday, month, quarter
}

extension Planner {
    /// Every confirmed pay period of a member starting in [from, to], oldest first.
    public func history(of member: UUID, from: Date, to: Date) -> [PeriodStats] {
        let records = budget.paydays.filter { $0.member == member && day($0.date) >= day(from) && day($0.date) <= day(to) }
            .sorted { $0.date < $1.date }
        return records.map { record in
            let start = day(record.date)
            let end = next(after: start, of: member) ?? calendar.date(byAdding: .month, value: 1, to: start)!
            func sum(_ match: (Target) -> Bool, done: Bool = false) -> Decimal {
                record.allocations.filter { match($0.target) && (!done || $0.isDone) }.reduce(0) { $0 + $1.amount }
            }
            let isBill: (Target) -> Bool = { if case .bill = $0 { true } else if case .subscription = $0 { true } else { false } }
            let isDebt: (Target) -> Bool = { if case .debt = $0 { true } else { false } }
            let isEnvelope: (Target) -> Bool = { if case .envelope = $0 { true } else { false } }
            let mine = Set(budget.envelopes.filter { share(of: member, owner: $0.owner, split: $0.split, on: start) > 0 }.map(\.id))
            let withdrawn = budget.withdrawals.filter { mine.contains($0.envelope) && day($0.date) >= start && day($0.date) < end }
                .reduce(0) { $0 + $1.amount }
            let interest = budget.envelopes.map(budget.terms(of:)).filter { mine.contains($0.id) && $0.holding.earnsInterest && $0.rate > 0 }
                .reduce(Decimal(0)) { total, envelope in
                    total + monthDays([envelope.interestDay], from: start, to: add(-1, to: end)!)
                        .filter { payout in payout > day(envelope.openedAt) && envelope.maturity.map { payout <= day($0) } ?? true }
                        .reduce(0) { sum, payout in sum + down(ledger(of: envelope, before: payout).accrued) }
                }
            let nextRecord = payday(of: member, on: end)
            return PeriodStats(
                date: start, expected: expected(of: member, on: start), income: (record.actual ?? expected(of: member, on: start))
                    + budget.inflows.filter { $0.member == member && $0.income == nil && day($0.date) >= start && day($0.date) < end }
                        .reduce(0) { $0 + budget.convert($1.amount, from: $1.currency) },
                bills: sum(isBill), debtPlanned: sum(isDebt), debtPaid: sum(isDebt, done: true),
                savingPlanned: sum(isEnvelope), saved: sum(isEnvelope, done: true), withdrawn: withdrawn, interest: interest,
                free: sum { $0 == .free }, leftover: nextRecord?.leftover
            )
        }
    }

    /// Periods summed by calendar month or quarter of their start.
    public func group(_ periods: [PeriodStats], by grouping: Grouping) -> [PeriodStats] {
        guard grouping != .payday else { return periods }
        var buckets: [Date: PeriodStats] = [:]
        for p in periods {
            var c = calendar.dateComponents([.year, .month], from: p.date)
            if grouping == .quarter, let m = c.month { c.month = (m - 1) / 3 * 3 + 1 }
            let key = calendar.date(from: c)!
            buckets[key] = (buckets[key] ?? .empty(key)) + p
        }
        return buckets.values.sorted { $0.date < $1.date }
    }

    /// One row per pay period, for spreadsheets.
    public func csv(_ periods: [PeriodStats]) -> String {
        let format = Date.ISO8601FormatStyle().year().month().day()
        let header = "date,expected,income,bills_and_subscriptions,debt_planned,debt_paid,savings_planned,saved,withdrawn,interest,free,leftover,overspent"
        let rows = periods.map { p in
            [p.date.formatted(format), "\(p.expected)", "\(p.income)", "\(p.bills)", "\(p.debtPlanned)", "\(p.debtPaid)",
             "\(p.savingPlanned)", "\(p.saved)", "\(p.withdrawn)", "\(p.interest)", "\(p.free)",
             p.leftover.map { "\($0)" } ?? "", "\(p.overspent)"].joined(separator: ",")
        }
        return ([header] + rows).joined(separator: "\n") + "\n"
    }
}
