# Swift Training Pipeline

## Overview

CrateBot uses a native Swift/CoreML training pipeline for audio tag classification. The pipeline extracts audio features using pre-trained neural networks and trains binary classifiers for each tag using CreateML's MLBoostedTreeClassifier.

## Pipeline Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           SWIFT TRAINING PIPELINE                           │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  1. DATA COLLECTION (TrainingDataCollector.swift)                          │
│     ├─ Scan directories for MP3 files                                      │
│     ├─ Read ID3 tags using configurable TagFieldMapping                    │
│     │   └─ genre=TCON, timing=TALB/TPE2 (user configurable), mood=TIT1/TALB│
│     ├─ Validate audio files (filter problematic files)                     │
│     └─ Create TaggedTrack objects                                          │
│                                                                             │
│  2. FEATURE EXTRACTION (CombinedFeatureExtractor.swift)                    │
│     ├─ Load audio at 16kHz                                                 │
│     ├─ EffNet embeddings: 1280 dimensions                                  │
│     ├─ Genre activations: 400 dimensions                                   │
│     ├─ CLAP embeddings: 512 dimensions                                     │
│     └─ Total: 2192-dim feature vector                                      │
│                                                                             │
│  3. AUGMENTATION (AudioAugmenter.swift)                                    │
│     ├─ SpecAugment: Time/frequency masking                                 │
│     ├─ Mixup: Beta distribution mixing (alpha=0.4)                         │
│     └─ Feature noise: 2% Gaussian noise                                    │
│                                                                             │
│  4a. MULTI-CLASS TRAINING (TagGroupRegistry + ModelTrainer)                │
│     ├─ Identify tag groups (configurable mutually exclusive tags)          │
│     ├─ Generate multi-class data per group                                 │
│     ├─ Train MLBoostedTreeClassifier per group                             │
│     └─ Remove grouped tags from binary training                            │
│                                                                             │
│  4b. BINARY TRAINING (ModelTrainer.swift)                                  │
│     ├─ Generate balanced positive/negative samples                         │
│     ├─ Log contrastive loss (diagnostic)                                   │
│     ├─ Apply Mixup augmentation                                            │
│     ├─ Z-score normalize features                                          │
│     ├─ Train MLBoostedTreeClassifier per tag                               │
│     │   └─ Parameters: maxDepth=6, iterations=100, stepSize=0.3            │
│     └─ Validate with holdout set (20%)                                     │
│                                                                             │
│  5. PACKAGING (TrainingCoordinator.swift)                                  │
│     ├─ Save .mlmodel files                                                 │
│     ├─ Create metadata.json with categories and tag groups                 │
│     └─ Clean up checkpoints                                                │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

## Key Components

| Component | File | Purpose |
|-----------|------|---------|
| **TrainingCoordinator** | `ML/TrainingCoordinator.swift` | Orchestrates full pipeline |
| **TrainingDataCollector** | `ML/TrainingDataCollector.swift` | Scans MP3s, reads ID3, extracts features |
| **CombinedFeatureExtractor** | `Audio/CombinedFeatureExtractor.swift` | EffNet + Genres + CLAP = 2192 dims |
| **ModelTrainer** | `ML/ModelTrainer.swift` | CreateML MLBoostedTreeClassifier |
| **TagGroupRegistry** | `ML/TagGroupRegistry.swift` | Configurable multi-class tag groups |
| **MultiClassTrainingDataGenerator** | `ML/MultiClassTrainingDataGenerator.swift` | Generates multi-class data |
| **AudioAugmenter** | `ML/AudioAugmenter.swift` | Mixup, SpecAugment |
| **ContrastiveLoss** | `ML/ContrastiveLoss.swift` | Diagnostic loss logging |
| **ID3Manager** | `Tags/ID3Manager.swift` | Read/write ID3 tags |

---

## Feature Extraction

### 2192-Dimensional Feature Vector

The Swift pipeline extracts rich audio features using three pre-trained models:

| Model | Dimensions | Purpose |
|-------|------------|---------|
| Discogs-EffNet | 1280 | General audio embeddings trained on millions of tracks |
| Jamendo Genres | 400 | Genre classification activations |
| CLAP | 512 | Semantic audio-text embeddings |

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
         ↓
