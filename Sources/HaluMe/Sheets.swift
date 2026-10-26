import HaluMeCore
import SwiftUI

/// A small modal with a title, content and Cancel / main action.
struct SheetFrame<Content: View>: View {
    let title: LocalizedStringKey
    let subtitle: LocalizedStringKey
    let action: LocalizedStringKey
    var canSave = true
    let save: () -> Void
    /// Shown as a red button on the left when editing something that exists.
    var delete: (() -> Void)?
    @ViewBuilder let content: Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.title2.weight(.semibold))
                Text(subtitle).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            content
            HStack {
                if let delete {
                    Button("Delete", role: .destructive) { delete(); dismiss() }
                        .buttonStyle(.borderless)
                        .foregroundStyle(Palette.red)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(SecondaryButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button(action) { save(); dismiss() }
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canSave)
            }
        }
        .padding(28)
        .frame(width: 440)
    }
}

struct PaySheet: View {
    @Environment(BudgetStore.self) private var store
    @State private var amount: Decimal = 0
    @State private var leftover: Decimal?
    @State private var keep: Decimal?
    /// What to do with the leftover: "note" (stats only), "spend" (keep it to live on) or an envelope's id.
    @State private var leftoverTo = "note"

    var body: some View {
        let planner = store.planner, me = store.me
        let start = me.flatMap { planner?.current(on: Date(), of: $0) } ?? Date()
        SheetFrame(title: "Pay arrived",
                   subtitle: "The real amount of your \(start.formatted(.dateTime.day().month(.wide))) pay. The plan adjusts to it.",
                   action: "Save", canSave: amount > 0, save: {
                       store.setPay(amount, leftover: leftover, keep: keep, payday: start)
                       store.useLeftover(leftover ?? 0, to: leftoverTo, payday: start)
                   }) {
            let currency = store.budget?.currency ?? "USD"
            let usual = me.flatMap { planner?.usual(of: $0, on: start) } ?? 0
            Field("Amount") { AmountField(amount: $amount, currency: currency) }
            if usual > 0, amount > usual {
                let extra = amount - usual
                VStack(alignment: .leading, spacing: 6) {
                    Toggle("Keep the extra \(extra.money(currency)) for the next payday", isOn: Binding(get: { keep != nil }, set: { keep = $0 ? extra : nil }))
                    Text("This pay is bigger than usual. Kept money comes with your next pay, so you get ahead instead of spending it now.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    if keep != nil {
                        Field("How much to keep") { AmountField(optional: $keep, currency: currency, placeholder: "0") }.frame(width: 200, alignment: .leading)
                    }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.green.opacity(0.08)))
            }
            Field("Left from your last pay", hint: "Optional. What was still on your card when this pay came. It shows in your stats whether you stayed within the plan.") {
                AmountField(optional: $leftover, currency: currency, placeholder: "Skip")
            }
            if let leftover, leftover > 0 {
                Field("What to do with it") {
                    Picker("What to do with it", selection: $leftoverTo) {
                        Text("Just note it").tag("note")
                        Text("Keep it to spend now").tag("spend")
                        Divider()
                        ForEach(store.budget?.envelopes ?? []) { Text("Put into \($0.name)").tag($0.id.uuidString) }
                    }
                    .labelsHidden()
                }
                Text(LocalizedStringKey(leftoverTo == "note" ? "Only your stats see it." : leftoverTo == "spend"
                     ? "It adds to what you can spend until the next pay." : "Move it there: this pay starts with a fuller envelope."))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onAppear {
            guard let planner, let me else { return }
            amount = planner.payday(of: me, on: start)?.actual ?? planner.expected(of: me, on: start)
            leftover = planner.payday(of: me, on: start)?.leftover
            keep = planner.payday(of: me, on: start)?.keep
            if let used = store.leftoverInflow(payday: start) {
                leftoverTo = used.allocations.first.flatMap { if case .envelope(let id) = $0.target { id.uuidString } else { nil } } ?? "spend"
            }
        }
    }
}

struct BalanceSheet: View {
    @Environment(BudgetStore.self) private var store
    @State private var amount: Decimal = 0
    @State private var coverFrom: UUID?
    @State private var cover: Decimal?

