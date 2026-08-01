import Foundation
import MetagrafCore
import OSLog

/// Drives the Metagraf keyboard.
///
/// The keyboard does not dictate. iOS refuses microphone access to app
/// extensions — keyboards are sandboxed against audio keylogging, and no
/// entitlement or Full Access switch changes that. So the split is: the app
/// captures speech, and the keyboard puts the result where the caret is,
/// without the user leaving the field they are typing in.
@MainActor
@Observable
final class KeyboardModel {
    let hasFullAccess: Bool

    private(set) var transcripts: [RecentTranscript] = []
    private(set) var justInserted: RecentTranscript.ID?

    private let logger = Logger(subsystem: Metagraf.bundleIdentifier, category: "Keyboard")
    private let recents = RecentTranscripts.shared
    private let insertText: (String) -> Void
    private let deleteBackward: () -> Void
    private let advance: () -> Void

    init(
        hasFullAccess: Bool,
        insert: @escaping (String) -> Void,
        deleteBackward: @escaping () -> Void,
        advanceToNextKeyboard: @escaping () -> Void
    ) {
        self.hasFullAccess = hasFullAccess
        self.insertText = insert
        self.deleteBackward = deleteBackward
        self.advance = advanceToNextKeyboard
    }

    /// Re-reads the shared list. Called every time the keyboard appears, since
    /// the app may have dictated something since it was last on screen.
    func refresh() {
        guard hasFullAccess else { return }
        transcripts = recents.all()
    }

    func insert(_ transcript: RecentTranscript) {
        insertText(transcript.text)
        justInserted = transcript.id
    }

    func delete(_ transcript: RecentTranscript) {
        recents.remove(transcript)
        refresh()
    }

    func deleteBackwards() {
        deleteBackward()
    }

    func nextKeyboard() {
        advance()
    }
}
