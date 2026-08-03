#if os(macOS)
import MetagrafCore
import MetagrafWhisper
import SwiftUI

/// Preferences window.
struct SettingsView: View {
    @Bindable var settings: SettingsStore
    let permissions: PermissionsCoordinator
    let models: ModelStore
    let updates: UpdateController
    let applyRuntimeSettings: () -> Void

    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") {
                GeneralSettings(settings: settings, updates: updates)
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
        .onChange(of: settings.hotKey) { _, _ in applyRuntimeSettings() }
        .onChange(of: settings.minimumHold) { _, _ in applyRuntimeSettings() }
        .onChange(of: settings.doubleTapWindow) { _, _ in applyRuntimeSettings() }
        .onChange(of: settings.modelID) { _, _ in applyRuntimeSettings() }
        .onChange(of: settings.playsSounds) { _, _ in applyRuntimeSettings() }
        .onChange(of: settings.pillPlacement) { _, _ in applyRuntimeSettings() }
    }
}

// MARK: - General

private struct GeneralSettings: View {
    @Bindable var settings: SettingsStore
    let updates: UpdateController

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

            Section("Updates") {
                Toggle("Receive beta updates", isOn: $settings.receivesBetaUpdates)
                    .onChange(of: settings.receivesBetaUpdates) { _, _ in
                        updates.channelsDidChange()
                    }

                Text("Beta builds may be less stable. Stable releases are always offered.")
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

                LabeledContent("Double-tap latch window") {
                    Slider(value: $settings.doubleTapWindow, in: 0.15...1.0, step: 0.05) {
                        EmptyView()
                    } minimumValueLabel: {
                        Text("0.15s").font(.caption)
                    } maximumValueLabel: {
                        Text("1s").font(.caption)
                    }
                    .frame(width: 220)
                }

                Text(
                    """
                    Tap twice within the latch window to keep dictation running \
                    hands-free; press once more to finish. Escape cancels.
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
    @State private var editedTerm = ""
    @State private var editedMisheard = ""

    var body: some View {
        VStack(spacing: 0) {
            Table(settings.vocabulary, selection: $selection) {
                TableColumn("Term") { entry in
                    Text(entry.term)
                }
                TableColumn("Also heard as") { entry in
                    Text(entry.misheard.joined(separator: ", "))
                        .foregroundStyle(entry.misheard.isEmpty ? .tertiary : .secondary)
                }
            }
            .tableStyle(.inset)
            .onChange(of: selection) { _, newValue in
                loadEditor(for: newValue)
            }

            if selection != nil {
                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    LabeledContent("Term") {
                        TextField("Preferred spelling", text: $editedTerm)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(commitEditor)
                    }

                    LabeledContent("Also heard as") {
                        TextField("meta graph, metagraph", text: $editedMisheard)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(commitEditor)
                    }

                    Text(
                        editedMisheard.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? "Optional: add common mistakes Metagraf should rewrite into this term, separated by commas."
                            : "Separate variants with commas. They are rewritten into the term after dictation."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                .padding(12)
                .onChange(of: editedTerm) { _, _ in commitEditor() }
                .onChange(of: editedMisheard) { _, _ in commitEditor() }
            }

            Divider()

            HStack(spacing: 8) {
                TextField("Add a preferred spelling", text: $newTerm)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(add)

                Button("Add", action: add)
                    .disabled(trimmedNewTerm.isEmpty)

                Button("Remove", action: removeSelected)
                    .disabled(selection == nil)
            }
            .padding(12)
        }
        .safeAreaInset(edge: .top) {
            Text(
                """
                Term is the spelling Metagraf should favour. Also heard as lists \
                wrong variants to rewrite into that term — for example “meta graph” \
                → “Metagraf”. Whisper models skip speech biasing; rewrite and \
                refinement still apply.
                """
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private var trimmedNewTerm: String {
        newTerm.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func loadEditor(for id: VocabularyEntry.ID?) {
        guard let id, let entry = settings.vocabulary.first(where: { $0.id == id }) else {
            editedTerm = ""
            editedMisheard = ""
            return
        }
        editedTerm = entry.term
        editedMisheard = entry.misheard.joined(separator: ", ")
    }

    private func commitEditor() {
        guard let selection,
              let index = settings.vocabulary.firstIndex(where: { $0.id == selection })
        else { return }

        let term = editedTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !term.isEmpty else { return }

        let duplicate = settings.vocabulary.contains {
            $0.id != selection && $0.term.caseInsensitiveCompare(term) == .orderedSame
        }
        guard !duplicate else { return }

        let misheard = Self.parseMisheard(editedMisheard)
        var entry = settings.vocabulary[index]
        guard entry.term != term || entry.misheard != misheard else { return }
        entry.term = term
        entry.misheard = misheard
        settings.vocabulary[index] = entry
    }

    private func add() {
        let term = trimmedNewTerm
        guard !term.isEmpty else { return }
        guard !settings.vocabulary.contains(where: { $0.term.caseInsensitiveCompare(term) == .orderedSame }) else {
            newTerm = ""
            return
        }
        let entry = VocabularyEntry(term: term)
        settings.vocabulary.append(entry)
        newTerm = ""
        selection = entry.id
        loadEditor(for: entry.id)
    }

    private func removeSelected() {
        guard let selection else { return }
        settings.vocabulary.removeAll { $0.id == selection }
        self.selection = nil
        editedTerm = ""
        editedMisheard = ""
    }

    private static func parseMisheard(_ raw: String) -> [String] {
        raw.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
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
