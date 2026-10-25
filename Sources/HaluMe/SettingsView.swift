import SwiftUI

/// HaluMe → Settings… (⌘,).
struct SettingsView: View {
    @Environment(BudgetStore.self) private var store
    @AppStorage(Reminders.paydayKey) private var payday = false
    @AppStorage(Reminders.billsKey) private var bills = false
    @AppStorage(Reminders.subscriptionsKey) private var subscriptions = false
    @State private var denied = false

    var body: some View {
        Form {
            HouseholdSection()
            SwiftUI.Section {
                WorkCalendarPicker(calendar: Binding(get: { store.budget?.workCalendar }, set: { store.budget?.workCalendar = $0 }))
            } header: {
                Text("Work calendar")
            }
            SwiftUI.Section {
                Toggle("On payday", isOn: ask($payday))
                Toggle("The day before bills and debt payments", isOn: ask($bills))
                Toggle("Before subscription charges and when a free trial ends", isOn: ask($subscriptions))
                if denied {
                    Text("Notifications are off for HaluMe. Turn them on in System Settings → Notifications.")
                        .font(.callout)
                        .foregroundStyle(Palette.red)
                }
            } header: {
                Text("Reminders")
            }
            SwiftUI.Section {
                Picker("Language", selection: Binding(get: { AppLanguage.current }, set: { AppLanguage.switchTo($0) })) {
                    ForEach(AppLanguage.allCases) { Text($0.title).tag($0) }
                }
                Text("HaluMe restarts in the new language.").font(.caption).foregroundStyle(.secondary)
            } header: {
                Text("Language")
            }
            SwiftUI.Section {
                LabeledContent("Currency", value: store.budget?.currency ?? "—")
                Button("Start Over…", role: .destructive) { store.confirmingStartOver = true }
                    .disabled(store.budget == nil)
            } header: {
                Text("Budget")
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: [payday, bills, subscriptions]) { store.syncReminders() }
    }

    /// Turning a reminder on asks for notification permission first.
    private func ask(_ binding: Binding<Bool>) -> Binding<Bool> {
        Binding {
            binding.wrappedValue
        } set: { on in
            guard on else { binding.wrappedValue = false; return }
            Task {
                let granted = await Reminders.requestPermission()
                denied = !granted
                binding.wrappedValue = granted
            }
        }
    }
}
