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

    func testTagThresholdsEncodeDecode() throws {
        let thresholds: [String: Float] = [
            "Funky": 0.7,
            "Dark": 0.9,
            "Driving": 0.6
        ]

        let metadata = ModelMetadata(
            name: "ThresholdModel",
            version: "1.0",
            pipelineVersion: "1.0",
            trainedAt: Date(),
            trainingFileCount: 100,
            categories: ["Descriptive"],
            tags: ["Descriptive": ["Funky", "Dark", "Driving"]],
            tagGroups: [],
            accuracy: 0.85,
            featureDimension: 1280,
            calibratorTemperature: nil,
            descriptiveSubCategories: nil,
            tagThresholds: thresholds
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(metadata)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ModelMetadata.self, from: data)

        XCTAssertEqual(decoded.tagThresholds?["Funky"], 0.7)
        XCTAssertEqual(decoded.tagThresholds?["Dark"], 0.9)
        XCTAssertEqual(decoded.tagThresholds?["Driving"], 0.6)
        XCTAssertEqual(decoded.tagThresholds?.count, 3)
    }

    func testTagThresholdsBackwardCompatibility() throws {
        // JSON without tagThresholds field (old format)
        let oldJson = """
        {
            "name": "LegacyModel",
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

        XCTAssertNil(metadata.tagThresholds)
        XCTAssertEqual(metadata.name, "LegacyModel")
    }

    // MARK: - Stage 1/Stage 2 pairing fields

    func testStagePairingFieldsEncodeDecode() throws {
        let metadata = ModelMetadata(
            name: "TwoStageModel",
            version: "1.0",
            pipelineVersion: "1.0",
            trainedAt: Date(),
            trainingFileCount: 100,
            categories: ["Genre", "Timing"],
            tags: ["Genre": ["House"], "Timing": ["Peak"]],
            tagGroups: [],
            accuracy: 0.85,
            featureDimension: 2960,
            stage1ModelVersion: "stage1-abc123",
            judgmentColumnNames: ["bin_Dark", "grp_BassType_Punchy", "bpm", "duration"]
        )

        let data = try JSONEncoder().encode(metadata)
        let decoded = try JSONDecoder().decode(ModelMetadata.self, from: data)

        XCTAssertEqual(decoded.stage1ModelVersion, "stage1-abc123")
        XCTAssertEqual(decoded.judgmentColumnNames,
                       ["bin_Dark", "grp_BassType_Punchy", "bpm", "duration"])
    }

    func testStagePairingFieldsBackwardCompatibility() throws {
        // JSON from a pre-two-stage model: no stage1ModelVersion / judgmentColumnNames
        let oldJson = """
        {
            "name": "Stage1OnlyModel",
            "version": "1.0",
            "pipelineVersion": "1.0",
            "trainedAt": 0,
            "trainingFileCount": 50,
            "categories": ["Genre"],
            "tags": {"Genre": ["House"]},
            "tagGroups": [],
            "featureDimension": 1680
        }
        """

        let metadata = try JSONDecoder().decode(ModelMetadata.self, from: oldJson.data(using: .utf8)!)

        XCTAssertNil(metadata.stage1ModelVersion)
        XCTAssertNil(metadata.judgmentColumnNames)
        XCTAssertEqual(metadata.name, "Stage1OnlyModel")
    }
}
