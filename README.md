# CrateBot 4

Audio tagging and vibe generation desktop app for DJs & Music Producers.

**CrateBot 4** is a reliability and performance-focused upgrade from CrateBot 3.

Built with **Electron + React + TypeScript** frontend and **Python FastAPI** backend.

## What's New in CrateBot 4

### Reliability Improvements
- **Feature Configuration Tracking**: Prevents crashes from dimension mismatches when PANNs/CLAP availability changes between training and tagging
- **Centralized Tag Taxonomy**: Single source of truth for tag transformations, eliminating inconsistency bugs
- **Pre-Training Validation**: Validates directory, files, and selected tags before starting expensive operations
- **Auto Model Reload**: Newly trained models are automatically loaded for immediate use
- **Better Error Messages**: Clearer feedback when things go wrong

### Performance Improvements
- **Lazy Model Loading**: Models load on first use, not startup (80% faster startup)
- **Process-Based Parallelism**: Multi-label training uses processes instead of threads (1.5-2x faster)
- **Two-Phase Training Data Collection**: Pre-filters files by tags before feature extraction
- **Shared Model Instances**: ML models shared across analyzer instances (reduced memory)

## Architecture

```
CrateBot4/
├── backend/           # FastAPI server (Python)
│   ├── api_server.py  # REST API + WebSocket endpoints
│   ├── task_manager.py # Async task handling
│   └── models/        # Pydantic schemas
├── python/            # Python core modules
│   ├── src/core/      # Audio analysis, tagging, vibe generation
│   │   ├── feature_config.py   # NEW: Feature configuration tracking
│   │   ├── taxonomy.py         # NEW: Centralized tag transformation
│   │   ├── model_loader.py     # NEW: Lazy model loading
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

### Running the API Server

```bash
# Install dependencies
cd python
pip install -r requirements.txt

# Run server
cd ..
python backend/run_server.py
```

API docs available at: http://127.0.0.1:8742/docs

## Features

- **ML-powered tagging**: Predict Genre, Timing, Mood, and Descriptive tags
- **184-dimensional feature vectors**: librosa + Essentia + PANNs + CLAP + Jamendo
- **Vibe generation**: Claude API-powered descriptive tags
- **Hook detection**: Whisper-based vocal transcription
- **PANNs integration**: Instrument and sound detection
- **CLAP embeddings**: Semantic audio understanding
- **Real-time progress**: WebSocket updates for long tasks
- **Checkpoint recovery**: Resume interrupted training

## Requirements

- Python 3.10+
- macOS (Windows/Linux planned)
- Anthropic API key (for vibe generation)

## Upgrade from CrateBot 3

CrateBot 4 is backwards compatible with CrateBot 3 models. Simply load your existing model file.

Note: Models trained in CrateBot 4 include feature configuration metadata for better compatibility validation.

## Key Changes

| Component | CrateBot 3 | CrateBot 4 |
|-----------|------------|------------|
| Feature tracking | None | FeatureConfig metadata in models |
| Tag transformation | Duplicated in 2 places | Centralized in taxonomy.py |
| Model loading | Eager (slow startup) | Lazy (instant startup) |
| Multi-label training | Thread-based | Process-based (faster) |
| Training validation | Minimal | Pre-validation + better errors |
| Model reload | Manual | Automatic after training |
