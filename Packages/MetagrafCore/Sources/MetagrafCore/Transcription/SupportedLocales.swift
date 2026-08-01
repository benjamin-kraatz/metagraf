import Foundation
import Speech

/// Which languages the on-device engine can handle, and which are downloaded.
public enum SupportedLocales {
    /// Every locale Apple's transcriber supports, sorted by display name.
    public static func all() async -> [Locale] {
        await SpeechTranscriber.supportedLocales.sorted { left, right in
            name(for: left).localizedStandardCompare(name(for: right)) == .orderedAscending
        }
    }

    /// Locales whose speech assets are already on the device, so choosing them
    /// costs no download.
    public static func installed() async -> Set<String> {
        Set(await SpeechTranscriber.installedLocales.map(\.identifier))
    }

    /// A human-readable name for a locale, in the user's own language.
    public static func name(for locale: Locale) -> String {
        Locale.current.localizedString(forIdentifier: locale.identifier)
            ?? locale.identifier
    }
}
