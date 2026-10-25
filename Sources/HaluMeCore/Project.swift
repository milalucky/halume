import Foundation

/// A big goal that is both a plan and a budget: moving abroad, a wedding, a renovation.
public struct Project: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public var owner: Owner
    public var split: Split
    /// When it should be done; tasks without a date count by then.
    public var target: Date
    public var stages: [Stage]
    /// The savings envelope that collects money for it.
    public var fund: UUID?
    /// Budget-currency value of one unit of each foreign currency used in tasks.
    public var rates: [String: Decimal]

    public init(id: UUID = UUID(), name: String, owner: Owner, split: Split = .equal, target: Date, stages: [Stage] = [],
                fund: UUID? = nil, rates: [String: Decimal] = [:]) {
        self.id = id; self.name = name; self.owner = owner; self.split = split; self.target = target
        self.stages = stages; self.fund = fund; self.rates = rates
    }

    public var tasks: [ProjectTask] { stages.flatMap(\.tasks) }

    /// A task's planned cost in the budget currency.
    public func cost(of task: ProjectTask) -> Decimal { convert(task.cost, task.currency) }

    /// What a done task actually cost, in the budget currency (the plan if nothing was entered).
    public func spent(on task: ProjectTask) -> Decimal { convert(task.spent ?? task.cost, task.currency) }

    func convert(_ amount: Decimal, _ currency: String?) -> Decimal {
        guard let currency, let rate = rates[currency] else { return amount }
        return amount * rate
    }

    public var planned: Decimal { tasks.reduce(0) { $0 + cost(of: $1) } }
    public var spentSoFar: Decimal { tasks.filter(\.isDone).reduce(0) { $0 + spent(on: $1) } }

    /// Money needed by each date for the tasks still ahead, cumulative and in date order.
    public func milestones() -> [(date: Date, needed: Decimal)] {
        var byDate: [Date: Decimal] = [:]
        for task in tasks where !task.isDone {
            byDate[task.due ?? target, default: 0] += cost(of: task)
        }
        var total: Decimal = 0
        return byDate.keys.sorted().map { date in
            total += byDate[date]!
            return (date, total)
        }
    }
}

public struct Stage: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var name: String
    public var tasks: [ProjectTask]

    public init(id: UUID = UUID(), name: String, tasks: [ProjectTask] = []) {
        self.id = id; self.name = name; self.tasks = tasks
    }
}

public struct ProjectTask: Codable, Sendable, Hashable, Identifiable {
    public var id: UUID
    public var title: String
    public var due: Date?
    /// Planned cost, in `currency` (nil: the budget's currency).
    public var cost: Decimal
    public var currency: String?
    /// What it actually cost once done, in the same currency.
    public var spent: Decimal?
    public var isDone: Bool
    public var assignee: UUID?
    /// Waits for this task.
    public var after: UUID?
    public var note: String
    public var link: String

    public init(id: UUID = UUID(), title: String, due: Date? = nil, cost: Decimal = 0, currency: String? = nil,
                spent: Decimal? = nil, isDone: Bool = false, assignee: UUID? = nil, after: UUID? = nil, note: String = "", link: String = "") {
        self.id = id; self.title = title; self.due = due; self.cost = cost; self.currency = currency; self.spent = spent
        self.isDone = isDone; self.assignee = assignee; self.after = after; self.note = note; self.link = link
    }
}

extension Planner {
    /// A project fund's contribution this payday: enough to reach every milestone in time, whichever needs most.
    func projectContribution(_ envelope: Envelope, project: Project, member: UUID, on date: Date, share: Decimal) -> Decimal {
        let saved = balance(of: envelope, before: date)
        var most: Decimal = 0
        for milestone in project.milestones() {
            let missing = max(0, milestone.needed - saved) * share
            guard missing > 0 else { continue }
            let count = paydays(of: member, from: date, to: max(day(milestone.date), date)).count
            most = max(most, missing / Decimal(max(count, 1)))
        }
        return up(most)
    }

    /// Tasks of all projects due in [from, to] and not done.
    public func projectTasks(from: Date, to: Date) -> [(project: Project, task: ProjectTask)] {
        budget.projects.flatMap { p in p.tasks.filter { !$0.isDone && ($0.due.map { day($0) >= day(from) && day($0) <= day(to) } ?? false) }.map { (p, $0) } }
            .sorted { ($0.task.due ?? .distantFuture) < ($1.task.due ?? .distantFuture) }
    }
}
