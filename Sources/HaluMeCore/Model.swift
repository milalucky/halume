import Foundation

/// One household budget: one person, a couple, or a family.
public struct Budget: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    /// ISO 4217 code, one per budget.
    public var currency: String
    /// ISO country code: taxes, holidays and how salaries are usually stated.
    public var country: String
    public var members: [Member]
    public var incomes: [Income]
    public var bills: [Bill]
    public var envelopes: [Envelope]
    public var debts: [Debt]
    public var subscriptions: [Subscription]
    public var withdrawals: [Withdrawal]
    public var absences: [Absence]
    public var wishes: [Wish]
    public var reservations: [Reservation]
    public var projects: [Project]
    /// Value of one unit of each foreign currency in the budget's currency.
    public var rates: [String: Decimal]
    public var ratesUpdated: Date?
    /// Holidays and moved days off for counting working days; nil means weekends only.
    public var workCalendar: WorkCalendar?
    public var paydays: [Payday]
    public var checks: [BalanceCheck]

    public init(id: UUID = UUID(), name: String, currency: String, members: [Member],
                incomes: [Income] = [], bills: [Bill] = [], envelopes: [Envelope] = [],
                debts: [Debt] = [], subscriptions: [Subscription] = [], withdrawals: [Withdrawal] = [],
                paydays: [Payday] = [], checks: [BalanceCheck] = []) {
        self.id = id; self.name = name; self.currency = currency; self.country = ""; self.members = members
        self.incomes = incomes; self.bills = bills; self.envelopes = envelopes
        self.debts = debts; self.subscriptions = subscriptions; self.withdrawals = withdrawals
        self.absences = []; self.workCalendar = nil; self.wishes = []; self.reservations = []; self.projects = []
        self.rates = [:]; self.ratesUpdated = nil
        self.paydays = paydays; self.checks = checks
    }

    // Lists added later decode as empty from older files.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        currency = try c.decode(String.self, forKey: .currency)
        country = try c.decodeIfPresent(String.self, forKey: .country) ?? ""
        members = try c.decode([Member].self, forKey: .members)
        incomes = try c.decodeIfPresent([Income].self, forKey: .incomes) ?? []
        bills = try c.decodeIfPresent([Bill].self, forKey: .bills) ?? []
        envelopes = try c.decodeIfPresent([Envelope].self, forKey: .envelopes) ?? []
        debts = try c.decodeIfPresent([Debt].self, forKey: .debts) ?? []
        subscriptions = try c.decodeIfPresent([Subscription].self, forKey: .subscriptions) ?? []
        withdrawals = try c.decodeIfPresent([Withdrawal].self, forKey: .withdrawals) ?? []
        absences = try c.decodeIfPresent([Absence].self, forKey: .absences) ?? []
        wishes = try c.decodeIfPresent([Wish].self, forKey: .wishes) ?? []
        reservations = try c.decodeIfPresent([Reservation].self, forKey: .reservations) ?? []
        projects = try c.decodeIfPresent([Project].self, forKey: .projects) ?? []
        rates = try c.decodeIfPresent([String: Decimal].self, forKey: .rates) ?? [:]
        ratesUpdated = try c.decodeIfPresent(Date.self, forKey: .ratesUpdated)
        workCalendar = try c.decodeIfPresent(WorkCalendar.self, forKey: .workCalendar)
        paydays = try c.decodeIfPresent([Payday].self, forKey: .paydays) ?? []
        checks = try c.decodeIfPresent([BalanceCheck].self, forKey: .checks) ?? []
    }
}

public struct Member: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public init(id: UUID = UUID(), name: String) { self.id = id; self.name = name }
}

/// Who a bill or an envelope belongs to.
public enum Owner: Codable, Sendable, Hashable {
    case member(UUID)
    case shared
}

/// How a shared item is divided between members.
public enum Split: Codable, Sendable, Hashable {
    case equal
    case byIncome
    case payer(UUID)
    /// Any weights (percentages or amounts), normalised.
    case weights([UUID: Decimal])
}

public enum Schedule: Codable, Sendable, Hashable {
    /// Days of the month; 31 means the last day of a shorter month.
    case monthly(days: [Int])
    case everyWeeks(Int, from: Date)
    /// Paid every day (couriers, drivers, shifts); planned by the week, from Monday.
    case daily(weekdaysOnly: Bool)
}

