import HaluMeCore
import SwiftUI

/// Everything outside the plan, newest first: money that came in, unplanned spending, money taken out of savings, moves.
struct HistoryPage: View {
    @Environment(BudgetStore.self) private var store

    private struct Entry: Identifiable {
        enum Kind { case inflow(Inflow), spending(Spending), project, transfer(Transfer) }
        let id: UUID
        let date: Date
        let title: String
        let detail: String
        /// Signed, in the budget's currency; nil for a move between savings.
        let amount: Decimal?
        let icon: String
        let kind: Kind
    }

    var body: some View {
        Page(title: "History") {
            Menu {
                Button("Money Came In…") { store.sheet = store.newInflow }
                Button("Unplanned Expense…") { store.sheet = .outflow(Spending()) }
                Button("Move Between Savings…") { store.sheet = .transfer(TransferSheet.new()) }
            } label: {
                Label("Add", systemImage: "plus")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Add money that came in, an unplanned expense or a move between savings")
        } content: {
            if let budget = store.budget {
                let entries = entries(of: budget)
                if entries.isEmpty {
                    EmptyState(icon: "clock.arrow.circlepath", title: "Nothing outside the plan yet",
                               text: "Gifts, bonuses, earnings, unplanned expenses and money taken out of savings show up here. Click one to change or delete it.")
                } else {
                    let months = Dictionary(grouping: entries) { Calendar.current.dateInterval(of: .month, for: $0.date)!.start }
                    ForEach(months.keys.sorted(by: >), id: \.self) { month in
                        let rows = months[month]!.sorted { $0.date > $1.date }
                        let net = rows.compactMap(\.amount).reduce(0, +)
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(month.formatted(.dateTime.month(.wide).year())).font(.headline)
                                Spacer()
                                Text(net >= 0 ? "+\(net.money(budget.currency))" : net.money(budget.currency))
                                    .font(.callout.weight(.medium)).monospacedDigit()
                                    .foregroundStyle(net >= 0 ? Palette.green : .secondary)
                            }
                            .padding(.bottom, 6)
                            ForEach(rows) { row(for: $0, currency: budget.currency) }
                        }
                        .card()
                    }
                }
            }
        }
    }

    private func row(for entry: Entry, currency: String) -> some View {
        Button { open(entry) } label: {
            HStack(spacing: 12) {
                Image(systemName: entry.icon)
                    .foregroundStyle(entry.amount.map { $0 >= 0 ? Palette.green : Palette.orange } ?? .secondary)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.title).lineLimit(1)
                    Text("\(entry.date.formatted(.dateTime.day().month(.abbreviated))) · \(entry.detail)")
                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                if let amount = entry.amount {
                    Text(amount >= 0 ? "+\(amount.money(currency))" : amount.money(currency))
                        .monospacedDigit()
                        .foregroundStyle(amount >= 0 ? Palette.green : .primary)
                }
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(helpText(entry))
        .contextMenu {
            if case .project = entry.kind {
                Button("Open Projects") { store.section = .projects }
            } else {
                Button("Edit…") { open(entry) }
                Button("Delete", role: .destructive) { delete(entry) }
            }
        }
    }

    private func helpText(_ entry: Entry) -> LocalizedStringKey {
        if case .project = entry.kind { "Paid for a project step. Change it in the project." } else { "Click to change or delete" }
    }

    private func open(_ entry: Entry) {
        switch entry.kind {
        case .inflow(let inflow): store.sheet = .inflow(inflow)
        case .spending(let spending): store.sheet = .outflow(spending)
        case .transfer(let transfer): store.sheet = .transfer(transfer)
        case .project: store.section = .projects
        }
    }

    private func delete(_ entry: Entry) {
        switch entry.kind {
        case .inflow(let inflow): store.deleteInflow(inflow.id)
        case .spending(let spending): store.deleteSpending(spending.id)
        case .transfer(let transfer): store.deleteTransfer(transfer.id)
        case .project: break
        }
    }

    private func entries(of budget: Budget) -> [Entry] {
        let name = { (id: UUID) in budget.envelopes.first { $0.id == id }?.name ?? String(localized: "Deleted saving") }
        var out: [Entry] = []
        for inflow in budget.inflows {
            let saved = inflow.allocations.reduce(Decimal(0)) { $0 + $1.amount }
            let income = inflow.income.flatMap { id in budget.incomes.first { $0.id == id } }
            let detail = income != nil ? String(localized: "Earnings, for next month")
                : saved > 0 ? String(localized: "\(saved.money(budget.currency)) into savings") : String(localized: "To spending money")
            out.append(Entry(id: inflow.id, date: inflow.date, title: inflow.note, detail: detail,
                             amount: budget.convert(inflow.amount, from: inflow.currency),
                             icon: income != nil ? "tray.and.arrow.down" : "plus.circle", kind: .inflow(inflow)))
        }
        for outflow in budget.outflows {
            out.append(Entry(id: outflow.id, date: outflow.date, title: outflow.note, detail: String(localized: "From spending money"),
                             amount: -budget.convert(outflow.amount, from: outflow.currency), icon: "minus.circle", kind: .spending(Spending(outflow))))
        }
        for w in budget.withdrawals {
            let project = store.isProjectPayment(w.id)
            out.append(Entry(id: w.id, date: w.date, title: w.note.isEmpty ? String(localized: "Taken out") : w.note,
                             detail: project ? String(localized: "Project step, from \(name(w.envelope))") : String(localized: "From \(name(w.envelope))"),
                             amount: -w.amount, icon: project ? "flag.checkered" : "arrow.uturn.backward.circle",
                             kind: project ? .project : .spending(Spending(w))))
        }
        for t in budget.transfers {
            out.append(Entry(id: t.id, date: t.date, title: "\(name(t.from)) → \(name(t.to))",
                             detail: String(localized: "Moved \(t.amount.money(budget.currency))"), amount: nil,
                             icon: "arrow.left.arrow.right.circle", kind: .transfer(t)))
        }
        return out
    }
}
