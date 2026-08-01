import Foundation

/// Where the dictation pill sits on screen.
///
/// A fixed set of anchors rather than free dragging: the pill floats above
/// every app and ignores clicks so it never gets in the way, and a draggable
/// overlay would have to accept mouse events to be moved — swallowing clicks in
/// whatever is underneath it.
public enum PillPlacement: String, Codable, CaseIterable, Sendable, Identifiable {
    case bottomCenter
    case bottomLeading
    case bottomTrailing
    case topCenter

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .bottomCenter: "Bottom, centred"
        case .bottomLeading: "Bottom left"
        case .bottomTrailing: "Bottom right"
        case .topCenter: "Top, centred"
        }
    }

    public var isTop: Bool { self == .topCenter }
}
