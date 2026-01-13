import XCTest
@testable import CrateBotCore

final class LegacyImporterTests: XCTestCase {

    // MARK: - DetectedLegacyData Tests

    func testDetectedLegacyDataIsEmptyWhenNoData() {
        let data = LegacyModels.DetectedLegacyData(
            hasConfig: false,
            hasModels: false,
            modelCount: 0,
            hasRefinementSession: false,
            refinementEntryCount: 0,
            hasCheckpoints: false,
            checkpointCount: 0,
            hasCache: false,
            cacheFileCount: 0
        )

        XCTAssertTrue(data.isEmpty)
    }

    func testDetectedLegacyDataIsNotEmptyWithConfig() {
        let data = LegacyModels.DetectedLegacyData(
            hasConfig: true,
            hasModels: false,
            modelCount: 0,
            hasRefinementSession: false,
            refinementEntryCount: 0,
            hasCheckpoints: false,
            checkpointCount: 0,
            hasCache: false,
            cacheFileCount: 0
        )

        XCTAssertFalse(data.isEmpty)
    }

    func testDetectedLegacyDataIsNotEmptyWithModels() {
        let data = LegacyModels.DetectedLegacyData(
            hasConfig: false,
            hasModels: true,
            modelCount: 3,
            hasRefinementSession: false,
            refinementEntryCount: 0,
            hasCheckpoints: false,
            checkpointCount: 0,
            hasCache: false,
            cacheFileCount: 0
        )

        XCTAssertFalse(data.isEmpty)
    }

    func testDetectedLegacyDataIsNotEmptyWithRefinements() {
        let data = LegacyModels.DetectedLegacyData(
            hasConfig: false,
            hasModels: false,
            modelCount: 0,
            hasRefinementSession: true,
            refinementEntryCount: 5,
            hasCheckpoints: false,
            checkpointCount: 0,
            hasCache: false,
            cacheFileCount: 0
        )

        XCTAssertFalse(data.isEmpty)
    }

    func testDetectedLegacyDataIsNotEmptyWithCheckpoints() {
        let data = LegacyModels.DetectedLegacyData(
            hasConfig: false,
            hasModels: false,
            modelCount: 0,
            hasRefinementSession: false,
            refinementEntryCount: 0,
            hasCheckpoints: true,
            checkpointCount: 2,
            hasCache: false,
            cacheFileCount: 0
        )

        XCTAssertFalse(data.isEmpty)
    }

    func testDetectedLegacyDataIsNotEmptyWithCache() {
        let data = LegacyModels.DetectedLegacyData(
            hasConfig: false,
            hasModels: false,
            modelCount: 0,
            hasRefinementSession: false,
            refinementEntryCount: 0,
            hasCheckpoints: false,
            checkpointCount: 0,
            hasCache: true,
            cacheFileCount: 10
        )

        XCTAssertFalse(data.isEmpty)
    }

    // MARK: - LegacyConfig Decoding Tests

    func testLegacyConfigDecodingWithAllFields() throws {
        let json = """
        {
            "anthropic_api_key": "sk-ant-test123",
            "default_model": "claude-3-opus",
            "whisper_model": "large-v3",
            "enable_panns": true,
            "enable_essentia": false,
            "last_used_folder": "/Users/test/Music",
            "recent_folders": ["/Users/test/Music", "/Users/test/Downloads"]
        }
        """

        let data = json.data(using: .utf8)!
        let config = try JSONDecoder().decode(LegacyModels.LegacyConfig.self, from: data)

        XCTAssertEqual(config.anthropicApiKey, "sk-ant-test123")
        XCTAssertEqual(config.defaultModel, "claude-3-opus")
        XCTAssertEqual(config.whisperModel, "large-v3")
        XCTAssertEqual(config.enablePanns, true)
        XCTAssertEqual(config.enableEssentia, false)
        XCTAssertEqual(config.lastUsedFolder, "/Users/test/Music")
        XCTAssertEqual(config.recentFolders, ["/Users/test/Music", "/Users/test/Downloads"])
    }