/// How a monthly salary is divided between two paydays.
public enum PaySplit: Codable, Sendable, Hashable {
    case equal
    /// Each payday gets the share of weekdays in the half of the month it pays for.
    case byWorkdays
    /// A fixed advance for the first half; the rest comes with the second payday.
    case advance(Decimal)
}

public enum WeekendShift: String, Codable, Sendable, Hashable {
    case earlier, later, none
}

public struct Income: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var member: UUID
    public var name: String
    public var schedule: Schedule
    public var shift: WeekendShift
    /// Per payday; per day for daily pay; for the whole month when `isMonthly`.
    public var expected: Decimal
    /// `expected` is a monthly salary split between the paydays by `split`.
    public var isMonthly: Bool
    public var split: PaySplit
    /// Set when `expected` is before tax: how tax is withheld.
    public var tax: TaxSetup?
    /// The currency it's paid in; nil: the budget's.
    public var currency: String?

    public init(id: UUID = UUID(), member: UUID, name: String, schedule: Schedule,
                shift: WeekendShift = .earlier, expected: Decimal, isMonthly: Bool = false, split: PaySplit = .equal,
                tax: TaxSetup? = nil, currency: String? = nil) {
        self.id = id; self.member = member; self.name = name
        self.schedule = schedule; self.shift = shift; self.expected = expected
        self.isMonthly = isMonthly; self.split = split; self.tax = tax; self.currency = currency
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        member = try c.decode(UUID.self, forKey: .member)
        name = try c.decode(String.self, forKey: .name)
        schedule = try c.decode(Schedule.self, forKey: .schedule)
        shift = try c.decodeIfPresent(WeekendShift.self, forKey: .shift) ?? .earlier
        expected = try c.decode(Decimal.self, forKey: .expected)
        isMonthly = try c.decodeIfPresent(Bool.self, forKey: .isMonthly) ?? false
        split = try c.decodeIfPresent(PaySplit.self, forKey: .split) ?? .equal
        tax = try c.decodeIfPresent(TaxSetup.self, forKey: .tax)
        currency = try c.decodeIfPresent(String.self, forKey: .currency)
    }
}

/// A monthly obligatory payment.
public struct Bill: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var owner: Owner
    public var name: String
    public var amount: Decimal
    /// nil: the budget's currency.
    public var currency: String?
    public var day: Int
    public var split: Split

    public init(id: UUID = UUID(), owner: Owner, name: String, amount: Decimal, currency: String? = nil, day: Int, split: Split = .equal) {
        self.id = id; self.owner = owner; self.name = name
        self.amount = amount; self.currency = currency; self.day = day; self.split = split
    }
}

public enum Goal: Codable, Sendable, Hashable {
    /// Reach `amount` by `by`; the contribution is recomputed every payday.
    case target(Decimal, by: Date)
    /// Percent of each pay (of the member's own pay for a shared envelope).
    case percent(Decimal)
    case perPayday(Decimal)
    /// A yearly expense spread over the year's paydays.
    case yearly(Decimal)
    /// No contributions, filled from leftovers only.
    case open
    /// A project's fund: enough by each task's due date.
    case project(UUID)
    /// A yearly cost due on a date (its day and month repeat every year), with an estimate that may change.
    case annual(Decimal, on: Date)
}

