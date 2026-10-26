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
// Interest by month: 100 000 at 12%, paid 10 000 on 10 Oct and 10 Nov; 15 Oct's due date adds 1% of 90 000.
let bank = Debt(owner: .member(me.id), name: "Bank", kind: .loan, balance: 100_000, asOf: d(2026, 10, 1), rate: 12, payment: 10_000, day: 15)
var banking = budget
banking.debts = [bank]
banking.paydays = [d(2026, 10, 10), d(2026, 11, 10)].map {
    Payday(member: me.id, date: $0, actual: nil, allocations: [Allocation(target: .debt(bank.id), amount: 10_000, isDone: true)])
}
let bankP = Planner(banking, calendar: calendar)
check(bankP.remaining(of: bank, before: d(2026, 11, 11)) == 80_900, "monthly interest between payments (\(bankP.remaining(of: bank, before: d(2026, 11, 11))))")
check(bankP.remaining(of: bank, before: d(2026, 12, 20)) == 80_900, "no interest guessed after the last payment marked done")

// Split every two weeks: 8 000 in four payments of 2 000 from 26 Oct; 26 Oct and 9 Nov fall before the 10 Nov payday.
var twoWeekly = Debt(owner: .member(me.id), name: "Split", kind: .installment, balance: 8_000, asOf: d(2026, 10, 20), payment: 2_000, day: 26)
twoWeekly.biweeklyFrom = d(2026, 10, 26)
var splitting = budget
splitting.debts = [twoWeekly]
splitting.paydays = []
let bwp = Planner(splitting, calendar: calendar)
check(bwp.dueDates(of: twoWeekly, from: d(2026, 10, 1), to: d(2026, 11, 30)) == [d(2026, 10, 26), d(2026, 11, 9), d(2026, 11, 23)], "every two weeks")
let splitPlan = bwp.plan(for: me.id, on: d(2026, 10, 23))
check(splitPlan.lines.contains { $0.target == .debt(twoWeekly.id) && $0.amount == 4_000 }, "two biweekly payments in one period (\(splitPlan.lines))")
check(bwp.payoff(of: twoWeekly, balance: 8_000, payment: 2_000, from: d(2026, 10, 26))?.date == d(2026, 12, 7), "last biweekly payment")

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

// Savings account: 300 000 at 12%, interest on the 1st stays in the account.
let ozon = Envelope(owner: .member(me.id), name: "Savings account", goal: .open, opening: 300_000, openedAt: d(2026, 9, 15),
                    holding: .savingsAccount, rate: 12, interestDay: 1)
var withInterest = budget
withInterest.envelopes = [ozon]
withInterest.paydays = []
var ip = Planner(withInterest, calendar: calendar)
// Accrued daily on the day's balance: 16 days to 1 Oct (1,578.08), then 31 days on the new balance (3,073.62).
func near(_ a: Decimal, _ b: String) -> Bool { abs((a - Decimal(string: b)!).double) < 0.01 }
check(near(ip.balance(of: ozon, before: d(2026, 10, 2)), "301578.08"), "16 days of interest added (\(ip.balance(of: ozon, before: d(2026, 10, 2))))")
check(near(ip.balance(of: ozon, before: d(2026, 11, 2)), "304651.70"), "compounded (\(ip.balance(of: ozon, before: d(2026, 11, 2))))")
check(ip.nextInterest(of: ozon, from: d(2026, 10, 25))! == (d(2026, 11, 1), 3_073), "next interest")
check(near(ip.balance(of: ozon, before: d(2026, 10, 20)), "301578.08"), "accrued interest isn't in the balance before the payout")
var toCard = ozon; toCard.interestToCard = true
withInterest.envelopes = [toCard]
ip = Planner(withInterest, calendar: calendar)
check(ip.balance(of: toCard, before: d(2026, 11, 2)) == 300_000, "interest paid to the card doesn't grow the balance")
withInterest.withdrawals = [Withdrawal(envelope: toCard.id, date: d(2026, 10, 20), amount: 50_000)]
ip = Planner(withInterest, calendar: calendar)
check(ip.balance(of: toCard, before: d(2026, 10, 21)) == 250_000, "withdrawal comes off")
check(Planner.yearlyInterest(on: 100_000, rate: 12) == 12_000, "yearly interest")

