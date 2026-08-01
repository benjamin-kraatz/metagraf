#if os(macOS)
import AppKit
import MetagrafCore
import SwiftUI

/// Owns the pill panel and keeps it parked above the Dock.
@MainActor
final class PillWindowController {
    /// The panel is a transparent canvas wide enough for the pill at its
    /// largest; the capsule sizes itself inside and animates freely without the
    /// window ever having to resize.
    private static let canvasSize = NSSize(width: 620, height: 90)

    /// Gap between the pill and the bottom of the screen's visible area.
    private static let bottomInset: CGFloat = 26

    private let panel: PillPanel
    private var screenObserver: (any NSObjectProtocol)?

    init(session: DictationSession) {
        panel = PillPanel(contentRect: NSRect(origin: .zero, size: Self.canvasSize))

        let host = NSHostingView(
            rootView: PillView(session: session)
                .frame(width: Self.canvasSize.width, height: Self.canvasSize.height)
        )
        panel.contentView = host

        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.reposition() }
        }
    }

    isolated deinit {
        if let screenObserver {
            NotificationCenter.default.removeObserver(screenObserver)
        }
    }

    func show() {
        reposition()
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    /// Centers the pill along the bottom of the active screen.
    func reposition() {
        guard let screen = activeScreen() else { return }
        let visible = screen.visibleFrame
        let origin = NSPoint(
            x: visible.midX - Self.canvasSize.width / 2,
            y: visible.minY + Self.bottomInset
        )
        panel.setFrame(NSRect(origin: origin, size: Self.canvasSize), display: false)
    }

    /// The screen the user is currently working on, which is the one holding
    /// the pointer rather than whichever screen is nominally "main".
    private func activeScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
    }
}
#endif
