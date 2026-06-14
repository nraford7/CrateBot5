import XCTest
@testable import CrateBotCore

final class ID3ManagerTests: XCTestCase {

    // MARK: - TagMapping Tests

    func testTagMappingIsGenreReturnsTrueForKnownGenres() {
        // Test all known genres
        XCTAssertTrue(TagMapping.isGenre("House"))
        XCTAssertTrue(TagMapping.isGenre("Techno"))
        XCTAssertTrue(TagMapping.isGenre("Jungle"))
        XCTAssertTrue(TagMapping.isGenre("Rap"))
        XCTAssertTrue(TagMapping.isGenre("DiscoFunk"))
        XCTAssertTrue(TagMapping.isGenre("PartyBreaks"))
        XCTAssertTrue(TagMapping.isGenre("Acapella"))
        XCTAssertTrue(TagMapping.isGenre("Dub/Reggae"))
    }

    func testTagMappingIsGenreReturnsFalseForUnknownValues() {
        // Test timing values that should not be treated as genres
        XCTAssertFalse(TagMapping.isGenre("Opener"))
        XCTAssertFalse(TagMapping.isGenre("Peak"))
        XCTAssertFalse(TagMapping.isGenre("Closer"))
        XCTAssertFalse(TagMapping.isGenre(""))
        XCTAssertFalse(TagMapping.isGenre("SomeRandomString"))
    }

    func testTagMappingIsGenreIsCaseInsensitive() {
        // Test that genre matching is case-insensitive
        XCTAssertTrue(TagMapping.isGenre("house"))
        XCTAssertTrue(TagMapping.isGenre("HOUSE"))
        XCTAssertTrue(TagMapping.isGenre("House"))
        XCTAssertTrue(TagMapping.isGenre("HoUsE"))
        XCTAssertTrue(TagMapping.isGenre("techno"))
        XCTAssertTrue(TagMapping.isGenre("TECHNO"))
        XCTAssertTrue(TagMapping.isGenre("discofunk"))
        XCTAssertTrue(TagMapping.isGenre("DISCOFUNK"))
        XCTAssertTrue(TagMapping.isGenre("dub/reggae"))
        XCTAssertTrue(TagMapping.isGenre("DUB/REGGAE"))
    }

    func testTagMappingKnownGenresCount() {
        // Verify we have exactly 8 known genres
        XCTAssertEqual(TagMapping.knownGenres.count, 8)
    }

    func testTagMappingFrameConstants() {
        // Verify frame constants are set correctly
        XCTAssertEqual(TagMapping.genre, "TCON")
        XCTAssertEqual(TagMapping.timing, "TALB")
        XCTAssertEqual(TagMapping.mood, "TIT1")
        XCTAssertEqual(TagMapping.comments, "COMM")
        XCTAssertEqual(TagMapping.vibeShort, "TCOM")
        XCTAssertEqual(TagMapping.vibeDescription, "TIT3")
        XCTAssertEqual(TagMapping.mixHint, "MVNM")
        XCTAssertEqual(TagMapping.scene, "TOWN")
        XCTAssertEqual(TagMapping.hook, "TEXT")
    }

    // MARK: - ExtractedTags Tests

    func testExtractedTagsDefaultInitialization() {
        let tags = ExtractedTags()

        XCTAssertNil(tags.title)
        XCTAssertNil(tags.artist)
        XCTAssertNil(tags.genre)
        XCTAssertNil(tags.timing)
        XCTAssertNil(tags.mood)
        XCTAssertNil(tags.comments)
        XCTAssertNil(tags.vibeShort)
        XCTAssertNil(tags.vibeDescription)
        XCTAssertNil(tags.mixHint)
        XCTAssertNil(tags.scene)
        XCTAssertNil(tags.hook)
    }

    func testExtractedTagsWithValues() {
        let tags = ExtractedTags(
            title: "Test Track",
            artist: "Test Artist",
            genre: "House",
            timing: "Peak",
            mood: "Energetic",
            comments: "Great track",
            vibeShort: "Uplifting",
            vibeDescription: "Perfect for summer parties",
            mixHint: "After a rough drop",
            scene: "Club",
            hook: "Catchy melody"
        )

        XCTAssertEqual(tags.title, "Test Track")
        XCTAssertEqual(tags.artist, "Test Artist")
        XCTAssertEqual(tags.genre, "House")
        XCTAssertEqual(tags.timing, "Peak")
        XCTAssertEqual(tags.mood, "Energetic")
        XCTAssertEqual(tags.comments, "Great track")
        XCTAssertEqual(tags.vibeShort, "Uplifting")
        XCTAssertEqual(tags.vibeDescription, "Perfect for summer parties")
        XCTAssertEqual(tags.mixHint, "After a rough drop")
        XCTAssertEqual(tags.scene, "Club")
        XCTAssertEqual(tags.hook, "Catchy melody")
    }

