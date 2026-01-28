import XCTest
@testable import CrateBotCore

final class CrateBotCoreTests: XCTestCase {
    func testVersion() {
        XCTAssertEqual(CrateBotCore.version, "1.0.0")
    }
}
