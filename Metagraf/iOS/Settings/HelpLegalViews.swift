#if os(iOS)
import MetagrafCore
import SwiftUI

struct PrivacyPolicyView: View {
    var body: some View {
        List {
            Section("Local by Design") {
                PrivacyDetailRow(
                    systemImage: "waveform",
                    title: "Audio and transcription",
                    detail: "Dictation audio is processed on this device. Metagraf does not upload your audio or transcripts to its own servers."
                )
                PrivacyDetailRow(
                    systemImage: "apple.intelligence",
                    title: "Refinement",
                    detail: "When enabled, Apple Intelligence refines text on this device. If it is unavailable or generation fails, Metagraf keeps the original transcript."
                )
            }

            Section("Stored Data") {
                PrivacyDetailRow(
                    systemImage: "clock",
                    title: "History",
                    detail: "Transcript history is stored locally for the retention period you choose. Select “Don’t keep any” to disable history."
                )
                PrivacyDetailRow(
                    systemImage: "keyboard",
                    title: "Keyboard extension",
                    detail: "The Metagraf keyboard reads recent transcripts from the app’s private shared container. Full Access is required for that shared-container access; the keyboard does not record audio."
                )
                PrivacyDetailRow(
                    systemImage: "text.badge.checkmark",
                    title: "Preferences and vocabulary",
                    detail: "Your settings and vocabulary are stored locally in the same private app group so the app and keyboard can work together."
                )
            }

            Section {
                Text("Metagraf contains no advertising or third-party analytics SDK. Apple may process diagnostic information according to your device analytics settings.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Privacy Policy")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PrivacyDetailRow: View {
    let systemImage: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(.tint)
                .frame(width: 24, alignment: .center)
        }
        .accessibilityElement(children: .combine)
        .padding(.vertical, 3)
    }
}

struct AppleIntelligenceRequirementsView: View {
    let settings: SettingsStore
    let availability: RefinementAvailabilityModel

    private let supportURL = URL(string: "https://support.apple.com/121115")!

    var body: some View {
        List {
            Section {
                RequirementRow(
                    systemImage: "iphone.gen3",
                    title: "Compatible device",
                    detail: "Your iPhone or iPad must support Apple Intelligence."
                )
                RequirementRow(
                    systemImage: "switch.2",
                    title: "Apple Intelligence enabled",
                    detail: "Turn it on manually in Settings › Apple Intelligence & Siri."
                )
                RequirementRow(
                    systemImage: "arrow.down.circle",
                    title: "On-device model ready",
                    detail: "After setup or an update, the language model may need time and Wi-Fi to finish downloading."
                )
                RequirementRow(
                    systemImage: "character.bubble",
                    title: "Supported language",
                    detail: "The dictation language selected in Metagraf must also be supported by Apple Intelligence."
                )
            } header: {
                Text("What Refinement Needs")
            }

            Section("Current Status") {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: statusIcon)
                        .foregroundStyle(statusColor)
                        .frame(width: 24)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(statusTitle)
                            .font(.body.weight(.medium))
                        Text(statusDetail)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)

                LabeledContent("Selected language") {
                    Text(SupportedLocales.name(for: settings.effectiveLocale))
                }
            }

            Section {
                Link(destination: supportURL) {
                    Label("Apple Intelligence support", systemImage: "arrow.up.right.square")
                }
            } footer: {
                Text("iOS does not provide an approved direct link to Apple Intelligence settings. Open Settings and choose Apple Intelligence & Siri.")
            }
        }
        .navigationTitle("Apple Intelligence")
        .navigationBarTitleDisplayMode(.inline)
        .task { await availability.refresh(settings: settings) }
    }

    private var statusIcon: String {
        switch availability.state {
        case .checking: "ellipsis.circle"
        case .available: "checkmark.circle.fill"
        case .unavailable: "exclamationmark.triangle.fill"
        }
    }

    private var statusColor: Color {
        switch availability.state {
        case .checking: .secondary
        case .available: .green
        case .unavailable: .orange
        }
    }

    private var statusTitle: LocalizedStringKey {
        switch availability.state {
        case .checking: "Checking availability…"
        case .available: "Ready for refinement"
        case .unavailable: "Not available right now"
        }
    }

    private var statusDetail: String {
        switch availability.state {
        case .checking:
            String(localized: "Metagraf is checking this device and the selected language.")
        case .available:
            String(localized: "AI-backed refinement styles and personas are available.")
        case .unavailable(let reason):
            reason
        }
    }
}

private struct RequirementRow: View {
    let systemImage: String
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.medium))
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(.tint)
                .frame(width: 24)
        }
        .accessibilityElement(children: .combine)
        .padding(.vertical, 3)
    }
}

#Preview("Requirements unavailable") {
    NavigationStack {
        AppleIntelligenceRequirementsView(
            settings: SettingsStore(defaults: UserDefaults(suiteName: "RequirementsPreview")!),
            availability: RefinementAvailabilityModel(
                state: .unavailable("The on-device model is still downloading.")
            )
        )
    }
}
#endif
