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

    func testPartialMatchingDoesNotOvermatch() {
        var registry = TagGroupRegistry()
        registry.addGroup(name: "Energy", tags: ["Low", "Medium", "High", "Peak"])

        // These should NOT match - different concepts
        XCTAssertNil(registry.groupName(for: "LowPitch"))
        XCTAssertNil(registry.groupName(for: "HighFidelity"))
        XCTAssertNil(registry.groupName(for: "MediumRare"))

        // These SHOULD match
        XCTAssertEqual(registry.groupName(for: "Low"), "Energy")
        XCTAssertEqual(registry.groupName(for: "LowEnergy"), "Energy")
        XCTAssertEqual(registry.groupName(for: "High"), "Energy")
    }

    func testPartialMatchingWithWordBoundaries() {
        var registry = TagGroupRegistry()
        registry.addGroup(name: "BassType", tags: ["Walking", "Rolling", "Punchy"])

        // Should match compound tags where class name is a word
        XCTAssertEqual(registry.groupName(for: "WalkingBass"), "BassType")
        XCTAssertEqual(registry.groupName(for: "Rolling_Bass"), "BassType")
        XCTAssertEqual(registry.groupName(for: "punchy-bass"), "BassType")

        // Should NOT match unrelated tags
        XCTAssertNil(registry.groupName(for: "Stalking"))
    }
}
