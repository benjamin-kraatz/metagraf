#if os(macOS)
import AppKit
import Darwin
import MetagrafCore
import MetagrafWhisper
import OSLog

/// Wires the always-running parts of the app: the hotkey tap, the pill, and the
/// dictation session they both talk to.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let session = DictationSession()
    let permissions = PermissionsCoordinator()
    let settings = SettingsStore.shared
    let models = ModelStore()
    private(set) var history: HistoryStore?

    private let logger = Logger(subsystem: Metagraf.bundleIdentifier, category: "App")
    private let hotKeys = HotKeyMonitor()
    private let inserter = TextInserter()
    private let focusedContextReader = FocusedContextReader()
    private let feedback = FeedbackPlayer()
    private var pill: PillWindowController?
    private var instanceLockFileDescriptor: Int32 = -1

    /// Which app was frontmost when recording began, and when it began.
    /// Captured up front because by the time the transcript is ready the user
    /// may have switched away.
    private var target: NSRunningApplication?
    private var startedAt: Date?

    /// Which model the session is currently loaded with, so switching only
    /// happens when the choice actually changed.
    private var activeModelID = ModelCatalog.default.id

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard acquireInstanceLock() else {
            logger.notice("Another Metagraf instance is already running; exiting duplicate process")
            NSApp.terminate(nil)
            return
        }

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

        // The user can turn the login item off in System Settings without the
        // app knowing, so trust the system rather than the stored preference.
        settings.launchAtLogin = LaunchAtLogin.isEnabled

        session.prewarm()
        startHotKeys()

        if !permissions.isReady {
            permissions.beginPolling()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotKeys.stop()
        releaseInstanceLock()
    }

    // MARK: - Delivery

    private func deliver(_ transcript: String) async throws {
        let target = target
        record(transcript, target: target)

        let strategy = settings.insertion(forBundleIdentifier: target?.bundleIdentifier)
        try await inserter.insert(transcript, using: strategy)
    }

    private func record(_ transcript: String, target: NSRunningApplication?) {
        // Prompting may deliberately incorporate relevant nearby content. Keep
        // the entire result ephemeral so opted-in context never enters History.
        guard !session.refinement.isPrompting else {
            startedAt = nil
            return
        }
        guard let history else { return }

        let duration = startedAt.map { Date.now.timeIntervalSince($0) } ?? 0
        startedAt = nil

        history.record(
            Transcript(
                text: transcript,
                localeIdentifier: settings.effectiveLocale.identifier,
                engineIdentifier: session.engineIdentifier.rawValue,
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
                let destination: RefinementDestinationContext
                if (settings.refinementStyle == .intelligent || settings.usesPromptingRefinement),
                   settings.usesNearbyAppContext {
                    destination = focusedContextReader.capture(applicationName: target?.localizedName)
                } else {
                    destination = RefinementDestinationContext(applicationName: target?.localizedName)
                }
                // Picked up fresh each time so changing the language or adding a
                // vocabulary term takes effect on the very next dictation.
                session.configuration = EngineConfiguration(
                    locale: settings.effectiveLocale,
                    contextualStrings: settings.contextualStrings
                )
                session.refinement = RefinementContext(
                    style: settings.refinementStyle,
                    persona: settings.refinementPersona,
                    personaAdaptation: settings.personaAdaptation,
                    locale: settings.effectiveLocale,
                    vocabulary: settings.vocabulary,
                    destination: destination
                )
            }

            // The hotkey is a bare modifier with no visible press, so the cue is
            // the only confirmation that dictation actually started.
            switch activation {
            case .began: feedback.play(.started)
            case .completed: feedback.play(.finished)
            case .cancelled, .aborted: feedback.play(.cancelled)
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

    /// Pushes the user's preferences into the pieces that hold their own copy.
    func applySettings() {
        feedback.isEnabled = settings.playsSounds
        pill?.reposition()

        hotKeys.binding = ModifierKey(rawValue: settings.hotKey) ?? .rightOption
        hotKeys.machine.minimumHold = settings.minimumHold
        hotKeys.machine.doubleTapWindow = settings.doubleTapWindow

        let model = EngineFactory.resolve(modelID: settings.modelID, store: models)
        if model.id != activeModelID {
            session.use(EngineFactory.make(for: model, store: models))
            activeModelID = model.id
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

    // MARK: - Single instance

    /// Only one process may own the global hotkey. A kernel-backed file lock is
    /// released automatically if the process crashes, unlike a sentinel file.
    private func acquireInstanceLock() -> Bool {
        guard instanceLockFileDescriptor == -1 else { return true }

        let lockURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(Metagraf.bundleIdentifier).instance.lock")
        let descriptor = Darwin.open(
            lockURL.path,
            O_CREAT | O_RDWR,
            S_IRUSR | S_IWUSR
        )
        guard descriptor >= 0 else {
            logger.error("Could not create the single-instance lock")
            return false
        }

        guard Darwin.lockf(descriptor, F_TLOCK, 0) == 0 else {
            Darwin.close(descriptor)
            return false
        }

        instanceLockFileDescriptor = descriptor
        return true
    }

    private func releaseInstanceLock() {
        guard instanceLockFileDescriptor >= 0 else { return }
        _ = Darwin.lockf(instanceLockFileDescriptor, F_ULOCK, 0)
        Darwin.close(instanceLockFileDescriptor)
        instanceLockFileDescriptor = -1
    }
}

extension HotKeyMonitor.Activation: Equatable {}
#endif
