import HaluMeCore
import SwiftUI

/// First run: welcome → pay → bills → savings → a preview of the first plan.
struct OnboardingView: View {
    @Environment(BudgetStore.self) private var store
    @State private var step = CommandLine.arguments.firstIndex(of: "--step").flatMap { Int(CommandLine.arguments[$0 + 1]) } ?? 0
    @State private var draft = CommandLine.arguments.contains("--demo") ? Draft(Demo.budget()) : Draft()

    private let count = 5

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    HStack {
                        Brand()
                        Spacer()
                        if step == 0 { LanguageMenu().padding(.trailing, 12) }
                        StepDots(count: count, current: step)
                    }
                    .padding(.bottom, 12)

                    Group {
                        switch step {
                        case 0: WelcomeStep(draft: $draft)
                        case 1: PayEditor(pay: $draft.pay, currency: draft.currency)
                        case 2: BillsEditor(bills: $draft.bills, currency: draft.currency, member: draft.member)
                        case 3: SavingsEditor(envelopes: $draft.envelopes, currency: draft.currency, member: draft.member)
                        default: PreviewStep(budget: draft.budget())
                        }
                    }
                    .transition(.asymmetric(insertion: .opacity.combined(with: .offset(x: 24)), removal: .opacity))
                    .id(step)
                }
                .frame(maxWidth: 600, alignment: .leading)
                .padding(.horizontal, 40)
                .padding(.top, 44)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity)
            }

            HStack {
                if step > 0 {
                    Button("Back") { step -= 1 }
                        .buttonStyle(SecondaryButtonStyle())
                        .keyboardShortcut(.cancelAction)
                }
                Spacer()
                Button(LocalizedStringKey(step == count - 1 ? "Start planning" : "Continue")) {
                    if step == count - 1 { store.budget = draft.budget() } else { step += 1 }
                }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(step == 1 && (draft.pay.amount <= 0 || (draft.pay.split == .advance && draft.pay.frequency == .twiceMonthly && draft.pay.advance >= draft.pay.amount)))
            }
            .frame(maxWidth: 600)
            .padding(.horizontal, 40)
            .padding(.vertical, 20)
            .frame(maxWidth: .infinity)
            .background(.bar.opacity(0.6))
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.9), value: step)
    }
}

// MARK: Draft

struct Draft {
    var name = ""
    var currency = Locale.current.currency?.identifier ?? "USD"
    var pay = PaySettings()
    var bills: [Bill] = []
    var envelopes: [Envelope] = []
    var member = UUID()

    init() {}

    /// Pre-filled from a budget (the demo).
    init(_ budget: Budget) {
        name = budget.name
        currency = budget.currency
        if let income = budget.incomes.first { pay = PaySettings(income) }
        bills = budget.bills
        envelopes = budget.envelopes
        member = budget.members[0].id
    }

    func budget() -> Budget {
        let name = name.trimmingCharacters(in: .whitespaces)
        var income = Income(member: member, name: "Salary", schedule: .monthly(days: [10]), expected: 0)
        pay.apply(to: &income)
        return Budget(
            name: name.isEmpty ? "My budget" : name, currency: currency,
            members: [Member(id: member, name: name.isEmpty ? "Me" : name)],
            incomes: [income], bills: bills.cleaned, envelopes: envelopes.cleaned
        )
    }
}

extension [Bill] {
    var cleaned: [Bill] { filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty && $0.amount > 0 } }
}

extension [Envelope] {
    /// Named envelopes, prioritised in list order.
    var cleaned: [Envelope] {
        filter { !$0.name.trimmingCharacters(in: .whitespaces).isEmpty }
            .enumerated().map { var e = $0.element; e.priority = $0.offset; return e }
    }
}

enum Frequency: String, CaseIterable, Identifiable {
    case twiceMonthly = "Twice a month", monthly = "Monthly", biweekly = "Every 2 weeks", weekly = "Weekly", daily = "Every day"
    var id: Self { self }
}

enum SplitKind: String, CaseIterable, Identifiable {
    case byWorkdays = "By working days", equal = "Equally", advance = "Fixed advance"
    var id: Self { self }
}