// Stats: two confirmed periods, a skipped transfer and leftover.
var history = budget
history.paydays = []
var hp = Planner(history, calendar: calendar)
var p1 = hp.confirm(hp.plan(for: me.id, on: d(2026, 10, 9)), actual: 70_000)
p1.allocations = p1.allocations.map { a in var a = a; if case .envelope = a.target, a.target != .envelope(cushion.id) { a.isDone = true }; return a }
var p2 = hp.confirm(hp.plan(for: me.id, on: d(2026, 10, 23)), actual: 80_000)
p2.leftover = 2_000
history.paydays = [p1, p2]
hp = Planner(history, calendar: calendar)
let periods = hp.history(of: me.id, from: d(2026, 10, 1), to: d(2026, 10, 31))
check(periods.count == 2 && periods[0].income == 70_000 && periods[0].expected == 80_000, "history income")
let cushionPlanned = p1.allocations.first { $0.target == .envelope(cushion.id) }!.amount
check(periods[0].missed == cushionPlanned && periods[0].leftover == 2_000, "missed transfer and leftover")
check(periods[0].overspent == max(0, cushionPlanned - 2_000), "overspent")
check(hp.group(periods, by: .month).count == 1 && hp.group(periods, by: .month)[0].income == 150_000, "grouped by month")
check(hp.csv(periods).split(separator: "\n").count == 3, "csv rows")

// Monthly salary split between two paydays: the 25th pays the first half, the 10th the rest of the month before.
for split in [PaySplit.equal, .byWorkdays, .advance(70_000)] {
    var monthlyBudget = budget
    monthlyBudget.incomes = [Income(member: me.id, name: "Salary", schedule: .monthly(days: [10, 25]), expected: 200_000,
                                    isMonthly: true, split: split)]
    let mp = Planner(monthlyBudget, calendar: calendar)
    let advance = mp.expected(of: me.id, on: d(2026, 10, 23)) // 25 Oct is a Sunday
    let rest = mp.expected(of: me.id, on: d(2026, 11, 10))
    check(advance + rest == 200_000 && advance > 0 && rest > 0, "\(split): \(advance) + \(rest) = 200 000")
    if case .advance = split { check(advance == 70_000, "fixed advance") }
    if case .byWorkdays = split {
        // October 2026: 11 weekdays in the 1st–15th out of 22.
        check(advance == 100_000, "advance by workdays (\(advance))")
    }
}

// Daily pay, planned by the week from Monday.
var dailyBudget = budget
dailyBudget.incomes = [Income(member: me.id, name: "Shifts", schedule: .daily(weekdaysOnly: true), expected: 5_000)]
let dailyPlanner = Planner(dailyBudget, calendar: calendar)
check(dailyPlanner.paydays(of: me.id, from: d(2026, 10, 1), to: d(2026, 10, 31)) == [d(2026, 10, 5), d(2026, 10, 12), d(2026, 10, 19), d(2026, 10, 26)],
      "daily pay planned on Mondays")
check(dailyPlanner.expected(of: me.id, on: d(2026, 10, 19)) == 25_000, "five weekdays a week")

// Household: a hidden gift envelope stays out of the shared part until its reveal date.
var family = budget
family.paydays = []
let gift = Envelope(owner: .member(me.id), name: "Gift for Alina", goal: .perPayday(3_000), priority: 5, hidden: true,
                    revealOn: d(2027, 3, 8))
