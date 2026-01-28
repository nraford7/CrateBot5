import XCTest
@testable import CrateBotCore

final class AudioPlayerTests: XCTestCase {
    func testInitialState() {
        let player = AudioPlayer()

        XCTAssertFalse(player.isPlaying)
        XCTAssertEqual(player.currentTime, 0)
        XCTAssertEqual(player.duration, 0)
    }

    func testPlayNonexistentFile() {
        let player = AudioPlayer()
        let fakeURL = URL(fileURLWithPath: "/nonexistent/file.mp3")

        do {
            try player.play(url: fakeURL)
            XCTFail("Should throw for nonexistent file")
        } catch {
            XCTAssertFalse(player.isPlaying)
        }
    }
}
