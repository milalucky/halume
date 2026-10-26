import Foundation
import HaluMeCore
@preconcurrency import UserNotifications

/// Local notifications for the next weeks: paydays, bills and debt payments, subscription charges and trial ends.
/// Rebuilt from the budget after every change; nothing leaves the Mac.
@MainActor
enum Reminders {
    static let paydayKey = "remind.payday"
    static let billsKey = "remind.bills"
    static let subscriptionsKey = "remind.subscriptions"

    static func isOn(_ key: String) -> Bool { UserDefaults.standard.bool(forKey: key) }

    /// Asks once, in context, when the user turns a reminder on.
    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])) ?? false
    }

    static func sync(_ budget: Budget?) {
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { pending in
            let ours = pending.map(\.identifier).filter { $0.hasPrefix("halume.") }
            center.removePendingNotificationRequests(withIdentifiers: ours)
        }
        guard let budget, let me = budget.members.first?.id else { return }
        let planner = Planner(budget)
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let horizon = calendar.date(byAdding: .day, value: 45, to: today)!
        var items: [(id: String, date: Date, title: String, body: String)] = []

        if isOn(paydayKey) {
            for date in planner.paydays(of: me, from: today, to: horizon) {
                items.append(("halume.pay.\(date.timeIntervalSince1970)", at(date, hour: 10),
                              String(localized: "Payday"),
                              String(localized: "Enter what came and tick off bills and savings. It takes a minute.")))
            }
        }
        if isOn(billsKey) {
            for bill in budget.bills {
                for date in planner.dueDates(day: bill.day, from: today, to: horizon) {
                    items.append(("halume.bill.\(bill.id).\(date.timeIntervalSince1970)", at(dayBefore(date), hour: 18),
                                  bill.name, String(localized: "Due tomorrow: \(bill.amount.money(budget.currency))")))
                }
            }
            for debt in budget.debts where planner.remaining(of: debt, before: today) > 0 {
                for date in planner.dueDates(of: debt, from: today, to: horizon) {
                    items.append(("halume.debt.\(debt.id).\(date.timeIntervalSince1970)", at(dayBefore(date), hour: 18),
                                  debt.name, String(localized: "Payment due tomorrow: \(debt.payment.money(debt.currency ?? budget.currency))")))
                }
            }
        }
        if isOn(subscriptionsKey) {
            for sub in budget.subscriptions where sub.isActive {
                if let ends = sub.trialEnds, ends > today {
                    let warn = calendar.date(byAdding: .day, value: -2, to: ends)!
                    items.append(("halume.trial.\(sub.id)", at(max(warn, today), hour: 11), sub.name,
                                  String(localized: "Free trial ends \(ends.relativeDay). Cancel now if you don't need it.")))
                }
                // Every three months: still using it?
                let review = calendar.date(byAdding: .month, value: 3, to: calendar.startOfDay(for: sub.reviewed ?? sub.anchor))!
                if review <= horizon {
                    items.append(("halume.review.\(sub.id)", at(max(review, calendar.date(byAdding: .day, value: 1, to: today)!), hour: 11), sub.name,
                                  String(localized: "Still using it? It costs \((Planner.monthlyCost(of: sub) * 12).rounded().money(sub.currency ?? budget.currency)) a year. Check in Subscriptions.")))
                }
                for date in planner.charges(of: sub, from: today, to: horizon) where date != sub.trialEnds.map(calendar.startOfDay) {
                    items.append(("halume.sub.\(sub.id).\(date.timeIntervalSince1970)", at(dayBefore(date), hour: 18), sub.name,
                                  String(localized: "Charge tomorrow: \(sub.amount.money(sub.currency ?? budget.currency))")))
                }
            }
        }

        // macOS keeps up to 64 pending notifications; the nearest ones matter most.
        for item in items.filter({ $0.date > Date() }).sorted(by: { $0.date < $1.date }).prefix(60) {
            let content = UNMutableNotificationContent()
            content.title = item.title
            content.body = item.body
            content.sound = .default
            let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: item.date)
            center.add(UNNotificationRequest(identifier: item.id, content: content,
                                             trigger: UNCalendarNotificationTrigger(dateMatching: parts, repeats: false)))
        }
    }

    private static func at(_ day: Date, hour: Int) -> Date {
        Calendar.current.date(bySettingHour: hour, minute: 0, second: 0, of: day)!
    }

    private static func dayBefore(_ date: Date) -> Date {
        Calendar.current.date(byAdding: .day, value: -1, to: date)!
    }
}
