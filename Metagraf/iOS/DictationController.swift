#if os(iOS)
import Foundation
import MetagrafCore
import OSLog
import UIKit

/// Owns the pieces the iOS app keeps alive: the dictation session, settings,
/// and history.
///
/// The macOS equivalent is `AppDelegate`. On iOS there is no frontmost app to
/// insert into, so a finished transcript goes to the clipboard and the user
/// decides where it lands — except in the keyboard extension, which inserts
/// directly.
@MainActor
@Observable
final class DictationController {
    let session = DictationSession()
    let settings = SettingsStore.shared
    private(set) var history: HistoryStore?

    /// Set when the last transcript was copied, so the UI can confirm it.
    private(set) var didCopyAt: Date?

    private let logger = Logger(subsystem: Metagraf.bundleIdentifier, category: "App")
    private var startedAt: Date?

    init() {
        do {
            let history = try HistoryStore(inMemory: false)
            history.prune(retentionDays: settings.retentionDays)
            self.history = history
        } catch {
            logger.error("History unavailable: \(error.localizedDescription, privacy: .public)")
        }

        session.deliver = { [weak self] transcript in
            self?.deliver(transcript)
        }

        session.prewarm()
    }

    var isRecording: Bool { session.phase == .recording }

    func toggle() async {
        if session.phase == .recording {
            await session.complete()
        } else if !session.phase.isBusy {
            applySettings()
            startedAt = .now
            await session.begin()
        }
    }

    func cancel() async {
        await session.abort()
    }

    /// Picked up fresh each time so a changed language or a new vocabulary term
    /// takes effect on the very next dictation.
    private func applySettings() {
        session.configuration = EngineConfiguration(
            locale: settings.effectiveLocale,
            contextualStrings: settings.contextualStrings
        )
        session.refinement = RefinementContext(
            style: settings.refinementStyle,
            locale: settings.effectiveLocale,
            vocabulary: settings.vocabulary
        )
    }

    private func deliver(_ transcript: String) {
        UIPasteboard.general.string = transcript
        didCopyAt = .now
        // Shared with the keyboard, which cannot dictate but can insert this.
        RecentTranscripts.shared.add(transcript)
        record(transcript)
    }

    private func record(_ transcript: String) {
        guard let history else { return }

        let duration = startedAt.map { Date.now.timeIntervalSince($0) } ?? 0
        startedAt = nil

        history.record(
            Transcript(
                text: transcript,
                localeIdentifier: settings.effectiveLocale.identifier,
                engineIdentifier: session.engineIdentifier.rawValue,
                durationSeconds: duration
            ),
            retentionDays: settings.retentionDays
        )
    }
}
#endif
