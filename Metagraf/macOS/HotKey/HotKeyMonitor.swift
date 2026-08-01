#if os(macOS)
import AppKit
import ApplicationServices
import Carbon.HIToolbox
import MetagrafCore
import OSLog

/// Watches for the global dictation key anywhere in the system.
///
/// A `CGEvent` tap is the only way to see a bare modifier being held while
/// another app is frontmost. The tap is `listenOnly`: the dictation key is a
/// modifier that types nothing on its own, so there is no reason to swallow it
/// and every reason not to interfere with other apps.
@MainActor
final class HotKeyMonitor {
    enum Activation {
        /// The key went down; start listening.
        case began
        /// The key was released after a real hold, or a latched session ended.
        case completed
        /// Released too quickly to be intentional; throw the audio away.
        case cancelled
        /// Escape was pressed mid-dictation.
        case aborted
    }

    enum MonitorError: Error, LocalizedError {
        case accessibilityNotTrusted
        case tapCreationFailed

        var errorDescription: String? {
            switch self {
            case .accessibilityNotTrusted:
                "Metagraf needs Accessibility access to see the dictation key."
            case .tapCreationFailed:
                "The system refused to install a keyboard event tap."
            }
        }
    }

    /// Called for every activation change. Set before `start()`.
    var onActivation: ((Activation) -> Void)?

    /// Which key starts dictation.
    var binding: ModifierKey = .rightOption

    /// Interpretation of presses and releases. Tested separately in the core
    /// package; this class only translates events into its inputs.
    var machine = HoldToTalkMachine()

    private let logger = Logger(subsystem: Metagraf.bundleIdentifier, category: "HotKey")
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    var isRunning: Bool { eventTap != nil }

    /// Whether dictation is currently latched on by a double tap.
    var isLatchedOn: Bool { machine.isLatchedOn }

    func start() throws {
        guard eventTap == nil else { return }
        guard AXIsProcessTrusted() else { throw MonitorError.accessibilityNotTrusted }

        let mask = (1 << CGEventType.flagsChanged.rawValue) | (1 << CGEventType.keyDown.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            // The tap source lives on the main run loop, so this really is the
            // main actor even though the C signature cannot say so.
            MainActor.assumeIsolated {
                let monitor = Unmanaged<HotKeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
                monitor.handle(type: type, event: event)
            }
            return Unmanaged.passUnretained(event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            throw MonitorError.tapCreationFailed
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        eventTap = tap
        runLoopSource = source
        logger.info("Hot key monitor started on \(self.binding.displayName, privacy: .public)")
    }

    func stop() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        machine.reset()
    }

    // MARK: - Event handling

    private func handle(type: CGEventType, event: CGEvent) {
        // The system disables a tap that takes too long or when the user changes
        // input settings. Re-enabling is the documented recovery.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
                logger.notice("Event tap re-enabled after being disabled by the system")
            }
            return
        }

        switch type {
        case .flagsChanged:
            guard event.getIntegerValueField(.keyboardEventKeycode) == binding.keyCode else { return }
            feed(event.flags.contains(binding.flag) ? .keyDown : .keyUp)

        case .keyDown:
            // Escape abandons whatever is in flight.
            if event.getIntegerValueField(.keyboardEventKeycode) == Int64(kVK_Escape) {
                feed(.abort)
            }

        default:
            break
        }
    }

    private func feed(_ input: HoldToTalkMachine.Input) {
        guard let output = machine.handle(input) else { return }

        switch output {
        case .begin: onActivation?(.began)
        case .complete: onActivation?(.completed)
        case .cancel: onActivation?(.cancelled)
        case .abort: onActivation?(.aborted)
        }
    }
}

/// Accessibility trust, which the event tap depends on.
enum AccessibilityPermission {
    static var isTrusted: Bool { AXIsProcessTrusted() }

    /// Asks the system to show the "grant access" prompt.
    @discardableResult
    static func requestTrust() -> Bool {
        // The constant `kAXTrustedCheckOptionPrompt` is a global `var` and so is
        // not concurrency-safe to reference; its value is this string.
        return AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    }

    static func openSystemSettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}
#endif
