import HaluMeCore
import SwiftUI

struct SubscriptionsPage: View {
    @Environment(BudgetStore.self) private var store

    var body: some View {
        Page(title: "Subscriptions") {
            Button { store.sheet = .subscription(newSubscription()) } label: { Label("Add", systemImage: "plus") }
                .buttonStyle(SecondaryButtonStyle())
        } content: {
            if let planner = store.planner {
                let budget = planner.budget
                let today = Date()
                let active = budget.subscriptions.filter(\.isActive)
                    .sorted { (planner.nextCharge(of: $0, after: today) ?? .distantFuture) < (planner.nextCharge(of: $1, after: today) ?? .distantFuture) }
                let cancelled = budget.subscriptions.filter { !$0.isActive }
                if budget.subscriptions.isEmpty {
                    EmptyState(icon: "repeat", title: "Track every subscription",
                               text: "Streaming, music, apps, cloud, bank packages: small charges add up. Add them once and see what they cost in a year.")
                } else {
                    Totals(planner: planner, active: active)
                    if !active.isEmpty {
                        VStack(spacing: 0) {
                            ForEach(Array(active.enumerated()), id: \.element.id) { i, sub in
                                if i > 0 { Divider().opacity(0.6) }
                                SubscriptionRow(sub: sub, planner: planner, today: today)
                            }
                        }
                        .card(padding: 16)
                    }
                    if !cancelled.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Cancelled").font(.headline)
                                Spacer()
                                Text("Saving \(cancelled.reduce(Decimal(0)) { $0 + Planner.monthlyCost(of: $1) }.money(budget.currency)) a month")
                                    .font(.callout).foregroundStyle(Palette.green)
                            }
                            VStack(spacing: 0) {
                                ForEach(cancelled) { SubscriptionRow(sub: $0, planner: planner, today: today) }
                            }
                            .card(padding: 16)
                        }
                    }
                }
            }
        }
    }

    private func newSubscription() -> Subscription {
        Subscription(owner: .member(store.me ?? UUID()), name: "", amount: 0, anchor: Date())
    }
}

private struct Totals: View {
    let planner: Planner
    let active: [Subscription]

