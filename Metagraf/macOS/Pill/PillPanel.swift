#if os(macOS)
import AppKit

/// The floating window that hosts the dictation pill.
///
/// `nonactivatingPanel` is the critical trait: showing the pill must never take
/// focus away from whatever the user is typing into, because that app is where
/// the transcript has to land.
final class PillPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        // Keep the floating pill out of the Dock's window list and Window menu.
        isExcludedFromWindowsMenu = true

        // The panel is a transparent canvas larger than the pill itself, so
        // clicks must fall through to whatever is underneath.
        ignoresMouseEvents = true
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}
#endif
