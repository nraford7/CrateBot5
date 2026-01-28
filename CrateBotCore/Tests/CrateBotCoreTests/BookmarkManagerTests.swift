import XCTest
@testable import CrateBotCore

final class BookmarkManagerTests: XCTestCase {
    var manager: BookmarkManager!
    var testDefaults: UserDefaults!

    override func setUp() {
        testDefaults = UserDefaults(suiteName: "BookmarkManagerTests")!
        testDefaults.removePersistentDomain(forName: "BookmarkManagerTests")
        manager = BookmarkManager(userDefaults: testDefaults)
    }

    override func tearDown() {
        manager.stopAllAccess()
        testDefaults.removePersistentDomain(forName: "BookmarkManagerTests")
    }

    func testInitialStateIsEmpty() {
        XCTAssertTrue(manager.musicFolderURLs.isEmpty)
    }

    func testHasAccessReturnsFalseForUnknownURL() {
        let unknownURL = URL(fileURLWithPath: "/some/random/path")
        XCTAssertFalse(manager.hasAccess(to: unknownURL))
    }

    func testRestoreResultForEmptyBookmarks() {
        let results = manager.restoreAllAccess()
        XCTAssertTrue(results.isEmpty)
    }
}
