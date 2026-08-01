#if os(macOS)
import MetagrafCore
import SwiftUI

/// Contents of the menu bar popover.
struct MenuBarContent: View {
    let session: DictationSession
    let permissions: PermissionsCoordinator

    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if !permissions.isReady {
                permissionWarning
            }

            if !session.lastTranscript.isEmpty {
                lastTranscript
            }

            Divider()

            VStack(alignment: .leading, spacing: 2) {
                menuButton("Open Metagraf", symbol: "waveform") {
                    openWindow(id: MetagrafWindow.main.rawValue)
                    NSApp.activate(ignoringOtherApps: true)
                }
                menuButton("Settings…", symbol: "gearshape") {
                    openSettings()
                    NSApp.activate(ignoringOtherApps: true)
                }
                menuButton("Quit Metagraf", symbol: "power") {
                    NSApp.terminate(nil)
                }
            }
        }
        .padding(14)
        .frame(width: 290, alignment: .leading)
        .onAppear { permissions.refresh() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 7) {
                Circle()
                    .fill(statusColor)
                    .frame(width: 7, height: 7)
                Text(statusTitle)
                    .font(.headline)
            }

            Text("Hold \(ModifierKey.rightOption.displayName) anywhere to dictate.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var permissionWarning: some View {
        Button {
            openWindow(id: MetagrafWindow.onboarding.rawValue)
            NSApp.activate(ignoringOtherApps: true)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Setup isn’t finished")
                        .font(.callout.weight(.medium))
                    Text("Dictation stays off until permissions are granted.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.orange.opacity(0.12), in: .rect(cornerRadius: 10))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
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

            Button("Copy again") {
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
        case .idle: permissions.isReady ? "Ready" : "Needs setup"
        case .preparing: "Getting ready…"
        case .recording: "Listening"
        case .transcribing: "Transcribing…"
        case .inserting: "Inserting…"
        case .failed(let message): message
        }
    }

    private var statusColor: Color {
        switch session.phase {
        case .idle: permissions.isReady ? .green : .orange
        case .recording: .red
        case .failed: .orange
        default: .yellow
        }
    }

    private func menuButton(
        _ title: String,
        symbol: String,
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