    func testLegacyConfigDecodingWithPartialFields() throws {
        let json = """
        {
            "anthropic_api_key": "sk-ant-partial",
            "whisper_model": "medium"
        }
        """

        let data = json.data(using: .utf8)!
        let config = try JSONDecoder().decode(LegacyModels.LegacyConfig.self, from: data)

        XCTAssertEqual(config.anthropicApiKey, "sk-ant-partial")
        XCTAssertNil(config.defaultModel)
        XCTAssertEqual(config.whisperModel, "medium")
        XCTAssertNil(config.enablePanns)
        XCTAssertNil(config.enableEssentia)
        XCTAssertNil(config.lastUsedFolder)
        XCTAssertNil(config.recentFolders)
    }

    func testLegacyConfigDecodingEmptyObject() throws {
        let json = "{}"

        let data = json.data(using: .utf8)!
        let config = try JSONDecoder().decode(LegacyModels.LegacyConfig.self, from: data)

        XCTAssertNil(config.anthropicApiKey)
        XCTAssertNil(config.defaultModel)
        XCTAssertNil(config.whisperModel)
        XCTAssertNil(config.enablePanns)
        XCTAssertNil(config.enableEssentia)
        XCTAssertNil(config.lastUsedFolder)
        XCTAssertNil(config.recentFolders)
    }

    // MARK: - LegacyRefinementEntry Decoding Tests

    func testLegacyRefinementEntryDecoding() throws {
        let json = """
        {
            "file_path": "/Users/test/Music/track.mp3",
            "original_tags": {
                "genre": "House",
                "mood": "energetic"
            },
            "corrected_tags": {
                "genre": "Tech House",
                "mood": "driving"
            },
            "timestamp": "2024-01-15T10:30:00Z"
        }
        """

        let data = json.data(using: .utf8)!
        let entry = try JSONDecoder().decode(LegacyModels.LegacyRefinementEntry.self, from: data)

        XCTAssertEqual(entry.filePath, "/Users/test/Music/track.mp3")
        XCTAssertEqual(entry.originalTags["genre"], "House")
        XCTAssertEqual(entry.originalTags["mood"], "energetic")
        XCTAssertEqual(entry.correctedTags["genre"], "Tech House")
        XCTAssertEqual(entry.correctedTags["mood"], "driving")
        XCTAssertEqual(entry.timestamp, "2024-01-15T10:30:00Z")
    }

    func testLegacyRefinementEntryArrayDecoding() throws {
        let json = """
        [
            {
                "file_path": "/track1.mp3",
                "original_tags": {"genre": "House"},
                "corrected_tags": {"genre": "Deep House"},
                "timestamp": "2024-01-15T10:00:00Z"
            },
            {
                "file_path": "/track2.mp3",
                "original_tags": {"genre": "Techno"},
                "corrected_tags": {"genre": "Minimal"},
                "timestamp": "2024-01-15T11:00:00Z"
            }
        ]
        """

        let data = json.data(using: .utf8)!
        let entries = try JSONDecoder().decode([LegacyModels.LegacyRefinementEntry].self, from: data)

        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].filePath, "/track1.mp3")
        XCTAssertEqual(entries[1].filePath, "/track2.mp3")
    }

    // MARK: - ImportError Tests

    func testImportErrorDescriptions() {
        let noLegacyDataError = LegacyImporter.ImportError.noLegacyData
        XCTAssertEqual(noLegacyDataError.errorDescription, "No legacy CrateBot3 data found")

        let backupFailedError = LegacyImporter.ImportError.backupFailed("Disk full")
        XCTAssertEqual(backupFailedError.errorDescription, "Backup failed: Disk full")

        let migrationFailedError = LegacyImporter.ImportError.migrationFailed("Invalid format")
        XCTAssertEqual(migrationFailedError.errorDescription, "Migration failed: Invalid format")

        let rollbackFailedError = LegacyImporter.ImportError.rollbackFailed("Backup not found")
        XCTAssertEqual(rollbackFailedError.errorDescription, "Rollback failed: Backup not found")
    }
}
