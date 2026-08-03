#if os(macOS)
import AppKit
import ApplicationServices
import Carbon.HIToolbox
import MetagrafCore
import OSLog

/// Gets a finished transcript into whatever app the user is typing in.
@MainActor
final class TextInserter {
    /// Outcome of an insertion attempt. Recoverable clipboard fallbacks are
    /// reported as `.copied` so the UI can confirm without treating them as
    /// hard failures.
    enum Result: Equatable {
        case inserted
        case copied(CopyReason)
    }

    enum CopyReason: Equatable {
        case secureInputActive
        case noFocusedTextField
        case eventCreationFailed
        case clipboardOnly

        var message: String {
            switch self {
            case .secureInputActive:
                String(localized: "Copied instead — a password field is capturing input.")
            case .noFocusedTextField:
                String(localized: "Copied instead — no text field is focused.")
            case .eventCreationFailed:
                String(localized: "Copied instead — the system refused a synthetic keystroke.")
            case .clipboardOnly:
                String(localized: "Copied to the clipboard")
            }
        }
    }

    enum InsertionError: LocalizedError, Equatable {
        case notTrusted

        var errorDescription: String? {
            String(localized: "Metagraf needs Accessibility access to insert text.")
        }
    }

    private static let virtualKeyV = CGKeyCode(kVK_ANSI_V)

    /// How long to leave the transcript on the clipboard before restoring, so
    /// the target app has actually read it.
    private static let pasteboardRestoreDelay = Duration.milliseconds(450)

    private let logger = Logger(subsystem: Metagraf.bundleIdentifier, category: "Insertion")

    /// Inserts `text`, falling back to leaving it on the clipboard when the
    /// preferred route is unavailable. Throws only for true failures where
    /// insertion could not proceed usefully; recoverable copy-fallback cases
    /// return `.copied` instead.
    @discardableResult
    func insert(_ text: String, using strategy: InsertionStrategy) async throws -> Result {
        switch strategy {
        case .clipboardOnly:
            copyToPasteboard(text)
            return .copied(.clipboardOnly)

        case .accessibility:
            do {
                try insertViaAccessibility(text)
                return .inserted
            } catch {
                logger.notice("Direct insertion failed, falling back to paste")
                return try await paste(text)
            }

        case .paste:
            return try await paste(text)
        }
    }

    // MARK: - Paste

    private func paste(_ text: String) async throws -> Result {
        // A password field puts the window server into secure input mode, where
        // synthetic keystrokes are dropped. Copying is the only honest option.
        guard !IsSecureEventInputEnabled() else {
            copyToPasteboard(text)
            return .copied(.secureInputActive)
        }

        guard AXIsProcessTrusted() else {
            copyToPasteboard(text)
            throw InsertionError.notTrusted
        }

        // Without a focused field, ⌘V would silently do nothing useful —
        // leave the transcript on the clipboard and say so.
        guard focusedUIElement() != nil else {
            copyToPasteboard(text)
            return .copied(.noFocusedTextField)
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
            return .copied(.eventCreationFailed)
        }

        // Restoring immediately would race the target app's read of the
        // pasteboard, so give it a beat.
        Task {
            try? await Task.sleep(for: Self.pasteboardRestoreDelay)
            snapshot.restore(to: pasteboard)
        }

        return .inserted
    }

    private func postCommandV() throws {
        guard
            let source = CGEventSource(stateID: .combinedSessionState),
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: Self.virtualKeyV, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: Self.virtualKeyV, keyDown: false)
        else {
            throw CopyReasonError.eventCreationFailed
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

        guard let element = focusedUIElement() else {
            throw AccessibilityFallback.noFocusedTextField
        }

        // Replacing the selection is what a keystroke would do: with an empty
        // selection it inserts at the caret, and with a selection it overwrites.
        let result = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        )

        guard result == .success else { throw AccessibilityFallback.noFocusedTextField }
    }

    private func focusedUIElement() -> AXUIElement? {
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
            return nil
        }

        return (focused as! AXUIElement)
    }

    // MARK: - Clipboard

    private func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

/// Internal signal that accessibility insertion should fall through to paste.
private enum AccessibilityFallback: Error {
    case noFocusedTextField
}

/// Internal signal that ⌘V could not be synthesized; paste maps it to `.copied`.
private enum CopyReasonError: Error {
    case eventCreationFailed
}
#endif
