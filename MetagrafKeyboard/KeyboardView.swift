import MetagrafCore
import SwiftUI

/// The keyboard's face: things you have dictated, ready to drop in.
struct KeyboardView: View {
    let model: KeyboardModel

    var body: some View {
        VStack(spacing: 0) {
            if model.hasFullAccess {
                content
            } else {
                fullAccessNeeded
            }
            controls
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if model.transcripts.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "waveform")
                    .font(.system(size: 22))
                    .foregroundStyle(.secondary)
                Text("Nothing dictated yet")
                    .font(.callout.weight(.medium))
                Text("Dictate in the Metagraf app and it will show up here.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 6) {
                    ForEach(model.transcripts) { transcript in
                        TranscriptChip(
                            transcript: transcript,
                            wasJustInserted: model.justInserted == transcript.id,
                            insert: { model.insert(transcript) },
                            delete: { model.delete(transcript) }
                        )
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxHeight: .infinity)
        }
    }

    private var fullAccessNeeded: some View {
        VStack(spacing: 8) {
            Image(systemName: "lock")
                .font(.system(size: 22))
                .foregroundStyle(.secondary)
            Text("Metagraf needs Full Access")
                .font(.callout.weight(.medium))
            Text(
                """
                Turn on Allow Full Access in Settings → General → Keyboard → \
                Keyboards → Metagraf. It is what lets this keyboard read what \
                you dictated in the app.
                """
            )
            .font(.footnote)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var controls: some View {
        HStack(spacing: 8) {
            KeyButton(symbol: "globe", label: "Switch keyboard") {
                model.nextKeyboard()
            }

            Text("Metagraf")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)

            KeyButton(symbol: "delete.left", label: "Delete") {
                model.deleteBackwards()
            }
        }
        .padding(.top, 6)
    }
}

// MARK: - Pieces

private struct TranscriptChip: View {
    let transcript: RecentTranscript
    let wasJustInserted: Bool
    let insert: () -> Void
    let delete: () -> Void

    var body: some View {
        Button(action: insert) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(transcript.text)
                        .font(.callout)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text(transcript.createdAt, format: .relative(presentation: .named))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Image(systemName: wasJustInserted ? "checkmark.circle.fill" : "arrow.down.left.circle")
                    .font(.system(size: 17))
                    .foregroundStyle(wasJustInserted ? AnyShapeStyle(.green) : AnyShapeStyle(.tint))
            }
            .padding(10)
            .background(.quaternary.opacity(0.5), in: .rect(cornerRadius: 12, style: .continuous))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .animation(.smooth(duration: 0.2), value: wasJustInserted)
        .contextMenu {
            Button("Remove", systemImage: "trash", role: .destructive, action: delete)
        }
        .accessibilityLabel(transcript.text)
        .accessibilityHint("Inserts this text")
    }
}

private struct KeyButton: View {
    let symbol: String
    let label: LocalizedStringKey
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .frame(width: 50, height: 40)
                .background(.quaternary, in: .rect(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
