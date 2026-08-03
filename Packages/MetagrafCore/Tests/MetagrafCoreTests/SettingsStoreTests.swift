import Foundation
import Testing

@testable import MetagrafCore

/// A throwaway defaults domain so tests never touch the real preferences.
private func makeDefaults() -> UserDefaults {
    let suite = "MetagrafTests.\(UUID().uuidString)"
    return UserDefaults(suiteName: suite)!
}

@Suite("Settings")
@MainActor
struct SettingsStoreTests {
    @Test("Preferences survive a relaunch")
    func valuesPersist() {
        let defaults = makeDefaults()

        let first = SettingsStore(defaults: defaults)
        first.localeIdentifier = "de_DE"
        first.insertion = .accessibility
        first.retentionDays = 7
        first.refinementStyle = .intelligent
        first.usesNearbyAppContext = true
        first.refinementPersona = .programmer
        first.personaAdaptation = .prompting
        first.vocabulary = [VocabularyEntry(term: "Metagraf", misheard: ["meta graph"])]
        first.showDockIcon = true

        let second = SettingsStore(defaults: defaults)
        #expect(second.localeIdentifier == "de_DE")
        #expect(second.insertion == .accessibility)
        #expect(second.retentionDays == 7)
        #expect(second.refinementStyle == .intelligent)
        #expect(second.usesNearbyAppContext)
        #expect(second.refinementPersona == .programmer)
        #expect(second.personaAdaptation == .prompting)
        #expect(second.usesPromptingRefinement)
        #expect(second.vocabulary.map(\.term) == ["Metagraf"])
        #expect(second.vocabulary.first?.misheard == ["meta graph"])
        #expect(second.showDockIcon)
    }

    @Test("Refinement defaults are conservative")
    func refinementDefaults() {
        let settings = SettingsStore(defaults: makeDefaults())
        #expect(settings.refinementStyle == .cleanup)
        #expect(!settings.usesNearbyAppContext)
        #expect(settings.refinementPersona == .none)
        #expect(settings.personaAdaptation == .contextualPolish)
    }

    @Test("An empty language setting follows the system")
    func emptyLocaleFollowsSystem() {
        let settings = SettingsStore(defaults: makeDefaults())

        settings.localeIdentifier = ""
        #expect(settings.effectiveLocale == .current)

        settings.localeIdentifier = "fr_FR"
        #expect(settings.effectiveLocale.identifier == "fr_FR")
    }

    @Test("A per-app rule overrides the global insertion strategy")
    func appRuleOverridesInsertion() {
        let settings = SettingsStore(defaults: makeDefaults())
        settings.insertion = .paste
        settings.appRules = [
            AppRule(
                bundleIdentifier: "com.apple.Terminal",
                displayName: "Terminal",
                insertion: .clipboardOnly
            )
        ]

        #expect(settings.insertion(forBundleIdentifier: "com.apple.Terminal") == .clipboardOnly)
        #expect(settings.insertion(forBundleIdentifier: "com.apple.TextEdit") == .paste)
        #expect(settings.insertion(forBundleIdentifier: nil) == .paste)
    }

    @Test("A rule with no override falls back to the global strategy")
    func ruleWithoutOverrideFallsBack() {
        let settings = SettingsStore(defaults: makeDefaults())
        settings.insertion = .paste
        settings.appRules = [
            AppRule(bundleIdentifier: "com.apple.Terminal", displayName: "Terminal")
        ]

        #expect(settings.insertion(forBundleIdentifier: "com.apple.Terminal") == .paste)
    }

    @Test("Blank vocabulary terms are not sent to the engine")
    func contextualStringsSkipBlanks() {
        let settings = SettingsStore(defaults: makeDefaults())
        settings.vocabulary = [
            VocabularyEntry(term: "Kubernetes"),
            VocabularyEntry(term: ""),
            VocabularyEntry(term: "Metagraf"),
        ]

        #expect(settings.contextualStrings == ["Kubernetes", "Metagraf"])
    }
}
