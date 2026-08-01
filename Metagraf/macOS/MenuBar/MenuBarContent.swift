#if os(macOS)
import MetagrafCore
import SwiftUI

/// Contents of the menu bar popover. Filled in during M2.
struct MenuBarContent: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Metagraf")
                .font(.headline)

            Text("Hold the dictation hotkey to start talking.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Divider()

            Button("Open Metagraf") { openWindow(id: MetagrafWindow.main.rawValue) }
            Button("Settings…") { openSettings() }
            Button("Quit Metagraf") { NSApplication.shared.terminate(nil) }
        }
        .buttonStyle(.plain)
        .padding(16)
        .frame(width: 260, alignment: .leading)
    }
}

#Preview {
    MenuBarContent()
}
#endif