family.envelopes.append(gift)
var fp = Planner(family, calendar: calendar)
var giftPay = fp.confirm(fp.plan(for: me.id, on: d(2026, 10, 23)), actual: 80_000)
giftPay.allocations = giftPay.allocations.map { a in var a = a; a.isDone = true; return a }
family.paydays = [giftPay]
family.withdrawals = [Withdrawal(envelope: gift.id, amount: 1_000)]
let shared = family.sharedPart(at: d(2026, 11, 1))
check(!shared.envelopes.contains { $0.id == gift.id } && shared.withdrawals.isEmpty, "hidden envelope not shared")
check(!shared.paydays[0].allocations.contains { $0.target == .envelope(gift.id) }, "transfers to it not shared")
check(shared.paydays[0].allocations.count == giftPay.allocations.count - 1, "everything else shared")
let mine = family.privatePart(of: me.id, at: d(2026, 11, 1))
check(mine.envelopes.map(\.id) == [gift.id] && mine.paydays[0].allocations.count == 1, "private part holds the gift")
check(family.privatePart(of: partner.id, at: d(2026, 11, 1)).envelopes.isEmpty, "the partner has nothing hidden")
let back = Budget.merged(shared: shared, private: mine)
check(Set(back.envelopes.map(\.id)) == Set(family.envelopes.map(\.id)) && Set(back.paydays[0].allocations) == Set(giftPay.allocations)
      && back.withdrawals == family.withdrawals, "merging gives the whole budget back")
check(family.sharedPart(at: d(2027, 3, 8)).envelopes.contains { $0.id == gift.id }, "revealed on the date")
let wantedPhone = Wish(owner: partner.id, name: "iPhone", price: 150_000)
family.wishes = [wantedPhone]
family.reservations = [Reservation(wish: wantedPhone.id, by: me.id)]
check(family.sharedPart(at: d(2026, 11, 1)).wishes == [wantedPhone] && family.sharedPart(at: d(2026, 11, 1)).reservations.isEmpty,
      "wishes shared, who gifts them not")
check(family.privatePart(of: me.id, at: d(2026, 11, 1)).reservations.count == 1, "the giver keeps the reservation")

// Russia's production calendar: January holidays shrink the advance and move paydays back.
var ru = budget
ru.paydays = []; ru.bills = []; ru.envelopes = []; ru.debts = []; ru.subscriptions = []
ru.incomes = [Income(member: me.id, name: "Salary", schedule: .monthly(days: [10, 25]), expected: 200_000, isMonthly: true, split: .byWorkdays)]
ru.workCalendar = .russia
var rp = Planner(ru, calendar: calendar)
check(rp.workdayCount(d(2026, 1, 1), d(2026, 1, 31)) == 15, "15 working days in January 2026")
check(rp.paydays(of: me.id, from: d(2026, 1, 20), to: d(2026, 1, 26)) == [d(2026, 1, 23)], "25 Jan (Sunday) paid on Friday the 23rd")
check(rp.expected(of: me.id, on: d(2026, 1, 23)) == 53_333, "January advance: 4 of 15 working days (\(rp.expected(of: me.id, on: d(2026, 1, 23))))")
check(rp.paydays(of: me.id, from: d(2026, 12, 26), to: d(2027, 1, 12)).contains(d(2026, 12, 30)), "10 Jan 2027 paid on 30 Dec, before the holidays")

// Vacation 2–15 Nov 2026: 14 days less the 4 Nov holiday = 13 paid days, money on Friday 30 Oct.
ru.absences = [Absence(member: me.id, kind: .vacation, from: d(2026, 11, 2), to: d(2026, 11, 15))]
rp = Planner(ru, calendar: calendar)
let vacationPay = rp.extras(of: me.id, from: d(2026, 10, 1), to: d(2026, 11, 30))
check(vacationPay.count == 1 && vacationPay[0].date == d(2026, 10, 30) && vacationPay[0].amount == 88_737, "vacation pay \(vacationPay)")
check(rp.expected(of: me.id, on: d(2026, 11, 25)) == 0, "no advance for a month's first half spent on vacation")
let octPlan = rp.plan(for: me.id, on: d(2026, 10, 23))
let kept = octPlan.lines.first { $0.target == .carry }?.amount ?? 0
check(kept > 0 && octPlan.extras.count == 1, "vacation pay partly kept (\(kept))")
let novPlan = rp.plan(for: me.id, on: d(2026, 11, 25))
check(novPlan.pay > 0 && novPlan.carriedIn > 0, "the empty advance is covered by what was kept (\(novPlan.pay))")

