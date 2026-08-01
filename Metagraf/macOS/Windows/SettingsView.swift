#if os(macOS)
import MetagrafCore
import MetagrafWhisper
import SwiftUI

/// Preferences window.
struct SettingsView: View {
    let settings: SettingsStore
    let permissions: PermissionsCoordinator
    let models: ModelStore

    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                GeneralSettings(settings: settings)
            }
            Tab("Dictation", systemImage: "mic") {
                DictationSettings(settings: settings)
            }
            Tab("Models", systemImage: "cube") {
                ModelsSettings(settings: settings, models: models)
            }
            Tab("Formatting", systemImage: "text.badge.checkmark") {
                FormattingSettings(settings: settings)
            }
            Tab("Personas", systemImage: "person.crop.circle") {
                PersonasSettings(settings: settings)
            }
            Tab("Vocabulary", systemImage: "character.book.closed") {
                VocabularySettings(settings: settings)
            }
            Tab("Privacy", systemImage: "hand.raised") {
                PrivacySettings(settings: settings, permissions: permissions)
            }
        }
        .frame(width: 580, height: 460)
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @Bindable var settings: SettingsStore

    var body: some View {
        Form {
            Section {
                Toggle("Launch Metagraf at login", isOn: $settings.launchAtLogin)
                    .onChange(of: settings.launchAtLogin) { _, enabled in
                        LaunchAtLogin.set(enabled)
                    }
            } footer: {
                Text("Metagraf lives in the menu bar and has no Dock icon.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("The pill") {
                Toggle("Keep the pill visible when idle", isOn: $settings.showPillWhenIdle)

                Picker("Position", selection: $settings.pillPlacement) {
                    ForEach(PillPlacement.allCases) { placement in
                        Text(LocalizedStringKey(placement.displayName)).tag(placement)
                    }
                }

                Text(
                    """
                    The pill floats above every app and ignores clicks, so it \
                    never gets in the way of what is underneath it.
                    """
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }

            Section("Sound") {
                Toggle("Play a cue when dictation starts and ends", isOn: $settings.playsSounds)
                Text("Useful because the dictation key has no visible press of its own.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Dictation

private struct DictationSettings: View {
    @Bindable var settings: SettingsStore

    @State private var locales: [Locale] = []
    @State private var installed: Set<String> = []
    @State private var isLoadingLocales = true

    var body: some View {
        Form {
            Section("Language") {
                Picker("Dictate in", selection: $settings.localeIdentifier) {
                    Text("Follow system language").tag("")
                    Divider()
                    ForEach(locales, id: \.identifier) { locale in
                        HStack {
                            Text(SupportedLocales.name(for: locale))
                            if installed.contains(locale.identifier) {
                                Image(systemName: "arrow.down.circle.fill")
                            }
                        }
                        .tag(locale.identifier)
                    }
                }
                .disabled(isLoadingLocales)

                if isLoadingLocales {
                    Text("Looking up available languages…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(
                        """
                        Languages with a download badge are already on this Mac. \
                        Others are fetched the first time you use them. \
                        Currently dictating in \(SupportedLocales.name(for: settings.effectiveLocale)).
                        """
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            Section("Hotkey") {
                Picker("Hold to dictate", selection: $settings.hotKey) {
                    ForEach(ModifierKey.allCases) { key in
                        Text(key.displayName).tag(key.rawValue)
                    }
                }

                LabeledContent("Ignore holds shorter than") {
                    Slider(value: $settings.minimumHold, in: 0.1...1.0, step: 0.05) {
                        EmptyView()
                    } minimumValueLabel: {
                        Text("0.1s").font(.caption)
                    } maximumValueLabel: {
                        Text("1s").font(.caption)
                    }
                    .frame(width: 220)
                }

                Text(
                    """
                    Tap twice quickly to keep dictation running hands-free; \
                    press once more to finish. Escape cancels.
                    """
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Where text goes") {
                Picker("Insert with", selection: $settings.insertion) {
                    ForEach(InsertionStrategy.allCases) { strategy in
                        Text(LocalizedStringKey(strategy.displayName)).tag(strategy)
                    }
                }
                Text(LocalizedStringKey(settings.insertion.explanation))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .task {
            locales = await SupportedLocales.all()
            installed = await SupportedLocales.installed()
            isLoadingLocales = false
        }
    }
}

// MARK: - Vocabulary

private struct VocabularySettings: View {
    @Bindable var settings: SettingsStore

    @State private var selection: VocabularyEntry.ID?
    @State private var newTerm = ""

    var body: some View {
        VStack(spacing: 0) {
            Table(settings.vocabulary, selection: $selection) {
                TableColumn("Term") { entry in
                    Text(entry.term)
                }
                TableColumn("Also heard as") { entry in
                    Text(entry.misheard.joined(separator: ", "))
                        .foregroundStyle(.secondary)
                }
            }
            .tableStyle(.inset)

            Divider()

            HStack(spacing: 8) {
                TextField("Add a name or term Metagraf keeps getting wrong", text: $newTerm)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(add)

                Button("Add", action: add)
                    .disabled(trimmedTerm.isEmpty)

                Button("Remove", action: removeSelected)
                    .disabled(selection == nil)
            }
            .padding(12)
        }
        .safeAreaInset(edge: .top) {
            Text("These words are fed to the speech model so it favours them over similar-sounding ones.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
        }
    }

    private var trimmedTerm: String {
        newTerm.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func add() {
        let term = trimmedTerm
        guard !term.isEmpty else { return }
        guard !settings.vocabulary.contains(where: { $0.term.caseInsensitiveCompare(term) == .orderedSame }) else {
            newTerm = ""
            return
        }
        settings.vocabulary.append(VocabularyEntry(term: term))
        newTerm = ""
    }

    private func removeSelected() {
        guard let selection else { return }
        settings.vocabulary.removeAll { $0.id == selection }
        self.selection = nil
    }
}

// MARK: - Privacy

private struct PrivacySettings: View {
    @Bindable var settings: SettingsStore
    let permissions: PermissionsCoordinator

    var body: some View {
        Form {
            Section("History") {
                Picker("Keep transcripts for", selection: $settings.retentionDays) {
                    Text("Don’t keep any").tag(0)
                    Text("7 days").tag(7)
                    Text("30 days").tag(30)
                    Text("90 days").tag(90)
                    Text("Forever").tag(36500)
                }
                Text(
                    """
                    Everything is transcribed on this Mac and nothing is uploaded. \
                    History is only for your own reference.
                    """
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("Permissions") {
                ForEach(PermissionsCoordinator.Permission.allCases) { permission in
                    LabeledContent(permission.title) {
                        if permissions.status(of: permission).isGranted {
                            Label("Granted", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .labelStyle(.titleAndIcon)
                        } else {
                            Button("Open System Settings") {
                                permissions.openSettings(for: permission)
                            }
                            .controlSize(.small)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { permissions.refresh() }
    }
}
#endif
