import AppKit
import SwiftUI

/// HaluMe → Settings… (⌘,).
struct SettingsView: View {
    @Environment(BudgetStore.self) private var store
    @AppStorage(Reminders.paydayKey) private var payday = false
    @AppStorage(Reminders.billsKey) private var bills = false
    @AppStorage(Reminders.subscriptionsKey) private var subscriptions = false
    @State private var denied = false
    @AppStorage(Appearance.key) private var theme = ""
    @AppStorage(NumberStyle.key) private var numbers = NumberStyle.current.rawValue

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
                Picker("Theme", selection: $theme) {
                    Text("As the system").tag("")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }
                .onChange(of: theme) { _, value in Appearance.apply(value) }
                Picker("Thousands", selection: $numbers) {
                    ForEach(NumberStyle.allCases) { Text($0.sample).tag($0.rawValue) }
                }
                .onChange(of: numbers) { store.look += 1 }
            } header: {
                Text("Look")
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
                LabeledContent("Country") {
                    CountryField(code: Binding(get: { store.budget?.country ?? "" }, set: { store.budget?.country = $0 }))
                        .frame(width: 220)
                }
                LabeledContent("Currency", value: store.budget?.currency ?? "—")
                Button("Start Over…", role: .destructive) { store.confirmingStartOver = true }
                    .disabled(store.budget == nil)
            } header: {
                Text("Budget")
            }
        }
        .formStyle(.grouped)
        .safeAreaInset(edge: .bottom) {
            HStack {
                Spacer()
                Button("Close") { NSApp.keyWindow?.performClose(nil) }
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
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

/// Light, dark or as the system, remembered between launches.
enum Appearance {
    static let key = "appearance"

    @MainActor
    static func apply(_ value: String) {
        NSApplication.shared.appearance = switch value {
        case "light": NSAppearance(named: .aqua)
        case "dark": NSAppearance(named: .darkAqua)
        default: nil
        }
    }
}
