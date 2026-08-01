import MetagrafCore
import SwiftUI

/// The keyboard's face.
struct KeyboardView: View {
    let model: KeyboardModel

    var body: some View {
        VStack(spacing: 14) {
            if model.hasFullAccess {
                status
                Spacer(minLength: 0)
                controls
            } else {
                fullAccessNeeded
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Pieces

    @ViewBuilder
    private var status: some View {
        switch model.phase {
        case .recording where !model.session.liveText.isEmpty:
            Text(model.session.liveText)
                .font(.callout)
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)

        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.footnote)
                .foregroundStyle(.orange)
                .frame(maxWidth: .infinity, alignment: .leading)

        default:
            Text(hint)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var hint: LocalizedStringKey {
        switch model.phase {
        case .idle: "Hold the button and speak."
        case .preparing: "Getting ready…"
        case .recording: "Listening…"
        case .transcribing: "Transcribing…"
        case .refining: "Tidying up…"
        case .inserting: "Inserting…"
        case .failed: ""
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            KeyButton(symbol: "globe", label: "Switch keyboard") {
                model.nextKeyboard()
            }

            MicButton(model: model)

            KeyButton(symbol: "delete.left", label: "Delete") {
                model.deleteBackwards()
            }
        }
    }

    private var fullAccessNeeded: some View {
        VStack(spacing: 10) {
            Image(systemName: "lock")
                .font(.system(size: 26))
                .foregroundStyle(.secondary)

            Text("Metagraf needs Full Access")
                .font(.headline)

            Text(
                """
                Turn on Allow Full Access in Settings → General → Keyboard → \
                Keyboards → Metagraf. It is what lets the keyboard reach the \
                microphone. Your speech is still transcribed on this iPhone.
                """
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)

            Button("Use another keyboard") { model.nextKeyboard() }
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Buttons

private struct MicButton: View {
    let model: KeyboardModel

    @State private var isPressed = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(model.isRecording ? AnyShapeStyle(.red) : AnyShapeStyle(.tint))

            HStack(spacing: 8) {
                Image(systemName: model.isRecording ? "waveform" : "mic.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .symbolEffect(.variableColor.iterative, isActive: model.isRecording)
                Text(model.isRecording ? "Listening" : "Hold to dictate")
                    .font(.callout.weight(.semibold))
            }
            .foregroundStyle(.white)
        }
        .frame(height: 62)
        .scaleEffect(isPressed ? 0.97 : 1)
        .contentShape(.rect)
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in
                    guard !isPressed else { return }
                    isPressed = true
                    Task { await model.startRecording() }
                }
                .onEnded { _ in
                    isPressed = false
                    Task { await model.finishRecording() }
                }
        )
        .animation(.smooth(duration: 0.15), value: isPressed)
        .animation(.smooth(duration: 0.2), value: model.isRecording)
        .accessibilityLabel("Dictate")
        .accessibilityHint("Hold to record, release to insert")
    }
}

private struct KeyButton: View {
    let symbol: String
    let label: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 18, weight: .medium))
                .frame(width: 54, height: 62)
                .background(.quaternary, in: .rect(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
