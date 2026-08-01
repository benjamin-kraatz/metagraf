#if os(macOS)
import Foundation
import MetagrafCore
import SwiftUI

/// Chooses how transcripts are tidied before they are inserted.
struct FormattingSettings: View {
    enum IntelligenceAvailabilitySource {
        case live
        case available
        case unavailable(String)
    }

    @Bindable var settings: SettingsStore

    @State private var unavailableReason: String?
    @State private var isChecking = true

    private let refiners = RefinerRegistry()
    private let availabilitySource: IntelligenceAvailabilitySource

    init(
        settings: SettingsStore,
        intelligenceAvailabilitySource: IntelligenceAvailabilitySource = .live
    ) {
        self.settings = settings
        availabilitySource = intelligenceAvailabilitySource

        switch intelligenceAvailabilitySource {
        case .live:
            _unavailableReason = State(initialValue: nil)
            _isChecking = State(initialValue: true)
        case .available:
            _unavailableReason = State(initialValue: nil)
            _isChecking = State(initialValue: false)
        case .unavailable(let reason):
            _unavailableReason = State(initialValue: reason)
            _isChecking = State(initialValue: false)
        }
    }

    var body: some View {
        Form {
            Section("Style") {
                Picker("Write it as", selection: $settings.refinementStyle) {
                    ForEach(RefinementStyle.allCases) { style in
                        HStack {
                            Text(LocalizedStringKey(style.displayName))
                            if style == .intelligent {
                                Image(systemName: unavailableReason == nil ? "sparkles" : "exclamationmark.circle")
                            }
                        }
                        .tag(style)
                        .disabled(style == .intelligent && (isChecking || unavailableReason != nil))
                    }
                }
                Text(LocalizedStringKey(settings.refinementStyle.explanation))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if settings.refinementStyle == .intelligent {
                    intelligenceAvailability

                    Toggle("Use nearby app context", isOn: $settings.usesNearbyAppContext)
                    Text(
                        """
                        When enabled, Metagraf reads selected and nearby text from the focused field \
                        only while dictation starts. It is processed on-device and is never saved.
                        """
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
            }

            Section("Apple Intelligence") {
                intelligenceAvailability

                Text(
                    """
                    “Exactly as spoken” does not post-process the transcript. Every other style \
                    asks Apple Intelligence to rewrite on-device and preserves the original \
                    transcript if it becomes unavailable or takes too long.
                    """
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .task {
            guard case .live = availabilitySource else { return }
            unavailableReason = await refiners.languageModelUnavailableReason()
            isChecking = false
        }
    }

    @ViewBuilder
    private var intelligenceAvailability: some View {
        if isChecking {
            Text("Checking availability…")
                .font(.callout)
                .foregroundStyle(.secondary)
        } else if let unavailableReason {
            Label(unavailableReason, systemImage: "exclamationmark.circle")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        } else {
            Label("Available on this Mac", systemImage: "checkmark.circle.fill")
                .font(.callout)
                .foregroundStyle(.green)
        }
    }
}

#if DEBUG
@MainActor
private func previewFormattingSettings() -> SettingsStore {
    let suite = "Metagraf.FormattingSettingsPreview"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    defaults.set(RefinementStyle.intelligent.rawValue, forKey: "refinement.style")
    return SettingsStore(defaults: defaults)
}

#Preview("Intelligent available") {
    FormattingSettings(
        settings: previewFormattingSettings(),
        intelligenceAvailabilitySource: .available
    )
    .frame(width: 520, height: 560)
}

#Preview("Intelligent unavailable") {
    FormattingSettings(
        settings: previewFormattingSettings(),
        intelligenceAvailabilitySource: .unavailable("Apple Intelligence is turned off in System Settings.")
    )
    .frame(width: 520, height: 560)
}
#endif
#endif