    func testExtractedTagsEquatable() {
        let tags1 = ExtractedTags(title: "Track", genre: "House", timing: "Peak")
        let tags2 = ExtractedTags(title: "Track", genre: "House", timing: "Peak")
        let tags3 = ExtractedTags(title: "Track", genre: "Techno", timing: "Peak")

        XCTAssertEqual(tags1, tags2)
        XCTAssertNotEqual(tags1, tags3)
    }

    // MARK: - TagsToWrite Tests

    func testTagsToWriteDefaultInitialization() {
        let tags = TagsToWrite()

        XCTAssertNil(tags.genre)
        XCTAssertNil(tags.timing)
        XCTAssertNil(tags.mood)
        XCTAssertNil(tags.comments)
        XCTAssertNil(tags.vibeShort)
        XCTAssertNil(tags.vibeDescription)
        XCTAssertNil(tags.mixHint)
        XCTAssertNil(tags.scene)
        XCTAssertNil(tags.hook)
        XCTAssertNil(tags.essentiaGenres)
        XCTAssertNil(tags.essentiaMoods)
        XCTAssertNil(tags.essentiaInstruments)
        XCTAssertFalse(tags.clearVibeFields)
        XCTAssertFalse(tags.preventAcapellaGenre)
        XCTAssertTrue(tags.overwrite)
    }

    func testTagsToWriteIsEmptyWhenAllNil() {
        let tags = TagsToWrite()
        XCTAssertTrue(tags.isEmpty)
    }

    func testTagsToWriteIsNotEmptyWhenGenreSet() {
        let tags = TagsToWrite(genre: "House")
        XCTAssertFalse(tags.isEmpty)
    }

    func testTagsToWriteIsNotEmptyWhenTimingSet() {
        let tags = TagsToWrite(timing: "Peak")
        XCTAssertFalse(tags.isEmpty)
    }

    func testTagsToWriteIsNotEmptyWhenMoodSet() {
        let tags = TagsToWrite(mood: "Energetic")
        XCTAssertFalse(tags.isEmpty)
    }

    func testTagsToWriteIsNotEmptyWhenCommentsSet() {
        let tags = TagsToWrite(comments: "Great track")
        XCTAssertFalse(tags.isEmpty)
    }

    func testTagsToWriteIsNotEmptyWhenVibeShortSet() {
        let tags = TagsToWrite(vibeShort: "Uplifting")
        XCTAssertFalse(tags.isEmpty)
    }

    func testTagsToWriteIsNotEmptyWhenVibeDescriptionSet() {
        let tags = TagsToWrite(vibeDescription: "Perfect for parties")
        XCTAssertFalse(tags.isEmpty)
    }

    func testTagsToWriteIsNotEmptyWhenMixHintSet() {
        let tags = TagsToWrite(mixHint: "2AM bridge after rough drums")
        XCTAssertFalse(tags.isEmpty)
    }

    func testTagsToWriteIsNotEmptyWhenClearVibeFieldsSet() {
        let tags = TagsToWrite(clearVibeFields: true)
        XCTAssertFalse(tags.isEmpty)
    }

    func testTagsToWriteIsNotEmptyWhenPreventAcapellaGenreSet() {
        let tags = TagsToWrite(preventAcapellaGenre: true)
        XCTAssertFalse(tags.isEmpty)
    }

    func testTagsToWriteIsNotEmptyWhenSceneSet() {
        let tags = TagsToWrite(scene: "Club")
        XCTAssertFalse(tags.isEmpty)
    }

    func testTagsToWriteIsNotEmptyWhenHookSet() {
        let tags = TagsToWrite(hook: "Catchy beat")
        XCTAssertFalse(tags.isEmpty)
    }

    func testTagsToWriteOverwriteDefaultValue() {
        let tags = TagsToWrite(genre: "House")
        XCTAssertTrue(tags.overwrite)
    }

