# Swift Training Pipeline Completion Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Complete the Swift training pipeline by verifying the CLAP model bundle, fixing documentation, adding audio validation, and verifying the entire flow works end-to-end.

**Architecture:** Verify CLAP CoreML bundle, fix mel spectrogram parameter docs, add minimum duration validation in TrainingDataCollector, then test full pipeline (collection → extraction → training → inference).

**Tech Stack:** Swift (CoreML, AVFoundation, CreateML), macOS 14+

---

## Task 1: Verify CLAP Model Bundle

**Files:**
- Verify: `/Users/noahraford/Projects/claude_projects/11_CrateBot/CrateBot5/CrateBotCore/Sources/CrateBotCore/Resources/CLAPAudioEncoder.mlpackage`

**Step 1: Verify model is in Resources**

Run:
```bash
ls -la /Users/noahraford/Projects/claude_projects/11_CrateBot/CrateBot5/CrateBotCore/Sources/CrateBotCore/Resources/*.mlpackage
```
Expected: Should list 4 mlpackage files including `CLAPAudioEncoder.mlpackage`

**Step 2: Commit (if needed)**

```bash
cd /Users/noahraford/Projects/claude_projects/11_CrateBot/CrateBot5
git add CrateBotCore/Sources/CrateBotCore/Resources/CLAPAudioEncoder.mlpackage
git commit -m "feat: add CLAP audio encoder CoreML model (512-dim embeddings)"
```

---

## Task 2: Fix Mel Spectrogram Parameter Documentation

**Files:**
- Modify: `/Users/noahraford/Projects/claude_projects/11_CrateBot/CrateBot5/CrateBotCore/Sources/CrateBotCore/ML/TrainingCoordinator.swift:796-810`

**Step 1: Read current implementation**

The `currentPipelineVersion()` function documents wrong parameters:
```swift
// WRONG - says 400 window, 160 hop
windowSize: 400,    // 25ms at 16kHz
hopSize: 160,       // 10ms at 16kHz
fftSize: 512
```

But `MelSpectrogramGenerator.swift` actually uses:
```swift
frameSize = 512      // MusiCNN uses 512
hopSize = 256        // MusiCNN uses 256
```

**Step 2: Update TrainingCoordinator.currentPipelineVersion()**

Replace lines 799-803 with:
```swift
FeaturePipelineVersion(
    extractorVersions: ["effnet": "v1", "clap": "v1"],
    windowingParams: FeaturePipelineVersion.WindowingParams(
        windowSize: 512,    // 32ms at 16kHz (MusiCNN/EffNet)
        hopSize: 256,       // 16ms at 16kHz (MusiCNN/EffNet)
        fftSize: 512        // EffNet FFT size
    ),
    normalizationParams: FeaturePipelineVersion.NormalizationParams(
        method: "log_mel",
        perFeature: false
    )
)
```

**Step 3: Verify the change compiles**

Run:
```bash
cd /Users/noahraford/Projects/claude_projects/11_CrateBot/CrateBot5/CrateBotCore
swift build 2>&1 | head -20
```
Expected: Build succeeds or shows unrelated warnings

**Step 4: Commit**

```bash
cd /Users/noahraford/Projects/claude_projects/11_CrateBot/CrateBot5
git add CrateBotCore/Sources/CrateBotCore/ML/TrainingCoordinator.swift
git commit -m "fix: correct mel spectrogram parameters in pipeline version (512/256 not 400/160)"
```

---

## Task 3: Add Minimum Audio Duration Validation

**Files:**
- Modify: `/Users/noahraford/Projects/claude_projects/11_CrateBot/CrateBot5/CrateBotCore/Sources/CrateBotCore/Audio/AudioAnalyzer.swift`

**Step 1: Read current AudioAnalyzer validation**

Check how `validateFiles(at:)` currently works and where to add duration check.

**Step 2: Add minimum duration constant**

Add near the top of `AudioAnalyzer.swift`:
```swift
/// Minimum audio duration in seconds for EffNet processing
/// EffNet needs 128 time frames with hopSize=256 at 16kHz
/// Required samples = (127 * 256) + 512 = 33,024 samples = 2.064 seconds
public static let minimumDurationSeconds: Double = 2.1
```

**Step 3: Add duration check to validation**

In the `validateFiles(at:)` method (or `validateFile(_:)` if it exists), add after loading audio metadata:
```swift
// Check minimum duration
if duration < Self.minimumDurationSeconds {
    return ValidationResult(
        url: url,
        isValid: false,
        error: AudioAnalyzerError.audioTooShort(
            duration: duration,
            required: Self.minimumDurationSeconds
        )
    )
}
```

**Step 4: Add error case if not exists**

If `AudioAnalyzerError` doesn't have `audioTooShort`, add:
```swift
case audioTooShort(duration: Double, required: Double)

// In errorDescription:
case .audioTooShort(let duration, let required):
    return "Audio too short: \(String(format: "%.1f", duration))s < \(String(format: "%.1f", required))s minimum"
```

