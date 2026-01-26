import XCTest
@testable import CrateBotCore

final class ModelMetadataTests: XCTestCase {

    func testDescriptiveSubCategoriesEncodeDecode() throws {
        let subCategories: [String: [String]] = [
            "BassType": ["Punchy", "Walking"],
            "Rhythm": ["Broken", "Driving"],
            "Vibes": ["Funky", "Dark"]
        ]

        let metadata = ModelMetadata(
            name: "TestModel",
            version: "1.0",
            pipelineVersion: "1.0",
            trainedAt: Date(),
            trainingFileCount: 100,
            categories: ["Descriptive"],
            tags: ["Descriptive": ["Punchy", "Walking", "Broken", "Driving", "Funky", "Dark"]],
            tagGroups: [],
            accuracy: 0.9,
            featureDimension: 1280,
            calibratorTemperature: nil,
            descriptiveSubCategories: subCategories
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(metadata)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ModelMetadata.self, from: data)

        XCTAssertEqual(decoded.descriptiveSubCategories?["BassType"], ["Punchy", "Walking"])
        XCTAssertEqual(decoded.descriptiveSubCategories?["Rhythm"], ["Broken", "Driving"])
        XCTAssertEqual(decoded.descriptiveSubCategories?["Vibes"], ["Funky", "Dark"])
    }

    func testBackwardsCompatibilityWithoutSubCategories() throws {
        // JSON without descriptiveSubCategories field (old format)
        let oldJson = """
        {
            "name": "OldModel",
            "version": "1.0",
            "pipelineVersion": "1.0",
            "trainedAt": 0,
            "trainingFileCount": 50,
            "categories": ["Descriptive"],
            "tags": {"Descriptive": ["Funky"]},
            "tagGroups": [],
            "featureDimension": 1280
        }
        """

        let decoder = JSONDecoder()
        let metadata = try decoder.decode(ModelMetadata.self, from: oldJson.data(using: .utf8)!)

        // Should decode without error, descriptiveSubCategories should be nil
        XCTAssertNil(metadata.descriptiveSubCategories)
        XCTAssertEqual(metadata.name, "OldModel")
    }
}
