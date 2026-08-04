#if os(iOS)
import AVFAudio
import Foundation

/// Short, quiet confirmation tones for mobile dictation.
///
/// The bundled samples avoid undocumented system-sound identifiers. The
/// default audio session respects Silent Mode and does not claim media playback.
@MainActor
final class MobileFeedbackPlayer {
    enum Cue {
        case started
        case finished

        var resourceName: String {
            switch self {
            case .started: "dictation-start"
            case .finished: "dictation-finish"
            }
        }
    }

    var isEnabled = true

    private var players: [AVAudioPlayer] = []

    func play(_ cue: Cue) {
        guard isEnabled else { return }

        guard let url = Bundle.main.url(forResource: cue.resourceName, withExtension: "wav") else {
            return
        }

        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.prepareToPlay()
            player.play()
            players.removeAll { !$0.isPlaying }
            players.append(player)
        } catch {
            // Feedback is optional and must never interfere with dictation.
        }
    }

}
#endif
