import MetagrafCore
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
            MainWindow()
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
            SettingsView()
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
