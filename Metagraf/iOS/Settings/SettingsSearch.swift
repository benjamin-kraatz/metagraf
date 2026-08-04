#if os(iOS)
import MetagrafCore
import SwiftUI

struct SettingsSearchItem: Identifiable {
    let route: MobileSettingsRoute
    let title: LocalizedStringKey
    let displayTitle: String
    let breadcrumb: String
    let keywords: [String]
    let currentValue: (SettingsStore) -> String?

    var id: MobileSettingsRoute { route }

    func matches(_ query: String) -> Bool {
        let normalizedQuery = Self.normalize(query)
        guard !normalizedQuery.isEmpty else { return true }
        return ([displayTitle, breadcrumb] + keywords)
            .map(Self.normalize)
            .contains { $0.contains(normalizedQuery) }
    }

    static func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
    }
}

enum SettingsSearchIndex {
    static let items: [SettingsSearchItem] = [
        SettingsSearchItem(
            route: .dictation,
            title: "Dictation",
            displayTitle: String(localized: "Dictation"),
            breadcrumb: String(localized: "Settings › Dictation"),
            keywords: ["language", "locale", "sound", "audio", "sprache", "gebietsschema", "ton", "klang"],
            currentValue: { SupportedLocales.name(for: $0.effectiveLocale) }
        ),
        SettingsSearchItem(
            route: .refinement,
            title: "Refinement",
            displayTitle: String(localized: "Refinement"),
            breadcrumb: String(localized: "Settings › Refinement"),
            keywords: ["style", "format", "apple intelligence", "cleanup", "email", "message", "notes", "stil", "formatierung", "bereinigen", "nachricht", "notizen"],
            currentValue: { String(localized: String.LocalizationValue($0.refinementStyle.displayName)) }
        ),
        SettingsSearchItem(
            route: .persona,
            title: "Persona & Adaptation",
            displayTitle: String(localized: "Persona & Adaptation"),
            breadcrumb: String(localized: "Settings › Refinement"),
            keywords: ["voice", "tone", "strength", "writer", "programmer", "persona", "anpassung", "stärke", "tonfall", "programmierer"],
            currentValue: { String(localized: String.LocalizationValue($0.refinementPersona.displayName)) }
        ),
        SettingsSearchItem(
            route: .vocabulary,
            title: "Vocabulary",
            displayTitle: String(localized: "Vocabulary"),
            breadcrumb: String(localized: "Settings › Tools"),
            keywords: ["words", "spelling", "misheard", "names", "wörterbuch", "schreibweise", "verhört", "namen"],
            currentValue: { $0.vocabulary.count.formatted() }
        ),
        SettingsSearchItem(
            route: .historyPrivacy,
            title: "History & Privacy",
            displayTitle: String(localized: "History & Privacy"),
            breadcrumb: String(localized: "Settings › History & Privacy"),
            keywords: ["retention", "transcripts", "storage", "local", "history", "privacy", "verlauf", "datenschutz", "aufbewahrung", "transkripte"],
            currentValue: { retentionValue($0.retentionDays) }
        ),
        SettingsSearchItem(
            route: .keyboard,
            title: "Keyboard & Shortcuts",
            displayTitle: String(localized: "Keyboard & Shortcuts"),
            breadcrumb: String(localized: "Settings › Tools"),
            keywords: ["extension", "full access", "action button", "control centre", "shortcut", "tastatur", "vollzugriff", "aktionstaste", "kontrollzentrum", "kurzbefehl"],
            currentValue: { _ in nil }
        ),
        SettingsSearchItem(
            route: .privacyPolicy,
            title: "Privacy Policy",
            displayTitle: String(localized: "Privacy Policy"),
            breadcrumb: String(localized: "Settings › Help & Legal"),
            keywords: ["data", "audio", "on device", "privacy", "daten", "audio", "lokal", "datenschutz"],
            currentValue: { _ in nil }
        ),
        SettingsSearchItem(
            route: .requirements,
            title: "Apple Intelligence Requirements",
            displayTitle: String(localized: "Apple Intelligence Requirements"),
            breadcrumb: String(localized: "Settings › Help & Legal"),
            keywords: ["unsupported", "download", "model", "siri", "language", "nicht unterstützt", "laden", "modell", "sprache", "voraussetzungen"],
            currentValue: { _ in nil }
        ),
    ]

    static func results(for query: String) -> [SettingsSearchItem] {
        let routes = Set(SettingsSearchCatalog.results(for: query).map(\.rawValue))
        return items.filter { routes.contains($0.route.rawValue) || $0.matches(query) }
    }

    private static func retentionValue(_ days: Int) -> String {
        switch days {
        case 0: String(localized: "Don’t keep any")
        case 7: String(localized: "7 days")
        case 30: String(localized: "30 days")
        case 90: String(localized: "90 days")
        default: String(localized: "Forever")
        }
    }
}

struct SettingsSearchResults: View {
    let query: String
    @Bindable var settings: SettingsStore
    let availability: RefinementAvailabilityModel

    private var results: [SettingsSearchItem] {
        SettingsSearchIndex.results(for: query)
    }

    var body: some View {
        List {
            if results.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                ForEach(results) { item in
                    NavigationLink(value: item.route) {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(item.title)
                                    .font(.body.weight(.medium))
                                Spacer()
                                if let value = item.currentValue(settings) {
                                    Text(value)
                                        .font(.callout)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Text(item.breadcrumb)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .accessibilityLabel("Settings search results")
    }
}

#Preview("Search results") {
    NavigationStack {
        SettingsSearchResults(
            query: "Sprache",
            settings: SettingsStore(defaults: UserDefaults(suiteName: "SearchPreview")!),
            availability: RefinementAvailabilityModel(state: .available)
        )
    }
}
#endif