    var body: some View {
        let budget = planner.budget
        let monthly = active.reduce(Decimal(0)) { $0 + Planner.monthlyCost(of: $1) }
        let yearly = monthly * 12
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 32) {
                Stat(label: "A month", value: monthly.rounded().money(budget.currency), big: true)
                Stat(label: "A year", value: yearly.rounded().money(budget.currency))
                Stat(label: "Active", value: "\(active.count)")
            }
            if let me = budget.members.first?.id, let perDay = planner.allowance(for: me, on: Date())?.perDay, perDay > 0, yearly > 0 {
                let days = Int((yearly / perDay).rounded(.up).double)
                Label("A year of subscriptions costs about \(days) days of your spending money.", systemImage: "lightbulb")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct SubscriptionRow: View {
    @Environment(BudgetStore.self) private var store
    let sub: Subscription
    let planner: Planner
    let today: Date
    @State private var hovering = false

    var body: some View {
        let currency = planner.budget.currency
        let next = planner.nextCharge(of: sub, after: today)
        let trialSoon = sub.isActive && sub.trialEnds.map { $0 >= today } == true
        Button { store.sheet = .subscription(sub) } label: {
            HStack(spacing: 12) {
                Monogram(name: sub.name, size: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(sub.name).foregroundStyle(sub.isActive ? .primary : .secondary)
                    Group {
                        if !sub.isActive {
                            Text("Cancelled")
                        } else if trialSoon, let ends = sub.trialEnds {
                            Text("Free trial ends \(ends.relativeDay)").foregroundStyle(Palette.orange)
                        } else if let next {
                            if sub.category.isEmpty {
                                Text("Next \(next.relativeDay)")
                            } else {
                                Text(LocalizedStringKey(sub.category)) + Text(" · ") + Text("next \(next.relativeDay)")
                            }
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text(sub.amount.money(currency)).monospacedDigit().foregroundStyle(sub.isActive ? .primary : .secondary)
                    Text(sub.cycle.per).font(.caption).foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 6)
            .background(RoundedRectangle(cornerRadius: 10).fill(.primary.opacity(hovering ? 0.05 : 0)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Edit…") { store.sheet = .subscription(sub) }
            Button(LocalizedStringKey(sub.isActive ? "Mark as Cancelled" : "Resume")) {
                var changed = sub
                changed.isActive.toggle()
                store.save(changed)
            }
            Button("Delete", role: .destructive) { store.deleteSubscription(sub.id) }
        }
    }
}

extension Cycle {
    var title: LocalizedStringKey {
        switch self {
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        case .quarterly: "Every 3 months"
        case .yearly: "Yearly"
        }
    }

    var per: LocalizedStringKey {
        switch self {
        case .weekly: "a week"
        case .monthly: "a month"
        case .quarterly: "in 3 months"
        case .yearly: "a year"
        }
    }
}

/// Categories are stored in English and shown translated.
let subscriptionCategories = ["Video", "Music", "Software", "Cloud", "Games", "Bank", "Shopping", "Health", "Other"]

// MARK: Editor

struct SubscriptionEditor: View {
    @Environment(BudgetStore.self) private var store
    @State var subscription: Subscription
    @State private var hasTrial = false

    private let suggestions = ["Yandex Plus", "Kinopoisk", "Spotify", "YouTube Premium", "Netflix", "iCloud+",
                               "Apple Music", "ChatGPT Plus", "Telegram Premium", "VK Music"]

    var body: some View {
        let currency = store.budget?.currency ?? "USD"
        let isNew = !(store.budget?.subscriptions.contains { $0.id == subscription.id } ?? false)
        SheetFrame(title: LocalizedStringKey(isNew ? "New subscription" : "Edit subscription"),
                   subtitle: "Charges go into the paycheck plan, and the app reminds you before each one.",
                   action: LocalizedStringKey(isNew ? "Add" : "Save"),
                   canSave: !subscription.name.trimmingCharacters(in: .whitespaces).isEmpty && subscription.amount > 0,
                   save: save) {
            Field("Name") { TextField("e.g. Music", text: $subscription.name) }
            if isNew, subscription.name.isEmpty {
                FlowLayout(spacing: 6) {
                    ForEach(suggestions, id: \.self) { name in
                        Button(name) { subscription.name = name }
                            .buttonStyle(.bordered)
                            .buttonBorderShape(.capsule)
                            .controlSize(.small)
                    }
                }
            }
            HStack(alignment: .top, spacing: 12) {
                Field("Price") { AmountField(amount: $subscription.amount, currency: currency) }
                Field("Billed") {
                    Picker("Billed", selection: $subscription.cycle) {
                        ForEach(Cycle.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                }
            }
            HStack(alignment: .top, spacing: 12) {
                Field("Next charge") {
                    DatePicker("Next charge", selection: $subscription.anchor, displayedComponents: .date).labelsHidden()
                }
                Field("Category") {
                    Picker("Category", selection: $subscription.category) {
                        Text("None").tag("")
                        ForEach(subscriptionCategories, id: \.self) { Text(LocalizedStringKey($0)).tag($0) }
                    }
                    .labelsHidden()
                }
            }
            Toggle("Free trial", isOn: $hasTrial)
            if hasTrial {
                Field("Trial ends", hint: "The first charge comes this day. You'll get a reminder two days before.") {
                    DatePicker("Trial ends", selection: Binding(get: { subscription.trialEnds ?? Date() },
                                                                set: { subscription.trialEnds = $0 }),
                               displayedComponents: .date)
                        .labelsHidden()
                }
            }
            if !isNew {
                HStack(spacing: 16) {
                    Button(LocalizedStringKey(subscription.isActive ? "Mark as Cancelled" : "Resume")) {
                        subscription.isActive.toggle()
                        save()
                        store.sheet = nil
                    }
                    Button("Delete", role: .destructive) {
                        store.deleteSubscription(subscription.id)
                        store.sheet = nil
                    }
                    .foregroundStyle(Palette.red)
                }
                .buttonStyle(.borderless)
            }
        }
        .onAppear { hasTrial = subscription.trialEnds != nil }
    }

    private func save() {
        var sub = subscription
        if !hasTrial { sub.trialEnds = nil } else if sub.trialEnds == nil { sub.trialEnds = Date() }
        store.save(sub)
    }
}