    func testTagsToWriteOverwriteCanBeSetFalse() {
        let tags = TagsToWrite(genre: "House", overwrite: false)
        XCTAssertFalse(tags.overwrite)
    }

    func testWriteFieldMappingSanitizesArtistTargets() {
        let mapping = WriteFieldMapping(
            genreFrame: .artist,
            timingFrame: .artist,
            moodFrame: .artist,
            descriptiveFrame: .artist
        )

        XCTAssertEqual(mapping.genreFrame, .genre)
        XCTAssertEqual(mapping.timingFrame, .albumArtist)
        XCTAssertEqual(mapping.moodFrame, .contentGroup)
        XCTAssertEqual(mapping.descriptiveFrame, .comments)
    }

    func testWriteFieldMappingDecodingSanitizesArtistTargets() throws {
        let data = """
        {
          "genreFrame": "artist",
          "timingFrame": "artist",
          "moodFrame": "artist",
          "descriptiveFrame": "artist"
        }
        """.data(using: .utf8)!

        let mapping = try JSONDecoder().decode(WriteFieldMapping.self, from: data)

        XCTAssertEqual(mapping.genreFrame, .genre)
        XCTAssertEqual(mapping.timingFrame, .albumArtist)
        XCTAssertEqual(mapping.moodFrame, .contentGroup)
        XCTAssertEqual(mapping.descriptiveFrame, .comments)
    }

    func testTagsToWriteEquatable() {
        let tags1 = TagsToWrite(genre: "House", mood: "Energetic")
        let tags2 = TagsToWrite(genre: "House", mood: "Energetic")
        let tags3 = TagsToWrite(genre: "Techno", mood: "Energetic")

        XCTAssertEqual(tags1, tags2)
        XCTAssertNotEqual(tags1, tags3)
    }

    func testTagsToWriteEquatableWithOverwrite() {
        let tags1 = TagsToWrite(genre: "House", overwrite: true)
        let tags2 = TagsToWrite(genre: "House", overwrite: true)
        let tags3 = TagsToWrite(genre: "House", overwrite: false)

        XCTAssertEqual(tags1, tags2)
        XCTAssertNotEqual(tags1, tags3)
    }

    // MARK: - ID3Error Tests

