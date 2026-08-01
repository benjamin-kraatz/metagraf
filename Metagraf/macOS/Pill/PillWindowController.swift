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

    /// Gap between the pill and the edge of the screen's visible area.
    private static let edgeInset: CGFloat = 26

    private let panel: PillPanel
    private let settings: SettingsStore
    private var screenObserver: (any NSObjectProtocol)?

    init(session: DictationSession, settings: SettingsStore) {
        self.settings = settings
        panel = PillPanel(contentRect: NSRect(origin: .zero, size: Self.canvasSize))

        let host = NSHostingView(
            rootView: PillView(session: session, settings: settings)
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

    /// Parks the pill at the chosen anchor of the active screen.
    func reposition() {
        guard let screen = activeScreen() else { return }
        let visible = screen.visibleFrame
        let size = Self.canvasSize

        let x: CGFloat = switch settings.pillPlacement {
        case .bottomCenter, .topCenter: visible.midX - size.width / 2
        case .bottomLeading: visible.minX + Self.edgeInset
        case .bottomTrailing: visible.maxX - size.width - Self.edgeInset
        }

        let y: CGFloat = settings.pillPlacement.isTop
            ? visible.maxY - size.height - Self.edgeInset
            : visible.minY + Self.edgeInset

        panel.setFrame(NSRect(origin: NSPoint(x: x, y: y), size: size), display: false)
    }

    /// The screen the user is currently working on, which is the one holding
    /// the pointer rather than whichever screen is nominally "main".
    private func activeScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
    }
}
#endif
