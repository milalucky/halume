import Charts
import HaluMeCore
import SwiftUI

extension BudgetStore {
    func save(_ asset: Asset) {
        guard var budget else { return }
        if let i = budget.assets.firstIndex(where: { $0.id == asset.id }) { budget.assets[i] = asset } else { budget.assets.append(asset) }
        self.budget = budget
    }

    func deleteAsset(_ id: UUID) { budget?.assets.removeAll { $0.id == id } }
}

/// Net worth: savings and things owned less debts, month by month, and how long savings would last without pay.
struct WorthPage: View {
    @Environment(BudgetStore.self) private var store
    @State private var household = false

    var body: some View {
        Page(title: "Net worth") {
            Button { store.sheet = .asset(Asset(name: "", kind: .home, owner: .member(store.me ?? UUID()), value: 0)) } label: {
                Label("Add property", systemImage: "plus")
            }
            .buttonStyle(SecondaryButtonStyle())
            .help("A flat, a car or anything else you own that's worth counting")
        } content: {
            if let planner = store.planner, let me = store.me {
                let currency = planner.budget.currency
                let who: UUID? = household ? nil : me
                let history = planner.worthHistory(of: who, months: 12, to: Date())
                let now = history.last!, yearAgo = history.first!
                if !store.partners.isEmpty {
                    Picker("Whose", selection: $household) {
                        Text("Mine").tag(false)
                        Text("Household").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 240)
                }
                VStack(alignment: .leading, spacing: 18) {
                    StatRow {
                        Stat(label: "Net worth", value: now.total.money(currency), big: true)
                        Stat(label: "In a year", value: (now.total - yearAgo.total >= 0 ? "+" : "") + (now.total - yearAgo.total).money(currency))
                    }
                    Chart(history, id: \.date) { point in
                        AreaMark(x: .value("Month", point.date), y: .value("Net worth", point.total.double))
                            .foregroundStyle(LinearGradient(colors: [Palette.orange.opacity(0.28), Palette.orange.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.monotone)
                        LineMark(x: .value("Month", point.date), y: .value("Net worth", point.total.double))
                            .foregroundStyle(Palette.orange)
                            .interpolationMethod(.monotone)
                    }
                    .chartYAxis { AxisMarks(position: .leading) { _ in AxisGridLine().foregroundStyle(.quaternary); AxisValueLabel() } }
                    .chartXAxis { AxisMarks(values: .stride(by: .month, count: 2)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated)) } }
                    .frame(height: 180)
                    .accessibilityLabel(Text("Net worth over the last year"))
                    HStack(spacing: 0) {
                        Part(label: "Savings", amount: now.savings, currency: currency, color: Palette.green)
                        Part(label: "Property", amount: now.assets, currency: currency, color: .blue)
                        Part(label: "Debts", amount: -now.debts, currency: currency, color: Palette.red)
                    }
                }
                .card()
                RunwayCard(runway: planner.runway(of: me, on: Date()), currency: currency)
                AssetsList(currency: currency)
                Text("Property keeps today's value in the chart's past months. Debts and savings use their real history.")
                    .font(.caption).foregroundStyle(.tertiary)
            }
        }
    }

    private struct Part: View {
        let label: LocalizedStringKey
        let amount: Decimal
        let currency: String
        let color: Color

        var body: some View {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Circle().fill(color).frame(width: 7, height: 7)
                    Text(label).font(.subheadline).foregroundStyle(.secondary)
                }
                Text(amount.money(currency)).font(.body.weight(.medium)).monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// How long savings carry you without pay, against the usual 3–6 months cushion.
struct RunwayCard: View {
    @Environment(BudgetStore.self) private var store
    let runway: Runway
    let currency: String

