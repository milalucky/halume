import Foundation
import HaluMeCore

var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(identifier: "UTC")!

@MainActor func d(_ y: Int, _ m: Int, _ day: Int) -> Date {
    calendar.date(from: DateComponents(year: y, month: m, day: day))!
}

var failures = 0
@MainActor func check(_ ok: Bool, _ what: String, line: Int = #line) {
    if !ok { failures += 1; print("FAIL line \(line): \(what)") }
}

let me = Member(name: "Milana"), partner = Member(name: "Alina")
let salary = Income(member: me.id, name: "Salary", schedule: .monthly(days: [10, 25]), expected: 80_000)
let partnerSalary = Income(member: partner.id, name: "Salary", schedule: .monthly(days: [10, 25]), expected: 40_000)
let rent = Bill(owner: .shared, name: "Rent", amount: 90_000, day: 5)
let phone = Bill(owner: .member(me.id), name: "Phone", amount: 1_000, day: 15)
let trip = Envelope(owner: .shared, name: "Trip", goal: .target(120_000, by: d(2027, 6, 1)), priority: 1)
let cushion = Envelope(owner: .member(me.id), name: "Cushion", goal: .percent(10), priority: 2)
let insurance = Envelope(owner: .member(me.id), name: "Insurance", goal: .yearly(24_000), priority: 3)
var budget = Budget(name: "Home", currency: "RUB", members: [me, partner],
                    incomes: [salary, partnerSalary], bills: [rent, phone], envelopes: [trip, cushion, insurance])
var planner = Planner(budget, calendar: calendar)

// Pay dates: 25 Oct 2026 is a Sunday, paid on Friday the 23rd.
check(planner.paydays(of: me.id, from: d(2026, 10, 1), to: d(2026, 11, 30)) == [d(2026, 10, 9), d(2026, 10, 23), d(2026, 11, 10), d(2026, 11, 25)],
      "monthly dates with weekend shift")
check(planner.next(after: d(2026, 10, 23), of: me.id) == d(2026, 11, 10), "next payday")
check(planner.expected(of: me.id, on: d(2026, 10, 23)) == 80_000, "expected pay on shifted day")

// Day 31 clamps to February's end; Jan 31 and Feb 28 2027 are Sundays → later → Feb 1, Mar 1.
let endOfMonth = Income(member: me.id, name: "x", schedule: .monthly(days: [31]), shift: .later, expected: 1)
check(planner.dates(of: endOfMonth, from: d(2027, 2, 1), to: d(2027, 3, 2)) == [d(2027, 2, 1), d(2027, 3, 1)], "day 31 in February")

let biweekly = Income(member: me.id, name: "x", schedule: .everyWeeks(2, from: d(2026, 1, 2)), shift: .none, expected: 1)
check(planner.dates(of: biweekly, from: d(2026, 10, 1), to: d(2026, 10, 31)) == [d(2026, 10, 9), d(2026, 10, 23)], "every 2 weeks")

// Rent (5 Nov) belongs to the 23 Oct payday, half each with an equal split.
let october = planner.plan(for: me.id, on: d(2026, 10, 23))
check(october.next == d(2026, 11, 10), "plan period end")
check(october.lines.first == .init(target: .bill(rent.id), name: "Rent", planned: 45_000, amount: 45_000), "rent share")
check(!october.lines.contains { $0.target == .bill(phone.id) }, "phone not in this period")
check(october.lines.contains { $0.target == .envelope(cushion.id) && $0.amount == 8_000 }, "10% cushion")
let tripLine = october.lines.first { $0.target == .envelope(trip.id) }!
let tripPaydays = planner.paydays(of: me.id, from: d(2026, 10, 23), to: d(2027, 6, 1)).count
check(tripLine.amount * Decimal(tripPaydays) >= 60_000, "trip share reached by the deadline")
check(october.free == 80_000 - october.lines.reduce(0) { $0 + $1.amount }, "free money")
check(october.shortfall == 0, "no shortfall")

