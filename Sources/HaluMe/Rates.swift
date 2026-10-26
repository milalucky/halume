import HaluMeCore
import SwiftUI

extension BudgetStore {
    /// Fetches rates for every foreign currency in use, at most twice a day unless one is missing or `force`.
    func refreshRates(force: Bool = false) async {
        guard let budget, !isDemo else { return }
        let codes = budget.foreignCurrencies
        guard !codes.isEmpty else { return }
        let stale = budget.ratesUpdated.map { Date().timeIntervalSince($0) > 12 * 3600 } ?? true
        guard force || stale || !codes.isSubset(of: Set(budget.rates.keys)) else { return }
        guard let fetched = await RateLoader.rates(in: budget.currency) else { return }
        var rates = self.budget?.rates ?? [:]
        for code in codes { if let r = fetched[code] { rates[code] = r } }
        setRates(rates, updated: Date())
    }

    /// Saves the budget's rates; projects count their foreign costs with them too.
    func setRates(_ rates: [String: Decimal], updated: Date? = nil) {
        guard var budget else { return }
        budget.rates = rates
        if let updated { budget.ratesUpdated = updated }
        for i in budget.projects.indices { budget.projects[i].rates = rates }
        self.budget = budget
    }
}

extension RateLoader {
    /// Value of one unit of each currency in `base`, from one request.
    static func rates(in base: String) async -> [String: Decimal]? {
        struct Reply: Decodable { let rates: [String: Double] }
        guard let url = URL(string: "https://open.er-api.com/v6/latest/\(base)"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let reply = try? JSONDecoder().decode(Reply.self, from: data) else { return nil }
        // The reply says how much of each currency one unit of `base` buys; invert it.
        return reply.rates.compactMapValues { $0 > 0 ? Decimal(string: String(format: "%.6f", 1 / $0)) : nil }
    }
}

/// Settings → Exchange rates: what each foreign currency is worth, editable.
struct RatesSection: View {
    @Environment(BudgetStore.self) private var store
    @State private var updating = false

    var body: some View {
        if let budget = store.budget, !budget.foreignCurrencies.isEmpty {
            SwiftUI.Section {
                ForEach(budget.foreignCurrencies.sorted(), id: \.self) { code in
                    LabeledContent("1 \(code) =") {
                        AmountField(optional: Binding(get: { budget.rates[code] },
                                                      set: { value in var r = budget.rates; r[code] = value; store.setRates(r) }),
                                    currency: budget.currency, placeholder: "Rate")
                            .frame(width: 180)
                    }
                }
                HStack {
                    if let updated = budget.ratesUpdated {
                        Text("Updated \(updated.formatted(.relative(presentation: .named)))").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(updating ? "Updating…" : "Update from the Internet") {
                        updating = true
                        Task { await store.refreshRates(force: true); updating = false }
                    }
                    .disabled(updating)
                }
            } header: {
                Text("Exchange rates")
            } footer: {
                Text("Amounts in other currencies count in \(budget.currency) at these rates. They update by themselves; type your own if your bank's differ.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
