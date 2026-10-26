import AppKit
import HaluMeCore
import SwiftUI

struct WishlistPage: View {
    @Environment(BudgetStore.self) private var store

    var body: some View {
        Page(title: "Wishlist") {
            Button { store.sheet = .wish(newWish()) } label: { Label("Add wish", systemImage: "plus") }
                .buttonStyle(SecondaryButtonStyle())
        } content: {
            if let budget = store.budget, let me = store.me {
                let open = budget.wishes.filter { !$0.isDone }
                if budget.wishes.isEmpty {
                    EmptyState(icon: "gift", title: "Things you want",
                               text: "Add what you'd like to have. Save for it yourself, or let your partner see it and gift it.")
                } else {
                    WishGroup(title: "My wishes", wishes: open.filter { $0.owner == me })
                    ForEach(store.partners) { partner in
                        let theirs = open.filter { $0.owner == partner.id }
                        if !theirs.isEmpty { WishGroup(title: "\(partner.name)'s wishes", wishes: theirs) }
                    }
                    let done = budget.wishes.filter(\.isDone)
                    if !done.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Got it").font(.headline)
                            ForEach(done) { wish in
                                HStack {
                                    Image(systemName: "checkmark.circle.fill").foregroundStyle(Palette.green)
                                    Text(wish.name)
                                    Spacer()
                                    Text(wish.price.money(wish.currency ?? budget.currency)).foregroundStyle(.secondary).monospacedDigit()
                                }
                                .contextMenu { Button("Delete", role: .destructive) { store.deleteWish(wish.id) } }
                            }
                        }
                        .card()
                    }
                }
            }
        }
    }

    private func newWish() -> Wish { Wish(owner: store.me ?? UUID(), name: "") }
}

private struct WishGroup: View {
    @Environment(BudgetStore.self) private var store
    let title: LocalizedStringKey
    let wishes: [Wish]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            if wishes.isEmpty {
                Text("Nothing yet.").foregroundStyle(.secondary)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 12)], spacing: 12) {
                ForEach(wishes) { WishCard(wish: $0) }
            }
        }
    }
}

private struct WishCard: View {
    @Environment(BudgetStore.self) private var store
    let wish: Wish

    var body: some View {
        let budget = store.budget!
        let mine = wish.owner == store.me
        let envelope = wish.envelope.flatMap { id in budget.envelopes.first { $0.id == id } }
        let saved = envelope.flatMap { e in store.planner?.balance(of: e, before: Calendar.current.date(byAdding: .day, value: 1, to: Date())!) }
        let reserved = budget.reservations.contains { $0.wish == wish.id && $0.by == store.me }
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                Text(wish.name).font(.body.weight(.semibold)).lineLimit(2)
                Spacer()
                if let url = URL(string: wish.link), url.scheme?.hasPrefix("http") == true {
                    IconButton(icon: "arrow.up.right", label: "Open link") { NSWorkspace.shared.open(url) }
                }
            }
            if wish.price > 0 {
                Text(wish.price.money(wish.currency ?? budget.currency))
                    .font(.system(size: 24, weight: .medium, design: .rounded)).monospacedDigit()
            }
            if !wish.note.isEmpty { Text(wish.note).font(.callout).foregroundStyle(.secondary).lineLimit(3) }
            if let saved, wish.price > 0 {
                Bar(value: (saved / max(budget.convert(wish.price, from: wish.currency), 1)).double)
                Text("\(saved.money(budget.currency)) saved").font(.caption).foregroundStyle(.secondary)
            }
            HStack(spacing: 8) {
                if mine {
                    if envelope == nil, wish.price > 0 {
                        Button("Save for It") { store.startSaving(for: wish) }.buttonStyle(SecondaryButtonStyle())
                    }
                    Spacer(minLength: 0)
                    IconButton(icon: "checkmark", label: "Got It") { store.markGot(wish) }
                } else {
                    Button { store.toggleReservation(wish) } label: {
                        Label(reserved ? "You're gifting this" : "I'll Gift This", systemImage: reserved ? "gift.fill" : "gift")
                    }
                    .buttonStyle(SecondaryButtonStyle())
                    .help(Text("Only you see this"))
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .card()
        .contextMenu {
            if mine {
                Button("Edit…") { store.sheet = .wish(wish) }
                Button("Delete", role: .destructive) { store.deleteWish(wish.id) }
            }
        }
    }
}

struct WishEditor: View {
    @Environment(BudgetStore.self) private var store
    @State var wish: Wish

    var body: some View {
        let isNew = !(store.budget?.wishes.contains { $0.id == wish.id } ?? false)
        SheetFrame(title: LocalizedStringKey(isNew ? "New wish" : "Edit wish"),
                   subtitle: "Your partner sees your wishes, so they can gift one. Who gifts what stays a surprise.",
                   action: LocalizedStringKey(isNew ? "Add" : "Save"),
                   canSave: !wish.name.trimmingCharacters(in: .whitespaces).isEmpty,
                   save: { store.save(wish) }) {
            if let me = store.me, !store.partners.isEmpty {
                Field("Whose wish") {
                    Picker("Whose wish", selection: $wish.owner) {
                        Text("Mine").tag(me)
                        ForEach(store.partners) { Text($0.name).tag($0.id) }
                    }
                    .labelsHidden()
                }
                .frame(width: 200, alignment: .leading)
            }
            Field("What") { BoxTextField("e.g. New phone", text: $wish.name) }
            Field("Price", hint: "Optional") {
                AmountField(amount: $wish.price, code: $wish.currency, budgetCurrency: store.budget?.currency ?? "USD")
            }
            Field("Link", hint: "Optional") { BoxTextField("https://", text: $wish.link) }
            Field("Note", hint: "Colour, size, where to buy") { BoxTextField("Optional", text: $wish.note) }
            if !isNew {
                Button("Delete", role: .destructive) { store.deleteWish(wish.id); store.sheet = nil }
                    .buttonStyle(.borderless)
                    .foregroundStyle(Palette.red)
            }
        }
    }
}
