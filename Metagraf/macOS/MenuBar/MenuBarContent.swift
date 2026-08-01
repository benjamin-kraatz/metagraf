#if os(macOS)
import MetagrafCore
import SwiftUI

/// Contents of the menu bar popover.
struct MenuBarContent: View {
    let session: DictationSession

    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if !session.lastTranscript.isEmpty {
                lastTranscript
            }

            Divider()

            VStack(alignment: .leading, spacing: 2) {
                menuButton("Open Metagraf", key: "waveform") {
                    openWindow(id: MetagrafWindow.main.rawValue)
                    NSApp.activate(ignoringOtherApps: true)
                }
                menuButton("Settings…", key: "gearshape") {
                    openSettings()
                    NSApp.activate(ignoringOtherApps: true)
                }
                menuButton("Quit Metagraf", key: "power") {
                    NSApp.terminate(nil)
                }
            }
        }
        .padding(14)
        .frame(width: 280, alignment: .leading)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(statusTitle)
                .font(.headline)
            Text("Hold \(ModifierKey.rightOption.displayName) anywhere to dictate.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var lastTranscript: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Last transcript")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(session.lastTranscript)
                .font(.callout)
                .lineLimit(3)
                .textSelection(.enabled)

            Button("Copy") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(session.lastTranscript, forType: .string)
            }
            .buttonStyle(.glass)
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var statusTitle: String {
        switch session.phase {
        case .idle: "Ready"
        case .preparing: "Getting ready…"
        case .recording: "Listening"
        case .transcribing: "Transcribing…"
        case .failed(let message): message
        }
    }

    private func menuButton(
        _ title: String,
        key symbol: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: symbol)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
#endif
