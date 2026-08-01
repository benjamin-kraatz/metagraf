#if os(macOS)
import AppKit
import MetagrafCore

/// Short audible cues for the start and end of dictation.
///
/// Worth having because the hotkey is a bare modifier with no visible press:
/// without a cue there is no confirmation that dictation actually started until
/// words appear, by which point the user may have spoken over the beginning.
@MainActor
final class FeedbackPlayer {
    enum Cue {
        case started
        case finished
        case cancelled
        case failed

        /// System sounds rather than bundled assets, so the cues match what the
        /// rest of the OS sounds like.
        var soundName: String {
            switch self {
            case .started: "Tink"
            case .finished: "Pop"
            case .cancelled: "Bottle"
            case .failed: "Funk"
            }
        }
    }

    var isEnabled = true

    /// Held so a rapid sequence does not cut its predecessor off mid-play.
    private var sounds: [String: NSSound] = [:]

    func play(_ cue: Cue) {
        guard isEnabled else { return }

        let sound: NSSound?
        if let cached = sounds[cue.soundName] {
            sound = cached
        } else {
            sound = NSSound(named: cue.soundName)
            sounds[cue.soundName] = sound
        }

        guard let sound else { return }
        if sound.isPlaying { sound.stop() }
        sound.play()
    }
}
#endif
