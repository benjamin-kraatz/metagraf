#if os(macOS)
import Carbon.HIToolbox
import CoreGraphics

/// A modifier key that can be held to dictate.
///
/// Left and right variants are distinguished because holding *right* Option
/// leaves the left one free for its normal job of typing alternate characters.
enum ModifierKey: String, CaseIterable, Codable, Sendable, Identifiable {
    case rightOption
    case leftOption
    case rightCommand
    case rightControl
    case rightShift
    case function

    var id: String { rawValue }

    /// Virtual key code reported by `flagsChanged` events.
    var keyCode: Int64 {
        switch self {
        case .rightOption: Int64(kVK_RightOption)
        case .leftOption: Int64(kVK_Option)
        case .rightCommand: Int64(kVK_RightCommand)
        case .rightControl: Int64(kVK_RightControl)
        case .rightShift: Int64(kVK_RightShift)
        case .function: Int64(kVK_Function)
        }
    }

    /// Flag that is set while the key is down.
    var flag: CGEventFlags {
        switch self {
        case .rightOption, .leftOption: .maskAlternate
        case .rightCommand: .maskCommand
        case .rightControl: .maskControl
        case .rightShift: .maskShift
        case .function: .maskSecondaryFn
        }
    }

    var displayName: String {
        switch self {
        case .rightOption: "Right ⌥"
        case .leftOption: "Left ⌥"
        case .rightCommand: "Right ⌘"
        case .rightControl: "Right ⌃"
        case .rightShift: "Right ⇧"
        case .function: "Globe (fn)"
        }
    }
}
#endif
