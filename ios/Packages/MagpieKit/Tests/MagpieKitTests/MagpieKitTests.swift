import XCTest
@testable import MagpieKit

final class MagpieKitTests: XCTestCase {
    func testVersion() {
        XCTAssertEqual(MagpieKit.version, "0.1.0")
    }
}
