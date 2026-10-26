import HaluMeCore
import SwiftUI

/// The app after onboarding: a sidebar of sections and the selected page.
struct MainView: View {
    @Environment(BudgetStore.self) private var store

    var body: some View {
        @Bindable var store = store
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 2) {
                Brand().padding(.horizontal, 10).padding(.bottom, 14)
                ForEach(Section.allCases) { section in
                    SidebarItem(section: section, selected: store.section == section) { store.section = section }
                }
                Spacer()
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 260)
        } detail: {
            Group {
                switch store.section {
                case .today: TodayPage()
                case .savings: SavingsPage()
                case .debts: DebtsPage()
                case .subscriptions: SubscriptionsPage()
                case .projects: ProjectsPage()
                case .wishlist: WishlistPage()
                case .stats: StatsPage()
                }
            }
            .backdrop()
            .id(store.look)
        }
        .sheet(item: $store.sheet) { sheet in
            Group {
                switch sheet {
                case .pay: PaySheet()
                case .balance: BalanceSheet()
                case .plan: PlanEditor()
                case .debt(let debt): DebtEditor(debt: debt)
                case .payoff(let id): PayoffSheet(debtID: id)
                case .subscription(let sub): SubscriptionEditor(subscription: sub)
                case .withdraw(let id): WithdrawSheet(envelopeID: id)
                case .timeOff: TimeOffSheet()
                case .wish(let wish): WishEditor(wish: wish)
                case .newProject: NewProjectSheet()
                case .task(let project, let stage, let task): TaskEditor(projectID: project, stageID: stage, task: task)
                case .rates(let id): RatesSheet(projectID: id)
                }
            }
            .environment(store)
            .tint(Palette.orange)
        }
        .confirmationDialog("Start over?", isPresented: $store.confirmingStartOver) {
            Button("Delete Budget and Start Over", role: .destructive) { store.startOver() }
        } message: {
            Text("Your plan, savings and history will be deleted. This can't be undone.")
        }
    }
}

extension Section {
    var title: LocalizedStringKey {
        switch self {
        case .today: "Today"
        case .savings: "Savings"
        case .debts: "Debts"
        case .subscriptions: "Subscriptions"
        case .projects: "Projects"
        case .wishlist: "Wishlist"
        case .stats: "Stats"
        }
    }

    var icon: String {
        switch self {
        case .today: "sun.max"
        case .savings: "tray.full"
        case .debts: "creditcard"
        case .subscriptions: "repeat"
        case .projects: "flag.checkered"
        case .wishlist: "gift"
        case .stats: "chart.bar.xaxis"
        }
    }
}

/// A sidebar row with the brand-coloured selection.
private struct SidebarItem: View {
    let section: Section
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Label(section.title, systemImage: section.icon)
                .font(.body.weight(selected ? .semibold : .regular))
                .foregroundStyle(selected ? AnyShapeStyle(Palette.orange) : AnyShapeStyle(.primary))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.vertical, 7)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(selected ? AnyShapeStyle(Palette.orange.opacity(0.14)) : AnyShapeStyle(.primary.opacity(hovering ? 0.06 : 0))))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A scrolling page with a title row and optional actions.
struct Page<Actions: View, Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let actions: Actions
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(alignment: .center) {
                    Text(title).font(.system(size: 28, weight: .semibold)).tracking(-0.3)
                    Spacer()
                    HStack(spacing: 8) { actions }
                }
                content
            }
            .frame(maxWidth: 680, alignment: .leading)
            .padding(.horizontal, 40)
            .padding(.top, 36)
            .padding(.bottom, 40)
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: Today

struct TodayPage: View {
    @Environment(BudgetStore.self) private var store

