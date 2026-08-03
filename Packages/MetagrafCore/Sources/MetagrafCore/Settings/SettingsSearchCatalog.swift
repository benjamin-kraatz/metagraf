import Foundation

/// Stable routes and bilingual aliases used by the mobile Settings search UI.
public enum SettingsSearchRouteID: String, CaseIterable, Sendable {
    case dictation, refinement, persona, vocabulary, historyPrivacy, keyboard, privacyPolicy, requirements
}

public enum SettingsSearchCatalog {
    private static let terms: [SettingsSearchRouteID: [String]] = [
        .dictation: ["dictation", "language", "locale", "sound", "sprache", "gebietsschema", "ton"],
        .refinement: ["refinement", "style", "format", "apple intelligence", "cleanup", "überarbeitung", "stil", "formatierung", "bereinigen"],
        .persona: ["persona", "adaptation", "voice", "tone", "strength", "anpassung", "tonfall", "stärke", "programmierer"],
        .vocabulary: ["vocabulary", "words", "spelling", "misheard", "wörterbuch", "vokabular", "schreibweise", "verhört"],
        .historyPrivacy: ["history", "privacy", "retention", "transcripts", "verlauf", "datenschutz", "aufbewahrung", "transkripte"],
        .keyboard: ["keyboard", "shortcut", "full access", "action button", "tastatur", "kurzbefehl", "vollzugriff", "aktionstaste"],
        .privacyPolicy: ["privacy policy", "data", "audio", "on device", "datenschutzerklärung", "daten", "lokal"],
        .requirements: ["apple intelligence requirements", "unsupported", "download", "model", "siri", "voraussetzungen", "nicht unterstützt", "modell", "sprache"],
    ]

    public static func results(for query: String) -> [SettingsSearchRouteID] {
        let query = normalize(query)
        guard !query.isEmpty else { return [] }
        return SettingsSearchRouteID.allCases.filter { route in
            terms[route, default: []].contains { normalize($0).contains(query) }
        }
    }

    private static func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }
}
