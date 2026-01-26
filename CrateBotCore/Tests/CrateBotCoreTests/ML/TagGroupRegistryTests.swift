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

    func testDefaultGroupsIncludeExpandedBassType() {
        let registry = TagGroupRegistry.defaultGroups

        // BassType should have 4 tags
        XCTAssertNotNil(registry.groupName(for: "Punchy"))
        XCTAssertNotNil(registry.groupName(for: "Walking"))
        XCTAssertNotNil(registry.groupName(for: "BoomingBass"))
        XCTAssertNotNil(registry.groupName(for: "GrindyBass"))

        // All should be in same group
        XCTAssertEqual(registry.groupName(for: "Punchy"), registry.groupName(for: "BoomingBass"))
    }

    func testDefaultGroupsIncludeVocalType() {
        let registry = TagGroupRegistry.defaultGroups

        // VocalType should exist with all 5 tags
        XCTAssertNotNil(registry.groupName(for: "Singing"))
        XCTAssertNotNil(registry.groupName(for: "Chanting"))
        XCTAssertNotNil(registry.groupName(for: "Spoken Word"))
        XCTAssertNotNil(registry.groupName(for: "Rap"))
        XCTAssertNotNil(registry.groupName(for: "Instrumental"))

        // All should be in same group
        XCTAssertEqual(registry.groupName(for: "Singing"), registry.groupName(for: "Instrumental"))
    }

    func testOldVibeGroupRemoved() {
        let registry = TagGroupRegistry.defaultGroups

        // Old Vibe group (Dark, Dope) should NOT exist as a multi-class group
        // These become binary vibes instead
        let darkGroup = registry.groupName(for: "Dark")
        let dopeGroup = registry.groupName(for: "Dope")

        // They should either be nil (not in any group) or not in a "Vibe" group
        if let darkGroup = darkGroup {
            XCTAssertNotEqual(darkGroup, "Vibe")
        }
        if let dopeGroup = dopeGroup {
            XCTAssertNotEqual(dopeGroup, "Vibe")
        }
    }
}