/// The pay form, read from and written back to an income.
struct PaySettings {
    var frequency = Frequency.twiceMonthly
    var firstDay = 10
    var secondDay = 25
    var lastPayday = Date()
    var shift = WeekendShift.earlier
    /// A month's salary for monthly schedules; per payday or per day otherwise.
    var amount: Decimal = 0
    var split = SplitKind.byWorkdays
    var advance: Decimal = 0
    var weekdaysOnly = true

    init() {}

    init(_ income: Income) {
        shift = income.shift
        amount = income.expected
        switch income.schedule {
        case .monthly(let days):
            frequency = days.count > 1 ? .twiceMonthly : .monthly
            firstDay = days.first ?? 10
            secondDay = days.dropFirst().first ?? 25
            // Older budgets stored the amount per payday.
            if !income.isMonthly { amount = income.expected * Decimal(days.count); split = .equal }
        case .everyWeeks(let weeks, let from):
            frequency = weeks == 1 ? .weekly : .biweekly
            lastPayday = from
        case .daily(let weekdays):
            frequency = .daily
            weekdaysOnly = weekdays
        }
        if income.isMonthly {
            switch income.split {
            case .equal: split = .equal
            case .byWorkdays: split = .byWorkdays
            case .advance(let a): split = .advance; advance = a
            }
        }
    }

    var isMonthly: Bool { frequency == .twiceMonthly || frequency == .monthly }

    func apply(to income: inout Income) {
        income.schedule = switch frequency {
        case .twiceMonthly: .monthly(days: [firstDay, secondDay].sorted())
        case .monthly: .monthly(days: [firstDay])
        case .biweekly: .everyWeeks(2, from: lastPayday)
        case .weekly: .everyWeeks(1, from: lastPayday)
        case .daily: .daily(weekdaysOnly: weekdaysOnly)
        }
        income.shift = shift
        income.expected = amount
        income.isMonthly = isMonthly
        income.split = switch split {
        case .equal: .equal
        case .byWorkdays: .byWorkdays
        case .advance: .advance(advance)
        }
    }
}

// MARK: Steps

private struct WelcomeStep: View {
    @Binding var draft: Draft

    var body: some View {
        StepTitle("Plan each paycheck,\nnot each coffee",
                  "When pay arrives, HaluMe splits it: bills first, then savings. The rest is yours to spend — no expense logging.")
        VStack(alignment: .leading, spacing: 16) {
            Point(icon: "calendar", title: "Knows your paydays", text: "Bills are matched to the pay that comes before them.")
            Point(icon: "checklist", title: "Tells you what to move", text: "A short checklist each payday, then nothing to do.")
            Point(icon: "sun.max", title: "One number a day", text: "How much you can spend until the next pay.")
        }
        .card(padding: 20)
        HStack(alignment: .top, spacing: 16) {
            Field("Your name") { BoxTextField("Optional", text: $draft.name) }
            Field("Currency") {
                CurrencyField(code: $draft.currency)
            }
        }
    }
}

struct PayEditor: View {
    @Binding var pay: PaySettings
    let currency: String
    var showsTitle = true

