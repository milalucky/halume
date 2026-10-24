import Foundation

/// One household budget: one person, a couple, or a family.
public struct Budget: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    /// ISO 4217 code, one per budget.
    public var currency: String
    public var members: [Member]
    public var incomes: [Income]
    public var bills: [Bill]
    public var envelopes: [Envelope]
    public var debts: [Debt]
    public var subscriptions: [Subscription]
    public var paydays: [Payday]
    public var checks: [BalanceCheck]

    public init(id: UUID = UUID(), name: String, currency: String, members: [Member],
                incomes: [Income] = [], bills: [Bill] = [], envelopes: [Envelope] = [],
                debts: [Debt] = [], subscriptions: [Subscription] = [],
                paydays: [Payday] = [], checks: [BalanceCheck] = []) {
        self.id = id; self.name = name; self.currency = currency; self.members = members
        self.incomes = incomes; self.bills = bills; self.envelopes = envelopes
        self.debts = debts; self.subscriptions = subscriptions
        self.paydays = paydays; self.checks = checks
    }

    // Lists added later decode as empty from older files.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        currency = try c.decode(String.self, forKey: .currency)
        members = try c.decode([Member].self, forKey: .members)
        incomes = try c.decodeIfPresent([Income].self, forKey: .incomes) ?? []
        bills = try c.decodeIfPresent([Bill].self, forKey: .bills) ?? []
        envelopes = try c.decodeIfPresent([Envelope].self, forKey: .envelopes) ?? []
        debts = try c.decodeIfPresent([Debt].self, forKey: .debts) ?? []
        subscriptions = try c.decodeIfPresent([Subscription].self, forKey: .subscriptions) ?? []
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
    public var expected: Decimal

    public init(id: UUID = UUID(), member: UUID, name: String, schedule: Schedule,
                shift: WeekendShift = .earlier, expected: Decimal) {
        self.id = id; self.member = member; self.name = name
        self.schedule = schedule; self.shift = shift; self.expected = expected
    }
}

/// A monthly obligatory payment.
public struct Bill: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var owner: Owner
    public var name: String
    public var amount: Decimal
    public var day: Int
    public var split: Split

    public init(id: UUID = UUID(), owner: Owner, name: String, amount: Decimal, day: Int, split: Split = .equal) {
        self.id = id; self.owner = owner; self.name = name
        self.amount = amount; self.day = day; self.split = split
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
}

public struct Envelope: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var owner: Owner
    public var name: String
    public var goal: Goal
    /// Lower is funded first when pay runs short.
    public var priority: Int
    public var split: Split
    /// Money already in it before the app.
    public var opening: Decimal

    public init(id: UUID = UUID(), owner: Owner, name: String, goal: Goal, priority: Int = 0,
                split: Split = .equal, opening: Decimal = 0) {
        self.id = id; self.owner = owner; self.name = name; self.goal = goal
        self.priority = priority; self.split = split; self.opening = opening
    }
}

public enum Target: Codable, Sendable, Hashable {
    case bill(UUID)
    case envelope(UUID)
    case debt(UUID)
    case subscription(UUID)
    case free
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
    public var day: Int
    public var split: Split

    public init(id: UUID = UUID(), owner: Owner, name: String, kind: DebtKind, original: Decimal? = nil,
                balance: Decimal, asOf: Date = Date(), rate: Decimal = 0, payment: Decimal, day: Int, split: Split = .equal) {
        self.id = id; self.owner = owner; self.name = name; self.kind = kind
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
    public var cycle: Cycle
    /// Any past or future charge date; the rest follow by the cycle.
    public var anchor: Date
    /// The free trial ends here; the first charge comes on this day.
    public var trialEnds: Date?
    public var isActive: Bool
    public var category: String
    public var note: String
    public var split: Split

    public init(id: UUID = UUID(), owner: Owner, name: String, amount: Decimal, cycle: Cycle = .monthly,
                anchor: Date, trialEnds: Date? = nil, isActive: Bool = true, category: String = "",
                note: String = "", split: Split = .equal) {
        self.id = id; self.owner = owner; self.name = name; self.amount = amount; self.cycle = cycle
        self.anchor = anchor; self.trialEnds = trialEnds; self.isActive = isActive
        self.category = category; self.note = note; self.split = split
    }
}
