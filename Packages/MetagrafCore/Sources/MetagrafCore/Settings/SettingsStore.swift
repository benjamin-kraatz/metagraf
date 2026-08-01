import Foundation
import OSLog

/// Every user-facing preference, backed by `UserDefaults`.
///
/// Values are held as stored properties so SwiftUI observes them, and written
/// through on assignment so nothing is lost if the app exits abruptly.
@MainActor
@Observable
public final class SettingsStore {
    public static let shared = SettingsStore()

    private let defaults: UserDefaults
    private let logger = Logger(subsystem: Metagraf.bundleIdentifier, category: "Settings")

    // MARK: - Dictation

    /// Empty means "follow the system language".
    public var localeIdentifier: String {
        didSet { write(localeIdentifier, .locale) }
    }

    /// Raw value of the modifier key that starts dictation. Stored as a string
    /// so the core package does not need to know about macOS key codes.
    public var hotKey: String {
        didSet { write(hotKey, .hotKey) }
    }

    /// Holds shorter than this are treated as accidental.
    public var minimumHold: TimeInterval {
        didSet { write(minimumHold, .minimumHold) }
    }

    /// Two taps this close together latch recording on.
    public var doubleTapWindow: TimeInterval {
        didSet { write(doubleTapWindow, .doubleTapWindow) }
    }

    public var insertion: InsertionStrategy {
        didSet { write(insertion.rawValue, .insertion) }
    }

    /// Identifier of the chosen model from `ModelCatalog`.
    public var modelID: String {
        didSet { write(modelID, .model) }
    }

    /// How transcripts are tidied before insertion.
    public var refinementStyle: RefinementStyle {
        didSet { write(refinementStyle.rawValue, .refinementStyle) }
    }

    // MARK: - Appearance

    /// Whether the pill stays visible when nothing is happening.
    public var showPillWhenIdle: Bool {
        didSet { write(showPillWhenIdle, .showPillWhenIdle) }
    }

    public var launchAtLogin: Bool {
        didSet { write(launchAtLogin, .launchAtLogin) }
    }

    // MARK: - History

    /// How long transcripts are kept. Zero means nothing is ever written down.
    public var retentionDays: Int {
        didSet { write(retentionDays, .retentionDays) }
    }

    public var vocabulary: [VocabularyEntry] {
        didSet { writeJSON(vocabulary, .vocabulary) }
    }

    public var appRules: [AppRule] {
        didSet { writeJSON(appRules, .appRules) }
    }

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        localeIdentifier = defaults.string(forKey: Key.locale.rawValue) ?? ""
        hotKey = defaults.string(forKey: Key.hotKey.rawValue) ?? "rightOption"
        minimumHold = defaults.object(forKey: Key.minimumHold.rawValue) as? TimeInterval ?? 0.25
        doubleTapWindow = defaults.object(forKey: Key.doubleTapWindow.rawValue) as? TimeInterval ?? 0.4
        insertion = defaults.string(forKey: Key.insertion.rawValue)
            .flatMap(InsertionStrategy.init(rawValue:)) ?? .paste
        modelID = defaults.string(forKey: Key.model.rawValue) ?? ModelCatalog.default.id
        refinementStyle = defaults.string(forKey: Key.refinementStyle.rawValue)
            .flatMap(RefinementStyle.init(rawValue:)) ?? .cleanup
        showPillWhenIdle = defaults.object(forKey: Key.showPillWhenIdle.rawValue) as? Bool ?? true
        launchAtLogin = defaults.object(forKey: Key.launchAtLogin.rawValue) as? Bool ?? false
        retentionDays = defaults.object(forKey: Key.retentionDays.rawValue) as? Int ?? 30

        vocabulary = Self.readJSON([VocabularyEntry].self, .vocabulary, from: defaults) ?? []
        appRules = Self.readJSON([AppRule].self, .appRules, from: defaults) ?? []
    }

    /// The locale dictation should use, resolving "follow the system".
    public var effectiveLocale: Locale {
        localeIdentifier.isEmpty ? .current : Locale(identifier: localeIdentifier)
    }

    /// Terms to bias recognition toward.
    public var contextualStrings: [String] {
        vocabulary.map(\.term).filter { !$0.isEmpty }
    }

    /// The insertion strategy for a given app, honouring any rule for it.
    public func insertion(forBundleIdentifier bundleID: String?) -> InsertionStrategy {
        guard
            let bundleID,
            let rule = appRules.first(where: { $0.bundleIdentifier == bundleID }),
            let override = rule.insertion
        else {
            return insertion
        }
        return override
    }

    // MARK: - Storage

    private enum Key: String {
        case locale = "dictation.locale"
        case hotKey = "dictation.hotKey"
        case minimumHold = "dictation.minimumHold"
        case doubleTapWindow = "dictation.doubleTapWindow"
        case insertion = "dictation.insertion"
        case model = "dictation.model"
        case refinementStyle = "refinement.style"
        case showPillWhenIdle = "appearance.showPillWhenIdle"
        case launchAtLogin = "general.launchAtLogin"
        case retentionDays = "history.retentionDays"
        case vocabulary = "vocabulary.entries"
        case appRules = "rules.apps"
    }

    private func write(_ value: Any, _ key: Key) {
        defaults.set(value, forKey: key.rawValue)
    }

    private func writeJSON(_ value: some Encodable, _ key: Key) {
        do {
            defaults.set(try JSONEncoder().encode(value), forKey: key.rawValue)
        } catch {
            logger.error("Could not save \(key.rawValue, privacy: .public)")
        }
    }

    private static func readJSON<T: Decodable>(
        _ type: T.Type,
        _ key: Key,
        from defaults: UserDefaults
    ) -> T? {
        guard let data = defaults.data(forKey: key.rawValue) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}
