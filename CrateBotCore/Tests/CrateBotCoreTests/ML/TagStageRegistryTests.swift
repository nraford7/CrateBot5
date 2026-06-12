import XCTest
@testable import CrateBotCore

final class TagStageRegistryTests: XCTestCase {

    // MARK: - Category → stage mapping

    func testTimingCategoryMapsToJudgment() {
        let registry = TagStageRegistry()
        XCTAssertEqual(registry.stage(forCategory: "Timing"), .judgment)
    }

    func testPerceptionCategoriesMapToPerception() {
        let registry = TagStageRegistry()
        XCTAssertEqual(registry.stage(forCategory: "Genre"), .perception)
        XCTAssertEqual(registry.stage(forCategory: "Mood"), .perception)
        XCTAssertEqual(registry.stage(forCategory: "Descriptive"), .perception)
    }

    func testUnknownCategoryDefaultsToPerception() {
        let registry = TagStageRegistry()
        XCTAssertEqual(registry.stage(forCategory: "SomethingNew"), .perception)
        XCTAssertEqual(registry.stage(forCategory: ""), .perception)
    }

    // MARK: - Reverse lookup

    func testCategoriesInJudgmentStage() {
        let registry = TagStageRegistry()
        XCTAssertEqual(registry.categories(in: .judgment), ["Timing"])
    }

    func testCategoriesInPerceptionStageAreSorted() {
        let registry = TagStageRegistry()
        XCTAssertEqual(registry.categories(in: .perception), ["Descriptive", "Genre", "Mood"])
    }

    // MARK: - Custom mapping injection

    func testCustomMappingOverridesDefault() {
        let registry = TagStageRegistry(categoryToStage: ["Scene": .judgment])
        XCTAssertEqual(registry.stage(forCategory: "Scene"), .judgment)
        // Timing is absent from the custom mapping → safe default
        XCTAssertEqual(registry.stage(forCategory: "Timing"), .perception)
    }
}