// Sick leave 10 days at 80%: 3 days from the employer on the next payday, 7 from the Social Fund two weeks later.
ru.absences = [Absence(member: me.id, kind: .sickLeave, from: d(2026, 10, 12), to: d(2026, 10, 21), sickPercent: 80)]
rp = Planner(ru, calendar: calendar)
let sick = rp.extras(of: me.id, from: d(2026, 10, 1), to: d(2026, 11, 30))
check(sick.map(\.kind) == [.sickPayEmployer, .sickPayFund] && sick[0].date == d(2026, 10, 23) && sick[1].date == d(2026, 11, 4),
      "sick pay arrivals \(sick.map(\.date))")
check(rp.expected(of: me.id, on: d(2026, 11, 10)) < rp.usual(of: me.id, on: d(2026, 11, 10)), "October's final pay is smaller")
// A big salary in Russia: the average day is capped at 6,827.40 (no tax set up here, so nothing withheld).
var rich = ru
rich.country = "RU"
rich.incomes[0].expected = 1_000_000
let richSick = Planner(rich, calendar: calendar).extras(of: me.id, from: d(2026, 10, 1), to: d(2026, 11, 30))
check(richSick.last?.amount == 38_233, "sick pay capped: 7 days × 6,827.40 × 80% (\(richSick.map(\.amount)))")

// Taxes, 2026.
// Canada, Alberta, $100,000: CPP 4,646.45, EI 1,123.07, federal 13,301.60, Alberta 6,470.38 → about $74,458 a year after tax.
let cppEI = TaxRules.canadaContributions(yearToDate: 100_000)
check((cppEI.pension * 100).rounded() == 423_045 && cppEI.pension2 == 416 && (cppEI.ei * 100).rounded() == 112_307, "CPP and EI")
let qc = TaxRules.canadaContributions(yearToDate: 120_000, province: "QC")
check((qc.pension * 100).rounded() == 447_930 && (qc.ei * 100).rounded() == 89_570 && (qc.qpip * 100).rounded() == 44_290, "QPP, EI and QPIP in Quebec")
let abTax = TaxRules.canadaIncomeTax(annual: 100_000, province: "AB")
check(abs((abTax - Decimal(string: "19771.98")!).double) < 1, "Alberta + federal income tax (\(abTax))")
// Provinces at $100,000, cross-checked with an independent Python calculation from the same tables
// (federal 13,301.60 outside Quebec; Ontario includes surtax and the $750 health premium, B.C. its tax reduction).
for (province, provincial) in [("ON", "6722.75"), ("BC", "5555.52"), ("SK", "8641.02"), ("MB", "9484.18"), ("NS", "12061.78")] {
    let total = TaxRules.canadaIncomeTax(annual: 100_000, province: province)
    check(abs((total - Decimal(string: "13301.60")! - Decimal(string: provincial)!).double) < 2, "\(province) at $100,000 (\(total))")
}
// Ontario at $20,000: the tax reduction ($600 less 288.02) wipes out the provincial tax; federal 103.50 remains.
let onLow = TaxRules.canadaIncomeTax(annual: 20_000, province: "ON")
check(abs((onLow - Decimal(string: "103.50")!).double) < 1, "Ontario tax reduction at $20,000 (\(onLow))")
let quebecTax = TaxRules.canadaIncomeTax(annual: 100_000, province: "QC")
check(quebecTax > 20_000 && quebecTax < 26_000, "Quebec in a sensible range (\(quebecTax))")
for code in ["NB", "NL", "PE", "NT", "NU", "YT"] {
    let total = TaxRules.canadaIncomeTax(annual: 100_000, province: code)
    check(total > 15_000 && total < 25_000, "\(code) at $100,000 in range (\(total))")
}