public struct Envelope: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var owner: Owner
    public var name: String
    public var goal: Goal
    /// Lower is funded first when pay runs short.
    public var priority: Int
    public var split: Split
    /// Money already in it on `openedAt`.
    public var opening: Decimal
    public var openedAt: Date
    /// Where the money lives; savings accounts and deposits earn `rate`.
    public var holding: Holding
    /// Annual interest, percent.
    public var rate: Decimal
    /// Day of the month the interest is paid.
    public var interestDay: Int
    /// Interest goes to the card (income) instead of staying in the account.
    public var interestToCard: Bool
    /// A deposit's end date.
    public var maturity: Date?
    /// Only the owner sees it (a gift for the partner), until `revealOn` if set.
    public var hidden: Bool
    public var revealOn: Date?

    public init(id: UUID = UUID(), owner: Owner, name: String, goal: Goal, priority: Int = 0,
                split: Split = .equal, opening: Decimal = 0, openedAt: Date = Date(),
                holding: Holding = .card, rate: Decimal = 0, interestDay: Int = 1,
                interestToCard: Bool = false, maturity: Date? = nil, hidden: Bool = false, revealOn: Date? = nil) {
        self.id = id; self.owner = owner; self.name = name; self.goal = goal
        self.priority = priority; self.split = split; self.opening = opening; self.openedAt = openedAt
        self.holding = holding; self.rate = rate; self.interestDay = interestDay
        self.interestToCard = interestToCard; self.maturity = maturity
        self.hidden = hidden; self.revealOn = revealOn
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        owner = try c.decode(Owner.self, forKey: .owner)
        name = try c.decode(String.self, forKey: .name)
        goal = try c.decode(Goal.self, forKey: .goal)
        priority = try c.decodeIfPresent(Int.self, forKey: .priority) ?? 0
        split = try c.decodeIfPresent(Split.self, forKey: .split) ?? .equal
        opening = try c.decodeIfPresent(Decimal.self, forKey: .opening) ?? 0
        openedAt = try c.decodeIfPresent(Date.self, forKey: .openedAt) ?? .distantPast
        holding = try c.decodeIfPresent(Holding.self, forKey: .holding) ?? .card
        rate = try c.decodeIfPresent(Decimal.self, forKey: .rate) ?? 0
        interestDay = try c.decodeIfPresent(Int.self, forKey: .interestDay) ?? 1
        interestToCard = try c.decodeIfPresent(Bool.self, forKey: .interestToCard) ?? false
        maturity = try c.decodeIfPresent(Date.self, forKey: .maturity)
        hidden = try c.decodeIfPresent(Bool.self, forKey: .hidden) ?? false
        revealOn = try c.decodeIfPresent(Date.self, forKey: .revealOn)
    }
}

public enum Holding: String, Codable, Sendable, Hashable, CaseIterable {
    case card, cash, savingsAccount, deposit, investments

    public var earnsInterest: Bool { self == .savingsAccount || self == .deposit }
}

/// Money taken out of an envelope.
public struct Withdrawal: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var envelope: UUID
    public var date: Date
    public var amount: Decimal
    public var note: String

    public init(id: UUID = UUID(), envelope: UUID, date: Date = Date(), amount: Decimal, note: String = "") {
        self.id = id; self.envelope = envelope; self.date = date; self.amount = amount; self.note = note
    }
}

public enum Target: Codable, Sendable, Hashable {
    case bill(UUID)
    case envelope(UUID)
    case debt(UUID)
    case subscription(UUID)
    /// Kept from a bigger pay (vacation pay) for the next, smaller one.
    case carry
    case free
}

public enum AbsenceKind: String, Codable, Sendable, Hashable, CaseIterable {
    case vacation, sickLeave, unpaid
}

/// Time off that changes what comes on paydays.
public struct Absence: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var member: UUID
    public var kind: AbsenceKind
    /// First and last day, both included.
    public var from: Date
    public var to: Date
    /// Sick pay as a share of average earnings, by insurance record: 60, 80 or 100.
    public var sickPercent: Int

    public init(id: UUID = UUID(), member: UUID, kind: AbsenceKind, from: Date, to: Date, sickPercent: Int = 100) {
        self.id = id; self.member = member; self.kind = kind; self.from = from; self.to = to; self.sickPercent = sickPercent
    }
}

public struct Allocation: Codable, Sendable, Hashable {
    public var target: Target
    public var amount: Decimal
    /// The user made the transfer or paid the bill.
    public var isDone: Bool

    public init(target: Target, amount: Decimal, isDone: Bool = false) {
        self.target = target; self.amount = amount; self.isDone = isDone
    }
}

/// A confirmed payday of one member: what came and where it went.
public struct Payday: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var member: UUID
    public var date: Date
    public var actual: Decimal?
    public var allocations: [Allocation]
    /// Money left from the previous pay when this one came, if the user said.
    public var leftover: Decimal?

    public init(id: UUID = UUID(), member: UUID, date: Date, actual: Decimal?, allocations: [Allocation]) {
        self.id = id; self.member = member; self.date = date
        self.actual = actual; self.allocations = allocations
    }
}

/// The one optional number: what is on the card right now.
public struct BalanceCheck: Codable, Sendable, Hashable {
    public var member: UUID
    public var date: Date
    public var amount: Decimal

    public init(member: UUID, date: Date, amount: Decimal) {
        self.member = member; self.date = date; self.amount = amount
    }
}

public enum DebtKind: String, Codable, Sendable, Hashable, CaseIterable {
    /// Buy now, pay later (Yandex Split, Klarna, store instalments): usually no interest.
    case installment
    case loan
    case mortgage
    case creditCard
    /// Money owed to a person.
    case personal
}

