import Foundation

/// Namespace for values that are shared between the macOS app, the iOS app, and
/// the iOS keyboard extension.
public enum Metagraf {
    /// Bundle identifier of the containing app.
    public static let bundleIdentifier = "de.dzwei.apps.metagraf"

    /// App group used to share settings and history between the app and its extensions.
    public static let appGroupIdentifier = "group.de.dzwei.apps.metagraf"

    /// Directory holding downloaded speech models and the transcript database.
    public static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appending(path: bundleIdentifier, directoryHint: .isDirectory)
    }

    /// Directory holding downloaded speech models.
    public static var modelsDirectory: URL {
        supportDirectory.appending(path: "Models", directoryHint: .isDirectory)
    }
}
