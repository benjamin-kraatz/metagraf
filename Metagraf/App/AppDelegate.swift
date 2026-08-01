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
    let settings = SettingsStore.shared
    private(set) var history: HistoryStore?

    private let logger = Logger(subsystem: Metagraf.bundleIdentifier, category: "App")
    private let hotKeys = HotKeyMonitor()
    private let inserter = TextInserter()
    private var pill: PillWindowController?

    /// Which app was frontmost when recording began, and when it began.
    /// Captured up front because by the time the transcript is ready the user
    /// may have switched away.
    private var target: NSRunningApplication?
    private var startedAt: Date?

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let history = try HistoryStore(inMemory: false)
            history.prune(retentionDays: settings.retentionDays)
            self.history = history
        } catch {
            logger.error("History unavailable: \(error.localizedDescription, privacy: .public)")
        }

        session.deliver = { [weak self] transcript in
            try await self?.deliver(transcript)
        }

        let pill = PillWindowController(session: session, settings: settings)
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

    // MARK: - Delivery

    private func deliver(_ transcript: String) async throws {
        let target = target
        record(transcript, target: target)

        let strategy = settings.insertion(forBundleIdentifier: target?.bundleIdentifier)
        try await inserter.insert(transcript, using: strategy)
    }

    private func record(_ transcript: String, target: NSRunningApplication?) {
        guard let history else { return }

        let duration = startedAt.map { Date.now.timeIntervalSince($0) } ?? 0
        startedAt = nil

        history.record(
            Transcript(
                text: transcript,
                localeIdentifier: settings.effectiveLocale.identifier,
                engineIdentifier: EngineID.appleSpeech.rawValue,
                durationSeconds: duration,
                appBundleIdentifier: target?.bundleIdentifier,
                appName: target?.localizedName
            ),
            retentionDays: settings.retentionDays
        )
    }

    // MARK: - Hotkey

    private func startHotKeys() {
        applySettings()

        hotKeys.onActivation = { [weak self] activation in
            guard let self else { return }

            if activation == .began {
                target = NSWorkspace.shared.frontmostApplication
                startedAt = .now
                // Picked up fresh each time so changing the language or adding a
                // vocabulary term takes effect on the very next dictation.
                session.configuration = EngineConfiguration(
                    locale: settings.effectiveLocale,
                    contextualStrings: settings.contextualStrings
                )
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

    /// Pushes the user's hotkey preferences into the monitor.
    func applySettings() {
        hotKeys.binding = ModifierKey(rawValue: settings.hotKey) ?? .rightOption
        hotKeys.machine.minimumHold = settings.minimumHold
        hotKeys.machine.doubleTapWindow = settings.doubleTapWindow
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
