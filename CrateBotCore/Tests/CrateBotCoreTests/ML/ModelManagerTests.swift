import XCTest
@testable import CrateBotCore

final class ModelManagerTests: XCTestCase {

    // MARK: - ModelMetadata Tests

    func testModelMetadataEncodingDecoding() throws {
        let metadata = ModelMetadata(
            name: "TestModel",
            version: "1.0.0",
            pipelineVersion: "v2",
            trainedAt: Date(timeIntervalSince1970: 1700000000),
            trainingFileCount: 500,
            categories: ["Genre", "Mood"],
            tags: ["Genre": ["Rock", "Jazz"], "Mood": ["Energetic", "Calm"]],
            accuracy: 0.85
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(metadata)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ModelMetadata.self, from: data)

        XCTAssertEqual(decoded.name, "TestModel")
        XCTAssertEqual(decoded.version, "1.0.0")
        XCTAssertEqual(decoded.pipelineVersion, "v2")
        XCTAssertEqual(decoded.trainingFileCount, 500)
        XCTAssertEqual(decoded.categories, ["Genre", "Mood"])
        XCTAssertEqual(decoded.tags["Genre"], ["Rock", "Jazz"])
        XCTAssertEqual(decoded.tags["Mood"], ["Energetic", "Calm"])
        XCTAssertEqual(decoded.accuracy, 0.85)
    }

    func testModelMetadataWithNilAccuracy() throws {
        let metadata = ModelMetadata(
            name: "TestModel",
            version: "1.0.0",
            pipelineVersion: "v2",
            trainedAt: Date(),
            trainingFileCount: 100,
            categories: [],
            tags: [:],
            accuracy: nil
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(metadata)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(ModelMetadata.self, from: data)

        XCTAssertNil(decoded.accuracy)
    }

    func testModelMetadataSaveAndLoad() throws {
        let tempDir = FileManager.default.temporaryDirectory
        let metadataURL = tempDir.appendingPathComponent("test_metadata.json")

        let metadata = ModelMetadata(
            name: "SaveLoadTest",
            version: "2.0.0",
            pipelineVersion: "v3",
            trainedAt: Date(timeIntervalSince1970: 1700000000),
            trainingFileCount: 1000,
            categories: ["Timing"],
            tags: ["Timing": ["Fast", "Slow"]],
            accuracy: 0.92
        )

        try metadata.save(to: metadataURL)
        let loaded = try ModelMetadata.load(from: metadataURL)

        XCTAssertEqual(loaded.name, "SaveLoadTest")
        XCTAssertEqual(loaded.version, "2.0.0")
        XCTAssertEqual(loaded.pipelineVersion, "v3")
        XCTAssertEqual(loaded.trainingFileCount, 1000)
        XCTAssertEqual(loaded.accuracy, 0.92)

        // Cleanup
        try? FileManager.default.removeItem(at: metadataURL)
    }

    // MARK: - AvailableModel Tests

    func testAvailableModelIdentifiable() {
        let model = AvailableModel(
            name: "TestModel",
            url: URL(fileURLWithPath: "/tmp/test.mlmodelc"),
            metadata: nil,
            isDefault: false
        )

        XCTAssertEqual(model.id, "TestModel")
        XCTAssertEqual(model.name, "TestModel")
        XCTAssertFalse(model.isDefault)
    }

    func testAvailableModelWithMetadata() {
        let metadata = ModelMetadata(
            name: "TestModel",
            version: "1.0.0",
            pipelineVersion: "v1",
            trainedAt: Date(),
            trainingFileCount: 50,
            categories: [],
            tags: [:]
        )

        let model = AvailableModel(
            name: "TestModel",
            url: URL(fileURLWithPath: "/tmp/test.mlmodelc"),
            metadata: metadata,
            isDefault: true
        )

        XCTAssertNotNil(model.metadata)
        XCTAssertEqual(model.metadata?.version, "1.0.0")
        XCTAssertTrue(model.isDefault)
    }

    // MARK: - ModelError Tests

    func testModelErrorDescriptions() {
        let notFound = ModelManager.ModelError.modelNotFound("TestModel")
        XCTAssertEqual(notFound.errorDescription, "Model not found: TestModel")

        let loadFailed = ModelManager.ModelError.loadFailed("Corrupted file")
        XCTAssertEqual(loadFailed.errorDescription, "Failed to load model: Corrupted file")

        let incompatible = ModelManager.ModelError.incompatiblePipelineVersion(expected: "v2", found: "v1")
        XCTAssertEqual(incompatible.errorDescription, "Model pipeline version mismatch: expected v2, found v1")

        let noModels = ModelManager.ModelError.noModelsAvailable
        XCTAssertEqual(noModels.errorDescription, "No models available")
    }

    // MARK: - ModelManager Tests

    func testModelManagerListModelsReturnsArray() async {
        let manager = ModelManager(additionalDirectories: [])
        let models = await manager.listModels()

        // Should return an array (may be empty if no models installed)
        XCTAssertNotNil(models)
    }

    func testModelManagerWithCustomDirectory() async throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("TestModels")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

        let manager = ModelManager(additionalDirectories: [tempDir])
        let models = await manager.listModels()

        // Empty directory should return empty array
        XCTAssertEqual(models.count, 0)

        // Cleanup
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testModelManagerGetModelReturnsNilForMissing() async {
        let manager = ModelManager(additionalDirectories: [])
        let model = await manager.getModel(named: "NonExistentModel")

        XCTAssertNil(model)
    }

    func testModelManagerModelsDirectory() async throws {
        let manager = ModelManager(additionalDirectories: [])
        let dir = try await manager.modelsDirectory()

        XCTAssertTrue(dir.path.contains("CrateBot/Models"))
    }
}
