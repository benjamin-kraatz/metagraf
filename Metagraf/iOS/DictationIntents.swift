#if os(iOS)
import AppIntents
import MetagrafCore
import SwiftUI

/// Signals that something outside the UI asked for dictation to start.
///
/// An App Intent that opens the app runs in the app's process, but it may run
/// before the dictation screen exists, so the request is parked here and picked
/// up when the view appears.
@MainActor
@Observable
final class DictationLaunchRequest {
    static let shared = DictationLaunchRequest()
    var isPending = false
}

/// Starts dictation from the Action Button, Control Center, or a Shortcut.
///
/// It has to open the app: iOS only lets the microphone be used by a
/// foreground app, so there is no version of this that records in the
/// background.
struct StartDictationIntent: AppIntent {
    static let title: LocalizedStringResource = "Start Dictation"
    static let description = IntentDescription(
        "Opens Metagraf and starts listening straight away."
    )
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        DictationLaunchRequest.shared.isPending = true
        return .result()
    }
}

/// Returns the most recent transcript, for use in a Shortcut without opening
/// the app.
struct LastTranscriptIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Last Transcript"
    static let description = IntentDescription(
        "Returns the most recent thing you dictated."
    )
    static let openAppWhenRun = false

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> {
        let text = RecentTranscripts.shared.all().first?.text ?? ""
        return .result(value: text)
    }
}

/// Phrases Siri and Spotlight offer without the user setting anything up.
struct MetagrafShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: StartDictationIntent(),
            phrases: [
                "Dictate with \(.applicationName)",
                "Start dictation in \(.applicationName)",
            ],
            shortTitle: "Dictate",
            systemImageName: "mic.fill"
        )
        AppShortcut(
            intent: LastTranscriptIntent(),
            phrases: ["Get my last \(.applicationName) transcript"],
            shortTitle: "Last transcript",
            systemImageName: "clock"
        )
    }
}
#endif
