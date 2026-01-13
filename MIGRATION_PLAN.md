# CrateBot Migration Plan: tkinter → Electron + React

## Overview
Migrate CrateBot from Python/tkinter (~7000 lines) to a modern **Electron + React/TypeScript** desktop app with **Python FastAPI backend**.

**Target:** macOS desktop app for DJs & Music Producers with all features preserved.

**Scope:** Full migration (all phases) - complete feature parity before release.

**Platform:** macOS first (Windows/Linux can be added later).

---

## Recommended Stack

| Layer | Technology | Rationale |
|-------|------------|-----------|
| **Desktop Shell** | Electron 28+ | Mature, excellent Python subprocess management, larger ecosystem |
| **Frontend** | React 18 + TypeScript + Vite | Industry standard, type safety, fast dev |
| **Styling** | TailwindCSS | Rapid UI, Apple HIG-inspired design |
| **State** | Zustand + React Query | Simple state + async data fetching |
| **Backend** | FastAPI + Uvicorn | Async Python, WebSocket support, auto-docs |
| **Packaging** | PyInstaller (sidecar) | Bundle Python as standalone executable |

### Why Electron over Tauri?
- Better Python subprocess management (critical for librosa/torch/whisper)
- More mature ecosystem and documentation
- Proven patterns for audio apps
- Bundle size overhead (~150MB) acceptable given ML models already ~100MB

---

## Architecture

```
┌─────────────────────────────────────────────┐
│              ELECTRON SHELL                  │
│  ┌───────────────────────────────────────┐  │
│  │     REACT FRONTEND (Renderer)         │  │
│  │  TypeScript + TailwindCSS + Zustand   │  │
│  └───────────────────────────────────────┘  │
│                    ↕ IPC                     │
│  ┌───────────────────────────────────────┐  │
│  │     MAIN PROCESS (Node.js)            │  │
│  │  Python lifecycle, file dialogs       │  │
│  └───────────────────────────────────────┘  │
└─────────────────────────────────────────────┘
                     ↕ HTTP + WebSocket
┌─────────────────────────────────────────────┐
│         PYTHON BACKEND (FastAPI)            │
│  ┌───────────────────────────────────────┐  │
│  │  REST API + WebSocket Progress        │  │
│  │  /api/train, /api/tag, /api/vibe      │  │
│  └───────────────────────────────────────┘  │
│  ┌───────────────────────────────────────┐  │
│  │  EXISTING CORE (unchanged)            │  │
│  │  audio_analyzer, tag_predictor,       │  │
│  │  vibe_generator, hook_transcriber     │  │
│  └───────────────────────────────────────┘  │
└─────────────────────────────────────────────┘
```

---

## Migration Phases

### Phase 0: Python API Layer (2-3 weeks)
**Goal:** Wrap existing Python modules with FastAPI without changing core logic.

**Tasks:**
1. Create `backend/api_server.py` with FastAPI app
2. Define Pydantic models for API contracts
3. Define API versioning + error schema (e.g., `/api/v1/*`, standard error payloads)
4. Implement endpoints:
   - `POST /api/train/start` - Start training job
   - `GET /api/train/status/{task_id}` - Training progress
   - `POST /api/tag/file` - Tag single file
   - `POST /api/tag/batch` - Tag multiple files
   - `POST /api/model/load` - Load model
   - `GET /api/model/info` - Model metadata
   - `WebSocket /ws/progress` - Real-time updates
5. Create async task manager for long-running jobs
6. Establish API contract docs (OpenAPI + examples)
7. Test API independently (curl/Postman)

**Files to create:**
- `backend/api_server.py`
- `backend/task_manager.py`
- `backend/models/` (Pydantic schemas)

---

### Phase 1: Electron + React Scaffold (2 weeks)
**Goal:** Basic Electron app with React, Python process management.

**Tasks:**
1. Initialize project: `npm create electron-vite@latest`
2. Set up React + TypeScript + TailwindCSS
3. Create Python process manager in main process
4. Implement IPC bridge for API calls
5. Basic layout with tab navigation
6. File/directory picker dialogs
7. Define env/config loading for Python sidecar path and model storage

