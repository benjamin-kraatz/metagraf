import MetagrafCore
import SwiftData
import SwiftUI

@main
struct MetagrafApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(
                session: appDelegate.session,
                permissions: appDelegate.permissions,
                updates: appDelegate.updates
            )
        } label: {
            MenuBarIcon(session: appDelegate.session, permissions: appDelegate.permissions)
        }
        .menuBarExtraStyle(.window)

        Window("Metagraf", id: MetagrafWindow.main.rawValue) {
            MainWindowContent()
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
                models: appDelegate.models,
                updates: appDelegate.updates
            )
            // Preferences are applied on close rather than on every keystroke,
            // so a half-typed value never takes effect.
            .onDisappear { appDelegate.applySettings() }
        }
    }
    #else
    @State private var controller = DictationController()

    var body: some Scene {
        WindowGroup {
            if let history = controller.history {
                RootView(controller: controller)
                    .modelContainer(history.container)
            } else {
                ContentUnavailableView(
                    "History is unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text("Dictation still works; only the transcript log could not be opened.")
                )
            }
        }
    }
    #endif
}

#if os(macOS)
private struct MainWindowContent: View {
    @EnvironmentObject private var appDelegate: AppDelegate

    var body: some View {
        // Use the delegate's container, not a fresh one: `modelContainer(for:)`
        // would build a second store and show a permanently empty history.
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
}
#endif

/// Identifiers for the app's windows, so `openWindow` calls stay typo-proof.
enum MetagrafWindow: String {
    case main
    case onboarding
}
