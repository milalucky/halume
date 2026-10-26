import HaluMeCore
import SwiftUI

/// The main number: about how much can be spent a day until payday.
struct Hero: View {
    let allowance: Allowance
    let start: Date
    let currency: String
    let note: String?
    var weekly = false

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
                Text(note ?? String(localized: "Day \(passed) of \(total)"))
                    .font(.callout).foregroundStyle(.secondary)
            }
            .frame(maxWidth: 360, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    private var payday: String {
        let date = allowance.next.formatted(.dateTime.day().month(.wide))
        if weekly {
            return allowance.daysLeft == 1 ? String(localized: "New week tomorrow") : String(localized: "\(allowance.daysLeft) days left this week")
        }
        return allowance.daysLeft == 1 ? String(localized: "Payday tomorrow, \(date)") : String(localized: "Payday in \(allowance.daysLeft) days, \(date)")
    }
}

struct PayBanner: View {
    let expected: Decimal
    let date: Date
    let currency: String
    var weekly = false
    let action: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 26))
                .foregroundStyle(Palette.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(weekly ? String(localized: "How much did you earn this week?") : String(localized: "Did your pay arrive?"))
                    .font(.body.weight(.semibold))
                Text(weekly ? String(localized: "Expected about \(expected.money(currency)). Enter the real amount at the end of the week to fix the plan.")
                            : String(localized: "Expected \(expected.money(currency)) on \(date.formatted(.dateTime.day().month(.wide))). Enter the real amount to fix the plan."))
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
    var weekly = false
    var onEditPlan: (() -> Void)?
    /// "from T-Bank card" for a line, when known.
    var source: ((Target) -> String?)?
    /// Which envelope a line belongs to (bills, subscriptions…); by its kind when not given.
    var group: ((Target) -> PlanGroup)?
    /// Money that came or went outside the plan this period (gifts, unplanned spending), signed.
    var outside: [(title: String, amount: Decimal)] = []
    /// nil shows the list read-only.
    let toggle: ((Target) -> Void)?
    @State private var folded: Set<PlanGroup> = [.subscriptions]

    var body: some View {
        let done = plan.lines.filter { isDone($0) }.count
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(weekly ? String(localized: "This week, from \(plan.date.formatted(.dateTime.day().month(.wide)))")
                                : String(localized: "From your \(plan.date.formatted(.dateTime.day().month(.wide))) pay"))
                        .font(.headline)
                    if toggle != nil, !plan.lines.isEmpty {
                        Text(done == plan.lines.count ? String(localized: "All done") : String(localized: "\(done) of \(plan.lines.count) done"))
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text(plan.pay.money(currency)).font(.title3.weight(.medium)).monospacedDigit()
            }
            .padding(.bottom, 10)

            ForEach(Array(plan.extras.enumerated()), id: \.offset) { _, arrival in
                Divider().opacity(0.6)
                IncomeRow(icon: "arrow.down.circle", title: Text(arrival.kind.title),
                          detail: Text(arrival.date.formatted(.dateTime.day().month(.wide))), amount: arrival.amount, currency: currency)
            }
            if plan.carriedIn > 0 {
                Divider().opacity(0.6)
                IncomeRow(icon: "arrow.uturn.forward", title: Text("Kept from the last pay"),
                          detail: Text("For this smaller payday"), amount: plan.carriedIn, currency: currency)
            }

            // Envelopes: each group of lines with its total; tap a header to fold it.
            ForEach(PlanGroup.allCases, id: \.self) { kind in
                let lines = plan.lines.filter { groupOf($0.target) == kind }
                if !lines.isEmpty {
                    Divider().opacity(0.6)
                    groupHeader(kind, lines: lines)
                    if !folded.contains(kind) {
                        ForEach(lines, id: \.target) { line in
                            row(line).padding(.leading, 14)
                        }
                    }
                }
            }

            ForEach(Array(outside.enumerated()), id: \.offset) { _, item in
                Divider().opacity(0.6)
                HStack(spacing: 12) {
                    Image(systemName: item.amount >= 0 ? "plus.circle" : "minus.circle")
                        .foregroundStyle(item.amount >= 0 ? Palette.green : Palette.orange).frame(width: 24)
                    Text(item.title)
                    Spacer()
                    Text((item.amount >= 0 ? "+" : "−") + abs(item.amount.double).formatted(.currency(code: currency).presentation(.narrow)
                        .precision(.fractionLength(0)).locale(NumberStyle.current.locale)))
                        .monospacedDigit()
                        .foregroundStyle(item.amount >= 0 ? Palette.green : .primary)
                }
                .padding(.vertical, 10)
            }

            Divider().opacity(0.6)
            HStack(spacing: 12) {
                Image(systemName: "sun.max.fill").foregroundStyle(Palette.orange).frame(width: 24)
                Text("Yours to spend").font(.body.weight(.semibold))
                Spacer()
                Text(max(0, plan.free + outside.reduce(0) { $0 + $1.amount }).money(currency)).font(.body.weight(.semibold)).monospacedDigit()
            }
            .padding(.vertical, 12)

            if plan.shortfall > 0 {
                VStack(alignment: .leading, spacing: 8) {
                    Label("This pay doesn't cover the whole plan: \(plan.shortfall.money(currency)) short. Goals with a date catch up from the next pays, or lower some savings.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.callout)
                        .foregroundStyle(Palette.red)
                    if let onEditPlan {
                        Button("Lower Savings…", action: onEditPlan).buttonStyle(SecondaryButtonStyle())
                    }
                }
                .padding(.top, 2)
            }
        }
        .card(padding: 20)
    }

    private func groupOf(_ target: Target) -> PlanGroup {
        if let group { return group(target) }
        return switch target {
        case .bill: .bills
        case .subscription: .subscriptions
        case .debt: .debts
        case .carry: .kept
        default: .savings
        }
    }

    private func groupHeader(_ kind: PlanGroup, lines: [Plan.Line]) -> some View {
        let done = lines.filter { isDone($0) }.count
        let total = lines.reduce(Decimal(0)) { $0 + $1.amount }
        return Button {
            withAnimation(.easeOut(duration: 0.15)) {
                if folded.contains(kind) { folded.remove(kind) } else { folded.insert(kind) }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: folded.contains(kind) ? "chevron.right" : "chevron.down")
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(.tertiary).frame(width: 24)
                Image(systemName: kind.icon).foregroundStyle(Palette.orange)
                Text(kind.title).font(.subheadline.weight(.semibold))
                if toggle != nil {
                    Text("\(done)/\(lines.count)").font(.caption).foregroundStyle(done == lines.count ? Palette.green : Color.secondary)
                }
                Spacer()
                Text(total.money(currency)).font(.subheadline.weight(.semibold)).monospacedDigit()
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(kind.title))
        .accessibilityValue(Text(total.money(currency)))
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
                Image(systemName: line.target.icon)
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(line.target == .carry ? String(localized: "Keep for \(plan.next.formatted(.dateTime.day().month(.wide)))") : line.name)
                    .strikethrough(done, color: .secondary).foregroundStyle(done ? .secondary : .primary)
                if let from = source?(line.target) {
                    (Text(line.target.kind) + Text(" · ") + Text(from)).font(.caption).foregroundStyle(.tertiary)
                } else {
                    Text(line.target.kind).font(.caption).foregroundStyle(.tertiary)
                }
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
                .help(done ? "Mark as not done" : line.target.isEnvelope ? "Mark as moved to savings" : "Mark as paid")
        } else {
            content
        }
    }
}