**Directory structure:**
```
cratebot-desktop/
├── electron/main/          # Electron main process
├── electron/preload/       # Preload scripts
├── src/                    # React frontend
│   ├── components/
│   ├── hooks/
│   ├── stores/
│   └── api/
├── backend/                # Python FastAPI
└── resources/              # Icons, bundled models
```

---

### Phase 2: Training Tab (2-3 weeks)
**Goal:** Full training functionality with real-time progress.

**Components:**
- `TrainingDirectoryPicker` - Directory selection
- `TagSelectionDialog` - Tag picker modal
- `TrainingProgress` - Progress bar + stats
- `TrainingConsole` - Log output
- `ModelSelector` - Model naming

**Features:**
- Pause/resume (checkpoint support)
- Cancel with cleanup
- Training metrics display
- Early performance baseline capture (timing + memory vs tkinter)

---

### Phase 3: Tagging Tab (2-3 weeks)
**Goal:** Batch tagging with vibe generation.

**Components:**
- `FileQueue` - Tree view with status icons
- `TaggingOptions` - Tag write checkboxes
- `TaggingProgress` - Per-file progress
- `VibeToggle` - Claude API toggle
- `HookToggle` - Whisper toggle
- `APIKeySettings` - Key management

**Features:**
- Drag-and-drop support
- Real-time status updates
- Error recovery
- API error handling + retry policies (network + model load)

---

### Phase 4: Refinement Tab (3-4 weeks)
**Goal:** Tag editor with audio playback.

**Components:**
- `PlaylistView` - Scrollable track list
- `AudioPlayer` - Waveform + transport (wavesurfer.js)
- `TagEditor` - Genre/Album dropdowns
- `CommentTagGrid` - Checkbox grid
- `VibeEditor` - Text areas
- `TagSummary` - Read-only display

**Technical:**
- Web Audio API for playback
- wavesurfer.js for waveform
- Electron protocol handler for file:// access
- Prototype spike for waveform performance on large files

---

### Phase 5: Polish & Packaging (2 weeks)
**Goal:** Production-ready app.

**Tasks:**
1. PyInstaller build for macOS
2. Dependency pinning + reproducible builds (pip/poetry + npm lockfiles)
3. Code signing (Apple Developer ID)
4. DMG creation
5. Auto-updater (electron-updater)
6. Dark mode support
7. Keyboard shortcuts
8. Performance optimization
9. Migration of user data/config/models from tkinter app

---

## Key Technical Solutions

### Python Integration
- Bundle Python as PyInstaller executable (sidecar)
- Electron spawns at startup, manages lifecycle
- Communicate via HTTP localhost + WebSocket

### Audio Playback
- Register `cratebot://` Electron protocol
- wavesurfer.js for waveform visualization
- Web Audio API for playback control

### Real-time Progress
- WebSocket connection for streaming updates
- Throttle to 10 updates/sec to prevent UI jank
- React Query for caching/refetching

### Model Storage
- Bundled models in `resources/models/`
- User models in `~/.cratebot/models/`
- Whisper downloaded on-demand (~1.5GB)

---

## Testing & Validation

**Testing strategy**
- Unit tests for core FastAPI handlers and task manager
- Integration tests for API + Python sidecar lifecycle
- E2E smoke tests for training/tagging flows (headless Electron)

**Performance validation**
- Baseline metrics vs tkinter (startup time, training throughput, memory)
- Track regressions per phase

---

## Migration & Compatibility

- Preserve existing `~/.cratebot` data when present
- Add a one-time migration step for config/model paths (with backup)
- Document rollback/repair steps if migration fails

---

## Dependency & Build Reliability

- Pin Python and Node dependencies (lockfiles + hashes where possible)
- Validate PyInstaller build for both Intel + Apple Silicon
- Cache large model downloads and validate checksums

---

## Phase Checklist

- [x] Phase 0 complete - Python API Layer with FastAPI
- [x] Phase 1 complete - Electron + React scaffold
- [x] Phase 2 complete - Training Tab
- [x] Phase 3 complete - Tagging Tab
- [x] Phase 4 complete - Refinement Tab with wavesurfer.js
- [x] Phase 5 complete - Polish & Packaging

---

## Appendix: API Contract (Draft)

**Base path**
- `/api/v1`

