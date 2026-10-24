import HaluMeCore
import SwiftUI

struct HomeView: View {
    @Environment(BudgetStore.self) private var store

    var body: some View {
        @Bindable var store = store
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack {
                    Brand()
                    Spacer()
                    IconButton(icon: "creditcard", label: "Check balance") { store.sheet = .balance }
                    IconButton(icon: "slider.horizontal.3", label: "Edit plan") { store.sheet = .plan }
                }
                if let budget = store.budget, let me = store.me, let planner = store.planner {
                    content(budget: budget, me: me, planner: planner)
                }
            }
            .frame(maxWidth: 640, alignment: .leading)
            .padding(.horizontal, 40)
            .padding(.top, 44)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity)
        }
        .sheet(item: $store.sheet) { sheet in
            switch sheet {
            case .pay: PaySheet()
            case .balance: BalanceSheet()
            case .plan: PlanEditor()
            }
        }
        .confirmationDialog("Start over?", isPresented: $store.confirmingStartOver) {
            Button("Delete Budget and Start Over", role: .destructive) { store.startOver() }
        } message: {
            Text("Your plan, savings and history will be deleted. This can't be undone.")
        }
    }

    @ViewBuilder
    private func content(budget: Budget, me: UUID, planner: Planner) -> some View {
        let today = Date()
        if let allowance = planner.allowance(for: me, on: today), let start = planner.current(on: today, of: me) {
            let record = planner.payday(of: me, on: start)
            Hero(allowance: allowance, start: start, currency: budget.currency,
                 note: balanceNote(budget: budget, me: me, start: start))
            if record?.actual == nil {
                PayBanner(expected: planner.expected(of: me, on: start), date: start, currency: budget.currency) {
                    store.sheet = .pay
                }
            }
            PlanList(plan: planner.plan(for: me, on: start), record: record, currency: budget.currency) {
                store.toggle($0, payday: start)
            }
        } else {
            Text("Your first payday hasn't come yet.").foregroundStyle(.secondary).card()
        }
        if !budget.envelopes.isEmpty {
            Envelopes(planner: planner, today: today)
        }
    }

    private func balanceNote(budget: Budget, me: UUID, start: Date) -> String? {
        guard let check = budget.checks.filter({ $0.member == me && $0.date >= start }).max(by: { $0.date < $1.date })
        else { return nil }
        return "From your balance of \(check.amount.money(budget.currency)), \(check.date.formatted(.relative(presentation: .named)))"
    }
}

/// The main number: about how much can be spent a day until payday.
struct Hero: View {
    let allowance: Allowance
    let start: Date
    let currency: String
    let note: String?

    var body: some View {
        let total = max(1, Calendar.current.dateComponents([.day], from: start, to: allowance.next).day ?? 1)
        let passed = total - allowance.daysLeft + 1
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(payday).font(.title3).foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(allowance.perDay.money(currency))
                        .font(.system(size: 64, weight: .medium, design: .rounded))
                        .tracking(-1)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text("a day").font(.title2).foregroundStyle(.secondary)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Bar(value: Double(passed) / Double(total))
                Text(note ?? "Day \(passed) of \(total)")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .frame(maxWidth: 360, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    private var payday: String {
        let date = allowance.next.formatted(.dateTime.day().month(.wide))
        return allowance.daysLeft == 1 ? "Payday tomorrow, \(date)" : "Payday in \(allowance.daysLeft) days, \(date)"
    }
}

private struct PayBanner: View {
    let expected: Decimal
    let date: Date
    let currency: String
    let action: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 26))
                .foregroundStyle(Palette.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Did your pay arrive?").font(.body.weight(.semibold))
                Text("Expected \(expected.money(currency)) on \(date.formatted(.dateTime.day().month(.wide))). Enter the real amount to fix the plan.")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            Button("Enter amount", action: action).buttonStyle(PrimaryButtonStyle())
        }
        .padding(18)
        .background(Palette.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(Palette.orange.opacity(0.25)))
    }
}

/// What the current paycheck pays for, with done marks.
struct PlanList: View {
    let plan: Plan
    let record: Payday?
    let currency: String
    /// nil shows the list read-only.
    let toggle: ((Target) -> Void)?

