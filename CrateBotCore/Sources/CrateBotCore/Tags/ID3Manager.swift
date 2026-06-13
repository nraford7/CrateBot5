import Foundation
import ID3TagEditor

// MARK: - ID3 Errors

/// Errors that can occur during ID3 tag operations.
public enum ID3Error: LocalizedError, Equatable {
    /// The specified file was not found.
    case fileNotFound(URL)

    /// Failed to read tags from the file.
    case readFailed(String)

    /// Failed to write tags to the file.
    case writeFailed(String)

    /// The file format is not supported (not an MP3 file).
    case invalidFormat(URL)

    public var errorDescription: String? {
        switch self {
        case .fileNotFound(let url):
            return "File not found: \(url.path)"
        case .readFailed(let reason):
            return "Failed to read ID3 tags: \(reason)"
        case .writeFailed(let reason):
            return "Failed to write ID3 tags: \(reason)"
        case .invalidFormat(let url):
            return "Invalid file format (expected MP3): \(url.path)"
        }
    }
}

// MARK: - ID3 Manager

/// Actor for thread-safe ID3 tag reading and writing operations.
///
/// Uses the ID3TagEditor library to read and write ID3v2.3 tags.
/// All operations are isolated to ensure thread safety.
public actor ID3Manager {
    /// The underlying ID3TagEditor instance.
    private let editor: ID3TagEditor

    /// Creates a new ID3Manager instance.
    public init() {
        self.editor = ID3TagEditor()
    }

    // MARK: - Reading Tags

    /// Reads ID3 tags from an MP3 file.
    ///
    /// - Parameter url: The URL of the MP3 file to read.
    /// - Returns: The extracted tags from the file.
    /// - Throws: `ID3Error` if the file cannot be read.
    public func readTags(from url: URL) throws -> ExtractedTags {
        // Check if file exists
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ID3Error.fileNotFound(url)
        }

        // Check file extension
        guard url.pathExtension.lowercased() == "mp3" else {
            throw ID3Error.invalidFormat(url)
        }

        do {
            // Read file data directly using the URL (preserves security-scoped access)
            let mp3Data = try Data(contentsOf: url)

            // Use the Data-based read method instead of path-based
            guard let tag = try editor.read(mp3: mp3Data) else {
                // No tag found - return empty tags
                return ExtractedTags()
            }

            let reader = ID3TagContentReader(id3Tag: tag)

            // Read title from TIT2 frame
            let title = reader.title()

            // Read artist from TPE1 frame
            let artist = reader.artist()

            // Read album artist from TPE2 frame
            let albumArtist = reader.albumArtist()

            // Read album from TALB frame
            let album = reader.album()

            // Read genre from TCON frame
            var extractedGenre: String?
            if let genreFrame = reader.genre() {
                extractedGenre = genreFrame.description
            }

            // Legacy timing support - keep for backwards compatibility
            var extractedTiming: String?
            if let genreFrame = reader.genre() {
                let genreValue = genreFrame.description ?? ""
                if !genreValue.isEmpty && !TagMapping.isGenre(genreValue) {
                    extractedTiming = genreValue
                }
            }
            if extractedTiming == nil, let albumValue = reader.album() {
                extractedTiming = albumValue
            }

            // Read mood from content group frame (TIT1)
            let mood = reader.contentGrouping()

            // Read comments from COMM frame
            // Try to get the best comment - prefer ones without "ID3v1" in description
            let commentsArray = reader.comments()
            var comments: String? = nil
            for comment in commentsArray {
                // Skip empty content
                let content = comment.content
                guard !content.isEmpty else { continue }

                // Clean up the content - remove ID3v1 prefixes if present
                var cleanContent = content

                // Remove common ID3v1 description prefixes that might be in content
                let prefixesToRemove = ["ID3v1 Comment", "ID3v1Comment", "Comment"]
                for prefix in prefixesToRemove {
                    if cleanContent.hasPrefix(prefix) {
                        cleanContent = String(cleanContent.dropFirst(prefix.count))
                            .trimmingCharacters(in: .whitespaces)
                    }
                }

                // Try to decode if it looks like it might be Latin-1 encoded
                if let latin1Data = cleanContent.data(using: .isoLatin1),
                   let utf8String = String(data: latin1Data, encoding: .utf8),
                   utf8String != cleanContent {
                    cleanContent = utf8String
                }

                if !cleanContent.isEmpty {
                    comments = cleanContent
                    break
                }
            }

            // Read vibe short from composer frame (TCOM)
            let vibeShort = reader.composer()

            // Read vibe description from subtitle frame (TIT3)
            let vibeDescription = reader.subtitle()

            // Read scene from file owner frame (TOWN)
            let extractedScene = reader.fileOwner()

            // Read hook from lyricist frame (TEXT)
            let extractedHook = reader.lyricist()

            // Read BPM from TBPM frame
            let bpm = reader.beatsPerMinute()

            // Read year from recording date
            let year: String?
            if let recordingDate = reader.recordingDateTime() {
                year = recordingDate.year.map { String($0) }
            } else {
                year = nil
            }

            // Read publisher from TPUB frame
            let publisher = reader.publisher()

            // Read conductor from TPE3 frame
            let conductor = reader.conductor()

            // Read encoded by from TENC frame
            let encodedBy = reader.encodedBy()

            // Read copyright - not directly available in reader, skip for now
            let copyright: String? = nil

            // Read original artist - not directly available in reader, skip for now
            let originalArtist: String? = nil

            return ExtractedTags(
                title: title,
                artist: artist,
                albumArtist: albumArtist,
                album: album,
                genre: extractedGenre,
                timing: extractedTiming,
                mood: mood,
                comments: comments,
                vibeShort: vibeShort,
                vibeDescription: vibeDescription,
                scene: extractedScene,
                hook: extractedHook,
                bpm: bpm.map { String($0) },
                year: year,
                publisher: publisher,
                conductor: conductor,
                encodedBy: encodedBy,
                copyright: copyright,
                originalArtist: originalArtist
            )
        } catch {
            throw ID3Error.readFailed(error.localizedDescription)
        }
    }

    // MARK: - Writing Tags

    /// Writes ID3 tags to an MP3 file.
    ///
    /// Only non-nil tag values will be written. Existing tags not specified
    /// in `tags` will be preserved.
    ///
    /// When `tags.overwrite` is `true` (default), specified tag values will replace
    /// existing values. When `false`, tags will only be written for fields that
    /// don't already have values in the file.
    ///
    /// - Parameters:
    ///   - tags: The tags to write.
    ///   - url: The URL of the MP3 file to write to.
    /// - Throws: `ID3Error` if the file cannot be written.
    public func writeTags(_ tags: TagsToWrite, to url: URL) throws {
        // Check if file exists
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ID3Error.fileNotFound(url)
        }

        // Check file extension
        guard url.pathExtension.lowercased() == "mp3" else {
            throw ID3Error.invalidFormat(url)
        }

        // Note: We don't check isWritableFile here because it doesn't work with
        // security-scoped resources. The actual write will fail if access is denied.

        // Skip if no tags to write
        guard !tags.isEmpty else {
            return
        }

        do {
            print("ID3Manager writeTags: starting for \(url.path)")
            if let attributes = try? FileManager.default.attributesOfItem(atPath: url.path) {
                let permissions = attributes[.posixPermissions] as? NSNumber
                let owner = attributes[.ownerAccountName] as? String
                let group = attributes[.groupOwnerAccountName] as? String
                print("ID3Manager writeTags: perms=\(permissions?.stringValue ?? "nil") owner=\(owner ?? "nil") group=\(group ?? "nil")")
            }

            // Get field mapping (use default if not specified)
            let mapping = tags.fieldMapping ?? .default

            // Read file data directly using the URL (preserves security-scoped access)
            let mp3Data = try Data(contentsOf: url)
            print("ID3Manager writeTags: read OK (\(mp3Data.count) bytes) for \(url.lastPathComponent)")

            // Read existing tags to preserve them (using Data-based method)
            let existingTag = try editor.read(mp3: mp3Data)

            // Build new tag, starting with existing frames if available
            var builder = ID32v3TagBuilder()

            // Preserve existing frames and merge with new values
            if let existing = existingTag {
                let reader = ID3TagContentReader(id3Tag: existing)

                // Handle genre - write to configured frame (default: TCON)
                let existingGenre = reader.genre()
                if let genre = tags.genre, tags.overwrite || existingGenre == nil {
                    builder = writeStringToFrame(builder, value: genre, frame: mapping.genreFrame, asGenre: true)
                } else if let existingGenre {
                    builder = builder.genre(frame: ID3FrameGenre(
                        genre: existingGenre.identifier,
                        description: existingGenre.description
                    ))
                }

                // Handle subGenre - write to mix artist frame (TPE4)
                // Using TPE4 for Essentia-predicted subgenre
                let existingMixArtist = reader.mixArtist()
                if let subGenre = tags.subGenre, tags.overwrite || existingMixArtist == nil {
                    builder = builder.mixArtist(frame: ID3FrameWithStringContent(content: subGenre))
                } else if let existingMixArtist {
                    builder = builder.mixArtist(frame: ID3FrameWithStringContent(content: existingMixArtist))
                }

                // Handle timing - write to configured frame (default: TALB, user may set TPE2)
                let existingTimingValue = readFromFrame(reader, frame: mapping.timingFrame)
                if let timing = tags.timing, tags.overwrite || existingTimingValue == nil {
                    builder = writeStringToFrame(builder, value: timing, frame: mapping.timingFrame)
                } else if let existingValue = existingTimingValue {
                    builder = writeStringToFrame(builder, value: existingValue, frame: mapping.timingFrame)
                }

                // Handle mood - write to configured frame (default: TIT1, user may set TALB)
                let existingMoodValue = readFromFrame(reader, frame: mapping.moodFrame)
                if let mood = tags.mood, tags.overwrite || existingMoodValue == nil {
                    builder = writeStringToFrame(builder, value: mood, frame: mapping.moodFrame)
                } else if let existingValue = existingMoodValue {
                    builder = writeStringToFrame(builder, value: existingValue, frame: mapping.moodFrame)
                }

                // Handle comments/descriptive - write to configured frame (default: COMM)
                let existingComment = reader.comments().first
                if let comments = tags.comments, tags.overwrite || existingComment == nil {
                    if mapping.descriptiveFrame == .comments {
                        builder = builder.comment(
                            language: .eng,
                            frame: ID3FrameWithLocalizedContent(
                                language: .eng,
                                contentDescription: "",
                                content: comments
                            )
                        )
                    } else {
                        builder = writeStringToFrame(builder, value: comments, frame: mapping.descriptiveFrame)
                    }
                } else if let existingComment {
                    builder = builder.comment(
                        language: existingComment.language,
                        frame: ID3FrameWithLocalizedContent(
                            language: existingComment.language,
                            contentDescription: existingComment.contentDescription,
                            content: existingComment.content
                        )
                    )
                }

                // Handle vibe short - write to composer frame (TCOM)
                let existingComposer = reader.composer()
                if let vibeShort = tags.vibeShort, tags.overwrite || existingComposer == nil {
                    builder = builder.composer(frame: ID3FrameWithStringContent(content: vibeShort))
                } else if let existingComposer {
                    builder = builder.composer(frame: ID3FrameWithStringContent(content: existingComposer))
                }

                // Handle vibe description - write to subtitle frame (TIT3),
                // which DJ tools and Music.app surface as "Description".
                let existingSubtitle = reader.subtitle()
                if let vibeDescription = tags.vibeDescription, tags.overwrite || existingSubtitle == nil {
                    builder = builder.subtitle(frame: ID3FrameWithStringContent(content: vibeDescription))
                } else if let existingSubtitle {
                    builder = builder.subtitle(frame: ID3FrameWithStringContent(content: existingSubtitle))
                }

                // Handle mix hint - write to iTunes Movement Name (MVNM),
                // visible as "Movement Name" in Music.app and DJ tools.
                // Carries the "how to play it" guidance, distinct from the
                // long prose description on TIT3 above.
                let existingMovement = reader.iTunesMovementName()
                if let mixHint = tags.mixHint, tags.overwrite || existingMovement == nil {
                    builder = builder.iTunesMovementName(frame: ID3FrameWithStringContent(content: mixHint))
                } else if let existingMovement {
                    builder = builder.iTunesMovementName(frame: ID3FrameWithStringContent(content: existingMovement))
                }

                // Handle scene - write to file owner frame (TOWN)
                let existingScene = reader.fileOwner()
                if let scene = tags.scene, tags.overwrite || existingScene == nil {
                    builder = builder.fileOwner(frame: ID3FrameWithStringContent(content: scene))
                } else if let existingScene {
                    builder = builder.fileOwner(frame: ID3FrameWithStringContent(content: existingScene))
                }

                // Handle hook - write to lyricist frame (TEXT)
                let existingHook = reader.lyricist()
                if let hook = tags.hook, tags.overwrite || existingHook == nil {
                    builder = builder.lyricist(frame: ID3FrameWithStringContent(content: hook))
                } else if let existingHook {
                    builder = builder.lyricist(frame: ID3FrameWithStringContent(content: existingHook))
                }

                // Handle Essentia genres - write to publisher frame (TPUB)
                let existingPublisher = reader.publisher()
                if let essentiaGenres = tags.essentiaGenres, tags.overwrite || existingPublisher == nil {
                    builder = builder.publisher(frame: ID3FrameWithStringContent(content: essentiaGenres))
                } else if let existingPublisher {
                    builder = builder.publisher(frame: ID3FrameWithStringContent(content: existingPublisher))
                }

                // Handle Essentia moods - write to conductor frame (TPE3)
                let existingConductor = reader.conductor()
                if let essentiaMoods = tags.essentiaMoods, tags.overwrite || existingConductor == nil {
                    builder = builder.conductor(frame: ID3FrameWithStringContent(content: essentiaMoods))
                } else if let existingConductor {
                    builder = builder.conductor(frame: ID3FrameWithStringContent(content: existingConductor))
                }

                // Handle Essentia instruments - write to encoded by frame (TENC)
                let existingEncodedBy = reader.encodedBy()
                if let essentiaInstruments = tags.essentiaInstruments, tags.overwrite || existingEncodedBy == nil {
                    builder = builder.encodedBy(frame: ID3FrameWithStringContent(content: essentiaInstruments))
                } else if let existingEncodedBy {
                    builder = builder.encodedBy(frame: ID3FrameWithStringContent(content: existingEncodedBy))
                }

                // Preserve other common frames (only if not used by mapping)
                if let title = reader.title() {
                    builder = builder.title(frame: ID3FrameWithStringContent(content: title))
                }
                if let artist = reader.artist() {
                    builder = builder.artist(frame: ID3FrameWithStringContent(content: artist))
                }
                // Preserve album artist if not used for timing
                if mapping.timingFrame != .albumArtist, let albumArtist = reader.albumArtist() {
                    builder = builder.albumArtist(frame: ID3FrameWithStringContent(content: albumArtist))
                }
                // Preserve album if not used for timing or mood
                if mapping.timingFrame != .album && mapping.moodFrame != .album, let album = reader.album() {
                    builder = builder.album(frame: ID3FrameWithStringContent(content: album))
                }
                // Preserve content grouping if not used for mood
                if mapping.moodFrame != .contentGroup, let grouping = reader.contentGrouping() {
                    builder = builder.contentGrouping(frame: ID3FrameWithStringContent(content: grouping))
                }
            } else {
                // No existing tag - just write new values using configured mapping
                if let genre = tags.genre {
                    builder = writeStringToFrame(builder, value: genre, frame: mapping.genreFrame, asGenre: true)
                }
                if let subGenre = tags.subGenre {
                    builder = builder.mixArtist(frame: ID3FrameWithStringContent(content: subGenre))
                }
                if let timing = tags.timing {
                    builder = writeStringToFrame(builder, value: timing, frame: mapping.timingFrame)
                }
                if let mood = tags.mood {
                    builder = writeStringToFrame(builder, value: mood, frame: mapping.moodFrame)
                }
                if let comments = tags.comments {
                    if mapping.descriptiveFrame == .comments {
                        builder = builder.comment(
                            language: .eng,
                            frame: ID3FrameWithLocalizedContent(
                                language: .eng,
                                contentDescription: "",
                                content: comments
                            )
                        )
                    } else {
                        builder = writeStringToFrame(builder, value: comments, frame: mapping.descriptiveFrame)
                    }
                }
                if let vibeShort = tags.vibeShort {
                    builder = builder.composer(frame: ID3FrameWithStringContent(content: vibeShort))
                }
                if let vibeDescription = tags.vibeDescription {
                    builder = builder.subtitle(frame: ID3FrameWithStringContent(content: vibeDescription))
                }
                if let mixHint = tags.mixHint {
                    builder = builder.iTunesMovementName(frame: ID3FrameWithStringContent(content: mixHint))
                }
                if let scene = tags.scene {
                    builder = builder.fileOwner(frame: ID3FrameWithStringContent(content: scene))
                }
                if let hook = tags.hook {
                    builder = builder.lyricist(frame: ID3FrameWithStringContent(content: hook))
                }
                if let essentiaGenres = tags.essentiaGenres {
                    builder = builder.publisher(frame: ID3FrameWithStringContent(content: essentiaGenres))
                }
                if let essentiaMoods = tags.essentiaMoods {
                    builder = builder.conductor(frame: ID3FrameWithStringContent(content: essentiaMoods))
                }
                if let essentiaInstruments = tags.essentiaInstruments {
                    builder = builder.encodedBy(frame: ID3FrameWithStringContent(content: essentiaInstruments))
                }
            }

            let newTag = builder.build()

            // Use the Data-based write method (returns modified Data instead of writing to path)
            let modifiedMp3Data = try editor.write(tag: newTag, mp3: mp3Data)

            print("ID3Manager writeTags: writing \(modifiedMp3Data.count) bytes to \(url.path)")

            // Check for extended attributes that might block writes
            if let xattrs = try? FileManager.default.attributesOfItem(atPath: url.path) {
                if let extendedAttrs = xattrs[FileAttributeKey(rawValue: "NSFileExtendedAttributes")] as? [String: Any] {
                    let attrNames = extendedAttrs.keys.joined(separator: ", ")
                    print("ID3Manager writeTags: extended attributes: \(attrNames)")
                    if extendedAttrs["com.apple.macl"] != nil {
                        print("ID3Manager writeTags: WARNING - file has com.apple.macl (app-specific access control)")
                    }
                }
            }

            // Write the data atomically using temp file + atomic move
            // Create temp file in same directory (ensures same filesystem for atomic move)
            let tempURL = url.deletingLastPathComponent()
                .appendingPathComponent(".cratebot_temp_\(UUID().uuidString).mp3")
            do {
                // Write to temp file first
                try modifiedMp3Data.write(to: tempURL, options: .atomic)

                // Atomic replace: move temp over original
                _ = try FileManager.default.replaceItemAt(url, withItemAt: tempURL)

                print("ID3Manager writeTags: atomic write OK for \(url.lastPathComponent)")
            } catch {
                let nsError = error as NSError
                print("ID3Manager writeTags: atomic write failed domain=\(nsError.domain) code=\(nsError.code)")

                // Clean up temp file on failure
                try? FileManager.default.removeItem(at: tempURL)

                // Provide helpful error message
                if nsError.code == NSFileWriteNoPermissionError || nsError.code == 1 {
                    throw ID3Error.writeFailed("Permission denied. This file may have macOS access restrictions. Try granting Full Disk Access to CrateBot in System Preferences -> Privacy & Security, or use 'Browse Files' to re-select the files.")
                }
                throw ID3Error.writeFailed(error.localizedDescription)
            }
        } catch let error as ID3Error {
            throw error
        } catch {
            let nsError = error as NSError
            print("ID3Manager writeTags: failed domain=\(nsError.domain) code=\(nsError.code) userInfo=\(nsError.userInfo)")
            throw ID3Error.writeFailed(error.localizedDescription)
        }
    }

    // MARK: - Private Helpers for Configurable Field Mapping

    /// Writes a string value to the specified frame type
    private func writeStringToFrame(
        _ builder: ID32v3TagBuilder,
        value: String,
        frame: ID3FrameType,
        asGenre: Bool = false
    ) -> ID32v3TagBuilder {
        switch frame {
        case .title:
            return builder.title(frame: ID3FrameWithStringContent(content: value))
        case .artist:
            return builder.artist(frame: ID3FrameWithStringContent(content: value))
        case .albumArtist:
            return builder.albumArtist(frame: ID3FrameWithStringContent(content: value))
        case .album:
            return builder.album(frame: ID3FrameWithStringContent(content: value))
        case .genre:
            if asGenre {
                return builder.genre(frame: ID3FrameGenre(genre: nil, description: value))
            } else {
                return builder.genre(frame: ID3FrameGenre(genre: nil, description: value))
            }
        case .contentGroup:
            return builder.contentGrouping(frame: ID3FrameWithStringContent(content: value))
        case .comments:
            return builder.comment(
                language: .eng,
                frame: ID3FrameWithLocalizedContent(
                    language: .eng,
                    contentDescription: "",
                    content: value
                )
            )
        case .composer:
            return builder.composer(frame: ID3FrameWithStringContent(content: value))
        case .subtitle:
            return builder.subtitle(frame: ID3FrameWithStringContent(content: value))
        case .conductor:
            return builder.conductor(frame: ID3FrameWithStringContent(content: value))
        case .lyricist:
            return builder.lyricist(frame: ID3FrameWithStringContent(content: value))
        case .fileOwner:
            return builder.fileOwner(frame: ID3FrameWithStringContent(content: value))
        }
    }

    /// Reads a string value from the specified frame type
    private func readFromFrame(_ reader: ID3TagContentReader, frame: ID3FrameType) -> String? {
        switch frame {
        case .title:
            return reader.title()
        case .artist:
            return reader.artist()
        case .albumArtist:
            return reader.albumArtist()
        case .album:
            return reader.album()
        case .genre:
            return reader.genre()?.description
        case .contentGroup:
            return reader.contentGrouping()
        case .comments:
            return reader.comments().first?.content
        case .composer:
            return reader.composer()
        case .subtitle:
            return reader.subtitle()
        case .conductor:
            return reader.conductor()
        case .lyricist:
            return reader.lyricist()
        case .fileOwner:
            return reader.fileOwner()
        }
    }
}
