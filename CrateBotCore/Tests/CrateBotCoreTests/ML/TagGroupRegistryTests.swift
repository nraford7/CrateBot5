import XCTest
@testable import CrateBotCore

final class TagGroupRegistryTests: XCTestCase {

    func testCreateAndFindGroup() {
        var registry = TagGroupRegistry()
        registry.addGroup(name: "BassType", tags: ["Walking", "Rolling", "Punchy"])

        XCTAssertEqual(registry.groupName(for: "Walking"), "BassType")
        XCTAssertEqual(registry.groupName(for: "WalkingBass"), "BassType")  // Partial match
        XCTAssertNil(registry.groupName(for: "Unknown"))
    }

    func testNormalizeTagToClass() {
        var registry = TagGroupRegistry()
        registry.addGroup(name: "BassType", tags: ["Walking", "Rolling"])

        XCTAssertEqual(registry.normalizeTagToClass("WalkingBass", inGroup: "BassType"), "Walking")
        XCTAssertEqual(registry.normalizeTagToClass("walking", inGroup: "BassType"), "Walking")
    }

    func testPersistence() throws {
        var registry = TagGroupRegistry()
        registry.addGroup(name: "Vibe", tags: ["Dope", "Chill"])

        let data = try JSONEncoder().encode(registry)
        let decoded = try JSONDecoder().decode(TagGroupRegistry.self, from: data)

        XCTAssertEqual(decoded.groups, registry.groups)
    }
}
