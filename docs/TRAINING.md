# CrateBot5 Training System

This document describes the machine learning training pipeline used in CrateBot5 (Swift/CoreML native implementation).

## Overview

CrateBot5 uses a **transfer learning approach** with pre-trained audio embeddings:

1. **Discogs-EffNet** extracts 1280-dimensional embeddings from audio
2. **MLBoostedTreeClassifier** (CreateML) trains binary classifiers per tag
3. Each tag gets its own classifier: "Does this track have tag X? Yes/No"

```
Audio File → EffNet Embeddings (1280-dim) → Binary Classifier → Tag Prediction
```

## Pipeline Architecture

### High-Level Flow

```
[Training Directories]
         ↓
[Scan for MP3 Files]
         ↓
[Read ID3 Tags from Files]
         ↓
[Discover & Filter Tags (min 50 samples)]
         ↓
[Extract EffNet Features (1280-dim)]
         ↓
[Train Binary Classifier per Tag]
         ↓
[Save .mlmodel Files + Metadata]
```

### Training Phases

| Phase | Description | Output |
|-------|-------------|--------|
| Collecting | Scan directories for MP3 files | File list |
| Discovering Tags | Read ID3 tags, count per-tag samples | Tag statistics |
| Filtering Tags | Apply minimum sample threshold | Valid tags |
| Extracting Features | Run EffNet on each track | 1280-dim embeddings |
| Training Models | Train classifiers per tag | .mlmodel files |
| Packaging | Save metadata + cleanup | Final model directory |

---

## Feature Extraction

### Discogs-EffNet Model

