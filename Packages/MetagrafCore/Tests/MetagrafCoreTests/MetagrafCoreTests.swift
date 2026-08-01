import Foundation
import Testing

@testable import MetagrafCore

@Test func supportDirectoryIsNamespacedByBundleIdentifier() {
    #expect(Metagraf.supportDirectory.lastPathComponent == Metagraf.bundleIdentifier)
    #expect(Metagraf.modelsDirectory.lastPathComponent == "Models")
}