    func testID3ErrorFileNotFound() {
        let url = URL(fileURLWithPath: "/nonexistent/file.mp3")
        let error = ID3Error.fileNotFound(url)

        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("File not found"))
        XCTAssertTrue(error.errorDescription!.contains("/nonexistent/file.mp3"))
    }

    func testID3ErrorReadFailed() {
        let error = ID3Error.readFailed("Test error message")

        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("Failed to read"))
        XCTAssertTrue(error.errorDescription!.contains("Test error message"))
    }

    func testID3ErrorWriteFailed() {
        let error = ID3Error.writeFailed("Write error message")

        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("Failed to write"))
        XCTAssertTrue(error.errorDescription!.contains("Write error message"))
    }

    func testID3ErrorInvalidFormat() {
        let url = URL(fileURLWithPath: "/path/to/file.wav")
        let error = ID3Error.invalidFormat(url)

        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("Invalid file format"))
        XCTAssertTrue(error.errorDescription!.contains("file.wav"))
    }

    func testID3ErrorEquatable() {
        let url1 = URL(fileURLWithPath: "/test/file1.mp3")
        let url2 = URL(fileURLWithPath: "/test/file2.mp3")

        XCTAssertEqual(ID3Error.fileNotFound(url1), ID3Error.fileNotFound(url1))
        XCTAssertNotEqual(ID3Error.fileNotFound(url1), ID3Error.fileNotFound(url2))
        XCTAssertEqual(ID3Error.readFailed("error"), ID3Error.readFailed("error"))
        XCTAssertNotEqual(ID3Error.readFailed("error1"), ID3Error.readFailed("error2"))
    }

    // MARK: - ID3Manager Tests

    func testID3ManagerReadFromNonexistentFileThrowsError() async {
        let manager = ID3Manager()
        let nonexistentURL = URL(fileURLWithPath: "/nonexistent/path/to/file.mp3")

        do {
            _ = try await manager.readTags(from: nonexistentURL)
            XCTFail("Expected fileNotFound error to be thrown")
        } catch let error as ID3Error {
            if case .fileNotFound(let url) = error {
                XCTAssertEqual(url, nonexistentURL)
            } else {
                XCTFail("Expected fileNotFound error, got \(error)")
            }
        } catch {
            XCTFail("Expected ID3Error, got \(error)")
        }
    }

    func testID3ManagerReadFromInvalidFormatThrowsError() async throws {
        let manager = ID3Manager()

        // Create a temporary text file with .txt extension
        let tempDir = FileManager.default.temporaryDirectory
        let textFileURL = tempDir.appendingPathComponent("test_\(UUID().uuidString).txt")

        FileManager.default.createFile(atPath: textFileURL.path, contents: "test".data(using: .utf8))

        defer {
            try? FileManager.default.removeItem(at: textFileURL)
        }

        do {
            _ = try await manager.readTags(from: textFileURL)
            XCTFail("Expected invalidFormat error to be thrown")
        } catch let error as ID3Error {
            if case .invalidFormat(let url) = error {
                XCTAssertEqual(url, textFileURL)
            } else {
                XCTFail("Expected invalidFormat error, got \(error)")
            }
        } catch {
            XCTFail("Expected ID3Error, got \(error)")
        }
    }

    func testID3ManagerWriteToNonexistentFileThrowsError() async {
        let manager = ID3Manager()
        let nonexistentURL = URL(fileURLWithPath: "/nonexistent/path/to/file.mp3")
        let tags = TagsToWrite(genre: "House")

        do {
            try await manager.writeTags(tags, to: nonexistentURL)
            XCTFail("Expected fileNotFound error to be thrown")
        } catch let error as ID3Error {
            if case .fileNotFound(let url) = error {
                XCTAssertEqual(url, nonexistentURL)
            } else {
                XCTFail("Expected fileNotFound error, got \(error)")
            }
        } catch {
            XCTFail("Expected ID3Error, got \(error)")
        }
    }

    func testID3ManagerWriteEmptyTagsDoesNotThrow() async throws {
        let manager = ID3Manager()

        // Create a temporary MP3 file (minimal valid MP3)
        let tempDir = FileManager.default.temporaryDirectory
        let mp3URL = tempDir.appendingPathComponent("test_\(UUID().uuidString).mp3")

        // Create minimal MP3 data (just enough to be a valid file for the check)
        // Note: This won't actually write tags since tags.isEmpty is true
        let minimalMP3Data = Data([0xFF, 0xFB, 0x90, 0x00]) // MP3 frame sync
        try minimalMP3Data.write(to: mp3URL)

        defer {
            try? FileManager.default.removeItem(at: mp3URL)
        }

        // Writing empty tags should not throw (early return)
        let emptyTags = TagsToWrite()
        try await manager.writeTags(emptyTags, to: mp3URL)
    }

    // MARK: - TagMapping Essentia Frame Constants Tests

    func testTagMappingEssentiaFrameConstants() {
        // Verify Essentia tag frame constants are set correctly
        XCTAssertEqual(TagMapping.essentiaGenres, "TPUB")
        XCTAssertEqual(TagMapping.essentiaMoods, "TPE3")
        XCTAssertEqual(TagMapping.essentiaInstruments, "TENC")
    }

    // MARK: - EssentiaTags Tests

    func testEssentiaTagsDefaultInitialization() {
        let tags = EssentiaTags()

        XCTAssertEqual(tags.genres, [])
        XCTAssertEqual(tags.moods, [])
        XCTAssertEqual(tags.instruments, [])
    }

    func testEssentiaTagsWithValues() {
        let tags = EssentiaTags(
            genres: ["Deep House", "Tech House", "Minimal"],
            moods: ["energetic", "dark", "groovy"],
            instruments: ["synthesizer", "drums", "bass"]
        )

        XCTAssertEqual(tags.genres, ["Deep House", "Tech House", "Minimal"])
        XCTAssertEqual(tags.moods, ["energetic", "dark", "groovy"])
        XCTAssertEqual(tags.instruments, ["synthesizer", "drums", "bass"])
    }

    func testEssentiaTagsStringFormatting() {
        let tags = EssentiaTags(
            genres: ["Deep House", "Tech House", "Minimal"],
            moods: ["energetic", "dark", "groovy"],
            instruments: ["synthesizer", "drums", "bass"]
        )

        XCTAssertEqual(tags.genresString, "Deep House, Tech House, Minimal")
        XCTAssertEqual(tags.moodsString, "energetic, dark, groovy")
        XCTAssertEqual(tags.instrumentsString, "synthesizer, drums, bass")
    }

    func testEssentiaTagsEmptyStringFormatting() {
        let tags = EssentiaTags()

        XCTAssertEqual(tags.genresString, "")
        XCTAssertEqual(tags.moodsString, "")
        XCTAssertEqual(tags.instrumentsString, "")
    }

    func testEssentiaTagsIsEmptyWhenAllEmpty() {
        let tags = EssentiaTags()
        XCTAssertTrue(tags.isEmpty)
    }

    func testEssentiaTagsIsNotEmptyWhenGenresSet() {
        let tags = EssentiaTags(genres: ["House"])
        XCTAssertFalse(tags.isEmpty)
    }

    func testEssentiaTagsIsNotEmptyWhenMoodsSet() {
        let tags = EssentiaTags(moods: ["energetic"])
        XCTAssertFalse(tags.isEmpty)
    }

    func testEssentiaTagsIsNotEmptyWhenInstrumentsSet() {
        let tags = EssentiaTags(instruments: ["drums"])
        XCTAssertFalse(tags.isEmpty)
    }

    func testEssentiaTagsEquatable() {
        let tags1 = EssentiaTags(genres: ["House"], moods: ["energetic"])
        let tags2 = EssentiaTags(genres: ["House"], moods: ["energetic"])
        let tags3 = EssentiaTags(genres: ["Techno"], moods: ["energetic"])

        XCTAssertEqual(tags1, tags2)
        XCTAssertNotEqual(tags1, tags3)
    }

    func testEssentiaTagsCodable() throws {
        let original = EssentiaTags(
            genres: ["House", "Techno"],
            moods: ["dark", "groovy"],
            instruments: ["synth", "drums"]
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(EssentiaTags.self, from: data)

        XCTAssertEqual(original, decoded)
    }

    // MARK: - TagsToWrite Essentia Fields Tests

    func testTagsToWriteIsNotEmptyWhenEssentiaGenresSet() {
        let tags = TagsToWrite(essentiaGenres: "Electronic---House, Electronic---Techno")
        XCTAssertFalse(tags.isEmpty)
    }

    func testTagsToWriteIsNotEmptyWhenEssentiaMoodsSet() {
        let tags = TagsToWrite(essentiaMoods: "energetic, dark, groovy")
        XCTAssertFalse(tags.isEmpty)
    }

    func testTagsToWriteIsNotEmptyWhenEssentiaInstrumentsSet() {
        let tags = TagsToWrite(essentiaInstruments: "synthesizer, drums, bass")
        XCTAssertFalse(tags.isEmpty)
    }

    func testTagsToWriteWithAllEssentiaFields() {
        let tags = TagsToWrite(
            essentiaGenres: "Electronic---House, Electronic---Techno",
            essentiaMoods: "energetic, dark, groovy",
            essentiaInstruments: "synthesizer, drums, bass"
        )

        XCTAssertEqual(tags.essentiaGenres, "Electronic---House, Electronic---Techno")
        XCTAssertEqual(tags.essentiaMoods, "energetic, dark, groovy")
        XCTAssertEqual(tags.essentiaInstruments, "synthesizer, drums, bass")
        XCTAssertFalse(tags.isEmpty)
    }

    func testTagsToWriteEquatableWithEssentiaFields() {
        let tags1 = TagsToWrite(essentiaGenres: "House", essentiaMoods: "dark")
        let tags2 = TagsToWrite(essentiaGenres: "House", essentiaMoods: "dark")
        let tags3 = TagsToWrite(essentiaGenres: "Techno", essentiaMoods: "dark")

        XCTAssertEqual(tags1, tags2)
        XCTAssertNotEqual(tags1, tags3)
    }

    // MARK: - ID3Manager Essentia Write/Read Tests

    /// Helper to create a writable test MP3 file
    /// Note: Uses a bundled test resource to avoid sandbox permission issues
    private func createWritableTestMP3() throws -> (url: URL, cleanup: () -> Void) {
        // Find the example MP3 in the test bundle
        guard let exampleURL = Bundle.module.url(forResource: "example", withExtension: "mp3") else {
            throw XCTSkip("Example MP3 file not found in test bundle")
        }

        // Create temp directory with unique name
        let testDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("CrateBotTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: testDir, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])

        let tempURL = testDir.appendingPathComponent("test.mp3")

        // Copy the file
        try FileManager.default.copyItem(at: exampleURL, to: tempURL)

        // Set writable permissions on the copied file
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: tempURL.path)

        let cleanup: () -> Void = {
            try? FileManager.default.removeItem(at: testDir)
        }

        return (tempURL, cleanup)
    }

    func testID3ManagerWriteAndReadEssentiaTags() async throws {
        let manager = ID3Manager()

        let (tempURL, cleanup) = try createWritableTestMP3()
        defer { cleanup() }

        // Write Essentia tags
        let tagsToWrite = TagsToWrite(
            essentiaGenres: "Electronic---House, Electronic---Techno",
            essentiaMoods: "energetic, dark, groovy",
            essentiaInstruments: "synthesizer, drums, bass"
        )

        try await manager.writeTags(tagsToWrite, to: tempURL)

        // Read back and verify
        let readTags = try await manager.readTags(from: tempURL)

        // Essentia genres are stored in publisher field (TPUB)
        XCTAssertEqual(readTags.publisher, "Electronic---House, Electronic---Techno")

        // Essentia moods are stored in conductor field (TPE3)
        XCTAssertEqual(readTags.conductor, "energetic, dark, groovy")

        // Essentia instruments are stored in encodedBy field (TENC)
        XCTAssertEqual(readTags.encodedBy, "synthesizer, drums, bass")
    }

    func testID3ManagerPreservesExistingEssentiaTagsWhenNotOverwriting() async throws {
        let manager = ID3Manager()

        let (tempURL, cleanup) = try createWritableTestMP3()
        defer { cleanup() }

        // Write initial Essentia tags
        let initialTags = TagsToWrite(
            essentiaGenres: "Original Genre",
            essentiaMoods: "Original Mood",
            essentiaInstruments: "Original Instruments"
        )
        try await manager.writeTags(initialTags, to: tempURL)

        // Try to write new tags with overwrite = false
        let newTags = TagsToWrite(
            essentiaGenres: "New Genre",
            essentiaMoods: "New Mood",
            essentiaInstruments: "New Instruments",
            overwrite: false
        )
        try await manager.writeTags(newTags, to: tempURL)

        // Read back - should have original values
        let readTags = try await manager.readTags(from: tempURL)
        XCTAssertEqual(readTags.publisher, "Original Genre")
        XCTAssertEqual(readTags.conductor, "Original Mood")
        XCTAssertEqual(readTags.encodedBy, "Original Instruments")
    }

    func testID3ManagerOverwritesEssentiaTagsWhenOverwriteTrue() async throws {
        let manager = ID3Manager()

        let (tempURL, cleanup) = try createWritableTestMP3()
        defer { cleanup() }

        // Write initial Essentia tags
        let initialTags = TagsToWrite(
            essentiaGenres: "Original Genre",
            essentiaMoods: "Original Mood",
            essentiaInstruments: "Original Instruments"
        )
        try await manager.writeTags(initialTags, to: tempURL)

        // Write new tags with overwrite = true (default)
        let newTags = TagsToWrite(
            essentiaGenres: "New Genre",
            essentiaMoods: "New Mood",
            essentiaInstruments: "New Instruments"
        )
        try await manager.writeTags(newTags, to: tempURL)

        // Read back - should have new values
        let readTags = try await manager.readTags(from: tempURL)
        XCTAssertEqual(readTags.publisher, "New Genre")
        XCTAssertEqual(readTags.conductor, "New Mood")
        XCTAssertEqual(readTags.encodedBy, "New Instruments")
    }

    func testID3ManagerNeverWritesGeneratedTagsToArtistFrame() async throws {
        let manager = ID3Manager()

        let (tempURL, cleanup) = try createWritableTestMP3()
        defer { cleanup() }

        let originalArtist = try await manager.readTags(from: tempURL).artist
        let artistTargetMapping = WriteFieldMapping(
            genreFrame: .artist,
            timingFrame: .artist,
            moodFrame: .artist,
            descriptiveFrame: .artist
        )

        try await manager.writeTags(
            TagsToWrite(
                genre: "House",
                timing: "Peak",
                mood: "Dark",
                comments: "Generated comments",
                fieldMapping: artistTargetMapping
            ),
            to: tempURL
        )

        let readTags = try await manager.readTags(from: tempURL)
        XCTAssertEqual(readTags.artist, originalArtist)
        XCTAssertNotEqual(readTags.artist, "House")
        XCTAssertNotEqual(readTags.artist, "Peak")
        XCTAssertNotEqual(readTags.artist, "Dark")
        XCTAssertNotEqual(readTags.artist, "Generated comments")
    }

    func testID3ManagerWriteAndReadVibeFieldsIncludingMovement() async throws {
        let manager = ID3Manager()

        let (tempURL, cleanup) = try createWritableTestMP3()
        defer { cleanup() }

        let tagsToWrite = TagsToWrite(
            vibeShort: "EMBER CLOCKWORK RISES BENEATH",
            vibeDescription: "Velvet pressure hangs in a rainlit stairwell.",
            mixHint: "2AM bridge after rough drums"
        )

        try await manager.writeTags(tagsToWrite, to: tempURL)

        let readTags = try await manager.readTags(from: tempURL)
        XCTAssertEqual(readTags.vibeShort, "EMBER CLOCKWORK RISES BENEATH")
        XCTAssertEqual(readTags.vibeDescription, "Velvet pressure hangs in a rainlit stairwell.")
        XCTAssertEqual(readTags.mixHint, "2AM bridge after rough drums")
    }

    func testID3ManagerClearVibeFieldsRemovesStaleComposerSubtitleAndMovement() async throws {
        let manager = ID3Manager()

        let (tempURL, cleanup) = try createWritableTestMP3()
        defer { cleanup() }

        try await manager.writeTags(
            TagsToWrite(
                vibeShort: "OLD THREE WORDS",
                vibeDescription: "This stale track description should disappear.",
                mixHint: "old movement"
            ),
            to: tempURL
        )

        try await manager.writeTags(TagsToWrite(clearVibeFields: true), to: tempURL)

        let readTags = try await manager.readTags(from: tempURL)
        XCTAssertNil(readTags.vibeShort)
        XCTAssertNil(readTags.vibeDescription)
        XCTAssertNil(readTags.mixHint)
    }

    func testID3ManagerPreventAcapellaGenreRemovesExistingAcapella() async throws {
        let manager = ID3Manager()

        let (tempURL, cleanup) = try createWritableTestMP3()
        defer { cleanup() }

        try await manager.writeTags(TagsToWrite(genre: "Acapella"), to: tempURL)
        let initialTags = try await manager.readTags(from: tempURL)
        XCTAssertEqual(initialTags.genre, "Acapella")

        try await manager.writeTags(TagsToWrite(preventAcapellaGenre: true), to: tempURL)

        let readTags = try await manager.readTags(from: tempURL)
        XCTAssertNil(readTags.genre)
    }

    func testID3ManagerPreventAcapellaGenreSkipsIncomingAcapella() async throws {
        let manager = ID3Manager()

        let (tempURL, cleanup) = try createWritableTestMP3()
        defer { cleanup() }
        let originalGenre = try await manager.readTags(from: tempURL).genre

        try await manager.writeTags(
            TagsToWrite(genre: "Acapella", preventAcapellaGenre: true),
            to: tempURL
        )

        let readTags = try await manager.readTags(from: tempURL)
        XCTAssertEqual(readTags.genre, originalGenre)
        XCTAssertNotEqual(readTags.genre, "Acapella")
    }

    // MARK: - Atomic Write Safety Tests

    func testID3ManagerAtomicWritePreservesOriginalOnFailure() async throws {
        let manager = ID3Manager()

        let (tempURL, cleanup) = try createWritableTestMP3()
        defer { cleanup() }

        // Read original content
        let originalData = try Data(contentsOf: tempURL)

        // Make file read-only to simulate write failure
        try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: tempURL.path)

        // Attempt to write (should fail)
        let tagsToWrite = TagsToWrite(genre: "Test Genre")
        do {
            try await manager.writeTags(tagsToWrite, to: tempURL)
            // If we get here, restore permissions and fail test
            try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: tempURL.path)
            XCTFail("Expected write to fail on read-only file")
        } catch {
            // Expected - write should fail
        }

        // Restore permissions to read file
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: tempURL.path)

        // Verify original file content is preserved
        let afterData = try Data(contentsOf: tempURL)
        XCTAssertEqual(originalData, afterData, "Original file should be preserved after failed write")
    }
}
