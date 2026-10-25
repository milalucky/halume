import Foundation

// What a household shares and what stays with one person. Sync stores the shared part where every
// member reads it (a CloudKit shared zone) and each private part only in its owner's private store.

extension Envelope {
    /// Hidden from the other members right now.
    public func isHidden(at date: Date) -> Bool {
        hidden && (revealOn.map { date < $0 } ?? true)
    }
}

extension Budget {
    private func hiddenEnvelopes(at date: Date) -> Set<UUID> {
        Set(envelopes.filter { $0.isHidden(at: date) }.map(\.id))
    }

    /// What every member's device sees: everything except envelopes still hidden and the money moved in or out of them.
    public func sharedPart(at date: Date) -> Budget {
        let hidden = hiddenEnvelopes(at: date)
        var part = self
        // Who gifts what stays with the giver.
        part.reservations = []
        part.envelopes.removeAll { hidden.contains($0.id) }
        part.withdrawals.removeAll { hidden.contains($0.envelope) }
        part.paydays = paydays.map { payday in
            var p = payday
            p.allocations.removeAll { if case .envelope(let id) = $0.target { hidden.contains(id) } else { false } }
            return p
        }
        return part
    }

    /// What stays with one member only: their hidden envelopes and the money moved in or out of them.
    public func privatePart(of member: UUID, at date: Date) -> Budget {
        let mine = Set(envelopes.filter { $0.isHidden(at: date) && $0.owner == .member(member) }.map(\.id))
        var part = Budget(id: id, name: name, currency: currency, members: [])
        part.envelopes = envelopes.filter { mine.contains($0.id) }
        part.withdrawals = withdrawals.filter { mine.contains($0.envelope) }
        part.reservations = reservations.filter { $0.by == member }
        part.paydays = paydays.compactMap { payday in
            var p = payday
            p.allocations = payday.allocations.filter { if case .envelope(let id) = $0.target { mine.contains(id) } else { false } }
            return p.allocations.isEmpty ? nil : p
        }
        return part
    }

    /// The shared part with one member's private part put back in.
    public static func merged(shared: Budget, private part: Budget) -> Budget {
        var budget = shared
        budget.envelopes += part.envelopes.filter { e in !shared.envelopes.contains { $0.id == e.id } }
        budget.withdrawals += part.withdrawals.filter { w in !shared.withdrawals.contains { $0.id == w.id } }
        budget.reservations += part.reservations.filter { !shared.reservations.contains($0) }
        for payday in part.paydays {
            if let i = budget.paydays.firstIndex(where: { $0.id == payday.id }) {
                let known = Set(budget.paydays[i].allocations.map(\.target))
                budget.paydays[i].allocations += payday.allocations.filter { !known.contains($0.target) }
            } else {
                budget.paydays.append(payday)
            }
        }
        return budget
    }
}
