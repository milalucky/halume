import AppKit
import SwiftUI

/// The app's own language, apart from the system's. Switching restarts the app.
enum AppLanguage: String, CaseIterable, Identifiable {
    case english = "en", russian = "ru"
    var id: Self { self }

    /// Shown in its own language, so anyone can find theirs.
    var title: String {
        switch self {
        case .english: "English"
        case .russian: "Русский"
        }
    }

    static var current: AppLanguage {
        AppLanguage(rawValue: Bundle.main.preferredLocalizations.first ?? "en") ?? .english
    }

    @MainActor
    static func switchTo(_ language: AppLanguage) {
        guard language != current else { return }
        UserDefaults.standard.set([language.rawValue], forKey: "AppleLanguages")
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        config.arguments = Array(CommandLine.arguments.dropFirst())
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }
}

/// A small globe menu: English / Русский.
struct LanguageMenu: View {
    var body: some View {
        Menu {
            ForEach(AppLanguage.allCases) { language in
                Button { AppLanguage.switchTo(language) } label: {
                    if language == AppLanguage.current {
                        Label(language.title, systemImage: "checkmark")
                    } else {
                        Text(language.title)
                    }
                }
            }
        } label: {
            Label(AppLanguage.current.title, systemImage: "globe")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(Text("Language"))
    }
}
