# CrateBot 5

Audio fingerprinting and intelligent music analysis suite for DJs.

**CrateBot** uses 135-dimensional machine learning models to analyze your music library and suggest songs you might want to use while playing live. Think of it as a DJ's intelligent crate-digging assistant.

> Built with Claude Code by someone who has basically never written a line of code in his life. See: [The Road Runner Economy](https://nraford7.github.io/road-runner-economy/)

## What It Does

- **ML-powered tagging**: Predict Genre, Timing, Mood, and Descriptive tags for your tracks
- **184-dimensional feature vectors**: Combines librosa, Essentia, PANNs, CLAP, and Jamendo analysis
- **Vibe generation**: Claude API-powered tags that capture what makes each track *distinctive*
- **Mnemonic anchors**: Album-art-like memory hooks (2-3 word phrases that *feel* like the track)
- **Hook detection**: Lyrics-first detection with Whisper fallback for finding memorable vocal moments
- **PANNs integration**: Instrument and sound detection
- **CLAP embeddings**: Semantic audio understanding
- **Real-time progress**: WebSocket updates for long analysis tasks
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

## Hook Detection

CrateBot uses a **lyrics-first** approach for detecting hooks (memorable vocal phrases):

1. **Fetch lyrics** from free APIs (LRCLIB, Lyrics.ovh)
2. **Analyze for repetition** - find chorus sections and repeated phrases
3. **Fall back to Whisper** transcription if no lyrics available

This dramatically improves accuracy for known tracks since lyrics are "ground truth" with no hallucination risk. Whisper can struggle with processed vocals (reverb, autotune, beat-synced mixing).

```python
# Automatic when using CachedHookTranscriber with artist/title
transcriber = CachedHookTranscriber(use_lyrics_first=True)
result = transcriber.detect_hook(path, artist="Artist", title="Song")
print(result.hook)  # "feel the groove tonight"
```

See [docs/LYRICS-FIRST-HOOK-DETECTION.md](docs/LYRICS-FIRST-HOOK-DETECTION.md) for details.

## Architecture

Built with **Electron + React + TypeScript** frontend and **Python FastAPI** backend.

```
CrateBot5/
├── backend/           # FastAPI server (Python)
│   ├── api_server.py  # REST API + WebSocket endpoints
│   ├── task_manager.py # Async task handling
│   └── models/        # Pydantic schemas
├── python/            # Python core modules
│   ├── src/core/      # Audio analysis, tagging, vibe generation
│   │   ├── feature_config.py   # Feature configuration tracking
│   │   ├── taxonomy.py         # Centralized tag transformation
│   │   ├── model_loader.py     # Lazy model loading
│   │   └── ...
│   ├── src/models/    # ML tag predictor
│   └── tests/         # Test suite
├── desktop/           # Electron + React
│   ├── electron/      # Main process
│   └── src/           # React frontend
└── resources/         # Icons, bundled models
```

## API Endpoints

- `POST /api/v1/train/start` - Start model training
- `POST /api/v1/tag/file` - Tag a single file
- `POST /api/v1/tag/batch` - Batch tagging
- `POST /api/v1/vibe/file` - Generate vibe description
- `GET /api/v1/model/info` - Current model info
- `POST /api/v1/model/load` - Load a model
- `WebSocket /api/v1/ws/progress/{task_id}` - Real-time progress

## Getting Started

```bash
# Install dependencies
cd python
pip install -r requirements.txt

# Run server
cd ..
python backend/run_server.py
```

API docs available at: http://127.0.0.1:8742/docs

## Requirements

- Python 3.10+
- macOS (Windows/Linux planned)
- Anthropic API key (for vibe generation)

## Key Features

| Feature | Description |
|---------|-------------|
| Feature tracking | FeatureConfig metadata in models |
| Tag transformation | Centralized in taxonomy.py |
| Model loading | Lazy loading (instant startup) |
| Multi-label training | Process-based parallelism (fast) |
| Training validation | Pre-validation + clear error messages |
| Model reload | Automatic after training |

## Status

Work in progress. DJ'ing is a main side quest.

---

*Part of the [Road Runner Economy](https://nraford7.github.io/road-runner-economy/) - built in hours, not months.*
