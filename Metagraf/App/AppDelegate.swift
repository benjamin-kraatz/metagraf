#if os(macOS)
import AppKit
import MetagrafCore
import OSLog

/// Wires the always-running parts of the app: the hotkey tap, the pill, and the
/// dictation session they both talk to.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let session = DictationSession()

    private let logger = Logger(subsystem: Metagraf.bundleIdentifier, category: "App")
    private let hotKeys = HotKeyMonitor()
    private var pill: PillWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Until insertion lands in M2, a finished transcript goes to the
        // clipboard so the loop is usable end to end.
        session.onTranscript = { transcript in
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(transcript, forType: .string)
        }

        let pill = PillWindowController(session: session)
        pill.show()
        self.pill = pill

        session.prewarm()
        startHotKeys()
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeys.stop()
    }

    private func startHotKeys() {
        hotKeys.onActivation = { [weak self] activation in
            guard let self else { return }
            Task {
                switch activation {
                case .began:
                    await self.session.begin()
                case .completed:
                    await self.session.complete()
                case .cancelled, .aborted:
                    await self.session.abort()
                }
            }
        }

        do {
            try hotKeys.start()
        } catch {
            logger.error("Hot key monitor unavailable: \(error.localizedDescription, privacy: .public)")
            // The prompt is the only way the user can grant this, and without it
            // the app cannot do its one job.
            AccessibilityPermission.requestTrust()
            waitForAccessibilityTrust()
        }
    }

    /// Polls for Accessibility trust, because the system sends no notification
    /// when the user flips the switch in System Settings.
    private func waitForAccessibilityTrust() {
        Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.5))
                guard let self, !self.hotKeys.isRunning else { return }
                guard AccessibilityPermission.isTrusted else { continue }

                do {
                    try self.hotKeys.start()
                    self.logger.info("Hot key monitor started after access was granted")
                    return
                } catch {
                    self.logger.error("Still unable to start: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }
}
#endif
