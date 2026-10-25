import Foundation
import HaluMeCore

/// Project actions on the budget: the fund envelope, paying tasks from it, moving later steps.
extension BudgetStore {
    func createProject(name: String, template: ProjectTemplate, target: Date, owner: Owner, split: Split) {
        guard var budget else { return }
        let id = UUID()
        let fund = Envelope(owner: owner, name: name, goal: .project(id),
                            priority: (budget.envelopes.map(\.priority).max() ?? -1) + 1, split: split)
        budget.envelopes.append(fund)
        budget.projects.append(Project(id: id, name: name, owner: owner, split: split, target: target,
                                       stages: template.stages(until: target), fund: fund.id))
        self.budget = budget
        openProject = id
    }

    func save(_ project: Project) {
        guard var budget, let i = budget.projects.firstIndex(where: { $0.id == project.id }) else { return }
        budget.projects[i] = project
        // The fund carries the project's name and owner.
        if let f = budget.envelopes.firstIndex(where: { $0.id == project.fund }) {
            budget.envelopes[f].name = project.name
            budget.envelopes[f].owner = project.owner
            budget.envelopes[f].split = project.split
        }
        self.budget = budget
    }

    /// Deletes the project; money already in its fund stays as an ordinary saving.
    func deleteProject(_ id: UUID) {
        guard var budget, let project = budget.projects.first(where: { $0.id == id }) else { return }
        if let f = budget.envelopes.firstIndex(where: { $0.id == project.fund }) { budget.envelopes[f].goal = .open }
        budget.projects.removeAll { $0.id == id }
        self.budget = budget
        openProject = nil
    }

    /// Saves a task into a stage; with `shiftLater`, tasks waiting for it move by as many days as its date did.
    func save(_ task: ProjectTask, in stageID: UUID, of projectID: UUID, shiftLater: Bool) {
        guard var project = budget?.projects.first(where: { $0.id == projectID }) else { return }
        let old = project.tasks.first { $0.id == task.id }
        for s in project.stages.indices { project.stages[s].tasks.removeAll { $0.id == task.id } }
        if let s = project.stages.firstIndex(where: { $0.id == stageID }) {
            let position = old.flatMap { o in project.stages[s].tasks.firstIndex { ($0.due ?? .distantFuture) > (o.due ?? .distantFuture) } }
            project.stages[s].tasks.insert(task, at: position ?? project.stages[s].tasks.count)
        }
        if shiftLater, let before = old?.due, let after = task.due {
            let delta = Calendar.current.dateComponents([.day], from: before, to: after).day ?? 0
            if delta != 0 { shift(after: task.id, by: delta, in: &project) }
        }
        save(project)
        if task.isDone != (old?.isDone ?? false) || task.spent != old?.spent { settle(task.id, in: projectID) }
    }

    private func shift(after id: UUID, by days: Int, in project: inout Project, depth: Int = 0) {
        guard depth < 20 else { return }
        for s in project.stages.indices {
            for t in project.stages[s].tasks.indices where project.stages[s].tasks[t].after == id {
                if let due = project.stages[s].tasks[t].due {
                    project.stages[s].tasks[t].due = Calendar.current.date(byAdding: .day, value: days, to: due)
                }
                shift(after: project.stages[s].tasks[t].id, by: days, in: &project, depth: depth + 1)
            }
        }
    }

    /// Marks a task done (paid from the fund, at its planned cost unless another amount was entered) or not done.
    func toggle(task id: UUID, in projectID: UUID) {
        guard var project = budget?.projects.first(where: { $0.id == projectID }) else { return }
        for s in project.stages.indices {
            if let t = project.stages[s].tasks.firstIndex(where: { $0.id == id }) { project.stages[s].tasks[t].isDone.toggle() }
        }
        save(project)
        settle(id, in: projectID)
    }

    func deleteTask(_ id: UUID, in projectID: UUID) {
        guard var project = budget?.projects.first(where: { $0.id == projectID }) else { return }
        if let payment = project.tasks.first(where: { $0.id == id })?.payment { budget?.withdrawals.removeAll { $0.id == payment } }
        for s in project.stages.indices {
            project.stages[s].tasks.removeAll { $0.id == id }
            for t in project.stages[s].tasks.indices where project.stages[s].tasks[t].after == id { project.stages[s].tasks[t].after = nil }
        }
        save(project)
    }

    /// Keeps the fund's payment for a task in line with it: a done task with a cost is paid out of the fund.
    private func settle(_ taskID: UUID, in projectID: UUID) {
        guard var budget, let p = budget.projects.firstIndex(where: { $0.id == projectID }) else { return }
        var project = budget.projects[p]
        guard let fund = project.fund,
              let s = project.stages.firstIndex(where: { $0.tasks.contains { $0.id == taskID } }),
              let t = project.stages[s].tasks.firstIndex(where: { $0.id == taskID }) else { return }
        var task = project.stages[s].tasks[t]
        if let payment = task.payment { budget.withdrawals.removeAll { $0.id == payment } }
        task.payment = nil
        let amount = project.spent(on: task)
        if task.isDone, amount > 0 {
            let withdrawal = Withdrawal(envelope: fund, amount: amount, note: task.title)
            budget.withdrawals.append(withdrawal)
            task.payment = withdrawal.id
        }
        project.stages[s].tasks[t] = task
        budget.projects[p] = project
        self.budget = budget
    }
}

enum ProjectTemplate: String, CaseIterable, Identifiable {
    case moveAbroad = "Move to another country", empty = "Empty"
    var id: Self { self }

    /// Stages with typical steps, dated evenly up to the target; costs are left for the user.
    func stages(until target: Date) -> [Stage] {
        guard self == .moveAbroad else { return [Stage(name: String(localized: "First steps"))] }
        let plan: [(String, [String])] = [
            ("Documents", ["Passports for everyone", "Apostilles and certified translations", "Education and work records assessment",
                           "Police certificates", "Language test"]),
            ("Visa", ["Application and government fees", "Biometrics (with the trip there)", "Medical exam", "Proof of funds"]),
            ("Before the move", ["Flights", "Movers or shipping belongings", "Pets: vet papers, microchip, carrier, flight",
                                 "Health insurance until local coverage", "Sell or store what stays",
                                 "Close contracts, banks and subscriptions"]),
            ("First month", ["Temporary housing", "Rental deposit and first month", "Phone and bank account",
                             "Transit and getting around", "Furniture and basics"]),
        ]
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let span = max(4, calendar.dateComponents([.day], from: today, to: target).day ?? 120)
        var previous: UUID?
        return plan.enumerated().map { i, stage in
            // Each stage takes its share of the time to the target; its steps spread across it.
            let start = span * i / plan.count, end = span * (i + 1) / plan.count
            let tasks = stage.1.enumerated().map { j, title -> ProjectTask in
                let offset = start + (end - start) * (j + 1) / stage.1.count
                return ProjectTask(title: String(localized: String.LocalizationValue(title)),
                                   due: calendar.date(byAdding: .day, value: offset, to: today)!, after: j == 0 && i > 0 ? previous : nil)
            }
            previous = tasks.last?.id
            return Stage(name: String(localized: String.LocalizationValue(stage.0)), tasks: tasks)
        }
    }
}