    var body: some View {
        let months = runway.months.double
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Safety cushion").font(.headline)
                Spacer()
                Text("\(runway.days) days").font(.title3.weight(.semibold)).monospacedDigit()
                    .foregroundStyle(months >= 3 ? Palette.green : months >= 1 ? Palette.orange : Palette.red)
            }
            Text(runway.monthlyNeed > 0
                 ? String(localized: "Without any pay, your savings would last about \(months.formatted(.number.precision(.fractionLength(1)))) months at \(runway.monthlyNeed.money(currency)) a month: bills, debts, subscriptions and your usual spending.")
                 : String(localized: "Add your bills and savings to see how long your money would last without pay."))
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Bar(value: min(1, months / 6))
                .accessibilityLabel(Text("\(months.formatted(.number.precision(.fractionLength(1)))) of 6 months"))
            HStack {
                Text("0").font(.caption2)
                Spacer()
                Text("3 months").font(.caption2)
                Spacer()
                Text("6 months").font(.caption2)
            }
            .foregroundStyle(.tertiary)
            if runway.locked > 0 {
                Text("Including \(runway.locked.money(currency)) in deposits you can't take out early.").font(.caption).foregroundStyle(.secondary)
            }
            if runway.monthlyNeed > 0, months < 3 {
                let missing = runway.monthlyNeed * 3 - runway.savings
                HStack {
                    Text("A common target is 3–6 months. About \(missing.money(currency)) more makes 3.").font(.callout)
                    Spacer()
                    Button("Edit Savings…") { store.sheet = .plan }.buttonStyle(SecondaryButtonStyle())
                }
            }
        }
        .card()
    }
}

private struct AssetsList: View {
    @Environment(BudgetStore.self) private var store
    let currency: String

    var body: some View {
        let assets = store.budget?.assets ?? []
        VStack(alignment: .leading, spacing: 10) {
            Text("Property").font(.headline)
            if assets.isEmpty {
                Text("A flat, a car, anything you could sell. Only for net worth: it never touches your plan.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            ForEach(assets) { asset in
                Button { store.sheet = .asset(asset) } label: {
                    HStack(spacing: 12) {
                        Image(systemName: asset.kind.icon).foregroundStyle(.blue).frame(width: 22)
                        Text(asset.name)
                        OwnerBadge(owner: asset.owner).font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text(asset.value.money(asset.currency ?? currency)).monospacedDigit()
                    }
                    .padding(.vertical, 4)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Click to change the value")
            }
        }
        .card()
    }
}

struct AssetEditor: View {
    @Environment(BudgetStore.self) private var store
    @State var asset: Asset

    var body: some View {
        let budget = store.budget!
        let isNew = !budget.assets.contains { $0.id == asset.id }
        SheetFrame(title: LocalizedStringKey(isNew ? "New property" : "Edit property"),
                   subtitle: "What it would sell for today, roughly. Update it now and then.",
                   action: LocalizedStringKey(isNew ? "Add" : "Save"),
                   canSave: !asset.name.trimmingCharacters(in: .whitespaces).isEmpty && asset.value > 0,
                   save: { store.save(asset) }, delete: isNew ? nil : { store.deleteAsset(asset.id) }) {
            Field("What kind") {
                Picker("Kind", selection: $asset.kind) {
                    ForEach(AssetKind.allCases, id: \.self) { Label($0.title, systemImage: $0.icon).tag($0) }
                }
                .labelsHidden()
            }
            Field("Name") { BoxTextField("e.g. Flat in Kazan", text: $asset.name) }
            HStack(alignment: .top, spacing: 12) {
                Field("Worth") { AmountField(amount: $asset.value, code: $asset.currency, budgetCurrency: budget.currency) }
                if let me = store.me, !store.partners.isEmpty {
                    Field("Whose") {
                        Picker("Whose", selection: $asset.owner) {
                            Text("Mine").tag(Owner.member(me))
                            Text("Shared").tag(Owner.shared)
                            ForEach(store.partners) { Text($0.name).tag(Owner.member($0.id)) }
                        }
                        .labelsHidden()
                    }
                }
            }
        }
    }
}

extension AssetKind {
    var title: LocalizedStringKey {
        switch self {
        case .home: "Home"
        case .car: "Car"
        case .valuables: "Valuables"
        case .other: "Other"
        }
    }

    var icon: String {
        switch self {
        case .home: "house"
        case .car: "car"
        case .valuables: "diamond"
        case .other: "shippingbox"
        }
    }
}
