import AppKit
import Charts
import HaluMeCore
import SwiftUI

struct ProjectsPage: View {
    @Environment(BudgetStore.self) private var store

    var body: some View {
        if let id = store.openProject, let project = store.budget?.projects.first(where: { $0.id == id }) {
            ProjectDetail(project: project)
        } else {
            Page(title: "Projects") {
                Button { store.sheet = .newProject } label: { Label("New project", systemImage: "plus") }
                    .buttonStyle(SecondaryButtonStyle())
            } content: {
                let projects = store.budget?.projects ?? []
                if projects.isEmpty {
                    EmptyState(icon: "flag.checkered", title: "Big plans, step by step",
                               text: "A move, a wedding, a renovation: steps with dates and costs, and money saved in time for each of them.")
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 12)], spacing: 12) {
                        ForEach(projects) { ProjectCard(project: $0) }
                    }
                }
            }
        }
    }
}

private func tomorrow() -> Date { Calendar.current.date(byAdding: .day, value: 1, to: Date())! }

private struct ProjectCard: View {
    @Environment(BudgetStore.self) private var store
    let project: Project
    @State private var hovering = false

    var body: some View {
        let budget = store.budget!
        let done = project.tasks.filter(\.isDone).count
        let fund = budget.envelopes.first { $0.id == project.fund }
        let saved = fund.flatMap { store.planner?.balance(of: $0, before: tomorrow()) } ?? 0
        let next = project.tasks.filter { !$0.isDone && $0.due != nil }.min { $0.due! < $1.due! }
        Button { store.openProject = project.id } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "flag.checkered").foregroundStyle(Palette.orange)
                    Text(project.name).font(.body.weight(.semibold))
                    Spacer()
                    OwnerBadge(owner: project.owner).font(.caption).foregroundStyle(.secondary)
                }
                Text("By \(project.target.formatted(.dateTime.month(.wide).year()))").font(.caption).foregroundStyle(.secondary)
                Bar(value: project.tasks.isEmpty ? 0 : Double(done) / Double(project.tasks.count))
                Text("\(done) of \(project.tasks.count) steps done").font(.caption).foregroundStyle(.secondary)
                if project.planned > 0 {
                    Text("\(saved.money(budget.currency)) saved of \((project.planned - project.spentSoFar).money(budget.currency)) still needed")
                        .font(.callout)
                }
                if let next {
                    Text("Next: \(next.title), \(next.due!.relativeDay)").font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .card()
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(.primary.opacity(hovering ? 0.12 : 0)))
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

// MARK: Detail

private struct ProjectDetail: View {
    @Environment(BudgetStore.self) private var store
    let project: Project
    @State private var newStage = ""
    @State private var confirmDelete = false

