#if os(macOS)
import Foundation

/// How a finished transcript reaches the app the user is working in.
enum InsertionStrategy: String, Codable, CaseIterable, Sendable, Identifiable {
    /// Put the text on the clipboard and synthesize ⌘V, then put the clipboard
    /// back. Works in essentially every app, including Electron and terminals.
    case paste

    /// Write directly into the focused text field through the Accessibility
    /// API. Leaves the clipboard alone, but many non-native apps either ignore
    /// it or handle it badly, so it is opt-in per app.
    case accessibility

    /// Only copy. For apps where synthesized keystrokes are unwelcome.
    case clipboardOnly

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .paste: "Paste"
        case .accessibility: "Direct insertion"
        case .clipboardOnly: "Copy only"
        }
    }

    var explanation: String {
        switch self {
        case .paste:
            "Pastes into the focused app and restores your clipboard afterwards."
        case .accessibility:
            "Writes into the text field without touching the clipboard. Not every app supports it."
        case .clipboardOnly:
            "Copies the transcript so you can paste it yourself."
        }
    }
}
#endif