[Run Feature Extractors]
         ↓
2192-dimensional embedding
```

---

## Multi-Class Tag Groups

Tag groups define mutually exclusive tags that should be trained as multi-class classifiers (softmax) rather than independent binary classifiers.

### Configuration

Tag groups are configurable in the Training UI. Default groups:

```swift
"BassType": ["Punchy", "Walking", "BoomingBass", "GrindyBass"]
"VocalType": ["Singing", "Chanting", "Spoken Word", "Rap", "Instrumental"]
"Energy": ["Low", "Medium", "High", "Peak"]
"Cultural": ["Asian", "Latin", "African", "MiddleEastern", "European"]
```

### How It Works

1. During training, tags matching these groups are trained as multi-class (softmax)
2. These tags are excluded from binary training
3. At inference, the model predicts ONE tag from each group

**Important:** Configure tag groups to match your actual vocabulary. If you don't have tags like "Punchy" or "Walking", these groups won't help.

---

## Augmentation

### Mixup (Default: Enabled)

Combines two training samples to create synthetic examples:

```
mixed_features = λ · sample1 + (1-λ) · sample2
```

- λ is drawn from Beta(0.4, 0.4) distribution
- 30% of training data is augmented
- Uses dominant label for classification

**Benefits:** Regularization, smooth decision boundaries, better generalization.

### SpecAugment

Time and frequency masking applied to mel spectrograms before feature extraction.

### Feature Noise

2% Gaussian noise added to feature vectors during training.

---

## Training Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| Min samples per tag | 50 | Tags with fewer samples are skipped |
| Max negative ratio | 3:1 | Prevents class imbalance |
| Max tree depth | 6 | MLBoostedTreeClassifier depth |
| Boosting iterations | 100 | Number of trees |
| Learning rate | 0.3 | Step size for gradient boosting |
| Validation split | 20% | Holdout for accuracy estimation |

---

## Contrastive Loss Diagnostics

Before training each tag, the pipeline computes supervised contrastive loss to measure how well features separate classes.

- **Loss < 2.0:** Excellent separation, expect high accuracy
- **Loss 2.0-5.0:** Good separation, reasonable accuracy
- **Loss > 5.0:** Poor separation, tag may be difficult to learn

This is diagnostic only (CreateML doesn't support custom losses), but helps identify problematic tags.

---

## Checkpoint System

Feature extraction is expensive (~2-5 seconds per track). The checkpoint system enables:

- **Resume interrupted training** without re-extracting features
- **Detect tag modifications** that require re-training
- **Cache features** for faster iteration

### Checkpoint Location

```
~/Library/Application Support/CrateBot/Checkpoints/{modelName}.checkpoint.json
```

### Compatibility

A checkpoint is invalidated if:
- Source directories changed
- ID3 tags were modified (detected via hash)
- Pipeline version changed

---

## Model Output

### Directory Structure

```
~/Library/Application Support/CrateBot/Models/{ModelName}/
├── house.mlmodel           # Binary classifier for "house"
├── techno.mlmodel          # Binary classifier for "techno"
├── EnergyGroup.mlmodel     # Multi-class classifier for Energy
├── ...
└── metadata.json           # Model metadata
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
  "tagGroups": {
    "Energy": ["Low", "Medium", "High", "Peak"]
  },
  "accuracy": 0.847
}
```

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

### Debugging

Check logs at: `~/Library/Application Support/CrateBot/debug.log`

---

## Code References

| Component | File | Key Functions |
|-----------|------|---------------|
| Training orchestration | `ML/TrainingCoordinator.swift` | `train()`, `currentPipelineVersion()` |
| Feature extraction | `Audio/CombinedFeatureExtractor.swift` | `extractFeatures()` |
| Data collection | `ML/TrainingDataCollector.swift` | `collect()`, `extractFeatures()` |
| Model training | `ML/ModelTrainer.swift` | `trainModels()` |
| Multi-class groups | `ML/TagGroupRegistry.swift` | `groups`, `isMultiClass()` |
| Checkpoint system | `ML/TrainingCheckpoint.swift` | `save()`, `load()`, `isCompatible()` |
| Inference | `ML/TaggingEngine.swift` | `analyze()`, `loadModel()` |