    var body: some View {
        let currency = store.budget?.currency ?? "USD"
        let expected = store.expectedBalance()
        let gap = expected.map { $0 - amount } ?? 0
        SheetFrame(title: "Check your balance",
                   subtitle: "What's on your card right now? HaluMe takes off what you still have to pay or put aside, and spreads the rest over the days left.",
                   action: "Update", save: {
                       store.checkBalance(amount)
                       if let coverFrom, let cover, cover > 0 { store.cover(cover, from: coverFrom) }
                   }) {
            Field("Balance") { AmountField(amount: $amount, currency: currency) }
            if amount > 0, let expected {
                if gap > 0 {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("About \(gap.money(currency)) more went than planned", systemImage: "exclamationmark.triangle")
                            .font(.body.weight(.medium))
                        Text("By the plan about \(expected.money(currency)) would be left now. You can cover the gap from an envelope, or let the amount a day shrink.")
                            .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        HStack(alignment: .top, spacing: 12) {
                            Field("Cover from") {
                                Picker("Cover from", selection: $coverFrom) {
                                    Text("Don't cover").tag(UUID?.none)
                                    ForEach(store.budget?.envelopes ?? []) { Text($0.name).tag(UUID?.some($0.id)) }
                                }
                                .labelsHidden()
                            }
                            if coverFrom != nil {
                                Field("How much") { AmountField(optional: $cover, currency: currency, placeholder: "0") }.frame(width: 150)
                            }
                        }
                    }
                    .padding(12)
                    .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Palette.orange.opacity(0.10)))
                    .onChange(of: coverFrom) { _, id in if id != nil, cover == nil { cover = gap } }
                } else {
                    Label("On plan: about \((-gap).money(currency)) more than expected is left.", systemImage: "checkmark.circle")
                        .font(.callout).foregroundStyle(Palette.green)
                }
            }
        }
    }
}

struct PlanEditor: View {
    private enum Section: String, CaseIterable, Identifiable {
        case pay = "Pay", bills = "Bills", savings = "Savings"
        var id: Self { self }
    }

    @Environment(BudgetStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var section = Section.pay
    @State private var pay = PaySettings()
    @State private var bills: [Bill] = []
    @State private var envelopes: [Envelope] = []

    var body: some View {
        let currency = store.budget?.currency ?? "USD"
        let member = store.me ?? UUID()
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Your plan").font(.title2.weight(.semibold))
                Picker("Section", selection: $section) {
                    ForEach(Section.allCases) { Text(LocalizedStringKey($0.rawValue)).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding([.horizontal, .top], 28)
            .padding(.bottom, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch section {
                    case .pay: PayEditor(pay: $pay, currency: currency, calendar: store.budget?.workCalendar, showsTitle: false)
                    case .bills: BillsEditor(bills: $bills, currency: currency, member: member, showsTitle: false)
                    case .savings:
                        Text("The top one is funded first when pay runs short.").foregroundStyle(.secondary)
                        SavingsEditor(envelopes: $envelopes, currency: currency, member: member, showsTitle: false)
                    }
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 20)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(SecondaryButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save(); dismiss() }
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
                    .disabled(pay.amount <= 0)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 18)
        }
        .frame(width: 640, height: 600)
        .onAppear {
            guard let budget = store.budget else { return }
            if let income = budget.incomes.first { pay = PaySettings(income, country: budget.country) }
            bills = budget.bills
            // Project funds are managed in Projects.
            envelopes = budget.envelopes.filter { if case .project = $0.goal { false } else { true } }.sorted { $0.priority < $1.priority }
        }
    }

    private func save() {
        guard var budget = store.budget else { return }
        if !budget.incomes.isEmpty { pay.apply(to: &budget.incomes[0]) }
        budget.bills = bills.cleaned
        let funds = budget.envelopes.filter { if case .project = $0.goal { true } else { false } }
        budget.envelopes = envelopes.cleaned + funds.enumerated().map { var f = $0.element; f.priority = envelopes.count + $0.offset; return f }
        store.budget = budget
    }
}
