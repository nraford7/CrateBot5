# CrateBot 2.0

Audio fingerprinting and intelligent music analysis suite for DJs.

**CrateBot** uses machine learning to analyze your music library and suggest songs you might want to use while playing live. Think of it as a DJ's intelligent crate-digging assistant.

> Built with Claude Code by someone who has basically never written a line of code in his life. See: [The Road Runner Economy](https://nraford7.github.io/road-runner-economy/)

## What It Does

- **ML-powered tagging**: Predict Genre, Timing, Mood, and Descriptive tags for your tracks
- **2192-dimensional feature vectors**: EffNet (1280) + Jamendo genres (400) + CLAP (512) embeddings
- **Native Swift training**: Train custom models on your own tagged library using CoreML
- **Vibe generation**: Claude API-powered tags that capture what makes each track *distinctive*
- **Mnemonic anchors**: Album-art-like memory hooks (2-3 word phrases that *feel* like the track)
- **Hook detection**: Native Speech framework for detecting memorable vocal moments
- **Real-time progress**: Live updates for long analysis tasks
- **Checkpoint recovery**: Resume interrupted training

## Vibe System

CrateBot generates two complementary tags for each track:

### Short Vibe Tag
**Format:** `[ENERGY] [DISTINCTIVE THING] [MOMENT]`

Identifies what makes the track unique - the thing you'd tell a friend to listen for.

```
DARK FLUTE MELODY PEAK
HARD ACID 303 SQUELCH PEAK
JOYFUL KALIMBA GROOVE OPENER
DREAMY STRINGS PIANO BLEND FLOATER
```

### Mnemonic Anchor
**Format:** `[synesthetic modifier] + [concrete anchor]`

A 2-3 word phrase that works like album art in text form - triggers recall through association, not description.

```
sweating serpent
chrome shaman
golden grandmother
velvet cathedral
```

The modifier translates sonic qualities to other senses (warm, dusty, chrome, velvet). The anchor is something you can picture (wizard, panther, cathedral, shaman).

## Architecture

Built with **SwiftUI** and **CoreML** for fully native macOS performance. **100% Swift** - no external dependencies.

```
CrateBot/
├── CrateBot.xcodeproj    # Xcode project
├── CrateBot/             # SwiftUI app
│   ├── App/              # App entry, state management
│   └── Views/            # SwiftUI views
├── CrateBotCore/         # Swift Package
│   ├── Audio/            # Feature extraction, playback
│   ├── ML/               # Training, inference (CoreML)
│   ├── Tags/             # ID3 tag management
│   ├── Data/             # SwiftData models, caching
│   ├── Networking/       # Anthropic API client
│   ├── Integrations/     # Vibe generation, hook detection
│   └── Resources/        # ML models (.mlpackage)
├── CrateBotModelLab/     # Model experimentation app
└── Models/               # Trained models directory
```

## Getting Started

1. **Open in Xcode**: `open CrateBot.xcodeproj`
2. **Build and Run**: Cmd+R
3. **Add Music Folders**: Grant access to your DJ library
4. **Train a Model**: Tag some tracks, then train on your library

## Requirements

- macOS 14.0+ (Sonoma)
- Xcode 15.0+
- Anthropic API key (optional, for vibe generation)

## Key Features

| Feature | Description |
|---------|-------------|
| Pure Swift | No external dependencies, native macOS performance |
| Feature caching | SwiftData persistence for extracted features |
| Direct API calls | Native Anthropic API client for vibe generation |
| Native speech | Apple Speech framework for hook detection |
| Configurable tag groups | Define mutually exclusive tags for multi-class training |
| Checkpoint recovery | Resume interrupted training sessions |
| Security-scoped bookmarks | Sandbox-safe access to music folders |

## Training Your Own Model

1. **Tag your tracks** using ID3 metadata (Genre, Mood, etc.)
2. **Configure field mapping** to tell CrateBot which ID3 frames to read
3. **Set up tag groups** for mutually exclusive categories (e.g., Energy: Low/Medium/High)
4. **Train** - CrateBot extracts features and trains CoreML classifiers
5. **Use** - Tag new tracks with your trained model

See [docs/SWIFT-TRAINING-PIPELINE.md](docs/SWIFT-TRAINING-PIPELINE.md) for detailed pipeline documentation.

## Status

Work in progress. DJ'ing is a main side quest.

---

*Part of the [Road Runner Economy](https://nraford7.github.io/road-runner-economy/) - built in hours, not months.*
