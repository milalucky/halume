import HaluMeCore
import SwiftUI

/// Who sends whom what this month for shared costs paid from one person's (or a shared) account.
struct OwedCard: View {
    @Environment(BudgetStore.self) private var store
    let planner: Planner
    let today: Date

    var body: some View {
        let owed = planner.owed(inMonthOf: today)
        let currency = planner.budget.currency
        if !owed.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("Shared costs in \(today.formatted(.dateTime.month(.wide)))", systemImage: "arrow.left.arrow.right")
                        .font(.headline)
                    Spacer()
                }
                ForEach(owed, id: \.self) { o in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(sentence(o)).fixedSize(horizontal: false, vertical: true)
                            Spacer()
                            if o.left > 0 {
                                Button("Mark as Sent") {
                                    store.budget?.settlements.append(Settlement(from: o.from, to: o.to, amount: o.left))
                                }
                                .buttonStyle(SecondaryButtonStyle())
                                .help("Records that the money was sent this month")
                            } else {
                                Label("Sent", systemImage: "checkmark.circle.fill").foregroundStyle(Palette.green)
                            }
                        }
                        Text(o.items.map { "\($0.name) \($0.amount.money(currency))" }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary)
                        if o.settled > 0, o.left > 0 {
                            Text("Already sent \(o.settled.money(currency)), \(o.left.money(currency)) to go.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                if let undo = lastSettlement() {
                    Button("Undo Last “Sent”") { store.budget?.settlements.removeAll { $0.id == undo } }
                        .buttonStyle(.borderless).font(.caption)
                }
            }
            .card()
        }
    }

    private func sentence(_ o: Owed) -> String {
        let currency = planner.budget.currency
        let from = name(o.from), amount = o.amount.money(currency)
        guard let to = o.to else { return o.from == store.me
            ? String(localized: "You put \(amount) into the shared account")
            : String(localized: "\(from) puts \(amount) into the shared account") }
        if o.from == store.me { return String(localized: "You send \(name(to)) \(amount)") }
        if to == store.me { return String(localized: "\(from) sends you \(amount)") }
        return String(localized: "\(from) sends \(name(to)) \(amount)")
    }

    private func name(_ id: UUID) -> String { planner.budget.members.first { $0.id == id }?.name ?? "" }

    private func lastSettlement() -> UUID? {
        let month = Calendar.current.dateInterval(of: .month, for: today)!
        return planner.budget.settlements.filter { month.contains($0.date) }.max { $0.date < $1.date }?.id
    }
}
