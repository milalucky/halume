import AppKit
import SwiftUI

@main
struct HaluMeApp: App {
    @State private var store = BudgetStore()
    @AppStorage("menuBar") private var menuBar = true

    init() {
        // Design checks: `--demo --light` / `--demo --dark`, set before any window draws.
        Appearance.apply(UserDefaults.standard.string(forKey: Appearance.key) ?? "")
        let args = CommandLine.arguments
        if args.contains("--demo"), args.contains("--light") { NSApplication.shared.appearance = NSAppearance(named: .aqua) }
        if args.contains("--demo"), args.contains("--dark") { NSApplication.shared.appearance = NSAppearance(named: .darkAqua) }
    }

    var body: some Scene {
        Window("HaluMe", id: "main") {
            Group {
                if store.budget == nil {
                    OnboardingView()
                } else {
                    MainView()
                }
            }
            .environment(store)
            .tint(Palette.orange)
            .frame(minWidth: 620, minHeight: 640)
            .backdrop()
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 760, height: 860)
        Settings {
            SettingsView().environment(store).tint(Palette.orange)
        }
        MenuBarExtra(isInserted: $menuBar) {
            MenuBarGlance().environment(store)
        } label: {
            MenuBarLabel().environment(store)
        }
        .commands {
            CommandMenu("Budget") {
                Button("Pay Arrived…") { store.sheet = .pay }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                Button("Check Balance…") { store.sheet = .balance }
                    .keyboardShortcut("b")
                Button("Edit Plan…") { store.sheet = .plan }
                    .keyboardShortcut("e")
                Button("Money Came In…") { store.sheet = store.newInflow }
                    .keyboardShortcut("i", modifiers: [.command, .shift])
                Button("Unplanned Expense…") { store.sheet = .outflow(Spending()) }
                    .keyboardShortcut("u", modifiers: [.command, .shift])
                Button("Vacation and Sick Leave…") { store.sheet = .timeOff(nil) }
                    .keyboardShortcut("t", modifiers: [.command, .shift])
                Button("Take Money Out…") {
                    if let first = store.budget?.envelopes.first { store.sheet = .withdraw(first.id) }
                }
                .disabled(store.budget?.envelopes.isEmpty ?? true)
                Button("Move Between Savings…") { store.sheet = .transfer(TransferSheet.new()) }
                    .disabled((store.budget?.envelopes.count ?? 0) < 2)
                Button("What If…") { store.sheet = .whatIf }
                    .keyboardShortcut("w", modifiers: [.command, .shift])
                Divider()
                Button("Start Over…") { store.confirmingStartOver = true }
            }
            CommandGroup(replacing: .help) {
                Button("How HaluMe Works") { store.sheet = .howItWorks }
            }
            CommandGroup(before: .sidebar) {
                ForEach(Array(Section.allCases.enumerated()), id: \.element) { i, section in
                    // ⌘1…⌘9 for the first nine; a two-digit Character would crash.
                    if i < 9 {
                        Button(section.title) { store.section = section }
                            .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")))
                    } else {
                        Button(section.title) { store.section = section }
                    }
                }
                Divider()
            }
        }
    }
}
