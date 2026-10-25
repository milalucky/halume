import HaluMeCore
import SwiftUI

/// Settings → Household: who shares this budget.
struct HouseholdSection: View {
    @Environment(BudgetStore.self) private var store
    @State private var name = ""
    @State private var monthly: Decimal = 0
    @State private var adding = false

    var body: some View {
        SwiftUI.Section {
            if let budget = store.budget {
                ForEach(budget.members) { member in
                    HStack {
                        Monogram(name: member.name, size: 26)
                        Text(member.name)
                        if member.id == store.me { Text("you").foregroundStyle(.secondary) }
                        Spacer()
                        if member.id != store.me {
                            Button("Remove", role: .destructive) { store.removeMember(member.id) }
                                .buttonStyle(.borderless)
                        }
                    }
                }
                if adding {
                    BoxTextField("Partner's name", text: $name)
                    AmountField(optional: Binding(get: { monthly == 0 ? nil : monthly }, set: { monthly = $0 ?? 0 }),
                                currency: budget.currency, placeholder: "Their salary a month (optional)")
                    HStack {
                        Spacer()
                        Button("Cancel") { adding = false }
                        Button("Add") {
                            store.addPartner(name: name.trimmingCharacters(in: .whitespaces), monthly: monthly)
                            name = ""; monthly = 0; adding = false
                        }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                        .keyboardShortcut(.defaultAction)
                    }
                } else {
                    Button("Add Partner…") { adding = true }
                }
            }
        } header: {
            Text("Household")
        } footer: {
            Text("Mark bills, savings, debts and subscriptions as shared to split them. Each of you sees your own share in your plan. Syncing between your devices comes with iCloud.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

/// "Whose is it": mine, shared (and how it's split) or the partner's. Shown once there is a partner.
struct OwnerFields: View {
    @Environment(BudgetStore.self) private var store
    @Binding var owner: Owner
    @Binding var split: Split

    var body: some View {
        if let me = store.me, !store.partners.isEmpty {
            HStack(alignment: .top, spacing: 12) {
                Field("Whose") {
                    Picker("Whose", selection: $owner) {
                        Text("Mine").tag(Owner.member(me))
                        Text("Shared").tag(Owner.shared)
                        ForEach(store.partners) { Text($0.name).tag(Owner.member($0.id)) }
                    }
                    .labelsHidden()
                }
                .frame(width: 170, alignment: .leading)
                if owner == .shared {
                    Field("Split") {
                        Picker("Split", selection: $split) {
                            Text("Equally").tag(Split.equal)
                            Text("By income").tag(Split.byIncome)
                            Text("I pay").tag(Split.payer(me))
                            ForEach(store.partners) { Text("\($0.name) pays").tag(Split.payer($0.id)) }
                        }
                        .labelsHidden()
                    }
                    .frame(width: 200, alignment: .leading)
                }
                Spacer(minLength: 0)
            }
        }
    }
}

/// For a saving of mine: hide it from the partner, optionally until a date (a gift).
struct HiddenFields: View {
    @Environment(BudgetStore.self) private var store
    @Binding var envelope: Envelope

    var body: some View {
        if let partner = store.partners.first, envelope.owner == .member(store.me ?? UUID()) {
            Toggle("Hide from \(partner.name)", isOn: $envelope.hidden)
                .help(Text("Kept only on your devices, not in the shared budget"))
            if envelope.hidden {
                HStack(spacing: 12) {
                    Toggle("Show on", isOn: Binding(get: { envelope.revealOn != nil },
                                                    set: { envelope.revealOn = $0 ? (envelope.revealOn ?? Date()) : nil }))
                    if envelope.revealOn != nil {
                        DateField(date: Binding(get: { envelope.revealOn ?? Date() }, set: { envelope.revealOn = $0 }),
                                  range: Date() ... .distantFuture)
                            .frame(width: 210)
                    }
                }
            }
        }
    }
}

/// A small mark on cards: shared, or hidden from the partner.
struct OwnerBadge: View {
    let owner: Owner
    var hidden = false
    var revealOn: Date?

    var body: some View {
        if hidden {
            Image(systemName: "eye.slash")
                .help(revealOn.map { Text("Hidden until \($0.formatted(date: .long, time: .omitted))") } ?? Text("Hidden from your partner"))
                .accessibilityLabel(Text("Hidden from your partner"))
        } else if owner == .shared {
            Image(systemName: "person.2")
                .help(Text("Shared"))
                .accessibilityLabel(Text("Shared"))
        }
    }
}
