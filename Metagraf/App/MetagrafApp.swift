import MetagrafCore
import SwiftData
import SwiftUI

@main
struct MetagrafApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(session: appDelegate.session, permissions: appDelegate.permissions)
        } label: {
            MenuBarIcon(session: appDelegate.session, permissions: appDelegate.permissions)
        }
        .menuBarExtraStyle(.window)

        Window("Metagraf", id: MetagrafWindow.main.rawValue) {
            // The delegate's container, not a fresh one: `modelContainer(for:)`
            // would build a second store and the window would show a
            // permanently empty history.
            if let history = appDelegate.history {
                MainWindow()
                    .modelContainer(history.container)
            } else {
                ContentUnavailableView(
                    "History is unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text("Dictation still works; only the transcript log could not be opened.")
                )
                .frame(minWidth: 420, minHeight: 260)
            }
        }
        .defaultSize(width: 900, height: 600)

        Window("Welcome to Metagraf", id: MetagrafWindow.onboarding.rawValue) {
            OnboardingWindow(permissions: appDelegate.permissions)
                .onAppear {
                    // An agent app has no Dock icon to click, so it has to ask
                    // for the foreground itself or the window opens unfocused
                    // behind everything.
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
        .windowResizability(.contentSize)
        .defaultLaunchBehavior(.suppressed)

        Settings {
            SettingsView(
                settings: appDelegate.settings,
                permissions: appDelegate.permissions,
                models: appDelegate.models
            )
            // Preferences are applied on close rather than on every keystroke,
            // so a half-typed value never takes effect.
            .onDisappear { appDelegate.applySettings() }
        }
    }
    #else
    var body: some Scene {
        WindowGroup {
            MainWindow()
        }
    }
    #endif
}

/// Identifiers for the app's windows, so `openWindow` calls stay typo-proof.
enum MetagrafWindow: String {
    case main
    case onboarding
}