    var body: some View {
        if showsTitle {
            StepTitle("When do you get paid?", "Enter your usual salary. When pay comes in different from it — sick leave, holidays, a bonus — you'll enter the real amount and the plan adjusts.")
        }
        Field("How often") {
            Picker("How often", selection: $pay.frequency) {
                ForEach(Frequency.allCases) { Text(LocalizedStringKey($0.rawValue)).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
        HStack(alignment: .top, spacing: 16) {
            switch pay.frequency {
            case .twiceMonthly:
                Field("First payday") { DayPicker(day: $pay.firstDay) }.frame(width: 120, alignment: .leading)
                Field("Second payday") { DayPicker(day: $pay.secondDay) }.frame(width: 120, alignment: .leading)
            case .monthly:
                Field("Payday") { DayPicker(day: $pay.firstDay) }.frame(width: 120, alignment: .leading)
            case .biweekly, .weekly:
                Field("Last payday") {
                    DateField(date: $pay.lastPayday, range: .distantPast ... Date())
                }
                .frame(width: 210, alignment: .leading)
            case .daily:
                EmptyView()
            }
            Field(amountLabel, hint: "After tax") { AmountField(amount: $pay.amount, currency: currency) }
        }
        if pay.frequency == .twiceMonthly {
            Field("How it's split", hint: splitHint) {
                Picker("Split", selection: $pay.split) {
                    ForEach(SplitKind.allCases) { Text(LocalizedStringKey($0.rawValue)).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            if pay.split == .advance {
                Field("Advance") { AmountField(amount: $pay.advance, currency: currency) }.frame(width: 200, alignment: .leading)
            }
        }
        if pay.frequency == .daily {
            Toggle("Weekdays only", isOn: $pay.weekdaysOnly)
            Text("HaluMe plans daily pay by the week: each Monday you see the week's bills and savings.")
                .font(.callout).foregroundStyle(.secondary)
        } else {
            Field("When payday falls on a weekend") {
                Picker("Weekend", selection: $pay.shift) {
                    Text("Paid before").tag(WeekendShift.earlier)
                    Text("Paid after").tag(WeekendShift.later)
                    Text("Same day").tag(WeekendShift.none)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        }
    }

    private var amountLabel: LocalizedStringKey {
        switch pay.frequency {
        case .twiceMonthly, .monthly: "Salary a month"
        case .biweekly, .weekly: "Each payday"
        case .daily: "Each day"
        }
    }

    private var splitHint: LocalizedStringKey {
        switch pay.split {
        case .byWorkdays: "Each payday gets the share of working days in its half of the month, like most payrolls."
        case .equal: "Half and half."
        case .advance: "A fixed advance on the payday late in the month, the rest on the other one."
        }
    }
}

struct BillsEditor: View {
    @Binding var bills: [Bill]
    let currency: String
    let member: UUID
    var showsTitle = true
    private let suggestions = ["Rent", "Utilities", "Phone", "Internet", "Subscriptions", "Loan"]

    var body: some View {
        if showsTitle {
            StepTitle("What do you pay every month?", "Each bill comes out of the paycheck before its due date. Skip this if you have none.")
        }
        if !bills.isEmpty {
            VStack(spacing: 14) {
                ForEach($bills) { $bill in
                    HStack(alignment: .bottom, spacing: 12) {
                        Field("Bill") { BoxTextField("Name", text: $bill.name) }
                        Field("Amount") { AmountField(amount: $bill.amount, currency: currency) }
                            .frame(width: 130, alignment: .leading)
                        Field("Due day") { DayPicker(day: $bill.day) }
                            .frame(width: 84, alignment: .leading)
                        RemoveButton { bills.removeAll { $0.id == bill.id } }
                    }
                }
            }
            .card(padding: 20)
        }
        Suggestions(names: suggestions.filter { name in !bills.contains { $0.name == String(localized: String.LocalizationValue(name)) } }) { name in
            bills.append(Bill(owner: .member(member), name: name, amount: 0, day: 1))
        }
    }
}

struct SavingsEditor: View {
    @Binding var envelopes: [Envelope]
    let currency: String
    let member: UUID
    var showsTitle = true

    var body: some View {
        if showsTitle {
            StepTitle("What are you saving for?",
                      "Savings come out of each pay before you spend it. When pay runs short, the top one is funded first.")
        }
        ForEach($envelopes) { $envelope in
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .bottom, spacing: 12) {
                    Field("Name") { BoxTextField("Name", text: $envelope.name) }
                    Field("How") {
                        Picker("How", selection: $envelope.kind) {
                            ForEach(GoalKind.allCases) { Text(LocalizedStringKey($0.rawValue)).tag($0) }
                        }
                        .labelsHidden()
                    }
                    .frame(width: 170, alignment: .leading)
                    RemoveButton { envelopes.removeAll { $0.id == envelope.id } }
                }
                HStack(alignment: .top, spacing: 12) {
                    if envelope.kind == .percent {
                        Field("Percent of each pay") {
                            PercentField(value: $envelope.value).frame(width: 90, alignment: .leading)
                        }
                    } else {
                        Field(envelope.kind.amountLabel) { AmountField(amount: $envelope.value, currency: currency) }
                            .frame(width: 170, alignment: .leading)
                    }
                    if envelope.kind == .target {
                        Field("By") {
                            DateField(date: $envelope.deadline, range: Date() ... .distantFuture)
                        }
                    }
                    Field("Already saved") { AmountField(amount: $envelope.opening, currency: currency) }
                        .frame(width: 150, alignment: .leading)
                    Spacer(minLength: 0)
                }
                HoldingFields(envelope: $envelope)
            }
            .card(padding: 20)
        }
        Suggestions(names: ["Emergency fund", "Vacation", "Gifts", "New laptop"]
            .filter { name in !envelopes.contains { $0.name == String(localized: String.LocalizationValue(name)) } }) { name in
            let goal: Goal = switch name {
            case String(localized: "Emergency fund"): .percent(10)
            case String(localized: "Gifts"): .yearly(0)
            default: .target(0, by: Calendar.current.date(byAdding: .month, value: 6, to: Date())!)
            }
            envelopes.append(Envelope(owner: .member(member), name: name, goal: goal))
        }
    }
}

private struct PreviewStep: View {
    let budget: Budget

    var body: some View {
        let planner = Planner(budget)
        let me = budget.members[0].id
        StepTitle("Here's your plan", "This is how your current paycheck splits. You can change any of it later.")
        if let allowance = planner.allowance(for: me, on: Date()), let start = planner.current(on: Date(), of: me) {
            Hero(allowance: allowance, start: start, currency: budget.currency, note: nil, weekly: budget.plansByWeek)
            PlanList(plan: planner.plan(for: me, on: start), record: nil, currency: budget.currency, weekly: budget.plansByWeek, toggle: nil)
        }
        Label("Debts, subscriptions and savings accounts are in the sidebar. Add them any time and the plan updates.",
              systemImage: "sidebar.left")
            .font(.callout)
            .foregroundStyle(.secondary)
    }
}

// MARK: Goal editing

enum GoalKind: String, CaseIterable, Identifiable {
    case target = "Goal by a date", percent = "% of each pay", perPayday = "Same each payday", yearly = "Yearly expense"
    var id: Self { self }

    var amountLabel: LocalizedStringKey {
        switch self {
        case .target: "Goal"
        case .perPayday: "Each payday"
        case .yearly: "Per year"
        case .percent: "Percent"
        }
    }
}

extension Envelope {
    var kind: GoalKind {
        get {
            switch goal {
            case .target: .target
            case .percent: .percent
            case .yearly: .yearly
            case .perPayday, .open: .perPayday
            }
        }
        set { goal = Self.goal(newValue, value: value, deadline: deadline) }
    }

    var value: Decimal {
        get {
            switch goal {
            case .target(let v, _), .percent(let v), .perPayday(let v), .yearly(let v): v
            case .open: 0
            }
        }
        set { goal = Self.goal(kind, value: newValue, deadline: deadline) }
    }

    var deadline: Date {
        get {
            if case .target(_, let by) = goal { return by }
            return Calendar.current.date(byAdding: .month, value: 6, to: Date())!
        }
        set { goal = Self.goal(kind, value: value, deadline: newValue) }
    }

    private static func goal(_ kind: GoalKind, value: Decimal, deadline: Date) -> Goal {
        switch kind {
        case .target: .target(value, by: deadline)
        case .percent: .percent(value)
        case .perPayday: .perPayday(value)
        case .yearly: .yearly(value)
        }
    }
}

// MARK: Pieces

struct StepTitle: View {
    let title: LocalizedStringKey, subtitle: LocalizedStringKey
    init(_ title: LocalizedStringKey, _ subtitle: LocalizedStringKey) { self.title = title; self.subtitle = subtitle }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 34, weight: .semibold)).tracking(-0.5)
            Text(subtitle).font(.title3).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct Point: View {
    let icon: String, title: LocalizedStringKey, text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Palette.orange)
                .frame(width: 34, height: 34)
                .background(Circle().fill(Palette.orange.opacity(0.14)))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body.weight(.semibold))
                Text(text).foregroundStyle(.secondary)
            }
        }
    }
}

private struct StepDots: View {
    let count: Int, current: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { i in
                Capsule()
                    .fill(i <= current ? AnyShapeStyle(Palette.orange.opacity(i == current ? 1 : 0.4)) : AnyShapeStyle(.quaternary))
                    .frame(width: i == current ? 20 : 6, height: 6)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Step \(current + 1) of \(count)")
    }
}