**Auth (local-only)**
- App launches FastAPI bound to `127.0.0.1` with a random port.
- Electron main process generates a short-lived token at launch.
- Renderer sends `Authorization: Bearer <token>` on all API calls.
- WebSocket connects with `?token=<token>` query param.
- Token expires on app exit or restart.

**Rate limits**
- Default: 30 requests/minute per process for standard endpoints.
- Burst: 5 requests/second for `/api/v1/train/status/*`.
- On limit: respond with `429` and standard error payload.

**WebSocket retry semantics**
- Client reconnects with exponential backoff (1s, 2s, 4s, 8s, 16s max).
- Client sends `last_event_id` on reconnect to resume progress stream.
- Server replays last 50 events per task when `last_event_id` provided.

**Standard error payload**
```json
{
  "error": {
    "code": "string",
    "message": "string",
    "details": {
      "field": "optional"
    }
  }
}
```

**POST /api/v1/train/start**
Request:
```json
{
  "training_dir": "/path/to/training",
  "model_name": "cratebot_v1",
  "selected_tags": ["house", "techno"],
  "options": {
    "resume_from_checkpoint": false
  }
}
```
Response:
```json
{
  "task_id": "uuid",
  "status": "queued"
}
```

**GET /api/v1/train/status/{task_id}**
Response:
```json
{
  "task_id": "uuid",
  "status": "running",
  "progress": 0.42,
  "eta_seconds": 780,
  "metrics": {
    "loss": 0.13
  }
}
```

**POST /api/v1/tag/file**
Request:
```json
{
  "file_path": "/path/to/audio.wav",
  "write_id3": true,
  "write_comment": true,
  "generate_vibe": false,
  "transcribe_hook": false
}
```
Response:
```json
{
  "file_path": "/path/to/audio.wav",
  "tags": ["house", "deep"],
  "confidence": {
    "house": 0.92,
    "deep": 0.78
  }
}
```

**POST /api/v1/tag/batch**
Request:
```json
{
  "file_paths": ["/path/a.wav", "/path/b.wav"],
  "options": {
    "write_id3": true,
    "write_comment": false
  }
}
```
Response:
```json
{
  "task_id": "uuid",
  "status": "queued"
}
```

**POST /api/v1/model/load**
Request:
```json
{
  "model_path": "/path/to/model",
  "device": "auto"
}
```
Response:
```json
{
  "model_name": "cratebot_v1",
  "device": "mps"
}
```

**GET /api/v1/model/info**
Response:
```json
{
  "model_name": "cratebot_v1",
  "version": "1.0.0",
  "tags": ["house", "techno"]
}
```

**WebSocket /ws/progress**
Message:
```json
{
  "task_id": "uuid",
  "stage": "training",
  "progress": 0.35,
  "message": "epoch 2/5"
}
```

---

## Timeline Estimate

| Phase | Duration | Risk |
|-------|----------|------|
| Phase 0: API Layer | 2-3 weeks | Low |
| Phase 1: Electron Shell | 2 weeks | Low |
| Phase 2: Training | 2-3 weeks | Medium |
| Phase 3: Tagging | 2-3 weeks | Medium |
| Phase 4: Refinement | 3-4 weeks | High |
| Phase 5: Polish | 2 weeks | Medium |
| **Total** | **13-17 weeks** | |

---

## Critical Files Reference

**Current implementation to port:**
- `/Users/noahraford/CrateBot/cratebot_gui_v2.py` - Main GUI (7000 lines)
- `/Users/noahraford/CrateBot/src/core/auto_tagger.py` - Core orchestration
- `/Users/noahraford/CrateBot/src/core/audio_analyzer.py` - Feature extraction
- `/Users/noahraford/CrateBot/src/core/vibe_generator.py` - Claude integration
- `/Users/noahraford/CrateBot/src/core/tag_predictor.py` - ML models
- `/Users/noahraford/CrateBot/src/core/hook_transcriber.py` - Whisper integration

**Core modules to keep unchanged:**
- All `src/core/*.py` files (business logic)
- All `src/models/*.py` files (ML)

---

## Success Criteria

1. **Feature parity** - All current features work
2. **Performance** - No slower than tkinter version
3. **Bundle size** - < 300MB for macOS
4. **Memory** - < 500MB during training
5. **Startup** - < 5 seconds to usable UI
6. **Cross-platform ready** - Architecture supports Windows/Linux