**Step 5: Verify build**

Run:
```bash
cd /Users/noahraford/Projects/claude_projects/11_CrateBot/CrateBot5/CrateBotCore
swift build 2>&1 | head -20
```
Expected: Build succeeds

**Step 6: Commit**

```bash
cd /Users/noahraford/Projects/claude_projects/11_CrateBot/CrateBot5
git add CrateBotCore/Sources/CrateBotCore/Audio/AudioAnalyzer.swift
git commit -m "feat: add minimum audio duration validation (2.1s for EffNet)"
```

---

## Task 4: Update Package.swift Resources (if needed)

**Files:**
- Check: `/Users/noahraford/Projects/claude_projects/11_CrateBot/CrateBot5/CrateBotCore/Package.swift`

**Step 1: Verify resources are correctly declared**

Run:
```bash
grep -A 20 "resources:" /Users/noahraford/Projects/claude_projects/11_CrateBot/CrateBot5/CrateBotCore/Package.swift
```

**Step 2: Check if mlpackage files are processed**

The Package.swift should have something like:
```swift
resources: [
    .process("Resources")
]
```

If it uses `.copy()` instead, CoreML models may not compile. Verify it's `.process()`.

**Step 3: Commit if changes needed**

Only commit if Package.swift needed modification.

---

## Task 5: Build and Run Swift Tests

**Files:**
- Test: Full CrateBotCore package

**Step 1: Clean and build the package**

Run:
```bash
cd /Users/noahraford/Projects/claude_projects/11_CrateBot/CrateBot5/CrateBotCore
swift build --clean
swift build
```
Expected: Build succeeds with all models compiled

**Step 2: Run existing tests**

Run:
```bash
cd /Users/noahraford/Projects/claude_projects/11_CrateBot/CrateBot5/CrateBotCore
swift test 2>&1 | tail -30
```
Expected: Tests pass or show expected failures (not crashes)

**Step 3: Verify CLAP model loads**

Create a quick test by checking logs when initializing CombinedFeatureExtractor:
```bash
cd /Users/noahraford/Projects/claude_projects/11_CrateBot/CrateBot5/CrateBotCore
swift build && swift test --filter "CombinedFeatureExtractor" 2>&1 || echo "No specific test, checking build output"
```

---

## Task 6: End-to-End Pipeline Test

**Files:**
- Test with: Sample MP3 files (user's music library)

**Step 1: Build the main CrateBot app**

Run:
```bash
cd /Users/noahraford/Projects/claude_projects/11_CrateBot/CrateBot5
xcodebuild -project CrateBot.xcodeproj -scheme CrateBot -configuration Debug build 2>&1 | tail -30
```
Expected: Build succeeds

**Step 2: Run the app and test training flow**

Open the app:
```bash
open /Users/noahraford/Projects/claude_projects/11_CrateBot/CrateBot5/CrateBot.xcodeproj
```

Then manually:
1. Add a training directory with tagged MP3s
2. Start training
3. Verify feature extraction uses 2192 dimensions (EffNet 1280 + Genres 400 + CLAP 512)
4. Verify model saves successfully

**Step 3: Test inference with trained model**

1. Load the trained model
2. Analyze a test track
3. Verify predictions include user tags + Essentia tags

---

## Task 7: Verify Feature Dimensions

**Files:**
- Check: Debug logs or console output

**Step 1: Check CombinedFeatureExtractor reports correct dimensions**

After running training or inference, check that logs show:
```
CombinedFeatureExtractor initialized successfully with config: EffNet+Genres+CLAP (2192)
```

NOT:
```
Warning: CLAP extractor unavailable... falling back to EffNet+Genres
```

**Step 2: Verify model metadata has correct feature dimension**

After training, check the model's JSON metadata:
```bash
cat ~/Library/Application\ Support/CrateBot/Models/<model-name>/<model-name>.json | grep featureDimension
```
Expected: `"featureDimension": 2192`

---

## Summary Checklist

| Task | Description | Status |
|------|-------------|--------|
| 1 | Convert CLAP to CoreML | Pending |
| 2 | Fix mel spectrogram params | Pending |
| 3 | Add audio duration validation | Pending |
| 4 | Verify Package.swift resources | Pending |
| 5 | Build and test Swift package | Pending |
| 6 | End-to-end pipeline test | Pending |
| 7 | Verify 2192 feature dimensions | Pending |

---

## Rollback Plan

If CLAP causes issues:
1. Remove `CLAPAudioEncoder.mlpackage` from Resources
2. Change default in `TrainingDataCollector.swift:130` from `.effnetGenresCLAP` to `.effnetPlusGenres`
3. Retrain models with 1680 dimensions

---

## Notes

- CLAP model download from HuggingFace is ~1GB (one-time)
- CoreML conversion produces ~50-100MB .mlpackage
- Full 2192-dim training takes longer but should improve accuracy
- Jamendo Essentia models are already bundled (no action needed)
