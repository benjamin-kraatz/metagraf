#if os(iOS)
import MetagrafCore
import SwiftUI

/// Native, searchable settings for the iPhone and iPad app.
struct MobileSettingsView: View {
    @Bindable var settings: SettingsStore
    let availability: RefinementAvailabilityModel

    @State private var searchText = ""

    var body: some View {
        Group {
            if searchText.isEmpty {
                settingsForm
            } else {
                SettingsSearchResults(
                    query: searchText,
                    settings: settings,
                    availability: availability
                )
            }
        }
        .navigationTitle("Settings")
        .searchable(text: $searchText, prompt: "Search Settings")
        .navigationDestination(for: MobileSettingsRoute.self) { route in
            destination(for: route)
        }
    }

    private var settingsForm: some View {
        Form {
            DictationSettingsSection(settings: settings, availability: availability)
            RefinementSettingsSection(settings: settings, availability: availability)

            Section("Tools") {
                NavigationLink(value: MobileSettingsRoute.vocabulary) {
                    SettingsNavigationLabel(
                        title: "Vocabulary",
                        systemImage: "text.badge.plus",
                        value: settings.vocabulary.isEmpty
                            ? String(localized: "None")
                            : settings.vocabulary.count.formatted()
                    )
                }

                NavigationLink(value: MobileSettingsRoute.keyboard) {
                    SettingsNavigationLabel(
                        title: "Keyboard & Shortcuts",
                        systemImage: "keyboard"
                    )
                }
            }

            HistoryPrivacySettingsSection(settings: settings)

            Section("Help & Legal") {
                NavigationLink(value: MobileSettingsRoute.privacyPolicy) {
                    SettingsNavigationLabel(
                        title: "Privacy Policy",
                        systemImage: "hand.raised"
                    )
                }

                NavigationLink(value: MobileSettingsRoute.requirements) {
                    SettingsNavigationLabel(
                        title: "Apple Intelligence Requirements",
                        systemImage: "apple.intelligence"
                    )
                }
            }

            Section {
                EmptyView()
            } footer: {
                HStack {
                    Spacer()
                    Text(AppVersion.displayString)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .textCase(nil)
                    Spacer()
                }
                .padding(.top, 8)
            }
        }
    }

    @ViewBuilder
    private func destination(for route: MobileSettingsRoute) -> some View {
        switch route {
        case .dictation:
            DictationSettingsView(settings: settings, availability: availability)
        case .refinement:
            RefinementSettingsView(settings: settings, availability: availability)
        case .persona:
            PersonaSettingsView(settings: settings, availability: availability)
        case .vocabulary:
            VocabularySettingsView(settings: settings)
        case .historyPrivacy:
            HistoryPrivacySettingsView(settings: settings)
        case .keyboard:
            KeyboardSetupView()
        case .privacyPolicy:
            PrivacyPolicyView()
        case .requirements:
            AppleIntelligenceRequirementsView(
                settings: settings,
                availability: availability
            )
        }
    }
}

private struct SettingsNavigationLabel: View {
    let title: LocalizedStringKey
    let systemImage: String
    var value: String? = nil

    var body: some View {
        Label {
            HStack {
                Text(title)
                Spacer()
                if let value {
                    Text(value)
                        .foregroundStyle(.secondary)
                }
            }
        } icon: {
            Image(systemName: systemImage)
                .foregroundStyle(.tint)
                .frame(width: 24)
        }
    }
}

enum MobileSettingsRoute: String, CaseIterable, Hashable {
    case dictation
    case refinement
    case persona
    case vocabulary
    case historyPrivacy
    case keyboard
    case privacyPolicy
    case requirements
}

private enum AppVersion {
    static var displayString: String {
        let bundle = Bundle.main
        let marketing = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
        return String(
            format: String(localized: "Metagraf %@ · Build %@"),
            locale: .current,
            marketing,
            build
        )
    }
}

#Preview("Available") {
    NavigationStack {
        MobileSettingsView(
            settings: SettingsStore(defaults: UserDefaults(suiteName: "MobileSettingsPreview")!),
            availability: RefinementAvailabilityModel(state: .available)
        )
    }
}

#Preview("Unavailable") {
    NavigationStack {
        MobileSettingsView(
            settings: makeUnavailablePreviewSettings(),
            availability: RefinementAvailabilityModel(
                state: .unavailable(String(localized: "Apple Intelligence is still downloading its model."))
            )
        )
    }
}

#Preview("Large type") {
    NavigationStack {
        MobileSettingsView(
            settings: SettingsStore(defaults: UserDefaults(suiteName: "MobileSettingsLargeTypePreview")!),
            availability: RefinementAvailabilityModel(state: .available)
        )
    }
    .environment(\.dynamicTypeSize, .accessibility3)
}

@MainActor
private func makeUnavailablePreviewSettings() -> SettingsStore {
    let settings = SettingsStore(defaults: UserDefaults(suiteName: "MobileSettingsUnavailablePreview")!)
    settings.refinementStyle = .raw
    return settings
}
#endif
