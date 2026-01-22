# CrateBot 5

Audio fingerprinting and intelligent music analysis suite for DJs.

**CrateBot** uses 135-dimensional machine learning models to analyze your music library and suggest songs you might want to use while playing live. Think of it as a DJ's intelligent crate-digging assistant.

> Built with Claude Code by someone who has basically never written a line of code in his life. See: [The Road Runner Economy](https://nraford7.github.io/road-runner-economy/)

## What It Does

- **ML-powered tagging**: Predict Genre, Timing, Mood, and Descriptive tags for your tracks
- **184-dimensional feature vectors**: Combines librosa, Essentia, PANNs, CLAP, and Jamendo analysis
- **Vibe generation**: Claude API-powered descriptive tags that capture the *feel* of a track
- **Hook detection**: Whisper-based vocal transcription to find memorable moments
- **PANNs integration**: Instrument and sound detection
- **CLAP embeddings**: Semantic audio understanding
- **Real-time progress**: WebSocket updates for long analysis tasks
- **Checkpoint recovery**: Resume interrupted training

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
