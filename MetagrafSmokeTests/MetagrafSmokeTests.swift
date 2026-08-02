import XCTest

final class MetagrafSmokeTests: XCTestCase {
    func testBundleLoads() {
        let testBundle = Bundle(for: Self.self)

        XCTAssertEqual(testBundle.bundleURL.pathExtension, "xctest")
        XCTAssertNotNil(testBundle.bundleIdentifier)
    }
}
