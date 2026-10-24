import AppKit
import SwiftUI

@main
struct HaluMeApp: App {
    @State private var store = BudgetStore()

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
            .onAppear {
                // Design checks: `--demo --light` / `--demo --dark`.
                if store.isDemo, CommandLine.arguments.contains("--light") { NSApp.appearance = NSAppearance(named: .aqua) }
                if store.isDemo, CommandLine.arguments.contains("--dark") { NSApp.appearance = NSAppearance(named: .darkAqua) }
            }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 760, height: 860)
        .commands {
            CommandMenu("Budget") {
                Button("Pay Arrived…") { store.sheet = .pay }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
                Button("Check Balance…") { store.sheet = .balance }
                    .keyboardShortcut("b")
                Button("Edit Plan…") { store.sheet = .plan }
                    .keyboardShortcut("e")
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
