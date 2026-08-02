#if os(macOS)
import MetagrafCore
import Sparkle

/// Owns Sparkle for the app lifetime and supplies the selected update channel.
@MainActor
final class UpdateController: NSObject, SPUUpdaterDelegate {
    private let settings: SettingsStore
    private lazy var controller = SPUStandardUpdaterController(
        startingUpdater: true,
        updaterDelegate: self,
        userDriverDelegate: nil
    )

    override init() {
        settings = .shared
        super.init()
        _ = controller
    }

    func checkForUpdates() {
        controller.checkForUpdates(nil)
    }

    func channelsDidChange() {
        controller.updater.resetUpdateCycleAfterShortDelay()
    }

    nonisolated func allowedChannels(for updater: SPUUpdater) -> Set<String> {
        MainActor.assumeIsolated {
            settings.receivesBetaUpdates ? ["beta"] : []
        }
    }
}
#endif
