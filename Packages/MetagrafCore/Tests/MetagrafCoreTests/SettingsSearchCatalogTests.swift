import Testing
@testable import MetagrafCore

@Suite("Settings search catalog")
struct SettingsSearchCatalogTests {
    @Test("English terms route to the expected page")
    func englishMatching() {
        #expect(SettingsSearchCatalog.results(for: "language") == [.dictation])
        #expect(SettingsSearchCatalog.results(for: "full access") == [.keyboard])
        #expect(SettingsSearchCatalog.results(for: "retention") == [.historyPrivacy])
    }

    @Test("German aliases and diacritics route correctly")
    func germanMatching() {
        #expect(SettingsSearchCatalog.results(for: "Sprache").contains(.dictation))
        #expect(SettingsSearchCatalog.results(for: "Starke") == [.persona])
        #expect(SettingsSearchCatalog.results(for: "Datenschutz").contains(.historyPrivacy))
        #expect(SettingsSearchCatalog.results(for: "Vollzugriff") == [.keyboard])
    }
}
