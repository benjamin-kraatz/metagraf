#if os(macOS)
import MetagrafCore
import OSLog
import ServiceManagement

/// Registers the app to start with the user's session.
enum LaunchAtLogin {
    private static let logger = Logger(subsystem: Metagraf.bundleIdentifier, category: "LaunchAtLogin")

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func set(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            logger.error("Could not update login item: \(error.localizedDescription, privacy: .public)")
        }
    }
}
#endif
