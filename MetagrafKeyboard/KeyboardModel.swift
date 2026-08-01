import Foundation
import MetagrafCore
import OSLog

/// Drives the keyboard's dictation.
///
/// Uses Apple's `SpeechAnalyzer` only. A keyboard extension runs under a hard
/// memory limit, and Whisper weights would not fit; Apple's engine runs out of
/// process, so the transcription happens somewhere the keyboard does not pay
/// for it.
@MainActor
@Observable
final class KeyboardModel {
    let session = DictationSession()
    let hasFullAccess: Bool

    private let logger = Logger(subsystem: Metagraf.bundleIdentifier, category: "Keyboard")
    private let settings: SettingsStore
    private let insert: (String) -> Void
    private let deleteBackward: () -> Void
    private let advance: () -> Void

    init(
        hasFullAccess: Bool,
        insert: @escaping (String) -> Void,
        deleteBackward: @escaping () -> Void,
        advanceToNextKeyboard: @escaping () -> Void
    ) {
        self.hasFullAccess = hasFullAccess
        self.insert = insert
        self.deleteBackward = deleteBackward
        self.advance = advanceToNextKeyboard

        // Without Full Access the shared container is unreachable, so the
        // keyboard falls back to its own defaults rather than failing outright.
        self.settings = hasFullAccess ? SettingsStore.shared : SettingsStore(defaults: .standard)

        session.deliver = { [weak self] transcript in
            self?.insert(transcript)
        }
    }

    var phase: DictationSession.Phase { session.phase }
    var isRecording: Bool { session.phase == .recording }

    func startRecording() async {
        guard !session.phase.isBusy else { return }

        session.configuration = EngineConfiguration(
            locale: settings.effectiveLocale,
            contextualStrings: settings.contextualStrings
        )
        session.refinement = RefinementContext(
            style: settings.refinementStyle,
            locale: settings.effectiveLocale,
            vocabulary: settings.vocabulary
        )

        await session.begin()
    }

    func finishRecording() async {
        guard session.phase == .recording else { return }
        await session.complete()
    }

    func cancel() async {
        await session.abort()
    }

    /// Tears everything down synchronously enough to survive the extension
    /// being dismissed.
    func stopImmediately() {
        Task { await session.abort() }
    }

    func deleteBackwards() {
        deleteBackward()
    }

    func insertSpace() {
        insert(" ")
    }

    func insertReturn() {
        insert("\n")
    }

    func nextKeyboard() {
        advance()
    }
}
