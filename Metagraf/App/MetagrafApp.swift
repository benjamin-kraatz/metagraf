import MetagrafCore
import SwiftUI

@main
struct MetagrafApp: App {
    var body: some Scene {
        #if os(macOS)
        MenuBarExtra("Metagraf", systemImage: "waveform") {
            MenuBarContent()
        }
        .menuBarExtraStyle(.window)

        Window("Metagraf", id: MetagrafWindow.main.rawValue) {
            MainWindow()
        }
        .defaultSize(width: 900, height: 600)

        Settings {
            SettingsView()
        }
        #else
        WindowGroup {
            MainWindow()
        }
        #endif
    }
}

/// Identifiers for the app's windows, so `openWindow` calls stay typo-proof.
enum MetagrafWindow: String {
    case main
    case onboarding
}
