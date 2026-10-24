import HaluMeCore
import SwiftUI

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
                Text(note ?? String(localized: "Day \(passed) of \(total)"))
                    .font(.callout).foregroundStyle(.secondary)
            }
            .frame(maxWidth: 360, alignment: .leading)
        }
        .accessibilityElement(children: .combine)
    }

    private var payday: String {
        let date = allowance.next.formatted(.dateTime.day().month(.wide))
        return allowance.daysLeft == 1 ? String(localized: "Payday tomorrow, \(date)") : String(localized: "Payday in \(allowance.daysLeft) days, \(date)")
    }
}

struct PayBanner: View {
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
                        Text(done == plan.lines.count ? String(localized: "All done") : String(localized: "\(done) of \(plan.lines.count) done"))
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
                Image(systemName: line.target.icon)
                    .foregroundStyle(.secondary)
                    .frame(width: 24)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(line.name).strikethrough(done, color: .secondary).foregroundStyle(done ? .secondary : .primary)
                Text(line.target.kind).font(.caption).foregroundStyle(.tertiary)
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
        case .free: "Yours to spend"
        }
    }

    var icon: String {
        switch self {
        case .bill: "doc.text"
        case .envelope: "arrow.down.to.line"
        case .debt: "creditcard"
        case .subscription: "repeat"
        case .free: "sun.max"
        }
    }
}
