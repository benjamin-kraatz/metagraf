#if os(iOS)
import MetagrafCore
import SwiftUI

/// Edits preferred spellings and common recognition mistakes using shared persistence.
struct VocabularySettingsView: View {
    @Bindable var settings: SettingsStore

    @State private var editor: VocabularyEditorState?

    var body: some View {
        List {
            Section {
                if settings.vocabulary.isEmpty {
                    ContentUnavailableView(
                        "No Vocabulary Yet",
                        systemImage: "text.badge.plus",
                        description: Text("Add names, product names, and specialist terms that Metagraf should spell correctly.")
                    )
                } else {
                    ForEach(settings.vocabulary) { entry in
                        Button {
                            editor = VocabularyEditorState(entry: entry)
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(entry.term)
                                    .foregroundStyle(.primary)
                                if !entry.misheard.isEmpty {
                                    Text(entry.misheard.joined(separator: ", "))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 2)
                        }
                        .accessibilityLabel(entry.term)
                        .accessibilityHint("Edit preferred spelling and misheard variants")
                    }
                    .onDelete(perform: delete)
                }
            } footer: {
                Text("Preferred spellings bias transcription. Misheard variants are rewritten after dictation; separate them with commas.")
            }
        }
        .navigationTitle("Vocabulary")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editor = VocabularyEditorState()
                } label: {
                    Label("Add term", systemImage: "plus")
                }
            }
        }
        .sheet(item: $editor) { state in
            VocabularyEditorSheet(
                state: state,
                existingEntries: settings.vocabulary,
                onSave: save
            )
        }
    }

    private func delete(at offsets: IndexSet) {
        settings.vocabulary.remove(atOffsets: offsets)
    }

    private func save(_ entry: VocabularyEntry) {
        if let index = settings.vocabulary.firstIndex(where: { $0.id == entry.id }) {
            settings.vocabulary[index] = entry
        } else {
            settings.vocabulary.append(entry)
        }
        settings.vocabulary.sort {
            $0.term.localizedStandardCompare($1.term) == .orderedAscending
        }
        editor = nil
    }
}

private struct VocabularyEditorState: Identifiable {
    let id = UUID()
    let entryID: VocabularyEntry.ID?
    var term: String
    var misheard: String

    init(entry: VocabularyEntry? = nil) {
        entryID = entry?.id
        term = entry?.term ?? ""
        misheard = entry?.misheard.joined(separator: ", ") ?? ""
    }
}

private struct VocabularyEditorSheet: View {
    @Environment(\.dismiss) private var dismiss

    let state: VocabularyEditorState
    let existingEntries: [VocabularyEntry]
    let onSave: (VocabularyEntry) -> Void

    @State private var term: String
    @State private var misheard: String

    init(
        state: VocabularyEditorState,
        existingEntries: [VocabularyEntry],
        onSave: @escaping (VocabularyEntry) -> Void
    ) {
        self.state = state
        self.existingEntries = existingEntries
        self.onSave = onSave
        _term = State(initialValue: state.term)
        _misheard = State(initialValue: state.misheard)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Metagraf", text: $term)
                        .textInputAutocapitalization(.words)
                } header: {
                    Text("Preferred Spelling")
                } footer: {
                    Text("Use the exact spelling you want in the transcript.")
                }

                Section {
                    TextField("meta graph, metagraph", text: $misheard, axis: .vertical)
                        .lineLimit(2...5)
                } header: {
                    Text("Also Heard As")
                } footer: {
                    Text("Optional. Separate common mistakes with commas.")
                }

                if isDuplicate {
                    Section {
                        Label("That preferred spelling is already in your vocabulary.", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle(state.entryID == nil ? "Add Term" : "Edit Term")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(
                            VocabularyEntry(
                                id: state.entryID ?? UUID(),
                                term: trimmedTerm,
                                misheard: parsedMisheard
                            )
                        )
                    }
                    .disabled(trimmedTerm.isEmpty || isDuplicate)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var trimmedTerm: String {
        term.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isDuplicate: Bool {
        existingEntries.contains {
            $0.id != state.entryID && $0.term.caseInsensitiveCompare(trimmedTerm) == .orderedSame
        }
    }

    private var parsedMisheard: [String] {
        var seen = Set<String>()
        return misheard.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { seen.insert($0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)).inserted }
    }
}

#Preview("Vocabulary") {
    let defaults = UserDefaults(suiteName: "VocabularyPreview")!
    let settings = SettingsStore(defaults: defaults)
    settings.vocabulary = [
        VocabularyEntry(term: "Metagraf", misheard: ["meta graph", "metagraph"]),
        VocabularyEntry(term: "SwiftUI"),
    ]
    return NavigationStack { VocabularySettingsView(settings: settings) }
}
#endif