/// Something being paid off: what is left, the rate and the monthly payment.
public struct Debt: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var owner: Owner
    public var name: String
    public var kind: DebtKind
    /// The amount borrowed, for progress.
    public var original: Decimal
    /// What was left to pay on `asOf`; payments marked done after it are taken off.
    public var balance: Decimal
    public var asOf: Date
    /// Annual interest, percent. 0 for most instalments and personal debts.
    public var rate: Decimal
    /// The usual monthly payment; may be changed any month.
    public var payment: Decimal
    /// The debt's currency (balance and payment); nil: the budget's.
    public var currency: String?
    public var day: Int
    public var split: Split

    public init(id: UUID = UUID(), owner: Owner, name: String, kind: DebtKind, original: Decimal? = nil,
                balance: Decimal, asOf: Date = Date(), rate: Decimal = 0, payment: Decimal, currency: String? = nil, day: Int,
                split: Split = .equal) {
        self.id = id; self.owner = owner; self.name = name; self.kind = kind; self.currency = currency
        self.original = original ?? balance; self.balance = balance; self.asOf = asOf
        self.rate = rate; self.payment = payment; self.day = day; self.split = split
    }
}

public enum Cycle: String, Codable, Sendable, Hashable, CaseIterable {
    case weekly, monthly, quarterly, yearly
}

/// A recurring charge: streaming, apps, premium accounts, bank packages.
public struct Subscription: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var owner: Owner
    public var name: String
    public var amount: Decimal
    /// nil: the budget's currency.
    public var currency: String?
    public var cycle: Cycle
    /// Any past or future charge date; the rest follow by the cycle.
    public var anchor: Date
    /// The free trial ends here; the first charge comes on this day.
    public var trialEnds: Date?
    public var isActive: Bool
    public var category: String
    public var note: String
    public var split: Split

    public init(id: UUID = UUID(), owner: Owner, name: String, amount: Decimal, currency: String? = nil, cycle: Cycle = .monthly,
                anchor: Date, trialEnds: Date? = nil, isActive: Bool = true, category: String = "",
                note: String = "", split: Split = .equal) {
        self.id = id; self.owner = owner; self.name = name; self.amount = amount; self.currency = currency; self.cycle = cycle
        self.anchor = anchor; self.trialEnds = trialEnds; self.isActive = isActive
        self.category = category; self.note = note; self.split = split
    }
}

/// Something someone wants: visible to the household, so a partner can gift it or the owner can save for it.
public struct Wish: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var owner: UUID
    public var name: String
    public var price: Decimal
    /// nil: the budget's currency.
    public var currency: String?
    public var link: String
    public var note: String
    /// The savings envelope collecting money for it.
    public var envelope: UUID?
    /// Got it (bought or received).
    public var isDone: Bool

    public init(id: UUID = UUID(), owner: UUID, name: String, price: Decimal = 0, currency: String? = nil, link: String = "",
                note: String = "", envelope: UUID? = nil, isDone: Bool = false) {
        self.id = id; self.owner = owner; self.name = name; self.price = price; self.currency = currency; self.link = link; self.note = note
        self.envelope = envelope; self.isDone = isDone
    }
}

/// "I'll gift this": kept only by the giver, so the wish's owner never sees it.
public struct Reservation: Codable, Sendable, Hashable {
    public var wish: UUID
    public var by: UUID

    public init(wish: UUID, by: UUID) { self.wish = wish; self.by = by }
}

extension Budget {
    /// An amount in `code` turned into the budget's currency (unknown rates count one to one).
    public func convert(_ amount: Decimal, from code: String?) -> Decimal {
        guard let code, code != currency, let rate = rates[code] else { return amount }
        return amount * rate
    }

    /// An amount in the budget's currency turned into `code`.
    public func convert(_ amount: Decimal, to code: String?) -> Decimal {
        guard let code, code != currency, let rate = rates[code], rate > 0 else { return amount }
        return amount / rate
    }

    /// Every foreign currency the budget uses.
    public var foreignCurrencies: Set<String> {
        var codes = Set<String>()
        codes.formUnion(bills.compactMap(\.currency)); codes.formUnion(debts.compactMap(\.currency))
        codes.formUnion(subscriptions.compactMap(\.currency)); codes.formUnion(wishes.compactMap(\.currency))
        codes.formUnion(incomes.compactMap(\.currency)); codes.formUnion(projects.flatMap { $0.tasks.compactMap(\.currency) })
        codes.remove(currency)
        return codes
    }
}
