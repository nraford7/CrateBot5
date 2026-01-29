# CrateBot Taxonomy System

This document describes the 4-category taxonomy system used for audio tagging.

## Overview

CrateBot uses a 4-category taxonomy to classify audio tracks:

| Category | Description | ID3 Tag (Read) | ID3 Tag (Write) |
|----------|-------------|----------------|-----------------|
| **Genre** | Musical genre/style | TCON (Genre) | TCON (Genre) |
| **Timing** | Set position/energy level | TCON (Genre)* | TALB (Album) |
| **Mood** | Emotional tone/vibe | TALB (Album) | TIT1 (Work) |
| **Descriptive** | Character/instruments (multi-label) | COMM (Comments) | COMM (Comments) |

*During training, Genre and Timing are **split** from the same ID3 Genre tag based on `ACTUAL_GENRE_VALUES`.

## Genre/Timing Split Logic

The Genre ID3 tag historically contained both genre and timing information mixed together. The system automatically splits these based on a whitelist of actual genre values.

### Actual Genre Values

Defined in `CrateBotCore/Sources/CrateBotCore/Tags/TagMapping.swift` (`TagMapping.knownGenres`):

```swift
public static let knownGenres: Set<String> = [
    "House",
    "Techno",
    "Jungle",
    "Rap",
    "DiscoFunk",
    "PartyBreaks",
    "Acapella",
    "Dub/Reggae"
]
```

### Split Logic

| Genre Tag Value | Recognized As | Assigned Genre |
|-----------------|---------------|----------------|
| House | Genre | House |
| Techno | Genre | Techno |
| Jungle | Genre | Jungle |
| Rap | Genre | Rap |
| DiscoFunk | Genre | DiscoFunk |
| PartyBreaks | Genre | PartyBreaks |
| Acapella | Genre | Acapella |
| Dub/Reggae | Genre | Dub/Reggae |
| Peak | Timing | House (default) |
| Build | Timing | House (default) |
| Start | Timing | House (default) |
| Sustain | Timing | House (default) |
| Release | Timing | House (default) |

If a Genre tag value is **not** in `ACTUAL_GENRE_VALUES`, it's treated as a timing value, and the track defaults to "House" genre.

## Timing Values

Standard timing/energy position values:

| Value | Description |
|-------|-------------|
| Start | Opening track, sets the mood |
| Build | Energy building, tension rising |
| Peak | Maximum energy, climax |
| Sustain | Maintaining high energy |
| Release | Winding down, closing |

## Training with Partial Data

### Timing Predictions for Non-House Genres

The timing classifier learns from **audio features** (energy, dynamics, spectral content), not from genre labels. This means:

1. **Training**: Timing classifier trains primarily on House tracks (which have timing labels)
2. **Prediction**: When tagging Techno, Jungle, or other genres without timing labels, the model predicts based on audio features learned from House

This works because timing concepts (build-up, peak intensity, release) are universal across genres - a "Peak" in House and a "Peak" in Techno share similar audio characteristics.

### Best Practices

- Ensure House tracks have good coverage of all timing values (Start, Build, Peak, Sustain, Release)
- The model can only predict what it's been trained on
- If you have 100 Peak tracks but only 5 Start tracks, Start predictions will be less reliable

## File Locations

| Component | File |
|-----------|------|
| Constants (genre list) | `CrateBotCore/Sources/CrateBotCore/Tags/TagMapping.swift` |
| Tag Scanner (split logic) | `CrateBotCore/Sources/CrateBotCore/Tags/ID3Manager.swift` |
| Tag Manager (ID3 read/write) | `CrateBotCore/Sources/CrateBotCore/Tags/ID3Manager.swift` |
| Training data collection | `CrateBotCore/Sources/CrateBotCore/ML/TrainingDataCollector.swift` |
| Model training | `CrateBotCore/Sources/CrateBotCore/ML/ModelTrainer.swift` |
| Lexicon (ID3 frame mapping) | `~/.cratebot/lexicon.json` |

## Lexicon Configuration

The lexicon (`~/.cratebot/lexicon.json`) controls which ID3 frames are used for writing:

```json
{
  "genre": {
    "id3_frame": "TCON",
    "mappings": {}
  },
  "timing": {
    "id3_frame": "TALB",
    "mappings": {}
  },
  "mood": {
    "id3_frame": "TIT1",
    "mappings": {}
  },
  "descriptive": {
    "id3_frame": "COMM",
    "mappings": {}
  }
}
```

## Adding New Genres

To add a new genre:

1. Edit `CrateBotCore/Sources/CrateBotCore/Tags/TagMapping.swift`
2. Add the genre to `TagMapping.knownGenres`:

```swift
public static let knownGenres: Set<String> = [
    "House",
    "Techno",
    // ... existing genres ...
    "NewGenre" // Add here
]
```

3. Retag your training files with the new genre value in the Genre ID3 tag
4. Retrain the model

## Historical Context

### The Bug (Fixed 2026-01-10)

The original implementation had a key mismatch:

- **Scanner** returned: `genre`, `album`, `comments`
- **Model** expected: `genre`, `timing`, `mood`, `descriptive`

This caused timing, mood, and descriptive classifiers to never train (they received `None` for their keys).

### The Fix

1. Updated tag scanning to split the Genre tag and use the new taxonomy keys
2. Updated tag selection UI to present 4 categories
3. Updated training data collection to transform tags to the new taxonomy
4. Added a known-genre list to define the genre/timing split

Model metadata now shows non-zero counts for all classifiers:

```json
{
  "genre_count": 8,
  "timing_count": 5,
  "mood_count": 6,
  "descriptive_count": 37
}
```