// US single, $100,000, Texas: federal 13,170 + FICA 7,650.
check(TaxRules.usFederalTax(annual: 100_000, married: false) == 13_170 && TaxRules.usFICA(yearToDate: 100_000) == 7_650, "US federal and FICA")
check(TaxRules.usFICA(yearToDate: 300_000) == Decimal(184_500) * Decimal(string: "0.062")! + 300_000 * Decimal(string: "0.0145")! + 900, "Social Security cap, extra Medicare")
// Russia: 250,000 a month passes 2.4 million in October; that payday's tax is 34,500 instead of 32,500.
var taxed = budget
taxed.paydays = []; taxed.bills = []; taxed.envelopes = []
taxed.incomes = [Income(member: me.id, name: "Salary", schedule: .monthly(days: [10]), shift: .none, expected: 250_000,
                        isMonthly: true, tax: TaxSetup(system: .russia))]
let tp = Planner(taxed, calendar: calendar)
check(tp.expected(of: me.id, on: d(2026, 9, 10)) == 217_500, "13% before the threshold (\(tp.expected(of: me.id, on: d(2026, 9, 10))))")
check(tp.expected(of: me.id, on: d(2026, 10, 10)) == 215_500, "15% on the part above 2.4 million")
check(tp.expected(of: me.id, on: d(2026, 11, 10)) == 212_500, "15% after it")
// Canada, Alberta, $120,000 a year paid twice a month: CPP and EI stop partway, so later paydays are bigger.
taxed.incomes = [Income(member: me.id, name: "Salary", schedule: .monthly(days: [15, 30]), shift: .earlier, expected: 10_000,
                        isMonthly: true, split: .equal, tax: TaxSetup(system: .canada, region: "AB"))]
let cp = Planner(taxed, calendar: calendar)
let early = cp.expected(of: me.id, on: d(2026, 2, 13)), late = cp.expected(of: me.id, on: d(2026, 12, 15))
let yearNet = cp.paydays(of: me.id, from: d(2026, 1, 1), to: d(2026, 12, 31)).reduce(Decimal(0)) { $0 + cp.expected(of: me.id, on: $1) }
check(late > early, "CPP/EI maxed out later in the year (\(early) → \(late))")
let expectedNet = 120_000 - TaxRules.canadaIncomeTax(annual: 120_000, province: "AB") - 4_646.45 - Decimal(string: "1123.07")!
check(abs((yearNet - expectedNet).double) < 25, "a year's paydays add up to the annual after-tax pay (\(yearNet) vs \(expectedNet))")

// Projects: a move with a visa fee in December and tickets (in CAD) plus movers in March.
var moving = budget
moving.paydays = []; moving.envelopes = []
let fund = Envelope(owner: .member(me.id), name: "Move", goal: .open)
var project = Project(name: "Move to Canada", owner: .member(me.id), target: d(2027, 6, 1), stages: [
    Stage(name: "Visa", tasks: [ProjectTask(title: "Visa fee", due: d(2026, 12, 15), cost: 50_000)]),
    Stage(name: "Move", tasks: [ProjectTask(title: "Tickets", due: d(2027, 3, 1), cost: 2_000, currency: "CAD"),
                                ProjectTask(title: "Movers", due: d(2027, 3, 1), cost: 200_000)]),
], fund: fund.id, rates: ["CAD": 60])
var projectFund = fund
projectFund.goal = .project(project.id)
moving.envelopes = [projectFund]
moving.projects = [project]
var mp = Planner(moving, calendar: calendar)
check(project.planned == 370_000, "planned in the budget currency (\(project.planned))")
check(project.milestones().map(\.needed) == [50_000, 370_000], "cumulative milestones")
let toMarch = mp.paydays(of: me.id, from: d(2026, 10, 23), to: d(2027, 3, 1)).count
let fundLine = mp.plan(for: me.id, on: d(2026, 10, 23)).lines.first { $0.target == .envelope(projectFund.id) }!
var perPay = Decimal(370_000) / Decimal(toMarch), roundedUp = Decimal()
NSDecimalRound(&roundedUp, &perPay, 0, .up)
check(fundLine.planned == roundedUp, "saving for the latest milestone (\(fundLine.planned))")
// The visa is paid (cost 48,000), so it leaves the milestones and the fund pays it out.
project.stages[0].tasks[0].isDone = true
project.stages[0].tasks[0].spent = 48_000
moving.projects = [project]
check(project.spentSoFar == 48_000 && project.milestones().map(\.needed) == [320_000], "done tasks leave the plan")

