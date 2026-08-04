#if os(iOS)
import MetagrafCore
import SwiftUI

struct DictationSettingsSection: View {
    @Bindable var settings: SettingsStore
    let availability: RefinementAvailabilityModel

    @State private var locales: [Locale] = []
    @State private var installed: Set<String> = []
    @State private var isLoading = true

    var body: some View {
        Section {
            Picker("Language", selection: $settings.localeIdentifier) {
                Text("Automatic (System Language)").tag("")
                ForEach(locales, id: \.identifier) { locale in
                    HStack {
                        Text(SupportedLocales.name(for: locale))
                        if installed.contains(locale.identifier) {
                            Image(systemName: "checkmark.circle.fill")
                        }
                    }
                    .tag(locale.identifier)
                }
            }
            .disabled(isLoading)
            .onChange(of: settings.localeIdentifier) {
                Task { await availability.refresh(settings: settings) }
            }

            Toggle("Sound cues", isOn: $settings.playsSounds)
        } header: {
            Text("Dictation")
        } footer: {
            Text("The selected language controls both transcription and Apple Intelligence refinement.")
        }
        .task {
            async let supported = SupportedLocales.all()
            async let downloaded = SupportedLocales.installed()
            locales = await supported
            installed = await downloaded
            isLoading = false
        }
    }
}

struct RefinementSettingsSection: View {
    @Bindable var settings: SettingsStore
    let availability: RefinementAvailabilityModel

    var body: some View {
        Section {
            Picker("Refinement style", selection: $settings.refinementStyle) {
                ForEach(RefinementStyle.allCases) { style in
                    Label {
                        Text(LocalizedStringKey(style.displayName))
                    } icon: {
                        Image(systemName: style.systemImage)
                    }
                    .tag(style)
                    .disabled(style.needsLanguageModel && !availability.allowsLanguageModel)
                }
            }
            .pickerStyle(.menu)

            NavigationLink(value: MobileSettingsRoute.persona) {
                HStack {
                    Label("Persona & Adaptation", systemImage: "person.crop.circle.badge.sparkles")
                    Spacer()
                    Text(LocalizedStringKey(settings.refinementPersona.displayName))
                        .foregroundStyle(.secondary)
                }
            }
            .disabled(!availability.allowsLanguageModel || settings.refinementStyle == .raw)

            RefinementAvailabilityNotice(
                settings: settings,
                availability: availability
            )
        } header: {
            Text("Refinement")
        } footer: {
            if availability.allowsLanguageModel {
                Text("Refinement is performed on this device with Apple Intelligence.")
            }
        }
    }
}

private struct RefinementAvailabilityNotice: View {
    let settings: SettingsStore
    let availability: RefinementAvailabilityModel

    var body: some View {
        switch availability.state {
        case .checking:
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text("Checking Apple Intelligence…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .accessibilityElement(children: .combine)

        case .available:
            EmptyView()

        case .unavailable(let reason):
            VStack(alignment: .leading, spacing: 6) {
                Label("Apple Intelligence unavailable", systemImage: "exclamationmark.triangle.fill")
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.orange)

                Text(reason)
                    .font(.callout)

                Text("Until it is ready, AI-backed styles are disabled and Metagraf uses “Exactly as spoken.” Check Settings › Apple Intelligence & Siri, then return here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine)
        }
    }
}

struct HistoryPrivacySettingsSection: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        Section {
            RetentionPicker(settings: settings)
        } header: {
            Text("History & Privacy")
        } footer: {
            Text("Audio, transcription, and refinement stay on this device. History is stored locally for your reference.")
        }
    }
}

private struct RetentionPicker: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        Picker("Keep transcripts for", selection: $settings.retentionDays) {
            Text("Don’t keep any").tag(0)
            Text("7 days").tag(7)
            Text("30 days").tag(30)
            Text("90 days").tag(90)
            Text("Forever").tag(36_500)
        }
    }
}

struct DictationSettingsView: View {
    @Bindable var settings: SettingsStore
    let availability: RefinementAvailabilityModel

    var body: some View {
        Form {
            DictationSettingsSection(settings: settings, availability: availability)
        }
        .navigationTitle("Dictation")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct RefinementSettingsView: View {
    @Bindable var settings: SettingsStore
    let availability: RefinementAvailabilityModel

    var body: some View {
        Form {
            RefinementSettingsSection(settings: settings, availability: availability)
        }
        .navigationTitle("Refinement")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct HistoryPrivacySettingsView: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        Form {
            HistoryPrivacySettingsSection(settings: settings)

            Section("Learn More") {
                NavigationLink("Privacy Policy", value: MobileSettingsRoute.privacyPolicy)
            }
        }
        .navigationTitle("History & Privacy")
        .navigationBarTitleDisplayMode(.inline)
    }
}

extension RefinementStyle {
    var systemImage: String {
        switch self {
        case .raw: "quote.bubble"
        case .cleanup: "sparkles"
        case .email: "envelope"
        case .message: "message"
        case .notes: "list.bullet"
        case .intelligent: "wand.and.stars"
        }
    }
}
#endif