CrateBot uses [Discogs-EffNet](https://essentia.upf.edu/models.html) for audio embeddings:

- **Input**: Mel spectrogram (128 time frames × 96 mel bands)
- **Output**: 1280-dimensional embedding vector
- **Pre-trained on**: Discogs dataset (millions of tracks)

### Audio Processing

```
Audio File (any format/sample rate)
         ↓
[Resample to 16kHz mono]
         ↓
[Generate Mel Spectrogram]
    - Frame size: 512 samples (32ms)
    - Hop size: 256 samples (16ms)
    - Mel bands: 96
    - Time frames: 128
    - Frequency range: 0-8000 Hz
         ↓
[EffNet Inference]
         ↓
1280-dimensional embedding
```

### Spectrogram Parameters

| Parameter | Value | Notes |
|-----------|-------|-------|
| Sample Rate | 16,000 Hz | All audio resampled |
| Frame Size | 512 samples | 32ms windows |
| Hop Size | 256 samples | 16ms hop |
| FFT Size | 512 | Matches frame size |
| Mel Bands | 96 | Frequency resolution |
| Time Frames | 128 | Temporal resolution |
| Min Duration | ~2.27 seconds | 36,352 samples required |

### Minimum Audio Duration

The mel spectrogram requires exactly 128 time frames. With hop size of 256 and frame size of 512:

```
Required samples = (128 - 1) × 256 + 512 = 36,352 samples
At 16kHz = 2.272 seconds minimum duration
```

**Tracks shorter than ~2.3 seconds will fail feature extraction.**

---

## Training Data Requirements

### Tag Sources

Tags are read from ID3 metadata in MP3 files:

| Field | ID3 Frame | Usage |
|-------|-----------|-------|
| Genre | TCON | Primary genre tag |
| Timing | TALB | Timing/energy classification |
| Mood | TIT1 | Mood/vibe tags |
| Descriptive | COMM | Comma-separated descriptors |

### Minimum Sample Requirements

| Constraint | Value | Reason |
|------------|-------|--------|
| Min samples per tag | 50 | Statistical significance |
| Max negative ratio | 3:1 | Prevent class imbalance |
| Min alphabetic chars | 30% | Filter garbage tags |
| Max tag length | 100 chars | Prevent metadata bloat |

### Tag Validation

Tags are sanitized before use:
- Remove non-printable characters
- Filter ID3v1 artifacts ("ID3v1 Comment")
- Remove encoder prefixes (iTunes, LAME, etc.)
- Require >30% alphabetic characters
- Truncate to 100 characters

### Skip Conditions

A tag will be **skipped** if:
- Fewer than 50 positive samples
- Zero negative samples (all tracks have the tag)
- Training fails (NaN/Inf in features)

A track will be **excluded** if:
- Audio duration < 2.27 seconds
- Feature extraction produces NaN/Inf values
- File is corrupted or unreadable

---

## Model Training

### Algorithm: MLBoostedTreeClassifier

CrateBot uses Apple's CreateML gradient boosting classifier:

| Parameter | Value | Description |
|-----------|-------|-------------|
| maxDepth | 6 | Maximum tree depth |
| maxIterations | 100 | Number of boosting rounds |
| stepSize | 0.3 | Learning rate |
| minLossReduction | 0.0 | Minimum loss to make split |
| minChildWeight | 1.0 | Minimum sum of weights in child |

### Training Process (per tag)

```
1. Split tracks: positive (has tag) vs negative (no tag)
2. Balance: cap negatives at 3× positives
3. Create DataFrame with 1280 feature columns
4. Z-score normalize each feature
5. Split 80/20 train/validation
6. Train MLBoostedTreeClassifier
7. Calculate training & validation accuracy
8. Save as {tag_name}.mlmodel
```

### Feature Normalization

Z-score normalization is applied **per feature** during training:

```swift
for each feature f in 0..<1280:
    mean = average(feature_f across all samples)
    stddev = standard_deviation(feature_f)
    normalized_f = (value - mean) / stddev
```

Features with near-zero variance (stddev < 1e-10) are logged but not skipped.

### Data Splitting

| Split | Percentage | Purpose |
|-------|------------|---------|
| Training | 80% | Model fitting |
| Validation | 20% | Accuracy estimation |

Random seed is fixed at 42 for reproducibility.

---

## Checkpoint System

### Purpose

Feature extraction is expensive (~2-5 seconds per track). The checkpoint system enables:
- **Resume interrupted training** without re-extracting features
- **Detect tag modifications** that require re-training
- **Cache features** for faster iteration

### Checkpoint Structure

```
~/Library/Application Support/CrateBot/Checkpoints/{modelName}.checkpoint.json
```

Contents:
```json
{
  "modelName": "MyModel",
  "createdAt": "2024-01-15T10:30:00Z",
  "sourceDirectories": ["/path/to/music"],
  "processedTracks": [
    {
      "id": "/path/to/track.mp3",
      "tags": ["house", "energetic"],
      "features": [0.123, -0.456, ...]  // 1280 floats
    }
  ],
  "totalTracksDiscovered": 500,
  "checkpointVersion": 2,
  "tagHash": "a1b2c3d4e5f6g7h8"
}
```

### Save Frequency

Checkpoints are saved:
- Every **50 tracks** during feature extraction
- After **all features extracted** (final save)

### Compatibility Checks

A checkpoint is **compatible** if:
- Source directories match
- Tag hash matches (version 2+)

A checkpoint is **incompatible** if:
- Directories changed → Full re-extraction
- Tags modified → Full re-extraction

### Tag Hash (Version 2)

```
1. Sort tracks by file path
2. Concatenate: "path1:tag1,tag2;path2:tag3,tag4;..."
3. Hash with djb2 algorithm
```

This detects if any tags were manually edited after the checkpoint was created.

### Checkpoint Lifecycle

```
1. Start training → Check for existing checkpoint
2. Compatible? → Load cached features, extract only new tracks
3. Incompatible? → Delete checkpoint, start fresh
4. During extraction → Save every 50 tracks
5. Training complete → Delete checkpoint
```

---

## Model Output

### Directory Structure

```
~/Library/Application Support/CrateBot/Models/{ModelName}/
├── house.mlmodel           # Binary classifier for "house"
├── techno.mlmodel          # Binary classifier for "techno"
├── energetic.mlmodel       # Binary classifier for "energetic"
├── ...
└── ModelName.json          # Metadata
```

### Metadata Format

```json
{
  "name": "ModelName",
  "version": "1.0.0",
  "pipelineVersion": "a1b2c3d4e5f6g7h8",
  "trainedAt": "2024-01-15T12:00:00Z",
  "trainingFileCount": 450,
  "categories": ["General"],
  "tags": {
    "General": ["house", "techno", "energetic", "chill"]
  },
  "accuracy": 0.847
}
```

### Pipeline Version

The `pipelineVersion` is a hash of:
- Extractor versions (effnet: v1)
- Windowing parameters (window/hop/fft sizes)
- Normalization method (log_mel)

This ensures models are invalidated when the feature pipeline changes.

---

## Inference

### Model Loading

```swift
// Load all classifiers from model directory
let (count, name) = try await engine.loadModel(from: modelDirectory)
// count = number of tag classifiers loaded
// name = model name from directory
```

### Prediction Process

```
Audio File
     ↓
[Extract EffNet embeddings]
     ↓
[Run each binary classifier]
     ↓
[Collect tags where classifier returns TRUE]
     ↓
[Filter to top N predictions]
     ↓
TaggingResult
```

### Inference Parameters

| Parameter | Value | Description |
|-----------|-------|-------------|
| topPredictionCount | 5 | Max tags per category |
| predictionThreshold | 0.2 | Min probability to include |

---

## Performance Characteristics

### Training Time Estimates

| Component | Time per Track | Notes |
|-----------|----------------|-------|
| Feature extraction | 2-5 seconds | Depends on track length |
| Model training | ~1 second per tag | With 50+ samples |

For 500 tracks with 20 tags: ~20-40 minutes total

### Memory Usage

| Component | Memory |
|-----------|--------|
| EffNet model | ~50 MB |
| Per-track features | 5 KB (1280 × 4 bytes) |
| Training DataFrame | ~50 MB for 1000 tracks |

### Accuracy Expectations

| Sample Count | Expected Accuracy |
|--------------|-------------------|
| 50-100 | 70-80% |
| 100-200 | 75-85% |
| 200-500 | 80-90% |
| 500+ | 85-95% |

Accuracy depends heavily on tag consistency and audio quality.

---

## Troubleshooting

### Common Skip Reasons

| Reason | Solution |
|--------|----------|
| "Insufficient samples (50 required)" | Add more tracks with this tag |
| "Training failed: NaN in features" | Check for corrupted audio files |
| "Zero negative samples" | Tag is too common (all tracks have it) |

### Feature Extraction Failures

| Error | Cause | Solution |
|-------|-------|----------|
| "Insufficient data" | Track < 2.27 seconds | Use longer tracks |
| "Invalid buffer" | Corrupted audio | Re-encode file |
| "NaN/Inf in features" | Audio anomaly | Exclude track |

### Checkpoint Issues

| Issue | Solution |
|-------|----------|
| "Source directories mismatch" | Training directories changed; will re-extract |
| "Tags modified" | ID3 tags were edited; will re-extract |
| Checkpoint not loading | Delete checkpoint file manually |

---

## Code References

| Component | File | Key Functions |
|-----------|------|---------------|
| Training orchestration | `ML/TrainingCoordinator.swift` | `train()`, `currentPipelineVersion()` |
| Feature extraction | `Audio/EffNetExtractor.swift` | `extractFeatures()` |
| Mel spectrogram | `Audio/MelSpectrogramGenerator.swift` | `generate()`, `flatten()` |
| Data collection | `ML/TrainingDataCollector.swift` | `collect()`, `extractFeatures()` |
| Model training | `ML/ModelTrainer.swift` | `trainModels()` |
| Checkpoint system | `ML/TrainingCheckpoint.swift` | `save()`, `load()`, `isCompatible()` |
| Inference | `ML/TaggingEngine.swift` | `analyze()`, `loadModel()` |
| Binary classifier | `ML/TagClassifier.swift` | `predict()`, `predictWithConfidence()` |

---

## Version History

| Version | Changes |
|---------|---------|
| CrateBot5 1.0 | Initial Swift/CoreML implementation |
| Checkpoint v2 | Added tag hash for edit detection |

---

## References

- [Discogs-EffNet](https://essentia.upf.edu/models.html) - Pre-trained audio embedding model
- [CreateML MLBoostedTreeClassifier](https://developer.apple.com/documentation/createml/mlboostedtreeclassifier) - Apple's gradient boosting classifier
- [Essentia](https://essentia.upf.edu/) - Audio analysis library (used for secondary predictions)
