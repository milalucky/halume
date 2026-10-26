import HaluMeCore
import SwiftUI

/// Settings → Household: who shares this budget, and how a partner's salary is used.
struct HouseholdSection: View {
    @Environment(BudgetStore.self) private var store
    @State private var editing: PartnerEdit?

    struct PartnerEdit: Identifiable {
        let id = UUID()
        var member: UUID?
    }

    var body: some View {
        SwiftUI.Section {
            if let budget = store.budget {
                ForEach(budget.members) { member in
                    HStack(alignment: .top) {
                        Monogram(name: member.name, size: 26)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(member.name)
                                if member.id == store.me { Text("you").foregroundStyle(.secondary) }
                            }
                            Text(summary(of: member.id, in: budget)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if member.id != store.me {
                            Button("Edit…") { editing = PartnerEdit(member: member.id) }.buttonStyle(.borderless)
                            Button("Remove", role: .destructive) { store.removeMember(member.id) }.buttonStyle(.borderless)
                        }
                    }
                }
                Button("Add Partner…") { editing = PartnerEdit(member: nil) }
            }
        } header: {
            Text("Household")
        } footer: {
            Text("A partner's salary is only used to split shared costs “by income”. Shared bills, savings, debts and subscriptions are split equally, by income, paid by one of you or in turns — set in each of them, together with the account it's paid from. Each of you sees your own share in your plan; syncing between your devices comes with iCloud.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .sheet(item: $editing) { edit in
            PartnerSheet(memberID: edit.member).environment(store).tint(Palette.orange)
        }
    }

    private func summary(of member: UUID, in budget: Budget) -> String {
        guard let income = budget.incomes.first(where: { $0.member == member }) else { return String(localized: "No salary given") }
        let amount = (income.isMonthly ? income.expected : income.expected).money(income.currency ?? budget.currency)
        let tax = income.tax == nil ? String(localized: "after tax") : String(localized: "before tax")
        return income.isMonthly ? String(localized: "\(amount) a month, \(tax)") : String(localized: "\(amount) each payday, \(tax)")
    }
}

/// A partner's name and salary, set up like your own.
struct PartnerSheet: View {
    @Environment(BudgetStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let memberID: UUID?
    @State private var name = ""
    @State private var pay = PaySettings()
    @State private var hasSalary = true

    var body: some View {
        let budget = store.budget!
        VStack(alignment: .leading, spacing: 16) {
            Text(memberID == nil ? "Add partner" : "Partner").font(.title2.weight(.semibold))
            Field("Name") { BoxTextField("Partner's name", text: $name) }
            Toggle("Give their salary (to split shared costs by income)", isOn: $hasSalary)
            if hasSalary {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        PayEditor(pay: $pay, currency: budget.currency, calendar: budget.workCalendar, showsTitle: false)
                    }
                }
                .frame(maxHeight: 420)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.buttonStyle(SecondaryButtonStyle()).keyboardShortcut(.cancelAction)
                Button(memberID == nil ? "Add" : "Save") {
                    store.savePartner(memberID, name: name.trimmingCharacters(in: .whitespaces), pay: hasSalary ? pay : nil)
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle())
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 620)
        .onAppear {
            name = memberID.flatMap { id in budget.members.first { $0.id == id }?.name } ?? ""
            if let id = memberID, let income = budget.incomes.first(where: { $0.member == id }) {
                pay = PaySettings(income, country: budget.country)
            } else {
                var fresh = PaySettings()
                fresh.country = budget.country
                fresh.frequency = ["CA", "US"].contains(budget.country) ? .biweekly : .twiceMonthly
                pay = fresh
                hasSalary = memberID == nil || budget.incomes.contains { $0.member == memberID }
            }
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
                            Text("Take turns, month by month").tag(Split.turns)
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