    var body: some View {
        Page(title: LocalizedStringKey(greeting)) {
            EmptyView()
        } content: {
            if let budget = store.budget, let me = store.me, let planner = store.planner {
                let today = Date()
                // The day's actions, named, not just icons.
                FlowLayout(spacing: 8) {
                    Button { store.sheet = .timeOff } label: { Label("Vacation, sick leave", systemImage: "calendar.badge.clock") }
                    Button { store.sheet = .balance } label: { Label("Balance on the card", systemImage: "creditcard") }
                    Button { store.sheet = .plan } label: { Label("Edit plan", systemImage: "slider.horizontal.3") }
                }
                .buttonStyle(SecondaryButtonStyle())
                if let allowance = planner.allowance(for: me, on: today), let start = planner.current(on: today, of: me) {
                    let record = planner.payday(of: me, on: start)
                    Hero(allowance: allowance, start: start, currency: budget.currency,
                         note: balanceNote(budget: budget, me: me, start: start), weekly: budget.plansByWeek)
                    if record?.actual == nil {
                        PayBanner(expected: planner.expected(of: me, on: start), date: start, currency: budget.currency, weekly: budget.plansByWeek) {
                            store.sheet = .pay
                        }
                    }
                    PlanList(plan: planner.plan(for: me, on: start), record: record, currency: budget.currency, weekly: budget.plansByWeek,
                             onEditPlan: { store.sheet = .plan }) {
                        store.toggle($0, payday: start)
                    }
                    ComingUp(planner: planner, today: today)
                    TaxAhead(planner: planner, me: me, today: today)
                } else {
                    Text("Your first payday hasn't come yet.").foregroundStyle(.secondary).card()
                }
            }
        }
    }

    /// "Good evening, Milana".
    private var greeting: String {
        let name = store.budget?.members.first { $0.id == store.me }?.name ?? ""
        let hour = Calendar.current.component(.hour, from: Date())
        let named = !name.isEmpty && name != String(localized: "Me")
        switch hour {
        case 5..<12: return named ? String(localized: "Good morning, \(name)") : String(localized: "Good morning")
        case 12..<18: return named ? String(localized: "Good afternoon, \(name)") : String(localized: "Good afternoon")
        default: return named ? String(localized: "Good evening, \(name)") : String(localized: "Good evening")
        }
    }

    private func balanceNote(budget: Budget, me: UUID, start: Date) -> String? {
        guard let check = budget.checks.filter({ $0.member == me && $0.date >= start }).max(by: { $0.date < $1.date })
        else { return nil }
        return String(localized: "From your balance of \(check.amount.money(budget.currency)), \(check.date.formatted(.relative(presentation: .named)))")
    }
}

/// Charges and trial ends in the next week.
private struct ComingUp: View {
    let planner: Planner
    let today: Date

    var body: some View {
        let budget = planner.budget
        let week = Calendar.current.date(byAdding: .day, value: 7, to: today)!
        let items = budget.subscriptions.compactMap { sub -> (Subscription, Date)? in
            guard let next = planner.nextCharge(of: sub, after: today), next <= week else { return nil }
            return (sub, next)
        }.sorted { $0.1 < $1.1 }
        let interest = budget.envelopes.compactMap { envelope -> (Envelope, Date, Decimal)? in
            guard let next = planner.nextInterest(of: envelope, from: today), next.date <= week, next.amount > 0 else { return nil }
            return (envelope, next.date, next.amount)
        }
        let me = budget.members.first?.id ?? UUID()
        let arrivals = planner.extras(of: me, from: today, to: week)
        let steps = planner.projectTasks(from: today, to: week)
        if !items.isEmpty || !interest.isEmpty || !arrivals.isEmpty || !steps.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Coming up this week").font(.headline)
                VStack(spacing: 0) {
                    ForEach(steps, id: \.task.id) { project, task in
                        HStack(spacing: 12) {
                            Image(systemName: "flag.checkered")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Palette.orange)
                                .frame(width: 32, height: 32)
                                .background(Circle().fill(Palette.orange.opacity(0.14)))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(task.title)
                                Text("\(project.name) · \(task.due!.relativeDay)").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            if task.cost > 0 { Text(project.cost(of: task).money(budget.currency)).monospacedDigit() }
                        }
                        .padding(.vertical, 8)
                    }
                    ForEach(Array(arrivals.enumerated()), id: \.offset) { _, arrival in
                        HStack(spacing: 12) {
                            Image(systemName: "arrow.down")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Palette.green)
                                .frame(width: 32, height: 32)
                                .background(Circle().fill(Palette.green.opacity(0.15)))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(arrival.kind.title)
                                Text(arrival.date.relativeDay).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("+" + arrival.amount.money(budget.currency)).monospacedDigit().foregroundStyle(Palette.green)
                        }
                        .padding(.vertical, 8)
                    }
                    ForEach(interest, id: \.0.id) { envelope, date, amount in
                        HStack(spacing: 12) {
                            Image(systemName: "percent")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(Palette.green)
                                .frame(width: 32, height: 32)
                                .background(Circle().fill(Palette.green.opacity(0.15)))
                            VStack(alignment: .leading, spacing: 1) {
                                Text("Interest from \(envelope.name)")
                                Text(envelope.interestToCard ? String(localized: "To your card \(date.relativeDay)") : String(localized: "Into the account \(date.relativeDay)"))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("+" + amount.money(budget.currency)).monospacedDigit().foregroundStyle(Palette.green)
                        }
                        .padding(.vertical, 8)
                    }
                    ForEach(items, id: \.0.id) { sub, date in
                        HStack(spacing: 12) {
                            Monogram(name: sub.name)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(sub.name)
                                Text(sub.trialEnds.map { Calendar.current.isDate($0, inSameDayAs: date) } == true
                                     ? String(localized: "Trial ends \(date.relativeDay)") : String(localized: "Charge \(date.relativeDay)"))
                                    .font(.caption)
                                    .foregroundStyle(sub.trialEnds != nil ? AnyShapeStyle(Palette.orange) : AnyShapeStyle(.secondary))
                            }
                            Spacer()
                            Text(sub.amount.money(budget.currency)).monospacedDigit()
                        }
                        .padding(.vertical, 8)
                    }
                }
                .card(padding: 16)
            }
        }
    }
}

