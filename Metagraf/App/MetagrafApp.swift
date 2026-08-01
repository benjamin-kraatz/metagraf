import MetagrafCore
import SwiftUI

@main
struct MetagrafApp: App {
    #if os(macOS)
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarContent(session: appDelegate.session)
        } label: {
            MenuBarIcon(session: appDelegate.session)
        }
        .menuBarExtraStyle(.window)

        Window("Metagraf", id: MetagrafWindow.main.rawValue) {
            MainWindow()
        }
        .defaultSize(width: 900, height: 600)

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
