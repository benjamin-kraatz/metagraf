#if os(macOS)
import MetagrafCore
import SwiftUI

/// Status item glyph. It mirrors the pill so the state of dictation is legible
/// even when the pill is on another screen.
struct MenuBarIcon: View {
    let session: DictationSession

    var body: some View {
        Image(systemName: symbol)
            .symbolEffect(.variableColor.iterative, isActive: session.phase == .recording)
    }

    private var symbol: String {
        switch session.phase {
        case .idle: "waveform"
        case .preparing, .transcribing: "waveform.badge.magnifyingglass"
        case .recording: "waveform.badge.mic"
        case .failed: "waveform.badge.exclamationmark"
        }
    }
}
#endif
