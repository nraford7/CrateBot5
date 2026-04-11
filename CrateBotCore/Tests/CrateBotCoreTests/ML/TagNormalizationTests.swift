import XCTest
@testable import CrateBotCore

final class TagNormalizationTests: XCTestCase {

    func testNormalizeTagTitleCases() {
        XCTAssertEqual(TagNormalizer.normalize("house"), "House")
        XCTAssertEqual(TagNormalizer.normalize("HOUSE"), "House")
        XCTAssertEqual(TagNormalizer.normalize("House"), "House")
    }

    func testNormalizeTagPreservesMultiWord() {
        XCTAssertEqual(TagNormalizer.normalize("deep house"), "Deep House")
        XCTAssertEqual(TagNormalizer.normalize("DEEP HOUSE"), "Deep House")
    }

    func testNormalizeTagTrimsWhitespace() {
        XCTAssertEqual(TagNormalizer.normalize("  house  "), "House")
        XCTAssertEqual(TagNormalizer.normalize("house\t"), "House")
    }

    func testNormalizeTagHandlesEmpty() {
        XCTAssertEqual(TagNormalizer.normalize(""), "")
        XCTAssertEqual(TagNormalizer.normalize("   "), "")
    }

    func testNormalizeTagHandlesSlashes() {
        XCTAssertEqual(TagNormalizer.normalize("dub/reggae"), "Dub/Reggae")
    }

    func testNormalizeTagPreservesSlashWithSpaces() {
        XCTAssertEqual(TagNormalizer.normalize("deep house/techno"), "Deep House/Techno")
        XCTAssertEqual(TagNormalizer.normalize("DRUM AND BASS/JUNGLE"), "Drum And Bass/Jungle")
    }
}