    var body: some View {
        let done = plan.lines.filter { isDone($0) }.count
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("From your \(plan.date.formatted(.dateTime.day().month(.wide))) pay").font(.headline)
                    if toggle != nil, !plan.lines.isEmpty {
                        Text(done == plan.lines.count ? "All done" : "\(done) of \(plan.lines.count) done")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(plan.pay.money(currency)).font(.title3.weight(.medium)).monospacedDigit()
            }
            .padding(.bottom, 10)

            ForEach(plan.lines, id: \.target) { line in
                Divider().opacity(0.6)
                row(line)
            }

            Divider().opacity(0.6)
            HStack(spacing: 12) {
                Image(systemName: "sun.max.fill").foregroundStyle(Palette.orange).frame(width: 24)
                Text("Yours to spend").font(.body.weight(.semibold))
                Spacer()
                Text(plan.free.money(currency)).font(.body.weight(.semibold)).monospacedDigit()
            }
            .padding(.vertical, 12)

            if plan.shortfall > 0 {
                Label("Short by \(plan.shortfall.money(currency)) this time. Goals with a date catch up from the next pays.",
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(Palette.red)
                    .padding(.top, 2)
            }
        }
        .card(padding: 20)
    }

    private func isDone(_ line: Plan.Line) -> Bool {
        record?.allocations.contains { $0.target == line.target && $0.isDone } ?? false
    }

    @ViewBuilder
    private func row(_ line: Plan.Line) -> some View {
        let done = isDone(line)
        let content = HStack(spacing: 12) {
            if toggle != nil {
                Image(systemName: done ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 19))
                    .foregroundStyle(done ? AnyShapeStyle(Palette.green) : AnyShapeStyle(.tertiary))
                    .frame(width: 24)
            } else {
                Image(systemName: line.target.isBill ? "doc.text" : "arrow.down.to.line")
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(line.name).strikethrough(done, color: .secondary).foregroundStyle(done ? .secondary : .primary)
                Text(line.target.isBill ? "Bill" : "Savings").font(.caption).foregroundStyle(.tertiary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text(line.amount.money(currency)).monospacedDigit().foregroundStyle(done ? .secondary : .primary)
                if line.amount < line.planned {
                    Text("of \(line.planned.money(currency))").font(.caption).foregroundStyle(Palette.red)
                }
            }
        }
        .padding(.vertical, 10)
        .contentShape(Rectangle())

        if let toggle {
            Button { withAnimation(.easeOut(duration: 0.15)) { toggle(line.target) } } label: { content }
                .buttonStyle(.plain)
                .accessibilityLabel("\(line.name), \(line.amount.money(currency))")
                .accessibilityValue(done ? "Done" : "Not done")
                .help(done ? "Mark as not done" : line.target.isBill ? "Mark as paid" : "Mark as moved to savings")
        } else {
            content
        }
    }
}

private struct Envelopes: View {
    let planner: Planner
    let today: Date

    var body: some View {
        let budget = planner.budget
        let tomorrow = Calendar.current.date(byAdding: .day, value: 1, to: today)!
        let total = budget.envelopes.reduce(Decimal(0)) { $0 + planner.balance(of: $1, before: tomorrow) }
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Savings").font(.headline)
                Spacer()
                Text(total.money(budget.currency)).font(.title3.weight(.medium)).monospacedDigit()
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 180), spacing: 12)], spacing: 12) {
                ForEach(budget.envelopes) { envelope in
                    let balance = planner.balance(of: envelope, before: tomorrow)
                    VStack(alignment: .leading, spacing: 10) {
                        Text(envelope.name).font(.subheadline.weight(.medium)).foregroundStyle(.secondary)
                        Text(balance.money(budget.currency))
                            .font(.system(size: 26, weight: .medium, design: .rounded))
                            .monospacedDigit()
                        if case .target(let goal, _) = envelope.goal, goal > 0 {
                            Bar(value: (balance / goal).double)
                        }
                        Text(caption(envelope, currency: budget.currency)).font(.caption).foregroundStyle(.secondary)
                    }
                    .frame(maxHeight: .infinity, alignment: .top)
                    .card()
                }
            }
        }
    }

    private func caption(_ envelope: Envelope, currency: String) -> String {
        switch envelope.goal {
        case .target(let goal, let by): "of \(goal.money(currency)) by \(by.formatted(.dateTime.month(.wide).year()))"
        case .percent(let p): "\(p.formatted())% of each pay"
        case .perPayday(let a): "\(a.money(currency)) each payday"
        case .yearly(let a): "\(a.money(currency)) a year"
        case .open: "From leftovers"
        }
    }
}

extension Target {
    var isBill: Bool { if case .bill = self { true } else { false } }
}
