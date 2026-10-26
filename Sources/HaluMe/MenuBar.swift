import AppKit
import HaluMeCore
import SwiftUI

/// The menu bar: today's amount at a glance, the next payday and what's due before it.
struct MenuBarGlance: View {
    @Environment(BudgetStore.self) private var store
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if let planner = store.planner, let me = store.me {
            let currency = planner.budget.currency
            let today = Date()
            if let allowance = planner.allowance(for: me, on: today) {
                Text("\(allowance.perDay.money(currency)) a day")
                Text(String(localized: "Payday in \(allowance.daysLeft) days, \(allowance.next.formatted(.dateTime.day().month(.wide)))"))
                let due = dueSoon(planner, me, before: allowance.next)
                if !due.isEmpty {
                    Divider()
                    ForEach(due, id: \.0) { name, date, amount in
                        Text("\(date.formatted(.dateTime.day().month(.abbreviated))) · \(name) · \(amount.money(currency))")
                    }
                }
                Divider()
            }
            Button("Money Came In…") { open(store.newInflow) }
            Button("Unplanned Expense…") { open(.outflow(Spending())) }
        }
        Button("Open HaluMe") { open(nil) }
        Divider()
        Button("Quit HaluMe") { NSApp.terminate(nil) }
    }

    private func open(_ sheet: Sheet?) {
        openWindow(id: "main")
        NSApp.activate(ignoringOtherApps: true)
        if let sheet { store.sheet = sheet }
    }

    /// Bills, debt payments and charges of the current plan not yet marked done.
    private func dueSoon(_ planner: Planner, _ me: UUID, before next: Date) -> [(String, Date, Decimal)] {
        guard let start = planner.current(on: Date(), of: me) else { return [] }
        let done = Set(planner.payday(of: me, on: start)?.allocations.filter(\.isDone).map(\.target) ?? [])
        return planner.plan(for: me, on: start).lines.compactMap { line in
            switch line.target {
            case .bill, .debt, .subscription: done.contains(line.target) ? nil : (line.name, start, line.amount)
            default: nil
            }
        }
        .prefix(6).map { $0 }
    }
}

/// The menu bar title: the amount a day, or the Halu mark before there's a plan.
struct MenuBarLabel: View {
    @Environment(BudgetStore.self) private var store

    var body: some View {
        if let planner = store.planner, let me = store.me, let allowance = planner.allowance(for: me, on: Date()) {
            Text(allowance.perDay.money(planner.budget.currency))
        } else {
            Image(systemName: "sun.max")
        }
    }
}
