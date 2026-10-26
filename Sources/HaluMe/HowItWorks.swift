import SwiftUI

/// The method in four steps: shown once, and from the Help menu.
struct HowItWorksSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                Text("How HaluMe works").font(.title2.weight(.semibold))
                Text("No logging of every coffee. You decide once per pay, then live freely.").foregroundStyle(.secondary)
            }
            Step(icon: "sun.max", title: "One number to live on",
                 text: "What's left after bills and savings is yours until the next pay. HaluMe turns it into an amount a day. Spend it however you like.")
            Step(icon: "tray.2", title: "Everything else is in envelopes",
                 text: "Three kinds. Money that leaves: rent, subscriptions, debts. Saving to spend: insurance, a trip, gifts — filled, then spent. Keeping: the cushion and long-term money, not to be touched.")
            Step(icon: "calendar.badge.checkmark", title: "On payday",
                 text: "Enter what came, say what was left from the last pay (keep it or put it into an envelope), and tick off the transfers. A minute or two.")
            Step(icon: "checkmark.seal", title: "Now and then",
                 text: "Check the card balance: if more went than planned, cover it from an envelope or let the amount a day shrink. Once a month, check that your accounts hold what the envelopes say.")
            HStack {
                Spacer()
                Button("Understood") { dismiss() }.buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 520)
    }

    private struct Step: View {
        let icon: String
        let title: LocalizedStringKey
        let text: LocalizedStringKey

        var body: some View {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Palette.orange)
                    .frame(width: 32, height: 32)
                    .background(Circle().fill(Palette.orange.opacity(0.14)))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title).font(.body.weight(.semibold))
                    Text(text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}