    var body: some View {
        let budget = store.budget!
        let currency = budget.currency
        let fund = budget.envelopes.first { $0.id == project.fund }
        let saved = fund.flatMap { store.planner?.balance(of: $0, before: tomorrow()) } ?? 0
        let foreign = Set(project.tasks.compactMap(\.currency)).subtracting([currency])
        Page(title: LocalizedStringKey(project.name)) {
            IconButton(icon: "chevron.left", label: "All projects") { store.openProject = nil }
            if !foreign.isEmpty {
                IconButton(icon: "dollarsign.arrow.circlepath", label: "Exchange rates") { store.sheet = .rates(project.id) }
            }
            Menu {
                Button("Delete Project…", role: .destructive) { confirmDelete = true }
            } label: { Image(systemName: "ellipsis") }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help(Text("More"))
        } content: {
            StatRow {
                Stat(label: "Planned", value: project.planned.money(currency), big: true)
                Stat(label: "Saved", value: saved.money(currency))
                Stat(label: "Spent", value: project.spentSoFar.money(currency))
                if let line = currentLine(fund: fund) {
                    Stat(label: "Each payday", value: line.money(currency))
                }
            }
            Milestones(project: project, saved: saved, currency: currency)
            if project.tasks.contains(where: { $0.due != nil }) {
                Timeline(project: project).card(padding: 18)
            }
            ForEach(project.stages) { stage in
                StageCard(project: project, stage: stage)
            }
            HStack(spacing: 8) {
                BoxTextField("New stage", text: $newStage).frame(maxWidth: 260)
                Button("Add Stage") {
                    var changed = project
                    changed.stages.append(Stage(name: newStage.trimmingCharacters(in: .whitespaces)))
                    store.save(changed)
                    newStage = ""
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(newStage.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .confirmationDialog("Delete this project?", isPresented: $confirmDelete) {
            Button("Delete Project", role: .destructive) { store.deleteProject(project.id) }
        } message: {
            Text("Its steps are deleted. Money already saved stays in Savings.")
        }
    }

    /// What the fund asks from the current paycheck.
    private func currentLine(fund: Envelope?) -> Decimal? {
        guard let fund, let me = store.me, let planner = store.planner, let start = planner.current(on: Date(), of: me) else { return nil }
        return planner.plan(for: me, on: start).lines.first { $0.target == .envelope(fund.id) }?.planned
    }
}

/// Money needed by each date, and whether the fund is on track.
private struct Milestones: View {
    let project: Project
    let saved: Decimal
    let currency: String

    var body: some View {
        let milestones = project.milestones().filter { $0.needed > 0 }.prefix(4)
        if !milestones.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Money needed").font(.headline)
                ForEach(Array(milestones), id: \.date) { m in
                    HStack {
                        Image(systemName: saved >= m.needed ? "checkmark.circle.fill" : "circle.dashed")
                            .foregroundStyle(saved >= m.needed ? Palette.green : Palette.orange)
                        Text("By \(m.date.formatted(.dateTime.day().month(.wide).year()))")
                        Spacer()
                        Text(m.needed.money(currency)).monospacedDigit()
                    }
                }
                Text("Each payday HaluMe puts aside enough to have this in time.").font(.caption).foregroundStyle(.secondary)
            }
            .card()
        }
    }
}

/// Stages on a time line, steps as dots, today as a line.
private struct Timeline: View {
    let project: Project

    var body: some View {
        let stages = project.stages.compactMap { stage -> (String, Date, Date)? in
            let dates = stage.tasks.compactMap(\.due)
            guard let first = dates.min(), let last = dates.max() else { return nil }
            return (stage.name, first, max(last, Calendar.current.date(byAdding: .day, value: 3, to: first)!))
        }
        let points = project.stages.flatMap { stage in stage.tasks.compactMap { t in t.due.map { (stage.name, $0, t.isDone) } } }
        Chart {
            ForEach(Array(stages.enumerated()), id: \.offset) { _, s in
                BarMark(xStart: .value("Start", s.1), xEnd: .value("End", s.2), y: .value("Stage", s.0), height: 14)
                    .foregroundStyle(Palette.orange.opacity(0.35))
                    .cornerRadius(7)
            }
            ForEach(Array(points.enumerated()), id: \.offset) { _, p in
                PointMark(x: .value("Due", p.1), y: .value("Stage", p.0))
                    .foregroundStyle(p.2 ? Palette.green : Palette.orange)
                    .symbolSize(40)
            }
            RuleMark(x: .value("Today", Date()))
                .foregroundStyle(Color.primary.opacity(0.4))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                .annotation(position: .top, alignment: .leading) { Text("Today").font(.caption2).foregroundStyle(.secondary) }
        }
        .chartXAxis { AxisMarks(values: .stride(by: .month)) { _ in AxisGridLine().foregroundStyle(.quaternary); AxisValueLabel(format: .dateTime.month(.abbreviated)) } }
        .frame(height: CGFloat(max(stages.count, 1)) * 34 + 40)
    }
}

private struct StageCard: View {
    @Environment(BudgetStore.self) private var store
    let project: Project
    let stage: Stage

    var body: some View {
        let currency = store.budget?.currency ?? "USD"
        let cost = stage.tasks.reduce(Decimal(0)) { $0 + project.cost(of: $1) }
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(stage.name).font(.headline)
                Text("\(stage.tasks.filter(\.isDone).count)/\(stage.tasks.count)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                if cost > 0 { Text(cost.money(currency)).monospacedDigit().foregroundStyle(.secondary) }
                IconButton(icon: "plus", label: "Add step") {
                    store.sheet = .task(project: project.id, stage: stage.id, task: ProjectTask(title: "", due: project.target))
                }
            }
            .padding(.bottom, 8)
            ForEach(stage.tasks) { task in
                Divider().opacity(0.6)
                TaskRow(project: project, stage: stage, task: task)
            }
            if stage.tasks.isEmpty {
                Text("No steps yet.").foregroundStyle(.secondary).padding(.vertical, 8)
            }
        }
        .card(padding: 18)
        .contextMenu {
            Button("Delete Stage", role: .destructive) {
                var changed = project
                changed.stages.removeAll { $0.id == stage.id }
                store.save(changed)
            }
            .disabled(!stage.tasks.isEmpty)
        }
    }
}

private struct TaskRow: View {
    @Environment(BudgetStore.self) private var store
    let project: Project
    let stage: Stage
    let task: ProjectTask

