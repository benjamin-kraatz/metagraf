#if os(macOS)
import MetagrafCore
import SwiftUI

/// The always-visible dictation indicator.
///
/// It stays small and quiet when idle, grows while the user speaks, and reports
/// what went wrong when something fails — so the state of dictation is never a
/// mystery, but it also never demands attention.
struct PillView: View {
    let session: DictationSession
    let settings: SettingsStore

    private static let barCount = 30
    @State private var history = [Float](repeating: 0, count: PillView.barCount)

    /// Hidden entirely when idle if the user asked for that, rather than merely
    /// dimmed — an always-on indicator is a matter of taste.
    private var isHidden: Bool {
        session.phase == .idle && !settings.showPillWhenIdle
    }

    var body: some View {
        HStack(spacing: 10) {
            leading
            trailing
        }
        .opacity(isHidden ? 0 : 1)
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(minWidth: 78)
        .fixedSize()
        .glassEffect(.clear, in: .capsule)
        // Only phase changes animate. Animating on `liveText` re-ran a 0.3s
        // geometry animation over the whole pill for every recognized token,
        // which visibly stalled the meter's own much faster animation.
        .animation(.smooth(duration: 0.3), value: session.phase)
        .animation(.smooth(duration: 0.25), value: isHidden)
        .onChange(of: session.level) { _, level in
            history.removeFirst()
            history.append(level)
        }
        .onChange(of: session.phase) { _, phase in
            if phase != .recording {
                history = [Float](repeating: 0, count: Self.barCount)
            }
        }
    }

    // MARK: - Pieces

    @ViewBuilder
    private var leading: some View {
        switch session.phase {
        case .idle:
            Image(systemName: "waveform")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)

        case .preparing, .transcribing, .refining, .inserting:
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.7)
                .frame(width: 14, height: 14)

        case .recording:
            meter

        case .copied:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.green)

        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.orange)
        }
    }

    @ViewBuilder
    private var trailing: some View {
        switch session.phase {
        case .idle:
            EmptyView()

        case .preparing:
            label("Getting ready…")

        case .recording:
            // A fixed width keeps the capsule's geometry stable for the whole
            // utterance, so arriving words never relayout the pill.
            HStack(spacing: 10) {
                Group {
                    if session.liveText.isEmpty {
                        label("Listening…")
                    } else {
                        Text(session.liveText)
                            .font(.system(size: 12))
                            .lineLimit(1)
                            .truncationMode(.head)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                elapsed
            }
            .frame(width: 320)

        case .refining:
            label("Tidying up…")

        case .inserting:
            label("Inserting…")

        case .transcribing:
            label("Transcribing…")

        case .copied(let message), .failed(let message):
            Text(message)
                .font(.system(size: 12))
                .lineLimit(2)
                .frame(maxWidth: 300, alignment: .leading)
        }
    }

    private var meter: some View {
        HStack(alignment: .center, spacing: 2) {
            ForEach(Array(history.enumerated()), id: \.offset) { _, value in
                Capsule(style: .continuous)
                    .fill(.tint)
                    .frame(width: 2.5, height: max(3, CGFloat(value) * 20))
            }
        }
        .frame(height: 20)
        .animation(.linear(duration: 0.09), value: history)
    }

    private var elapsed: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { context in
            let seconds = session.recordingStartedAt.map {
                context.date.timeIntervalSince($0)
            } ?? 0
            Text(Duration.seconds(max(0, seconds)), format: .time(pattern: .minuteSecond))
                .font(.system(size: 12, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }

    private func label(_ text: LocalizedStringKey) -> some View {
        Text(text)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
    }

    private var tint: Color? {
        switch session.phase {
        case .recording: .accentColor.opacity(0.35)
        case .copied: .green.opacity(0.3)
        case .failed: .orange.opacity(0.3)
        default: nil
        }
    }
}

#Preview("Idle") {
    PillView(session: DictationSession(), settings: SettingsStore())
        .padding(40)
}
#endif