// A yearly cost on a date: car insurance ~36,000 every 15 March.
var insured = budget
insured.paydays = []
let insurance2 = Envelope(owner: .member(me.id), name: "Car insurance", goal: .annual(36_000, on: d(2020, 3, 15)), priority: 9)
insured.envelopes = [insurance2]
let ip2 = Planner(insured, calendar: calendar)
check(ip2.nextOccurrence(of: d(2020, 3, 15), from: d(2026, 10, 23)) == d(2027, 3, 15), "next 15 March")
let toInsurance = ip2.paydays(of: me.id, from: d(2026, 10, 23), to: d(2027, 3, 15)).count
var insurancePer = Decimal(36_000) / Decimal(toInsurance), insuranceUp = Decimal()
NSDecimalRound(&insuranceUp, &insurancePer, 0, .up)
check(ip2.plan(for: me.id, on: d(2026, 10, 23)).lines.first { $0.target == .envelope(insurance2.id) }?.planned == insuranceUp,
      "saved by the date")

// Currencies: a $20 subscription and a 3,000 KZT bill in a rouble budget.
var multi = budget
multi.paydays = []; multi.envelopes = []; multi.debts = []
multi.rates = ["USD": 80, "KZT": Decimal(string: "0.16")!]
let gpt = Subscription(owner: .member(me.id), name: "ChatGPT", amount: 20, currency: "USD", anchor: d(2026, 11, 1))
let kzBill = Bill(owner: .member(me.id), name: "Phone KZ", amount: 3_000, currency: "KZT", day: 2)
multi.subscriptions = [gpt]; multi.bills = [kzBill]
let mpl = Planner(multi, calendar: calendar).plan(for: me.id, on: d(2026, 10, 23))
check(mpl.lines.first { $0.target == .subscription(gpt.id) }?.amount == 1_600, "USD subscription in roubles")
check(mpl.lines.first { $0.target == .bill(kzBill.id) }?.amount == 480, "KZT bill in roubles")
check(multi.foreignCurrencies == ["USD", "KZT"], "foreign currencies in use")
let usdDebt = Debt(owner: .member(me.id), name: "Card", kind: .creditCard, balance: 1_000, asOf: d(2026, 10, 1), payment: 100, currency: "USD", day: 28)
multi.debts = [usdDebt]
var mpp = Planner(multi, calendar: calendar)
var paidUSD = mpp.confirm(mpp.plan(for: me.id, on: d(2026, 10, 23)), actual: 80_000)
check(paidUSD.allocations.first { $0.target == .debt(usdDebt.id) }?.amount == 8_000, "$100 payment is 8,000 roubles")
paidUSD.allocations = paidUSD.allocations.map { a in var a = a; a.isDone = true; return a }
multi.paydays = [paidUSD]
mpp = Planner(multi, calendar: calendar)
check(mpp.remaining(of: usdDebt, before: d(2026, 11, 10)) == 900, "the dollar balance goes down by $100")