extension Target {
    var isEnvelope: Bool { if case .envelope = self { true } else { false } }

    var kind: LocalizedStringKey {
        switch self {
        case .bill: "Bill"
        case .envelope: "Savings"
        case .debt: "Debt payment"
        case .subscription: "Subscription"
        case .carry: "Covers a smaller payday"
        case .free: "Yours to spend"
        }
    }

    var icon: String {
        switch self {
        case .bill: "doc.text"
        case .envelope: "arrow.down.to.line"
        case .debt: "creditcard"
        case .subscription: "repeat"
        case .carry: "arrow.uturn.forward"
        case .free: "sun.max"
        }
    }
}

/// Money coming in within a period, apart from the payday itself.
private struct IncomeRow: View {
    let icon: String
    let title: Text
    let detail: Text
    let amount: Decimal
    let currency: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundStyle(Palette.green).frame(width: 24)
            VStack(alignment: .leading, spacing: 1) {
                title
                detail.font(.caption).foregroundStyle(.tertiary)
            }
            Spacer()
            Text("+" + amount.money(currency)).monospacedDigit().foregroundStyle(Palette.green)
        }
        .padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }
}

/// The envelopes a paycheck is split into, in plan order.
enum PlanGroup: Int, CaseIterable, Hashable {
    case bills, subscriptions, debts, kept, toSpend, savings, projects

    var title: LocalizedStringKey {
        switch self {
        case .bills: "Bills"
        case .subscriptions: "Subscriptions"
        case .debts: "Debts"
        case .kept: "Kept for later"
        case .toSpend: "Saving to spend"
        case .savings: "Savings"
        case .projects: "Projects"
        }
    }

    var icon: String {
        switch self {
        case .bills: "doc.text"
        case .subscriptions: "repeat"
        case .debts: "creditcard"
        case .kept: "arrow.uturn.forward"
        case .toSpend: "shippingbox"
        case .savings: "tray.full"
        case .projects: "flag.checkered"
        }
    }
}
