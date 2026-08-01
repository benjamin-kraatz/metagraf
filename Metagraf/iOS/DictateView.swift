#if os(iOS)
import MetagrafCore
import SwiftUI

/// The main screen: a single large control that listens while held.
struct DictateView: View {
    let controller: DictationController

    private var session: DictationSession { controller.session }

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Spacer()

                transcriptArea

                Spacer()

                RecordButton(session: session) {
                    await controller.toggle()
                }

                Text(hint)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(height: 44)
                    .animation(.smooth, value: session.phase)

                Spacer(minLength: 12)
            }
            .padding(.horizontal, 24)
            .navigationTitle("Metagraf")
        }
    }

    @ViewBuilder
    private var transcriptArea: some View {
        switch session.phase {
        case .recording where !session.liveText.isEmpty:
            ScrollView {
                Text(session.liveText)
                    .font(.title3)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .defaultScrollAnchor(.bottom)
            .frame(maxHeight: 260)

        case .idle where !session.lastTranscript.isEmpty:
            LastTranscript(text: session.lastTranscript)

        case .failed(let message):
            ContentUnavailableView(
                "That didn’t work",
                systemImage: "exclamationmark.triangle",
                description: Text(message)
            )

        default:
            LevelMeter(level: session.level, isActive: session.phase == .recording)
        }
    }

    private var hint: LocalizedStringKey {
        switch session.phase {
        case .idle: "Tap and hold to dictate. Your words never leave this iPhone."
        case .preparing: "Getting ready…"
        case .recording: "Listening — let go when you’re done."
        case .transcribing: "Transcribing…"
        case .refining: "Tidying up…"
        case .inserting: "Copying…"
        case .failed: ""
        }
    }
}

// MARK: - Record button

private struct RecordButton: View {
    let session: DictationSession
    let action: () async -> Void

    @State private var isPressed = false

    private var isRecording: Bool { session.phase == .recording }

    var body: some View {
        ZStack {
            Circle()
                .fill(isRecording ? AnyShapeStyle(.red.opacity(0.18)) : AnyShapeStyle(.tint.opacity(0.14)))
                .frame(width: 148, height: 148)
                .scaleEffect(isRecording ? 1 + CGFloat(session.level) * 0.22 : 1)
                .animation(.smooth(duration: 0.12), value: session.level)

            Circle()
                .fill(isRecording ? AnyShapeStyle(.red) : AnyShapeStyle(.tint))
                .frame(width: 104, height: 104)
                .scaleEffect(isPressed ? 0.94 : 1)

            Image(systemName: isRecording ? "waveform" : "mic.fill")
                .font(.system(size: 38, weight: .medium))
                .foregroundStyle(.white)
                .symbolEffect(.variableColor.iterative, isActive: isRecording)
        }
        .contentShape(.circle)
        // A hold gesture rather than a toggle, matching the Mac: speaking while
        // holding is what makes dictation feel like a key rather than a mode.
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !isPressed else { return }
                    isPressed = true
                    Task { await action() }
                }
                .onEnded { _ in
                    isPressed = false
                    Task { await action() }
                }
        )
        .disabled(session.phase.isBusy && !isRecording)
        .animation(.smooth(duration: 0.18), value: isPressed)
        .animation(.smooth(duration: 0.25), value: isRecording)
        .accessibilityLabel("Dictate")
        .accessibilityHint("Hold to record, release to transcribe")
    }
}

// MARK: - Pieces

private struct LevelMeter: View {
    let level: Float
    let isActive: Bool

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<18, id: \.self) { index in
                Capsule()
                    .fill(.tint.opacity(isActive ? 0.85 : 0.18))
                    .frame(width: 5, height: height(for: index))
            }
        }
        .frame(height: 70)
        .animation(.smooth(duration: 0.12), value: level)
    }

    /// A shape that peaks in the middle, so an idle meter still reads as a
    /// waveform rather than a flat line.
    private func height(for index: Int) -> CGFloat {
        let distance = abs(Double(index) - 8.5) / 8.5
        let envelope = 1 - distance * 0.65
        let amplitude = isActive ? Double(level) : 0.12
        return max(6, 62 * envelope * max(0.12, amplitude))
    }
}

private struct LastTranscript: View {
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Copied to the clipboard", systemImage: "checkmark.circle.fill")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.green)

            ScrollView {
                Text(text)
                    .font(.title3)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 220)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 16))
    }
}
#endif