// Accounts: two envelopes in one 12% savings account get its terms; interest to a card leaves balances alone.
var banked = budget
banked.paydays = []
let ozonAccount = Account(name: "Ozon savings", kind: .savings, owner: .member(me.id), rate: 12, interestDay: 1)
let cushionIn = Envelope(owner: .member(me.id), name: "Cushion", goal: .open, opening: 100_000, openedAt: d(2026, 9, 15), account: ozonAccount.id)
let tripIn = Envelope(owner: .member(me.id), name: "Trip", goal: .open, opening: 50_000, openedAt: d(2026, 9, 15), account: ozonAccount.id)
banked.accounts = [ozonAccount]
banked.envelopes = [cushionIn, tripIn]
var bp = Planner(banked, calendar: calendar)
check(near(bp.balance(of: cushionIn, before: d(2026, 10, 2)), "100526.03") && near(bp.balance(of: tripIn, before: d(2026, 10, 2)), "50263.01"),
      "account interest shared by its envelopes")
let card = Account(name: "T-Bank card", kind: .card, owner: .member(me.id))
banked.accounts[0].interestTo = card.id
banked.accounts.append(card)
bp = Planner(banked, calendar: calendar)
check(bp.balance(of: cushionIn, before: d(2026, 10, 2)) == 100_000 && bp.nextInterest(of: cushionIn, from: d(2026, 10, 25))?.amount == 1_019,
      "interest paid to a card")

// Which payday pays: rent from the 25th, internet split over both, a shared bill in turns.
var slotted = budget
slotted.paydays = []; slotted.envelopes = []; slotted.debts = []; slotted.subscriptions = []
var rentSlot = Bill(owner: .member(me.id), name: "Rent", amount: 60_000, day: 5)
rentSlot.slot = .payday(1)
var netSlot = Bill(owner: .member(me.id), name: "Internet", amount: 1_000, day: 20)
netSlot.slot = .split
var cleaning = Bill(owner: .shared, name: "Cleaning", amount: 5_000, day: 12, split: .turns)
slotted.bills = [rentSlot, netSlot, cleaning]
let sp = Planner(slotted, calendar: calendar)
let latePay = sp.plan(for: me.id, on: d(2026, 10, 23)), earlyPay = sp.plan(for: me.id, on: d(2026, 11, 10))
check(latePay.lines.first { $0.target == .bill(rentSlot.id) }?.amount == 60_000, "rent from the late-month pay")
check(earlyPay.lines.first { $0.target == .bill(rentSlot.id) } == nil, "not from the other one")
check(latePay.lines.first { $0.target == .bill(netSlot.id) }?.amount == 500 && earlyPay.lines.first { $0.target == .bill(netSlot.id) }?.amount == 500,
      "internet split between both paydays")
let novTurn = sp.share(of: me.id, owner: .shared, split: .turns, on: d(2026, 11, 10))
let decTurn = sp.share(of: me.id, owner: .shared, split: .turns, on: d(2026, 12, 10))
check(novTurn + decTurn == 1 && novTurn * decTurn == 0, "taking turns month by month")

// Money outside the plan: a 30,000 gift (10,000 to a saving), a 6,000 repair, a move between savings.
var outside = budget
outside.paydays = []; outside.debts = []; outside.subscriptions = []
let jar = Envelope(owner: .member(me.id), name: "Jar", goal: .open), box = Envelope(owner: .member(me.id), name: "Box", goal: .open)
outside.envelopes = [jar, box]
var op = Planner(outside, calendar: calendar)
let allowanceBefore = op.allowance(for: me.id, on: d(2026, 10, 25))!.perDay
outside.inflows = [Inflow(member: me.id, date: d(2026, 10, 24), amount: 30_000, note: "Gift",
                          allocations: [Allocation(target: .envelope(jar.id), amount: 10_000, isDone: true)])]
outside.outflows = [Outflow(member: me.id, date: d(2026, 10, 25), amount: 6_000, note: "Repair")]
outside.transfers = [Transfer(from: jar.id, to: box.id, date: d(2026, 10, 26), amount: 4_000)]
op = Planner(outside, calendar: calendar)
let periodDays = Decimal(18) // 23 Oct – 10 Nov
check(op.balance(of: jar, before: d(2026, 10, 30)) == 6_000 && op.balance(of: box, before: d(2026, 10, 30)) == 4_000, "gift into a saving, then moved")
let allowanceAfter = op.allowance(for: me.id, on: d(2026, 10, 25))!.perDay
check(abs((allowanceAfter - allowanceBefore - Decimal(14_000) / periodDays).double) <= 1,
      "spending money +20,000 − 6,000 over the period (\(allowanceBefore) → \(allowanceAfter))")

