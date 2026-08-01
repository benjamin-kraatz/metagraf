#if os(iOS)
import MetagrafCore
import SwiftUI

/// Top-level iOS navigation.
struct RootView: View {
    let controller: DictationController

    var body: some View {
        TabView {
            Tab("Dictate", systemImage: "mic") {
                DictateView(controller: controller)
            }

            Tab("History", systemImage: "clock") {
                NavigationStack {
                    HistoryList()
                }
            }

            Tab("Settings", systemImage: "gearshape") {
                NavigationStack {
                    MobileSettingsView(settings: controller.settings)
                }
            }
        }
    }
}

/// Settings on iOS. Deliberately narrower than the Mac's: there is no hotkey,
/// no insertion strategy, and no Whisper models, because the keyboard extension
/// and this app both use Apple's on-device engine.
struct MobileSettingsView: View {
    @Bindable var settings: SettingsStore

    @State private var locales: [Locale] = []
    @State private var installed: Set<String> = []
    @State private var isLoadingLocales = true

    var body: some View {
        Form {
            Section("Language") {
                Picker("Dictate in", selection: $settings.localeIdentifier) {
                    Text("Follow system language").tag("")
                    ForEach(locales, id: \.identifier) { locale in
                        Text(SupportedLocales.name(for: locale)).tag(locale.identifier)
                    }
                }
                .disabled(isLoadingLocales)

                if !isLoadingLocales {
                    Text("Currently dictating in \(SupportedLocales.name(for: settings.effectiveLocale)).")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Formatting") {
                Picker("Write it as", selection: $settings.refinementStyle) {
                    ForEach(RefinementStyle.allCases) { style in
                        Text(style.displayName).tag(style)
                    }
                }
                Text(settings.refinementStyle.explanation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Privacy") {
                Picker("Keep transcripts for", selection: $settings.retentionDays) {
                    Text("Don’t keep any").tag(0)
                    Text("7 days").tag(7)
                    Text("30 days").tag(30)
                    Text("90 days").tag(90)
                    Text("Forever").tag(36500)
                }
                Text("Everything is transcribed on this iPhone and nothing is uploaded.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                NavigationLink("Set up the keyboard") {
                    KeyboardSetupView()
                }
            } footer: {
                Text("Dictate straight into any app without switching to Metagraf.")
            }
        }
        .navigationTitle("Settings")
        .task {
            locales = await SupportedLocales.all()
            installed = await SupportedLocales.installed()
            isLoadingLocales = false
        }
    }
}

/// Explains the two steps iOS requires before the keyboard works.
struct KeyboardSetupView: View {
    var body: some View {
        List {
            Section {
                StepRow(
                    number: 1,
                    title: "Add the keyboard",
                    detail: "Settings → General → Keyboard → Keyboards → Add New Keyboard → Metagraf."
                )
                StepRow(
                    number: 2,
                    title: "Turn on Full Access",
                    detail: "Tap Metagraf in that list and enable Allow Full Access."
                )
            } footer: {
                Text(
                    """
                    iOS only lets a keyboard reach the microphone and your \
                    settings with Full Access granted. Metagraf still transcribes \
                    entirely on this iPhone — nothing is sent anywhere.
                    """
                )
            }

            Section {
                Button("Open Settings") {
                    guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
                    UIApplication.shared.open(url)
                }
            }
        }
        .navigationTitle("Keyboard")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct StepRow: View {
    let number: Int
    let title: LocalizedStringKey
    let detail: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text(number.formatted())
                .font(.headline.monospacedDigit())
                .frame(width: 26, height: 26)
                .background(.tint.opacity(0.15), in: .circle)

            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.headline)
                Text(detail)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
#endif