let november = planner.plan(for: me.id, on: d(2026, 11, 10))
check(november.lines.contains { $0.target == .bill(phone.id) && $0.amount == 1_000 }, "phone in November period")
check(!november.lines.contains { $0.target == .bill(rent.id) }, "rent not twice")

// Insurance: 24 000 over 24 paydays a year.
check(october.lines.contains { $0.target == .envelope(insurance.id) && $0.amount == 1_000 }, "yearly spread")

// Short pay: bills first, then envelopes by priority.
budget.paydays = [Payday(member: me.id, date: d(2026, 10, 23), actual: 50_000, allocations: [])]
planner = Planner(budget, calendar: calendar)
let short = planner.plan(for: me.id, on: d(2026, 10, 23))
check(short.lines[0].amount == 45_000, "rent paid first")
check(short.lines[1].target == .envelope(trip.id) && short.lines[1].amount == short.lines[1].planned, "trip (priority 1) funded in full")
check(short.lines[2].target == .envelope(cushion.id) && short.lines[2].amount == 5_000 - short.lines[1].amount, "cushion gets the rest")
check(short.free == 0 && short.shortfall > 0, "shortfall reported")

// Split by income: 80k vs 40k → two thirds.
var byIncome = budget
byIncome.bills = [Bill(owner: .shared, name: "Rent", amount: 90_000, day: 5, split: .byIncome)]
byIncome.paydays = []
check(Planner(byIncome, calendar: calendar).plan(for: me.id, on: d(2026, 10, 23)).lines.first?.amount == 60_000, "split by income")

// A done transfer counts toward the target, so later contributions drop.
budget.paydays = []
planner = Planner(budget, calendar: calendar)
var record = planner.confirm(planner.plan(for: me.id, on: d(2026, 10, 23)), actual: 80_000)
let before = planner.plan(for: me.id, on: d(2026, 11, 10)).lines.first { $0.target == .envelope(trip.id) }!.amount
record.allocations = record.allocations.map { a in
    var a = a; if a.target == .envelope(trip.id) { a.amount = 30_000; a.isDone = true }; return a
}
budget.paydays = [record]
planner = Planner(budget, calendar: calendar)
let after = planner.plan(for: me.id, on: d(2026, 11, 10)).lines.first { $0.target == .envelope(trip.id) }!.amount
check(after < before, "target catches up after an extra transfer (\(before) → \(after))")
check(planner.confirm(planner.plan(for: me.id, on: d(2026, 10, 23)), actual: 80_000).id == record.id, "confirm keeps the record id")

// Per day without a check: free money over the 18-day period.
let free = record.allocations.first { $0.target == .free }!.amount
let plain = planner.allowance(for: me.id, on: d(2026, 10, 25))!
check(plain.daysLeft == 16 && plain.next == d(2026, 11, 10), "days left")
check(plain.perDay == (free / 18).rounded(), "per day from free money")

// With a check: balance minus what is still to transfer, over days left from the check.
budget.checks = [BalanceCheck(member: me.id, date: d(2026, 10, 30), amount: 70_000)]
planner = Planner(budget, calendar: calendar)
let unpaid = record.allocations.filter { !$0.isDone && $0.target != .free }.reduce(0) { $0 + $1.amount }
check(planner.allowance(for: me.id, on: d(2026, 10, 31))!.perDay == ((70_000 - unpaid) / 11).rounded(), "per day from balance")

// Debts: 120 000 at 12% with 10 000 a month → 13 months; 0% split → exact months.
let loan = Debt(owner: .member(me.id), name: "Car", kind: .loan, balance: 120_000, rate: 12, payment: 10_000, day: 15)
let car = planner.payoff(balance: 120_000, rate: 12, payment: 10_000, from: d(2026, 11, 15))!
check(car.months == 13 && car.interest > 7_000 && car.interest < 9_000, "loan payoff (\(car.months) months, \(car.interest))")
let faster = planner.payoff(balance: 120_000, rate: 12, payment: 15_000, from: d(2026, 11, 15))!
check(faster.months == 9 && faster.interest < car.interest, "paying more is faster and cheaper")
check(planner.payoff(balance: 100_000, rate: 24, payment: 1_000, from: d(2026, 11, 15)) == nil, "payment below interest never ends")
check(planner.payoff(balance: 12_000, rate: 0, payment: 3_000, from: d(2026, 11, 15))?.months == 4, "split in 4")

