#if os(macOS)
import AppKit
import MetagrafCore
import OSLog

/// Wires the always-running parts of the app: the hotkey tap, the pill, and the
/// dictation session they both talk to.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let session = DictationSession()
    let permissions = PermissionsCoordinator()

    /// Which app was frontmost when recording began. Captured up front because
    /// by the time the transcript is ready the user may have switched away, and
    /// per-app rules in M3 need to know where the text was headed.
    private(set) var target: NSRunningApplication?

    private let logger = Logger(subsystem: Metagraf.bundleIdentifier, category: "App")
    private let hotKeys = HotKeyMonitor()
    private let inserter = TextInserter()
    private var pill: PillWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        session.deliver = { [weak self] transcript in
            try await self?.inserter.insert(transcript, using: .paste)
        }

        let pill = PillWindowController(session: session)
        pill.show()
        self.pill = pill

        session.prewarm()
        startHotKeys()

        if !permissions.isReady {
            permissions.beginPolling()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeys.stop()
    }

    private func startHotKeys() {
        hotKeys.onActivation = { [weak self] activation in
            guard let self else { return }

            if activation == .began {
                target = NSWorkspace.shared.frontmostApplication
            }

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
                    self.permissions.refresh()
                    self.logger.info("Hot key monitor started after access was granted")
                    return
                } catch {
                    self.logger.error("Still unable to start: \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }
}

extension HotKeyMonitor.Activation: Equatable {}
#endif
