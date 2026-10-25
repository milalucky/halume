import AppKit
import SwiftUI

@main
struct HaluMeApp: App {
    @State private var store = BudgetStore()

    init() {
        // Design checks: `--demo --light` / `--demo --dark`, set before any window draws.
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
        .commands {
            CommandMenu("Budget") {
                Button("Pay Arrived…") { store.sheet = .pay }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                Button("Check Balance…") { store.sheet = .balance }
                    .keyboardShortcut("b")
                Button("Edit Plan…") { store.sheet = .plan }
                    .keyboardShortcut("e")
                Button("Take Money Out…") {
                    if let first = store.budget?.envelopes.first { store.sheet = .withdraw(first.id) }
                }
                .disabled(store.budget?.envelopes.isEmpty ?? true)
                Divider()
                Button("Start Over…") { store.confirmingStartOver = true }
            }
            CommandGroup(before: .sidebar) {
                ForEach(Array(Section.allCases.enumerated()), id: \.element) { i, section in
                    Button(section.title) { store.section = section }
                        .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")))
                }
                Divider()
            }
        }
    }
}