let split = Debt(owner: .member(me.id), name: "Split", kind: .installment, balance: 9_000, asOf: d(2026, 10, 1), payment: 3_000, day: 28)
var withDebts = budget
withDebts.debts = [loan, split]
withDebts.paydays = []
var dp = Planner(withDebts, calendar: calendar)
let debtPlan = dp.plan(for: me.id, on: d(2026, 10, 23))
check(debtPlan.lines.contains { $0.target == .debt(split.id) && $0.amount == 3_000 }, "split payment on the 28th in this period")
check(!debtPlan.lines.contains { $0.target == .debt(loan.id) }, "loan on the 15th is next period")
var paid = dp.confirm(debtPlan, actual: 80_000)
paid.allocations = paid.allocations.map { a in var a = a; if a.target == .debt(split.id) { a.isDone = true }; return a }
withDebts.paydays = [paid]
dp = Planner(withDebts, calendar: calendar)
check(dp.remaining(of: split, before: d(2026, 11, 10)) == 6_000, "split left after a payment")
withDebts.debts[1].balance = 5_000  // 3 000 already paid → 2 000 left
dp = Planner(withDebts, calendar: calendar)
check(dp.plan(for: me.id, on: d(2026, 11, 25)).lines.contains { $0.target == .debt(split.id) && $0.amount == 2_000 },
      "last payment is only what's left")

// Subscriptions: monthly on the 3rd, yearly in March, trial until Nov 20.
let music = Subscription(owner: .member(me.id), name: "Music", amount: 299, anchor: d(2025, 1, 3))
let cloud = Subscription(owner: .member(me.id), name: "Cloud", amount: 1_490, cycle: .yearly, anchor: d(2025, 3, 14))
let trial = Subscription(owner: .member(me.id), name: "Movies", amount: 499, anchor: d(2026, 10, 20), trialEnds: d(2026, 11, 20))
check(planner.charges(of: music, from: d(2026, 10, 23), to: d(2026, 11, 9)) == [d(2026, 11, 3)], "monthly charge in period")
check(planner.charges(of: cloud, from: d(2026, 10, 1), to: d(2027, 3, 31)) == [d(2027, 3, 14)], "yearly charge")
check(planner.charges(of: trial, from: d(2026, 10, 23), to: d(2026, 11, 19)).isEmpty, "nothing during the trial")
check(planner.nextCharge(of: trial, after: d(2026, 10, 25)) == d(2026, 11, 20), "first charge when the trial ends")
let monthEnd = Subscription(owner: .member(me.id), name: "x", amount: 1, anchor: d(2026, 1, 31))
check(planner.charges(of: monthEnd, from: d(2026, 2, 1), to: d(2026, 3, 31)) == [d(2026, 2, 28), d(2026, 3, 31)], "month-end anchor")
check(Planner.monthlyCost(of: cloud) == Decimal(1_490) / 12, "yearly cost per month")
var withSubs = budget
withSubs.subscriptions = [music, cloud, trial]
withSubs.paydays = []
check(Planner(withSubs, calendar: calendar).plan(for: me.id, on: d(2026, 10, 23)).lines.contains { $0.target == .subscription(music.id) && $0.amount == 299 },
      "subscription in the plan")

// Old files without the newer lists still load.
let old = #"{"id":"\#(UUID())","name":"Old","currency":"RUB","members":[]}"#
check((try? JSONDecoder().decode(Budget.self, from: Data(old.utf8)))?.debts.isEmpty == true, "older budget file decodes")

// Round trip.
let data = try JSONEncoder().encode(budget)
check(try JSONDecoder().decode(Budget.self, from: data) == budget, "Codable round trip")

print(failures == 0 ? "All checks passed" : "\(failures) checks failed")
exit(failures == 0 ? 0 : 1)

extension Decimal {
    func rounded() -> Decimal {
        var value = self, result = Decimal()
        NSDecimalRound(&result, &value, 0, .down)
        return result
    }
}
