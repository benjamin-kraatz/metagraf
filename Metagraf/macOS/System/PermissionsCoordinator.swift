#if os(macOS)
import AppKit
import AVFoundation
import MetagrafCore
import SwiftUI

/// Tracks the two permissions Metagraf cannot work without.
///
/// macOS sends no notification when a privacy switch is flipped, so the state
/// is polled while any permission is still outstanding.
@MainActor
@Observable
final class PermissionsCoordinator {
    enum Status: Equatable {
        case granted
        case denied
        case notDetermined

        var isGranted: Bool { self == .granted }
    }

    enum Permission: String, CaseIterable, Identifiable {
        case microphone
        case accessibility

        var id: String { rawValue }

        var title: String {
            switch self {
            case .microphone: "Microphone"
            case .accessibility: "Accessibility"
            }
        }

        var reason: String {
            switch self {
            case .microphone:
                "So Metagraf can hear you while you hold the dictation key."
            case .accessibility:
                "So Metagraf can notice the dictation key in other apps, and paste what you said."
            }
        }

        var symbol: String {
            switch self {
            case .microphone: "mic"
            case .accessibility: "accessibility"
            }
        }

        var settingsURL: URL? {
            switch self {
            case .microphone:
                URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
            case .accessibility:
                URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
            }
        }
    }

    private(set) var microphone: Status = .notDetermined
    private(set) var accessibility: Status = .notDetermined

    private var pollTask: Task<Void, Never>?

    init() {
        refresh()
    }

    isolated deinit {
        pollTask?.cancel()
    }

    /// Everything needed for dictation is granted.
    var isReady: Bool {
        microphone.isGranted && accessibility.isGranted
    }

    func status(of permission: Permission) -> Status {
        switch permission {
        case .microphone: microphone
        case .accessibility: accessibility
        }
    }

    func refresh() {
        microphone = switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: .granted
        case .notDetermined: .notDetermined
        default: .denied
        }

        // Accessibility has no "not determined" state that can be read; it is
        // either trusted or not.
        accessibility = AXIsProcessTrusted() ? .granted : .notDetermined
    }

    /// Polls until everything is granted, so the UI updates as the user flips
    /// switches in System Settings without needing a relaunch.
    func beginPolling() {
        guard pollTask == nil else { return }

        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1))
                guard let self else { return }
                self.refresh()
                if self.isReady {
                    self.pollTask = nil
                    return
                }
            }
        }
    }

    func request(_ permission: Permission) async {
        switch permission {
        case .microphone:
            _ = await MicrophoneAuthorization.request()
        case .accessibility:
            AccessibilityPermission.requestTrust()
        }
        refresh()
        beginPolling()
    }

    func openSettings(for permission: Permission) {
        guard let url = permission.settingsURL else { return }
        NSWorkspace.shared.open(url)
        beginPolling()
    }
}
#endif
