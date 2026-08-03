#if os(macOS)
import MetagrafCore
import SwiftUI

/// Contents of the menu bar popover.
struct MenuBarContent: View {
    let session: DictationSession
    let permissions: PermissionsCoordinator
    let updates: UpdateController

    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header

            if !permissions.isReady {
                permissionWarning
            }

            if !session.lastTranscript.isEmpty {
                lastTranscript
            }

            Divider()

            VStack(alignment: .leading, spacing: 1) {
                menuButton("Open Metagraf") {
                    openMainWindow()
                }
                menuButton("Settings…") {
                    openSettings()
                    NSApp.activate(ignoringOtherApps: true)
                }
                menuButton("Check for Updates…") {
                    updates.checkForUpdates()
                }

                Divider()
                    .padding(.vertical, 3)

                menuButton("Quit Metagraf") {
                    NSApp.terminate(nil)
                }
            }
        }
        .padding(10)
        .frame(width: 260, alignment: .leading)
        .onAppear { permissions.refresh() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            statusTitle
                .font(.callout.weight(.semibold))

            Text("Hold \(ModifierKey.rightOption.displayName) anywhere to dictate.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
    }

    private var permissionWarning: some View {
        Button {
            openWindow(id: MetagrafWindow.onboarding.rawValue)
            NSApp.activate(ignoringOtherApps: true)
        } label: {
            HStack(spacing: 8) {
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
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.orange.opacity(0.12), in: .rect(cornerRadius: 6))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    private var lastTranscript: some View {
        VStack(alignment: .leading, spacing: 5) {
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
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 6)
    }

    private var statusTitle: Text {
        switch session.phase {
        case .idle where permissions.isReady: Text("Ready")
        case .idle: Text("Needs setup")
        case .preparing: Text("Getting ready…")
        case .recording: Text("Listening")
        case .transcribing: Text("Transcribing…")
        case .refining: Text("Tidying up…")
        case .inserting: Text("Inserting…")
        case .copied(let message), .failed(let message): Text(message)
        }
    }

    private func openMainWindow() {
        openWindow(id: MetagrafWindow.main.rawValue)

        // SwiftUI creates or reveals the window asynchronously. Wait for that
        // work before making it key; activating the accessory app alone can
        // leave the menu-bar popover as the focused window.
        Task { @MainActor in
            await Task.yield()
            guard let window = NSApp.windows.first(where: {
                $0.identifier?.rawValue == MetagrafWindow.main.rawValue
            }) else { return }

            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func menuButton(
        _ title: LocalizedStringKey,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 13))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .frame(height: 24)
                .contentShape(.rect)
        }
        .buttonStyle(MenuItemButtonStyle())
    }
}

private struct MenuItemButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        MenuItemButton(configuration: configuration)
    }

    private struct MenuItemButton: View {
        let configuration: Configuration
        @State private var isHovering = false

        var body: some View {
            configuration.label
                .foregroundStyle(isHovering ? .white : .primary)
                .background(
                    isHovering ? Color.accentColor : Color.clear,
                    in: .rect(cornerRadius: 4)
                )
                .opacity(configuration.isPressed ? 0.85 : 1)
                .onHover { isHovering = $0 }
        }
    }
}

#Preview {
    MenuBarContent(
        session: DictationSession(),
        permissions: PermissionsCoordinator(),
        updates: UpdateController()
    )
}
#endif
