#if os(macOS)
import MetagrafCore
import SwiftUI

/// Chooses how transcripts are tidied before they are inserted.
struct FormattingSettings: View {
    @Bindable var settings: SettingsStore

    @State private var unavailableReason: String?
    @State private var isChecking = true

    private let refiners = RefinerRegistry()

    var body: some View {
        Form {
            Section("Style") {
                Picker("Write it as", selection: $settings.refinementStyle) {
                    ForEach(RefinementStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                Text(settings.refinementStyle.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Apple Intelligence") {
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

                Text(
                    """
                    "Exactly as spoken" will not post-process the transcript. \
                    The other styles ask Apple Intelligence to rewrite the text \
                    on this device, and fall back to the cleaned-up version if \
                    it is unavailable or takes too long.
                    """
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .formStyle(.grouped)
        .task {
            unavailableReason = await refiners.languageModelUnavailableReason()
            isChecking = false
        }
    }
}
#endif
