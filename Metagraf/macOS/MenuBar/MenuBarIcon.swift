#if os(macOS)
import MetagrafCore
import SwiftUI

/// Status item glyph. It mirrors the pill so the state of dictation is legible
/// even when the pill is on another screen.
struct MenuBarIcon: View {
    let session: DictationSession
    let permissions: PermissionsCoordinator

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Image(systemName: symbol)
            .symbolEffect(.variableColor.iterative, isActive: session.phase == .recording)
            .task {
                // The status item is the only view that exists from launch in an
                // agent app, so first-run onboarding is triggered from here.
                guard !permissions.isReady else { return }
                openWindow(id: MetagrafWindow.onboarding.rawValue)
            }
            .onReceive(NotificationCenter.default.publisher(for: .metagrafOpenMainWindow)) { _ in
                openWindow(id: MetagrafWindow.main.rawValue)
                Task { @MainActor in
                    await Task.yield()
                    guard let window = NSApp.windows.first(where: {
                        $0.identifier?.rawValue == MetagrafWindow.main.rawValue
                    }) else { return }
                    window.makeKeyAndOrderFront(nil)
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
    }

    private var symbol: String {
        switch session.phase {
        case .idle: "waveform"
        case .preparing, .transcribing, .refining, .inserting: "waveform.badge.magnifyingglass"
        case .recording: "waveform.badge.mic"
        case .copied: "waveform.badge.checkmark"
        case .failed: "waveform.badge.exclamationmark"
        }
    }
}
#endif
