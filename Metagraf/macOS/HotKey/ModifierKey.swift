#if os(macOS)
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
        case .rightOption: 0x3D
        case .leftOption: 0x3A
        case .rightCommand: 0x36
        case .rightControl: 0x3E
        case .rightShift: 0x3C
        case .function: 0x3F
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