// Typed amounts.
for (typed, value) in [("55000", 55_000), ("55 000", 55_000), ("55\u{00A0}000 ₽", 55_000), ("₽117,500", 117_500),
                       ("$1,234.50", Decimal(string: "1234.5")!), ("12,5", Decimal(string: "12.5")!), ("1.234,56", Decimal(string: "1234.56")!),
                       ("1 000 000", 1_000_000), ("0", 0), ("16%", 16)] as [(String, Decimal)] {
    check(Amount.parse(typed) == value, "parse \(typed) → \(String(describing: Amount.parse(typed)))")
}
check(Amount.parse("") == nil && Amount.parse("abc") == nil, "nothing typed")

// Old files without the newer lists still load.
let old = #"{"id":"\#(UUID())","name":"Old","currency":"RUB","members":[]}"#
check((try? JSONDecoder().decode(Budget.self, from: Data(old.utf8)))?.debts.isEmpty == true, "older budget file decodes")

// Round trip.
let data = try JSONEncoder().encode(budget)
check(try JSONDecoder().decode(Budget.self, from: data) == budget, "Codable round trip")

// Irregular income: October's earnings (40 000 + 30 000) are November's budget; nothing recorded → the estimate.
var freelance = Income(member: me.id, name: "Freelance", schedule: .monthly(days: [1]), shift: .none, expected: 50_000)
freelance.irregular = true
var freeBudget = Budget(name: "Free", currency: "RUB", members: [me], incomes: [freelance])
freeBudget.inflows = [Inflow(member: me.id, date: d(2026, 10, 5), amount: 40_000, income: freelance.id),
                      Inflow(member: me.id, date: d(2026, 10, 20), amount: 30_000, income: freelance.id),
                      Inflow(member: me.id, date: d(2026, 10, 21), amount: 5_000, note: "Gift")]
let freeP = Planner(freeBudget, calendar: calendar)
check(freeP.expected(of: me.id, on: d(2026, 11, 1)) == 70_000, "last month's earnings are this month's pay")
check(freeP.expected(of: me.id, on: d(2026, 10, 1)) == 50_000, "estimate before anything is recorded")
check(freeP.adjustment(of: me.id, from: d(2026, 10, 1), to: d(2026, 10, 31)) == 5_000, "earnings aren't spending money now; a gift is")

// Pay ahead: a 120 000 pay (usual 80 000) keeps 30 000 for the next payday.
var ahead = budget
ahead.bills = []; ahead.envelopes = []
var bigPay = Payday(member: me.id, date: d(2026, 10, 23), actual: 120_000, allocations: [])
bigPay.keep = 30_000
ahead.paydays = [bigPay]
let ap = Planner(ahead, calendar: calendar)
check(ap.plan(for: me.id, on: d(2026, 10, 23)).lines.first { $0.target == .carry }?.amount == 30_000, "the chosen part is kept")
check(ap.plan(for: me.id, on: d(2026, 11, 10)).carriedIn == 30_000, "and arrives with the next pay")
bigPay.keep = 90_000
ahead.paydays = [bigPay]
check(Planner(ahead, calendar: calendar).plan(for: me.id, on: d(2026, 10, 23)).lines.first { $0.target == .carry }?.amount == 40_000,
      "never more than the extra")

print(failures == 0 ? "All checks passed" : "\(failures) checks failed")
exit(failures == 0 ? 0 : 1)

extension Decimal {
    var double: Double { NSDecimalNumber(decimal: self).doubleValue }

    func rounded() -> Decimal {
        var value = self, result = Decimal()
        NSDecimalRound(&result, &value, 0, .down)
        return result
    }
}
