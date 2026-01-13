# Training Checkpoint & Crash Prevention Progress

**Date:** 2026-01-13
**Status:** In Progress - Investigation Needed

## Completed Work

### 1. Training Checkpoint System
Created a checkpoint system to save and resume training progress:

**New File:** `CrateBotCore/Sources/CrateBotCore/ML/TrainingCheckpoint.swift`
- `TrainingCheckpoint` struct - Serializable checkpoint data containing:
  - Model name
  - Source directories (for compatibility validation)
  - Processed tracks with extracted features
  - Timestamp and version
- `CheckpointManager` class:
  - Saves checkpoints to `~/Library/Application Support/CrateBot/Checkpoints/{modelName}.checkpoint.json`
  - Loads existing checkpoints when training resumes
  - Validates checkpoint compatibility with current training run
  - Deletes checkpoint after successful training completion
  - `saveInterval = 50` tracks between saves

**Modified:** `TrainingDataCollector.swift`
- Added new `extractFeatures` overload with checkpoint support
- Saves checkpoint every 50 tracks during feature extraction
- Saves final checkpoint when extraction completes

**Modified:** `TrainingCoordinator.swift`
- Added `CheckpointManager` as dependency
- Checks for existing checkpoint before feature extraction
- Merges checkpoint data with newly collected tracks
- Deletes checkpoint after successful training

### 2. Crash Prevention - Integer Overflow Fix
Fixed crash caused by `AVAudioPCMBuffer` integer overflow:

**Modified:** `AudioAnalyzer.swift` (line ~189-197)
- Added check for `frameCount × bytesPerFrame > UInt32.max`
- Throws `AnalyzerError.bufferOverflow` instead of crashing

**Update:** 2026-01-13
- Adjusted buffer size calculation to account for non-interleaved channel layouts
- Validation and load guards now use `bytesPerFrame * channelCount` when `format.isInterleaved == false`

### 3. Pre-flight File Validation System
Added validation to exclude problematic files before training starts:

**Modified:** `AudioAnalyzer.swift`
- Added `ValidationResult` struct with file metadata
- Added `validateFile(at:)` method checking:
  - File readability
  - Duration limit (30 minutes max)
  - Frame count overflow (Int64 → UInt32)
  - Buffer size overflow (frameCount × bytesPerFrame > UInt32.max)
  - Invalid format data (zero sample rate, channels, length)
- Added `validateFiles(at:)` for concurrent validation

**Modified:** `TrainingDataCollector.swift`
- Added `ExcludedFile` struct to track excluded files with reasons
- Updated `CollectionResult` to include `excludedFiles` array
- `collectTrainingData` now:
  1. Discovers all MP3 files
  2. Validates all files concurrently
  3. Excludes problematic files with logging
  4. Collects tags only from valid files

**Modified:** `TrainingCoordinator.swift`
- Logs excluded files with warnings

## Outstanding Issue

Training is still failing after implementing the pre-flight validation. The exact error message from the UI is needed to diagnose the issue.

### Possible Causes to Investigate

1. **Validation excluding all files** - The validation might be incorrectly marking all files as invalid due to:
   - File permission issues in sandbox
   - Concurrent file access issues
   - Invalid sample rate/channel count in some files

2. **Checkpoint loading issue** - The new checkpoint code might have a bug:
   - Incompatible checkpoint format
   - Error in merging checkpoint tracks with collected tracks

3. **extractFeatures signature change** - The new method overload might not be called correctly

4. **Progress callback issue** - The `allFileNames` array might not match after excluding files

## Next Steps

1. **Get exact error message** from UI to identify failure point

2. **Add debug logging** to validation:
   ```swift
   logger.info("Validating file: \(url.lastPathComponent)")
   logger.info("  - Sample rate: \(sampleRate)")
   logger.info("  - Channels: \(channels)")
   logger.info("  - Length: \(file.length)")
   logger.info("  - Bytes per frame: \(bytesPerFrame)")
   logger.info("  - Total bytes: \(totalBytes)")
   logger.info("  - Result: \(isValid ? "valid" : "invalid")")
   ```

3. **Test validation independently** - Create a test that validates a known good file

4. **Check if all files are being excluded** - Log counts at each step:
   - Total discovered
   - Excluded count
   - Valid count
   - Tracks with tags count

5. **Review checkpoint loading logic** - Ensure tracks are properly merged when resuming

## Files Changed

| File | Changes |
|------|---------|
| `TrainingCheckpoint.swift` | NEW - Checkpoint structs, manager, tag hash validation, CheckpointCompatibility enum |
| `AudioAnalyzer.swift` | Added ValidationResult, validateFile, validateFiles, buffer overflow check |
| `TrainingDataCollector.swift` | Added ExcludedFile, updated CollectionResult, added validation phase, checkpoint-aware extractFeatures |
| `TrainingCoordinator.swift` | Added CheckpointManager, checkpoint loading/saving with tag hash validation, excluded files logging |

## Testing Status (2026-01-13)

### Completed Tests
- [x] Verify validation correctly identifies problematic files (`testValidateNonExistentFile`)
- [x] Verify validation does not exclude valid files (`testValidateValidAudioFile`, `testValidateStereoFile`)
- [x] Test checkpoint save/load cycle (`testSaveAndLoadCheckpoint`)
- [x] Test checkpoint compatibility validation (`testCheckpointCompatibilityWithMatchingDirectories`, `testCheckpointIncompatibleWithDifferentDirectories`)
- [x] Test tag hash validation (`testTagHashComputation`, `testTagHashChangesWhenTagsChange`, `testCheckpointIncompatibleWhenTagsModified`)
- [x] Test backwards compatibility with v1 checkpoints (`testBackwardsCompatibilityWithV1Checkpoint`)

### New Test Files
- `TrainingCheckpointTests.swift` - 21 tests covering checkpoint save/load, tag hash computation, compatibility validation
- `AudioAnalyzerTests.swift` - Extended with 6 new validation tests

### Fixed Compilation Issues
- Fixed `TrainingDataCollectorTests.swift` - Updated initializer to match new signature (removed effnetExtractor parameter)
- Fixed `TrainingCoordinatorTests.swift` - Updated State enum tests to use DetailedProgress instead of Double

### Tag Hash Validation
Added tag hash validation to prevent training on stale labels when resuming from checkpoint:
- `TrainingCheckpoint.tagHash` - Stores hash of track IDs and their tags at checkpoint creation
- `TrainingCheckpoint.computeTagHash(from:)` - Static method to compute deterministic hash from tracks
- `CheckpointManager.isCheckpointCompatible(_:sourceDirectories:currentTracks:)` - Enhanced to validate tag hashes
- `CheckpointCompatibility` enum - Returns detailed compatibility status with reasons
- `IncompatibilityReason` enum - Describes why checkpoint is incompatible (`.sourceDirectoriesMismatch`, `.tagsModified`)

When tags have been modified since checkpoint creation:
1. Checkpoint is marked incompatible
2. Old checkpoint is deleted
3. Training starts fresh with current tags

## Remaining Investigation

- [ ] Test resume from checkpoint after interruption (manual testing recommended)
- [ ] Test training completes successfully with valid files (integration test)
