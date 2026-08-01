#if os(macOS)
import AppKit
import ApplicationServices
import Carbon.HIToolbox
import MetagrafCore
import OSLog

/// Gets a finished transcript into whatever app the user is typing in.
@MainActor
final class TextInserter {
    enum InsertionError: LocalizedError, Equatable {
        case secureInputActive
        case noFocusedTextField
        case notTrusted
        case eventCreationFailed

        var errorDescription: String? {
            switch self {
            case .secureInputActive:
                "Copied instead — a password field is capturing input."
            case .noFocusedTextField:
                "Copied instead — no text field is focused."
            case .notTrusted:
                "Metagraf needs Accessibility access to insert text."
            case .eventCreationFailed:
                "Copied instead — the system refused a synthetic keystroke."
            }
        }
    }

    private static let virtualKeyV = CGKeyCode(kVK_ANSI_V)

    /// How long to leave the transcript on the clipboard before restoring, so
    /// the target app has actually read it.
    private static let pasteboardRestoreDelay = Duration.milliseconds(450)

    private let logger = Logger(subsystem: Metagraf.bundleIdentifier, category: "Insertion")

    /// Inserts `text`, falling back to leaving it on the clipboard when the
    /// preferred route is unavailable. Throws only to explain that fallback —
    /// the text is on the clipboard either way, so nothing is ever lost.
    func insert(_ text: String, using strategy: InsertionStrategy) async throws {
        switch strategy {
        case .clipboardOnly:
            copyToPasteboard(text)

        case .accessibility:
            do {
                try insertViaAccessibility(text)
            } catch {
                logger.notice("Direct insertion failed, falling back to paste")
                try await paste(text)
            }

        case .paste:
            try await paste(text)
        }
    }

    // MARK: - Paste

    private func paste(_ text: String) async throws {
        // A password field puts the window server into secure input mode, where
        // synthetic keystrokes are dropped. Copying is the only honest option.
        guard !IsSecureEventInputEnabled() else {
            copyToPasteboard(text)
            throw InsertionError.secureInputActive
        }

        guard AXIsProcessTrusted() else {
            copyToPasteboard(text)
            throw InsertionError.notTrusted
        }

        let pasteboard = NSPasteboard.general
        let snapshot = PasteboardSnapshot(of: pasteboard)
        copyToPasteboard(text)

        // The dictation key is a modifier. In latched mode the user is holding
        // it as we insert, and a stray ⌥ would turn ⌘V into something else, so
        // wait for the keyboard to settle first.
        await waitForModifiersToClear()

        do {
            try postCommandV()
        } catch {
            snapshot.restore(to: pasteboard)
            copyToPasteboard(text)
            throw error
        }

        // Restoring immediately would race the target app's read of the
        // pasteboard, so give it a beat.
        Task {
            try? await Task.sleep(for: Self.pasteboardRestoreDelay)
            snapshot.restore(to: pasteboard)
        }
    }

    private func postCommandV() throws {
        guard
            let source = CGEventSource(stateID: .combinedSessionState),
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: Self.virtualKeyV, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: Self.virtualKeyV, keyDown: false)
        else {
            throw InsertionError.eventCreationFailed
        }

        // Setting flags explicitly rather than inheriting whatever is physically
        // held down.
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand

        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    /// Waits briefly for physically held modifiers to be released.
    private func waitForModifiersToClear() async {
        let interesting: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
        let deadline = ContinuousClock.now.advanced(by: .milliseconds(300))

        while ContinuousClock.now < deadline {
            let flags = CGEventSource.flagsState(.combinedSessionState)
            if flags.intersection(interesting).isEmpty { return }
            try? await Task.sleep(for: .milliseconds(15))
        }
    }

    // MARK: - Accessibility

    private func insertViaAccessibility(_ text: String) throws {
        guard AXIsProcessTrusted() else { throw InsertionError.notTrusted }

        let system = AXUIElementCreateSystemWide()
        var focused: AnyObject?
        let status = AXUIElementCopyAttributeValue(
            system,
            kAXFocusedUIElementAttribute as CFString,
            &focused
        )

        guard
            status == .success,
            let focused,
            CFGetTypeID(focused) == AXUIElementGetTypeID()
        else {
            throw InsertionError.noFocusedTextField
        }

        // Replacing the selection is what a keystroke would do: with an empty
        // selection it inserts at the caret, and with a selection it overwrites.
        let element = focused as! AXUIElement
        let result = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        )

        guard result == .success else { throw InsertionError.noFocusedTextField }
    }

    // MARK: - Clipboard

    private func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
#endif
