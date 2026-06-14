import XCTest
@testable import CrateBotCore

final class KeychainManagerTests: XCTestCase {
    func testNormalizedCredentialTrimsWhitespace() {
        XCTAssertEqual(
            KeychainManager.normalizedCredential("  sk-ant-test\n"),
            "sk-ant-test"
        )
    }

    func testNormalizedCredentialCanBeEmpty() {
        XCTAssertTrue(KeychainManager.normalizedCredential(" \n\t").isEmpty)
    }
}