struct EmptyState: View {
    let icon: String
    let title: LocalizedStringKey
    let text: LocalizedStringKey

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 34, weight: .light)).foregroundStyle(Palette.orange)
            Text(title).font(.title3.weight(.semibold))
            Text(text).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 360)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .card()
    }
}

/// A round letter badge instead of a brand logo.
struct Monogram: View {
    let name: String
    var size: CGFloat = 32

    var body: some View {
        let letter = name.trimmingCharacters(in: .whitespaces).first.map { String($0).uppercased() } ?? "•"
        let hue = Double(name.unicodeScalars.reduce(0) { $0 &+ Int($1.value) * 37 } % 360) / 360
        Text(letter)
            .font(.system(size: size * 0.45, weight: .semibold, design: .rounded))
            .foregroundStyle(Color(hue: hue, saturation: 0.55, brightness: 0.95))
            .frame(width: size, height: size)
            .background(Circle().fill(Color(hue: hue, saturation: 0.5, brightness: 0.7).opacity(0.22)))
            .accessibilityHidden(true)
    }
}

extension Date {
    /// "today", "tomorrow", "in 3 days", "on Nov 20".
    var relativeDay: String {
        let calendar = Calendar.current
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: Date()), to: calendar.startOfDay(for: self)).day ?? 0
        switch days {
        case 0: return String(localized: "today")
        case 1: return String(localized: "tomorrow")
        case 2...6: return String(localized: "in \(days) days")
        default: return String(localized: "on \(formatted(.dateTime.day().month(.abbreviated)))")
        }
    }
}

/// Take-home pay changes ahead because of tax: a higher bracket, contributions done for the year, a new year.
private struct TaxAhead: View {
    let planner: Planner
    let me: UUID
    let today: Date

    var body: some View {
        let changes = planner.taxChanges(of: me, from: today, to: Calendar.current.date(byAdding: .year, value: 1, to: today)!).prefix(2)
        if !changes.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Ahead").font(.headline)
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(changes), id: \.date) { change in
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(headline(change)).font(.body.weight(.medium))
                                Text(reason(change)).font(.callout).foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: change.delta > 0 ? "arrow.up.right" : "arrow.down.right")
                                .foregroundStyle(change.delta > 0 ? Palette.green : Palette.orange)
                        }
                    }
                }
                .card()
            }
        }
    }

    private func headline(_ change: TaxChange) -> String {
        let currency = planner.budget.currency
        let date = change.date.formatted(.dateTime.day().month(.wide))
        let amount = abs(change.delta.double).formatted(.currency(code: currency).presentation(.narrow).precision(.fractionLength(0)))
        return change.delta > 0 ? String(localized: "From \(date): about \(amount) more after tax")
                                : String(localized: "From \(date): about \(amount) less after tax")
    }

    private func reason(_ change: TaxChange) -> String {
        let up = change.delta > 0
        switch change.system {
        case .russia:
            let rate = (change.rate * 100).formatted()
            return up ? String(localized: "A new tax year: back to 13%.")
                      : String(localized: "This year's income passes a threshold, so part of it is taxed at \(rate)%.")
        case .canada:
            return up ? String(localized: "CPP and EI for this year are paid in full.")
                      : String(localized: "A new year: CPP and EI start again.")
        case .unitedStates:
            return up ? String(localized: "Social Security for this year is paid in full.")
                      : String(localized: "A new year: Social Security starts again.")
        case .flat:
            return ""
        }
    }
}