    var body: some View {
        let budget = store.budget!
        let overdue = !task.isDone && (task.due.map { $0 < Calendar.current.startOfDay(for: Date()) } ?? false)
        let waitsFor = task.after.flatMap { id in project.tasks.first { $0.id == id } }
        HStack(spacing: 12) {
            Button { store.toggle(task: task.id, in: project.id) } label: {
                Image(systemName: task.isDone ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 19))
                    .foregroundStyle(task.isDone ? AnyShapeStyle(Palette.green) : AnyShapeStyle(.tertiary))
            }
            .buttonStyle(.plain)
            .help(task.isDone ? Text("Mark as not done") : Text("Mark as done"))
            .accessibilityLabel(Text(task.title))
            .accessibilityValue(task.isDone ? Text("Done") : Text("Not done"))
            Button { store.sheet = .task(project: project.id, stage: stage.id, task: task) } label: {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(task.title).strikethrough(task.isDone, color: .secondary).foregroundStyle(task.isDone ? .secondary : .primary)
                        HStack(spacing: 6) {
                            if let due = task.due {
                                Text(due.formatted(.dateTime.day().month(.abbreviated).year()))
                                    .foregroundStyle(overdue ? Palette.red : .secondary)
                            }
                            if let waitsFor, !waitsFor.isDone {
                                Text("after \(waitsFor.title)").lineLimit(1)
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let assignee = task.assignee, let member = budget.members.first(where: { $0.id == assignee }) {
                        Monogram(name: member.name, size: 22).help(Text(member.name))
                    }
                    VStack(alignment: .trailing, spacing: 1) {
                        if task.isDone, task.spent != nil {
                            Text(project.spent(on: task).money(budget.currency)).monospacedDigit()
                        } else if task.cost > 0 {
                            Text(project.cost(of: task).money(budget.currency)).monospacedDigit().foregroundStyle(.secondary)
                        }
                        if let code = task.currency, code != budget.currency, task.cost > 0 {
                            Text((task.spent ?? task.cost).money(code)).font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, 8)
        .contextMenu {
            Button("Delete Step", role: .destructive) { store.deleteTask(task.id, in: project.id) }
        }
    }
}

// MARK: Sheets

struct NewProjectSheet: View {
    @Environment(BudgetStore.self) private var store
    @State private var name = ""
    @State private var template = ProjectTemplate.moveAbroad
    @State private var target = Calendar.current.date(byAdding: .month, value: 9, to: Date())!
    @State private var owner = Owner.shared
    @State private var split = Split.equal

    var body: some View {
        SheetFrame(title: "New project", subtitle: "Steps with dates and costs. HaluMe saves for each of them in time.",
                   action: "Create", canSave: !name.trimmingCharacters(in: .whitespaces).isEmpty,
                   save: { store.createProject(name: name.trimmingCharacters(in: .whitespaces), template: template, target: target,
                                               owner: owner, split: split) }) {
            Field("Name") { BoxTextField("e.g. Move to Canada", text: $name) }
            Field("Start from") {
                Picker("Start from", selection: $template) {
                    ForEach(ProjectTemplate.allCases) { Text(LocalizedStringKey($0.rawValue)).tag($0) }
                }
                .labelsHidden()
            }
            if template != .empty {
                Text("Typical steps, spread up to your date. Add costs and dates for your case; remove what you don't need.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Field("Done by") { DateField(date: $target, range: Date() ... .distantFuture) }.frame(width: 240, alignment: .leading)
            OwnerFields(owner: $owner, split: $split)
        }
        .onAppear { if store.partners.isEmpty, let me = store.me { owner = .member(me) } }
    }
}

struct TaskEditor: View {
    @Environment(BudgetStore.self) private var store
    let projectID: UUID
    @State var stageID: UUID
    @State var task: ProjectTask
    @State private var hasDate = true
    @State private var shiftLater = true
    @State private var originalDue: Date?

    var body: some View {
        let budget = store.budget!
        let project = budget.projects.first { $0.id == projectID }!
        let isNew = !project.tasks.contains { $0.id == task.id }
        let currency = Binding(get: { task.currency ?? budget.currency }, set: { task.currency = $0 == budget.currency ? nil : $0 })
        let waiting = project.tasks.contains { $0.after == task.id }
        SheetFrame(title: LocalizedStringKey(isNew ? "New step" : "Edit step"),
                   subtitle: "Its cost is saved for by its date. When it's done, what it cost comes out of the project fund.",
                   action: LocalizedStringKey(isNew ? "Add" : "Save"),
                   canSave: !task.title.trimmingCharacters(in: .whitespaces).isEmpty,
                   save: {
                       if !hasDate { task.due = nil }
                       store.save(task, in: stageID, of: projectID, shiftLater: shiftLater && waiting)
                   }) {
            Field("Step") { BoxTextField("e.g. Biometrics appointment", text: $task.title) }
            HStack(alignment: .top, spacing: 12) {
                Field("Stage") {
                    Picker("Stage", selection: $stageID) {
                        ForEach(project.stages) { Text($0.name).tag($0.id) }
                    }
                    .labelsHidden()
                }
                if !store.partners.isEmpty, let me = store.me {
                    Field("Who") {
                        Picker("Who", selection: $task.assignee) {
                            Text("Anyone").tag(UUID?.none)
                            Text("Me").tag(UUID?.some(me))
                            ForEach(store.partners) { Text($0.name).tag(UUID?.some($0.id)) }
                        }
                        .labelsHidden()
                    }
                }
            }
            HStack(alignment: .top, spacing: 12) {
                Field("Cost") { AmountField(amount: $task.cost, currency: currency.wrappedValue) }
                Field("Currency") { CurrencyField(code: currency) }.frame(width: 200, alignment: .leading)
            }
            if task.isDone {
                Field("Actually spent", hint: "Leave empty if it cost as planned") {
                    AmountField(optional: $task.spent, currency: currency.wrappedValue, placeholder: "As planned")
                }
            }
            HStack(alignment: .center, spacing: 12) {
                Toggle("Date", isOn: $hasDate)
                if hasDate {
                    DateField(date: Binding(get: { task.due ?? project.target }, set: { task.due = $0 })).frame(width: 220)
                }
            }
            if waiting, hasDate, let originalDue, let due = task.due, due != originalDue {
                Toggle("Move the steps that wait for this one by as much", isOn: $shiftLater)
            }
            Field("After", hint: "This step waits for another one") {
                Picker("After", selection: $task.after) {
                    Text("Nothing").tag(UUID?.none)
                    ForEach(project.tasks.filter { $0.id != task.id }) { Text($0.title).tag(UUID?.some($0.id)) }
                }
                .labelsHidden()
            }
            Field("Note", hint: "Optional") { BoxTextField("Addresses, what to bring, who to call", text: $task.note) }
            Field("Link", hint: "Optional") { BoxTextField("https://", text: $task.link) }
            if !isNew {
                HStack(spacing: 16) {
                    if let url = URL(string: task.link), url.scheme?.hasPrefix("http") == true {
                        Button("Open Link") { NSWorkspace.shared.open(url) }
                    }
                    Button("Delete Step", role: .destructive) {
                        store.deleteTask(task.id, in: projectID)
                        store.sheet = nil
                    }
                    .foregroundStyle(Palette.red)
                }
                .buttonStyle(.borderless)
            }
        }
        .onAppear {
            hasDate = task.due != nil || isNew
            originalDue = task.due
        }
    }
}

/// Exchange rates for a project's foreign costs: typed in or fetched.
struct RatesSheet: View {
    @Environment(BudgetStore.self) private var store
    let projectID: UUID
    @State private var rates: [String: Decimal] = [:]
    @State private var loading = false
    @State private var failed = false

    var body: some View {
        let budget = store.budget!
        let project = budget.projects.first { $0.id == projectID }!
        let codes = Set(project.tasks.compactMap(\.currency)).subtracting([budget.currency]).sorted()
        SheetFrame(title: "Exchange rates", subtitle: "Costs in other currencies count in \(budget.currency) at these rates.",
                   action: "Save", save: {
                       var changed = project
                       changed.rates = rates
                       store.save(changed)
                   }) {
            ForEach(codes, id: \.self) { code in
                Field("1 \(code) =") {
                    AmountField(optional: Binding(get: { rates[code] }, set: { rates[code] = $0 }), currency: budget.currency, placeholder: "Rate")
                }
            }
            HStack {
                Button(loading ? "Updating…" : "Update from the Internet") { update(codes, to: budget.currency) }
                    .disabled(loading)
                if failed { Text("Couldn't load the rates.").font(.caption).foregroundStyle(Palette.red) }
            }
        }
        .onAppear { rates = project.rates }
    }

    private func update(_ codes: [String], to base: String) {
        loading = true
        failed = false
        Task {
            for code in codes {
                if let rate = await RateLoader.rate(of: code, in: base) { rates[code] = rate } else { failed = true }
            }
            loading = false
        }
    }
}

/// Exchange rates from open.er-api.com (free, no key; nothing about the user is sent).
enum RateLoader {
    static func rate(of code: String, in base: String) async -> Decimal? {
        struct Reply: Decodable { let rates: [String: Double] }
        guard let url = URL(string: "https://open.er-api.com/v6/latest/\(code)"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let reply = try? JSONDecoder().decode(Reply.self, from: data),
              let value = reply.rates[base] else { return nil }
        return Decimal(string: String(format: "%.4f", value))
    }
}
