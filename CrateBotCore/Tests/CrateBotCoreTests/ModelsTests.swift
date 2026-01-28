import XCTest
import SwiftData
@testable import CrateBotCore

final class ModelsTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!

    override func setUp() async throws {
        let schema = Schema([CachedFeatures.self, TagOverride.self])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: schema, configurations: [config])
        context = ModelContext(container)
    }

    func testCachedFeaturesCreation() throws {
        let features = CachedFeatures(
            audioHash: "abc123",
            compressedFeatures: Data([0x01, 0x02, 0x03]),
            pipelineVersion: "v1.0",
            featureCount: 512
        )

        context.insert(features)
        try context.save()

        let descriptor = FetchDescriptor<CachedFeatures>()
        let fetched = try context.fetch(descriptor)

        XCTAssertEqual(fetched.count, 1)
        XCTAssertEqual(fetched.first?.audioHash, "abc123")
        XCTAssertEqual(fetched.first?.featureCount, 512)
    }

    func testTagOverrideWithDefaults() throws {
        let override = TagOverride(audioHash: "xyz789")

        XCTAssertNil(override.genre)
        XCTAssertEqual(override.mood, [])
        XCTAssertNil(override.timing)
        XCTAssertEqual(override.descriptive, [])
    }

    func testTagOverrideWithValues() throws {
        let override = TagOverride(
            audioHash: "xyz789",
            genre: "House",
            mood: ["energetic", "uplifting"],
            timing: "Peak",
            descriptive: ["funky", "groovy"]
        )

        context.insert(override)
        try context.save()

        let descriptor = FetchDescriptor<TagOverride>()
        let fetched = try context.fetch(descriptor)

        XCTAssertEqual(fetched.first?.mood, ["energetic", "uplifting"])
        XCTAssertEqual(fetched.first?.descriptive, ["funky", "groovy"])
    }
}
