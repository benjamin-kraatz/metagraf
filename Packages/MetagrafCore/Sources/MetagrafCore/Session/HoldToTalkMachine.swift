import Foundation

/// Decides what a press of the dictation key means.
///
/// Kept free of AppKit and event taps so the awkward parts — telling a
/// deliberate hold from an accidental brush, and latching on a double tap —
/// can be tested directly instead of by hand with a keyboard.
public struct HoldToTalkMachine: Sendable, Equatable {
    public enum Input: Sendable, Equatable {
        case keyDown
        case keyUp
        /// Escape, or anything else that should abandon the utterance.
        case abort
    }

    public enum Output: Sendable, Equatable {
        case begin
        case complete
        case cancel
        case abort
    }

    /// Holds shorter than this are treated as accidental.
    public var minimumHold: TimeInterval

    /// Two short taps this close together latch recording on.
    public var doubleTapWindow: TimeInterval

    private var isKeyDown = false
    private var isActive = false
    private var isLatched = false
    private var keyDownAt: Date?
    private var lastShortReleaseAt: Date?

    public init(minimumHold: TimeInterval = 0.25, doubleTapWindow: TimeInterval = 0.4) {
        self.minimumHold = minimumHold
        self.doubleTapWindow = doubleTapWindow
    }

    /// Whether dictation is currently held on by a double tap.
    public var isLatchedOn: Bool { isLatched }

    /// Whether a dictation is in flight.
    public var isDictating: Bool { isActive }

    /// Feeds one key transition and returns the action it implies, if any.
    public mutating func handle(_ input: Input, at now: Date = .now) -> Output? {
        switch input {
        case .keyDown:
            return handleKeyDown(at: now)
        case .keyUp:
            return handleKeyUp(at: now)
        case .abort:
            guard isActive else { return nil }
            reset()
            return .abort
        }
    }

    private mutating func handleKeyDown(at now: Date) -> Output? {
        // Another key carrying the same modifier flag can produce a repeat;
        // only real transitions matter.
        guard !isKeyDown else { return nil }
        isKeyDown = true

        if isLatched {
            isLatched = false
            isActive = false
            keyDownAt = nil
            return .complete
        }

        keyDownAt = now
        isActive = true
        return .begin
    }

    private mutating func handleKeyUp(at now: Date) -> Output? {
        guard isKeyDown else { return nil }
        isKeyDown = false

        guard isActive, let downAt = keyDownAt else { return nil }
        keyDownAt = nil

        let held = now.timeIntervalSince(downAt)
        if held >= minimumHold {
            isActive = false
            lastShortReleaseAt = nil
            return .complete
        }

        // A short tap right after another short tap means "stay on". Recording
        // is already running from this tap's `begin`, so nothing is emitted.
        if let previous = lastShortReleaseAt, downAt.timeIntervalSince(previous) < doubleTapWindow {
            isLatched = true
            lastShortReleaseAt = nil
            return nil
        }

        lastShortReleaseAt = now
        isActive = false
        return .cancel
    }

    public mutating func reset() {
        isKeyDown = false
        isActive = false
        isLatched = false
        keyDownAt = nil
        lastShortReleaseAt = nil
    }
}
