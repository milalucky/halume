import HaluMeCore
import SwiftUI

/// A small modal with a title, content and Cancel / main action.
private struct SheetFrame<Content: View>: View {
    let title: String
    let subtitle: String
    let action: String
    var canSave = true
    let save: () -> Void
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

    var body: some View {
        let planner = store.planner, me = store.me
        let start = me.flatMap { planner?.current(on: Date(), of: $0) } ?? Date()
        SheetFrame(title: "Pay arrived",
                   subtitle: "The real amount of your \(start.formatted(.dateTime.day().month(.wide))) pay. The plan adjusts to it.",
                   action: "Save", canSave: amount > 0, save: { store.setPay(amount, payday: start) }) {
            Field("Amount") { AmountField(amount: $amount, currency: store.budget?.currency ?? "USD") }
        }
        .onAppear {
            guard let planner, let me else { return }
            amount = planner.payday(of: me, on: start)?.actual ?? planner.expected(of: me, on: start)
        }
    }
}

struct BalanceSheet: View {
    @Environment(BudgetStore.self) private var store
    @State private var amount: Decimal = 0

    var body: some View {
        SheetFrame(title: "Check your balance",
                   subtitle: "What's on your card right now? HaluMe takes off what you still have to pay or put aside, and spreads the rest over the days left.",
                   action: "Update", save: { store.checkBalance(amount) }) {
            Field("Balance") { AmountField(amount: $amount, currency: store.budget?.currency ?? "USD") }
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
                    ForEach(Section.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            .padding([.horizontal, .top], 28)
            .padding(.bottom, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch section {
                    case .pay: PayEditor(pay: $pay, currency: currency, showsTitle: false)
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
            if let income = budget.incomes.first { pay = PaySettings(income) }
            bills = budget.bills
            envelopes = budget.envelopes.sorted { $0.priority < $1.priority }
        }
    }

    private func save() {
        guard var budget = store.budget else { return }
        if !budget.incomes.isEmpty { pay.apply(to: &budget.incomes[0]) }
        budget.bills = bills.cleaned
        budget.envelopes = envelopes.cleaned
        store.budget = budget
    }
}
