# CrateBot3 Architecture Documentation

> Comprehensive technical documentation for the CrateBot3 audio tagging application.

---

## Table of Contents

1. [Overview](#1-overview)
2. [System Architecture](#2-system-architecture)
3. [Frontend (Electron + React)](#3-frontend-electron--react)
4. [Backend (FastAPI)](#4-backend-fastapi)
5. [Python Core Engine](#5-python-core-engine)
6. [Data Flow & Workflows](#6-data-flow--workflows)
7. [Storage & Persistence](#7-storage--persistence)
8. [API Reference](#8-api-reference)
9. [Build & Deployment](#9-build--deployment)

---

## 1. Overview

**CrateBot3** is a desktop application that automatically tags DJ music files using machine learning. It uses a 4-field taxonomy (genre, timing, mood, descriptive) and can generate AI-powered "vibes" (creative descriptions) using Claude.

### Key Features
- **ML-based tag prediction** - 4-classifier architecture for genre, timing, mood, and descriptive tags
- **Lexicon customization** - Map canonical tags to your preferred vocabulary without retraining
- **Override system** - Save per-track corrections via audio hash
- **Batch processing** - Tag hundreds of files automatically
- **AI vibe generation** - Creative descriptions via Claude API
- **Hook detection** - Identify memorable vocal phrases using Whisper
- **Manual refinement** - Review and correct predictions with audio playback

### Tech Stack
| Layer | Technology |
|-------|------------|
| Desktop | Electron 28 |
| Frontend | React 18 + TypeScript + Tailwind CSS |
| State | Zustand |
| Backend | Python FastAPI + Uvicorn |
| ML | scikit-learn, LightGBM |
| Audio | librosa, Essentia, PANNs |
| LLM | Anthropic Claude API |
| Speech | faster-whisper |

---

## 2. System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Electron Desktop App                         │
│         (React + TypeScript + Zustand State Management)         │
│  Main Process: electron/main.ts                                 │
│  Renderer: React UI (Vite dev server or bundled)                │
└─────────────────┬───────────────────────────────────────────────┘
                  │ HTTP REST + WebSocket (localhost:8742)
                  │
┌─────────────────▼───────────────────────────────────────────────┐
│              Python FastAPI Backend                             │
│    backend/api_server.py (127.0.0.1:8742)                       │
│    - REST endpoints for all operations                          │
│    - WebSocket for real-time progress                           │
│    - Task Manager for async operations                          │
└─────────────────┬───────────────────────────────────────────────┘
                  │
┌─────────────────▼───────────────────────────────────────────────┐
│              Python Core Analysis Engine                        │
│    python/src/core/                                             │
│    - Audio feature extraction (97 features)                     │
│    - ML model training & inference                              │
│    - ID3 tag management                                         │
│    - Vibe generation (Claude API)                               │
│    - Hook detection (Whisper)                                   │
└─────────────────────────────────────────────────────────────────┘
```

### Communication Flow
1. User interacts with React UI
2. Frontend calls API via `api/client.ts`
3. FastAPI backend processes request
4. Backend delegates to Python core modules
5. Results returned via REST or streamed via WebSocket
6. Electron preload provides native file dialogs

---

## 3. Frontend (Electron + React)

### Directory Structure
```
desktop/
├── electron/
│   ├── main.ts          # Electron main process
│   └── preload.ts       # IPC bridge to renderer
├── src/
│   ├── main.tsx         # React entry point
│   ├── App.tsx          # Root component with tab routing
│   ├── api/
│   │   └── client.ts    # API client (fetch + WebSocket)
│   ├── components/      # React components
│   ├── hooks/           # Custom React hooks
│   ├── stores/          # Zustand state stores
│   └── styles/          # Tailwind CSS
└── index.html           # HTML entry with splash screen
```

### Main Process (electron/main.ts)

```typescript
// Key responsibilities:
- Creates BrowserWindow with React app
- Spawns Python backend as child process
- Registers cratebot:// protocol for secure audio playback
- Implements IPC handlers for file dialogs
- Manages auto-updates via electron-updater
```

**IPC Handlers:**
| Channel | Purpose |
|---------|---------|
| `dialog:openDirectory` | Native folder picker |
| `dialog:openFiles` | Native file picker with filters |
| `dialog:saveFile` | Native save dialog |
| `shell:openExternal` | Open URLs in browser |
| `python:isRunning` | Check backend status |
| `python:restart` | Restart Python server |

### State Management (stores/appStore.ts)

```typescript
interface AppState {
  // Server connection
  serverStatus: 'connecting' | 'connected' | 'disconnected' | 'error'

  // Model state
  model: {
    loaded: boolean
    path?: string
    selectedTags?: { genre: string[], timing: string[], mood: string[], descriptive: string[] }
  }

  // Feature availability
  settings: {
    apiKeySet: boolean
    vibeAvailable: boolean
    hookAvailable: boolean
    pannsAvailable: boolean
  }

  // Current background task
  currentTask?: {
    id: string
    type: 'training' | 'tagging' | 'vibe'
    progress: number
    status: string
  }

  // Toast notifications
  toast?: { message: string, kind: 'success' | 'error' | 'info' }
}

// Actions
checkServerStatus()    // Poll /api/v1/health
loadModelInfo()        // Get model metadata
loadModel(path)        // Load model from disk
loadSettings()         // Get feature availability
setToast(msg, kind)    // Show notification
```

### React Components

#### Tab Components
| Component | File | Purpose |
|-----------|------|---------|
| `TrainTab` | TrainTab.tsx | Model training workflow |
| `TagTab` | TagTab.tsx | Batch file tagging |
| `RefineTab` | RefineTab.tsx | Manual tag refinement |
| `SettingsTab` | SettingsTab.tsx | Configuration |

#### Supporting Components
| Component | File | Purpose |
|-----------|------|---------|
| `Sidebar` | Sidebar.tsx | Tab navigation |
| `StatusBar` | StatusBar.tsx | Connection status, theme toggle |
| `FileQueue` | FileQueue.tsx | File list with status indicators |
| `DropZone` | DropZone.tsx | Drag-drop file area |
| `TagSelectionDialog` | TagSelectionDialog.tsx | Multi-select tag picker |
| `TrainingProgress` | TrainingProgress.tsx | Progress visualization |
| `AudioPlayer` | refine/AudioPlayer.tsx | Audio playback with waveform |

### Custom Hooks

#### useTraining (hooks/useTraining.ts)
```typescript
// Manages training workflow state
const {
  status,              // 'idle' | 'scanning' | 'training' | 'complete' | 'error'
  taskId,              // Current task ID
  progress,            // 0-100
  phase,               // 'collecting' | 'training' | 'saving'
  currentFile,         // File being processed
  filesProcessed,
  totalFiles,
  metrics,             // { accuracy, f1, ... }
  logs,                // Log messages
  discoveredTags,      // From scanDirectory()

  // Actions
  scanDirectory,       // Discover tags in directory
  startTraining,       // Begin training task
  cancelTraining,      // Cancel running task
  reset,
} = useTraining()
```

#### useTagging (hooks/useTagging.ts)
```typescript
// Manages batch tagging state
const {
  files,               // QueuedFile[]
  isProcessing,
  isPaused,
  currentIndex,
  startTime,           // For ETA calculation
  error,

  // Actions
  addFiles,            // Add files to queue
  removeFile,          // Remove single file
  clearFiles,          // Clear queue
  startTagging,        // Begin batch tagging
  stopTagging,         // Cancel
  pauseTagging,        // Pause processing
  resumeTagging,       // Resume processing
  retryFile,           // Retry failed file
  loadFromDirectory,   // Add all MP3s from directory
} = useTagging()
```

#### useRefinement (hooks/useRefinement.ts)
```typescript
// Manages manual refinement session with 4-field taxonomy
const {
  items,               // Files to review (with hasOverride flag)
  currentIndex,
  currentItem,         // Current file with tags (genre, timing, mood, descriptive)
  availableTags,       // { genre[], timing[], mood[], descriptive[] }
  stats,               // { approved, corrected, skipped, pending }

  // Actions
  loadDirectory,       // Load files for refinement
  loadFiles,           // Load specific file paths
  selectItem,          // Jump to specific file
  nextItem, prevItem,
  updateTags,          // Edit tags (4-field taxonomy)
  approveAndNext,      // Save and advance
  skipAndNext,
  saveAsCorrection,    // Save override for this track
  clearSession,
} = useRefinement()
```

#### useElectron (hooks/useElectron.ts)
```typescript
// Wrapper for Electron IPC
const { dialog, shell, python, app } = useElectron()

dialog.openDirectory()           // Native folder picker
dialog.openFiles({ filters })    // Native file picker
dialog.saveFile({ filters })     // Native save dialog
shell.openExternal(url)          // Open in browser
python.isRunning()               // Check backend status
python.restart()                 // Restart Python server
```

### API Client (api/client.ts)

```typescript
// Typed API wrapper with automatic fallback
const api = {
  // Health
  health: () => GET('/api/v1/health'),

  // Settings
  getSettings: () => GET('/api/v1/settings'),
  setApiKey: (key) => POST('/api/v1/settings/api-key', { api_key: key }),

  // Model
  getModelInfo: () => GET('/api/v1/model/info'),
  loadModel: (path) => POST('/api/v1/model/load', { model_path: path }),
  listModels: () => GET('/api/v1/model/list'),

  // Training
  startTraining: (params) => POST('/api/v1/train/start', params),
  getTrainingStatus: (id) => GET(`/api/v1/train/status/${id}`),
  cancelTraining: (id) => POST(`/api/v1/train/cancel/${id}`),

  // Tagging
  tagFile: (params) => POST('/api/v1/tag/file', params),
  tagBatch: (params) => POST('/api/v1/tag/batch', params),
  cancelTagging: (id) => POST(`/api/v1/tag/cancel/${id}`),

  // Vibe
  generateVibe: (params) => POST('/api/v1/vibe/file', params),
  generateVibeBatch: (params) => POST('/api/v1/vibe/batch', params),

  // Tags
  readTags: (path) => POST('/api/v1/tags/read', { file_path: path }),
  writeTags: (path, tags) => POST('/api/v1/tags/write', { file_path: path, tags }),

  // Lexicon (vocabulary customization)
  getLexicon: () => GET('/api/v1/lexicon'),
  updateLexicon: (update) => PUT('/api/v1/lexicon', update),

  // Overrides (per-track corrections)
  getOverride: (path) => GET(`/api/v1/override/${encodeURIComponent(path)}`),
  saveOverride: (path, tags) => POST('/api/v1/override', { file_path: path, tags }),

  // Tasks
  getTaskStatus: (id) => GET(`/api/v1/tasks/${id}`),
  pauseTask: (id) => POST(`/api/v1/tasks/${id}/pause`),
  resumeTask: (id) => POST(`/api/v1/tasks/${id}/resume`),

  // Files
  scanTags: (dir) => POST('/api/v1/scan/tags', { directory: dir }),
  findMp3s: (dir) => GET(`/api/v1/files/mp3s?directory=${dir}`),
}

// WebSocket for progress
createProgressSocket(taskId, onMessage)
```

---

## 4. Backend (FastAPI)

### Directory Structure
```
backend/
├── api_server.py       # FastAPI application
├── task_manager.py     # Async task orchestration
├── run_server.py       # Entry point
├── migration.py        # Migration from v2
└── models/
    └── schemas.py      # Pydantic request/response models
```

### API Server (api_server.py)

FastAPI application running on port 8742.

#### Endpoint Groups

**Health & Settings**
```python
GET  /                           # Root health check
GET  /api/v1/health              # Detailed health status
GET  /api/v1/settings            # Feature availability
POST /api/v1/settings/api-key    # Store Anthropic API key
```

**Model Management**
```python
GET  /api/v1/model/info          # Current model metadata
POST /api/v1/model/load          # Load model from path
GET  /api/v1/model/list          # List available models
```

**Training**
```python
POST /api/v1/train/start         # Start training (async)
GET  /api/v1/train/status/{id}   # Get training progress
POST /api/v1/train/cancel/{id}   # Cancel training
GET  /api/v1/train/checkpoints   # List checkpoints
```

**Tagging**
```python
POST /api/v1/tag/file            # Tag single file (sync)
POST /api/v1/tag/batch           # Batch tag (async)
POST /api/v1/tag/cancel/{id}     # Cancel batch
```

**Vibe Generation**
```python
POST /api/v1/vibe/file           # Generate vibe (sync)
POST /api/v1/vibe/batch          # Batch vibes (async)
```

**Tag I/O**
```python
POST /api/v1/tags/read           # Read ID3 tags
POST /api/v1/tags/write          # Write ID3 tags
POST /api/v1/scan/tags           # Discover tags in directory
```

**Lexicon (Vocabulary Customization)**
```python
GET  /api/v1/lexicon             # Get lexicon configuration
PUT  /api/v1/lexicon             # Update category ID3 frame or mappings
```

**Overrides (Per-Track Corrections)**
```python
GET  /api/v1/override/{path}     # Get override for file (if exists)
POST /api/v1/override            # Save per-track correction
```

**Task Management**
```python
GET  /api/v1/tasks               # List all tasks
GET  /api/v1/tasks/{id}          # Get task status
POST /api/v1/tasks/{id}/pause    # Pause task
POST /api/v1/tasks/{id}/resume   # Resume task
```

**WebSocket**
```python
WS   /api/v1/ws/progress/{id}    # Real-time progress streaming
```

**File Operations**
```python
GET  /api/v1/files/browse        # Browse directory
GET  /api/v1/files/mp3s          # Find MP3s in directory
```

### Task Manager (task_manager.py)

Orchestrates async operations with progress tracking.

```python
class TaskManager:
    """Manages background tasks with progress updates."""

    def create_task(task_type: str) -> str:
        """Create new task, returns task_id."""

    def get_task(task_id: str) -> Task:
        """Get task by ID."""

    def run_task(task_id: str, wrapper_fn) -> Any:
        """Execute task in thread pool."""

    def update_progress(task_id, progress, phase, message):
        """Update task progress (triggers WebSocket broadcast)."""

    def cancel_task(task_id: str) -> bool:
        """Request task cancellation."""

    def pause_task(task_id: str) -> bool:
        """Pause running task."""

    def resume_task(task_id: str) -> bool:
        """Resume paused task."""

    def subscribe_async(task_id, queue):
        """Subscribe to progress updates via asyncio.Queue."""

class Task:
    task_id: str
    task_type: str  # 'training' | 'tagging' | 'vibe'
    status: TaskStatus  # PENDING | RUNNING | COMPLETED | FAILED | CANCELLED | PAUSED
    progress: TaskProgress
    result: Any
    error: str
    log_messages: List[str]
    created_at, started_at, completed_at: datetime
```

### Schemas (models/schemas.py)

Pydantic models for API contracts.

```python
# Task Status
class TaskStatus(str, Enum):
    PENDING = "pending"
    RUNNING = "running"
    COMPLETED = "completed"
    FAILED = "failed"
    CANCELLED = "cancelled"
    PAUSED = "paused"

# Training
class TrainingRequest(BaseModel):
    training_dir: str
    output_model_path: str
    selected_tags: SelectedTags
    test_size: float = 0.2

class TrainingStatus(BaseModel):
    task_id: str
    status: TaskStatus
    progress: float
    phase: str
    files_processed: int
    total_files: int
    samples_collected: int

# Tagging
class TaggingBatchRequest(BaseModel):
    file_paths: List[str]
    overwrite: bool = False
    dry_run: bool = False
    tags_to_write: TagsToWrite
    generate_vibes: bool = False
    generate_hooks: bool = False

class TaggingResult(BaseModel):
    file_path: str
    status: str  # 'tagged' | 'failed' | 'skipped'
    predicted_tags: PredictedTags
    error: Optional[str]

# Model
class ModelInfo(BaseModel):
    loaded: bool
    path: Optional[str]
    selected_tags: Optional[SelectedTags]
    feature_count: Optional[int]

# Settings
class SettingsResponse(BaseModel):
    anthropic_api_key_set: bool
    vibe_available: bool
    hook_available: bool
    panns_available: bool
```

---

## 5. Python Core Engine

### Directory Structure
```
python/src/
├── core/
│   ├── auto_tagger.py       # Main orchestrator
│   ├── tag_manager.py       # ID3 tag I/O (lexicon-aware)
│   ├── tag_predictor.py     # ML model (4 classifiers)
│   ├── lexicon.py           # Vocabulary customization
│   ├── overrides.py         # Per-track corrections (SQLite)
│   ├── audio_hash.py        # SHA256 audio fingerprinting
│   ├── fast_analyzer.py     # Audio feature extraction
│   ├── feature_cache.py     # SQLite feature cache
│   ├── essentia_analyzer.py # High-level audio features
│   ├── panns_analyzer.py    # Sound recognition
│   ├── clap_analyzer.py     # CLAP embeddings
│   ├── jamendo_analyzer.py  # Jamendo auxiliary classifiers
│   ├── vibe_generator.py    # Claude API integration
│   ├── hook_transcriber.py  # Whisper hook detection
│   ├── tag_scanner.py       # Directory tag discovery
│   ├── config.py            # Model path resolution
│   └── constants.py         # Taxonomy constants
└── models/
    └── tag_predictor.py     # ML model class
```

### AutoTagger (core/auto_tagger.py)

Main orchestrator that coordinates all operations.

```python
class AutoTagger:
    """Main class for audio tagging operations."""

    def __init__(self, model_path: str = None, use_cache: bool = True):
        self.analyzer = CachedAnalyzer()      # Feature extraction
        self.tag_manager = TagManager()        # ID3 read/write
        self.predictor = TagPredictor()        # ML model
        if model_path:
            self.predictor.load_model(model_path)

    def tag_file(self, file_path: str, **options) -> dict:
        """Predict and write tags for single file."""
        features = self.analyzer.extract_features(file_path)
        predictions = self.predictor.predict(features)
        if not options.get('dry_run'):
            self.tag_manager.write_tags(file_path, predictions)
        return predictions

    def tag_directory(self, directory: str, progress_callback=None) -> List[dict]:
        """Batch process entire directory."""

    def generate_vibe(self, file_path: str, **options) -> dict:
        """Generate AI vibe description."""

    def train_from_directory(self, directory: str, selected_tags: dict,
                            progress_callback=None) -> dict:
        """Train model on tagged files."""
```

### TagManager (core/tag_manager.py)

Handles ID3 tag reading and writing using Mutagen. Supports lexicon-based vocabulary mapping and configurable ID3 frames.

```python
class TagManager:
    """Read and write ID3 tags to MP3 files."""

    def read_tags(self, file_path: str, lexicon: Lexicon = None) -> dict:
        """Read all relevant tags from file."""
        # Returns: genre, timing, mood, descriptive, title, artist, etc.
        # If lexicon provided, reads from configured ID3 frames

    def write_tags(self, file_path: str, tags: dict,
                   overwrite: bool = False, lexicon: Lexicon = None):
        """Write tags to file using lexicon-configured frames."""
        # Default ID3 mapping:
        #   genre → TCON, timing → TALB, mood → TIT1, descriptive → COMM
        # Lexicon can override to custom TXXX frames
```

### Lexicon (core/lexicon.py)

User vocabulary customization without model retraining.

```python
class Lexicon:
    """Maps canonical tags to user-preferred vocabulary."""

    # File: ~/.cratebot/lexicon.json
    # Structure per category: { "id3_frame": "TCON", "mappings": {"House": "Deep House"} }

    def get_mapping(self, category: str, canonical_tag: str) -> str:
        """Get user vocabulary for a canonical tag."""

    def set_mapping(self, category: str, canonical_tag: str, user_tag: str):
        """Set a vocabulary mapping."""

    def get_id3_frame(self, category: str) -> str:
        """Get the ID3 frame for a category (e.g., 'TCON', 'TXXX:CUSTOM')."""

    def set_id3_frame(self, category: str, frame: str):
        """Change which ID3 frame a category writes to."""

    def apply_to_tags(self, tags: dict) -> dict:
        """Apply all mappings to a tags dict."""
```

### OverrideStore (core/overrides.py)

Per-track corrections that persist across model changes.

```python
class OverrideStore:
    """SQLite-backed per-track tag corrections."""

    # File: ~/.cratebot/overrides.db
    # Key: SHA256 hash of audio content (first 30 seconds)
    # Value: JSON tags dict

    def get(self, audio_hash: str) -> Optional[dict]:
        """Get override tags for an audio hash."""

    def set(self, audio_hash: str, tags: dict):
        """Save override tags for an audio hash."""

    def delete(self, audio_hash: str):
        """Remove override for an audio hash."""
```

### AudioHash (core/audio_hash.py)

Content-based audio fingerprinting for override lookup.

```python
def compute_audio_hash(file_path: str, duration: float = 30.0) -> str:
    """Compute SHA256 hash of audio content (first N seconds).

    Ignores metadata changes - same audio = same hash.
    """
```

### TagPredictor (models/tag_predictor.py)

ML model with 4-classifier architecture for the new taxonomy.

```python
class TagPredictor:
    """Train and predict audio tags using ML."""

    def __init__(self):
        self.genre_classifier = None       # RandomForest or LightGBM
        self.timing_classifier = None      # Start, Build, Peak, Sustain, Release
        self.mood_classifier = None        # Happy, Dark, Emotional, Aggressive, Dreamy, Groovy
        self.descriptive_classifier = None # Multi-label
        self.scaler = StandardScaler()
        self.selected_tags = {}

    def train(self, training_data: List[dict], selected_tags: dict,
              test_size: float = 0.2) -> dict:
        """Train classifiers on labeled data."""
        # 1. Normalize features (184 dimensions)
        # 2. Encode labels
        # 3. Train 4 classifiers
        # 4. Evaluate metrics
        # Returns: { accuracy, f1, per_class_metrics }

    def predict(self, features: dict) -> dict:
        """Predict tags from audio features."""
        # Returns: { genre, timing, mood, descriptive, confidences }

    def save_model(self, path: str):
        """Serialize model to pickle file (version 2.0)."""

    def load_model(self, path: str):
        """Load model from pickle file."""
```

### FastAudioAnalyzer (core/fast_analyzer.py)

Extracts 184 audio features from MP3 files using multiple analysis backends.

```python
class FastAudioAnalyzer:
    """Extract audio features using librosa, Essentia, PANNs, CLAP, and Jamendo."""

    FEATURE_VECTOR_SIZE = 184  # Total dimensions

    def extract_features(self, file_path: str) -> dict:
        """Extract all features from audio file."""
        # Returns dict with:
        # - feature_vector: numpy array (184 dimensions)
        # - tempo, energy, danceability, etc.
        # - essentia_features: mood, voice_instrumental
        # - panns_detections: genre, instruments, drums
        # - clap_embeddings: semantic audio representations
        # - jamendo_features: auxiliary classifiers

# Feature breakdown (184 total):
# - 57 librosa features:
#     - Spectral: centroid, bandwidth, rolloff, contrast (7)
#     - Temporal: ZCR, RMS (2)
#     - MFCC: 13 coefficients (26 with delta)
#     - Chroma: 12 pitch classes (12)
#     - Rhythm: tempo, beats (10)
# - 8 Essentia features:
#     - mood_happy, mood_sad, mood_aggressive, mood_relaxed
#     - danceability, voice_instrumental, arousal, valence
# - 32 PANNs features:
#     - Genre embeddings (PCA reduced from 2048)
# - 32 CLAP features:
#     - Semantic audio embeddings (HTSAT-tiny, 768→32 PCA)
# - 55 Jamendo features:
#     - Mood, genre, instrument auxiliary classifiers
```

### FeatureCache (core/feature_cache.py)

SQLite-based caching for extracted features.

```python
class FeatureCache:
    """Cache audio features to avoid re-extraction."""

    # Location: ~/.cratebot/feature_cache.db
    # Key: (file_path, file_mtime, cache_version)
    # Value: feature_vector + metadata

    def get(self, file_path: str) -> Optional[dict]:
        """Get cached features if valid."""

    def put(self, file_path: str, features: dict):
        """Store features in cache."""

    def is_valid(self, file_path: str) -> bool:
        """Check if cache entry is still valid."""
```

### EssentiaAnalyzer (core/essentia_analyzer.py)

High-level audio features using pre-trained models.

```python
class EssentiaAnalyzer:
    """Extract mood and danceability using Essentia models."""

    # Models: MusiCNN trained on various datasets
    # Features extracted:
    # - mood_happy, mood_sad, mood_aggressive, mood_relaxed (0-1)
    # - danceability (0-1)
    # - voice_instrumental (0=instrumental, 1=vocal)
    # - arousal, valence (emotional dimensions)
```

### PANNsAnalyzer (core/panns_analyzer.py)

Sound recognition using AudioSet embeddings.

```python
class PANNsAnalyzer:
    """Extract genre and instrument features using PANNs CNN14."""

    # Pre-trained on AudioSet (2M+ audio clips)
    # Detects:
    # - Genre: House, Techno, Disco, Funk, Soul, Jazz, Hip Hop
    # - Instruments: Piano, Guitar, Synth, Strings, Brass
    # - Drums: Kit, Hi-hat, Snare, Bass Drum
    # - Vocals: Singing, Male/Female voice
    # - Mood: Happy, Sad
```

### VibeGenerator (core/vibe_generator.py)

AI-powered vibe descriptions using Claude.

```python
class VibeGenerator:
    """Generate creative vibe descriptions using Claude API."""

    def generate(self, file_path: str, audio_analysis: dict,
                 existing_tags: dict) -> dict:
        """Generate vibe and description."""
        # Builds context from:
        # - Audio features (tempo, energy, mood)
        # - Existing tags (title, artist, genre)
        # - PANNs detections (instruments, genre)
        # - Hook (if available)

        # Prompt format:
        # "[VIBE GENRE], [MEMORABLE HOOK], [WHEN/WHERE]"
        # Example: "HYPNOTIC MINIMAL, BASSLINE BURROWING INTO YOUR SKULL, WAREHOUSE 4AM"

        # Returns:
        # - vibe: short creative phrase (100 chars)
        # - description: expanded natural language description

def is_vibe_available() -> bool:
    """Check if Claude API key is configured."""
```

### HookTranscriber (core/hook_transcriber.py)

Vocal hook detection using Whisper.

```python
class HookTranscriber:
    """Detect memorable vocal hooks using speech-to-text."""

    def transcribe_and_find_hook(self, file_path: str) -> dict:
        """Find the most repeated memorable phrase."""
        # 1. Transcribe audio using faster-whisper
        # 2. Extract n-grams (3-7 words)
        # 3. Count phrase occurrences
        # 4. Filter filler words
        # 5. Return most repeated phrase

        # Returns:
        # - hook: memorable phrase
        # - occurrences: repeat count

def is_hook_transcription_available() -> bool:
    """Check if Whisper model is available."""
```

### TagScanner (core/tag_scanner.py)

Discovers existing tags in a directory.

```python
class TagScanner:
    """Scan directory for existing tag values."""

    def scan_directory(self, directory: str, recursive: bool = True) -> dict:
        """Collect all unique tag values."""
        # Returns:
        # {
        #   'genre': {'values': {'House': 50, 'Techno': 30}, 'total_files': 100},
        #   'album': {'values': {'Dark': 20, 'Light': 15}, 'total_files': 100},
        #   'comments': {'values': {'Vocal': 40, 'Instrumental': 60}, 'total_files': 100},
        # }
```

### Constants (core/constants.py)

```python
# Confidence thresholds
GENRE_CONFIDENCE_THRESHOLD = 0.6
ALBUM_CONFIDENCE_THRESHOLD = 0.6
COMMENTS_CONFIDENCE_THRESHOLD = 0.4

# Training
MIN_TRAINING_SAMPLES = 20
MIN_SAMPLES_PER_CLASS = 10

# Audio analysis
ANALYSIS_DURATION_FAST = 45.0  # seconds
ANALYSIS_START_OFFSET = 0.33   # 33% into track

# Feature cache
CACHE_VERSION = 6

# Claude API
CLAUDE_MODEL = "claude-sonnet-4-20250514"
VIBE_TEMPERATURE = 0.9
```

---

## 6. Data Flow & Workflows

### Training Workflow

```
1. User selects directory
   └─> TrainTab.tsx: handleSelectDirectory()
       └─> useTraining.scanDirectory()
           └─> api.scanTags(directory)
               └─> POST /api/v1/scan/tags
                   └─> TagScanner.scan_directory()

2. User selects tags
   └─> TagSelectionDialog shows discovered tags
   └─> User checks desired genre/album/comments

3. User starts training
   └─> useTraining.startTraining(config)
       └─> api.startTraining(params)
           └─> POST /api/v1/train/start
               └─> TaskManager.create_task('training')
               └─> Background: training_wrapper()

4. Training executes (in ThreadPoolExecutor)
   └─> For each MP3 with selected tags:
       ├─> FastAudioAnalyzer.extract_features()
       ├─> Collect (features, tags) pairs
       └─> Progress callback → WebSocket
   └─> TagPredictor.train(data, selected_tags)
   └─> TagPredictor.save_model(output_path)

5. Frontend receives progress
   └─> WebSocket /api/v1/ws/progress/{task_id}
   └─> useTraining updates state
   └─> TrainingProgress.tsx renders
```

### Tagging Workflow

```
1. User adds files
   └─> TagTab.tsx: handleSelectFiles() or drag-drop
       └─> useTagging.addFiles(paths)

2. User configures options
   └─> Checkboxes: write genre, album, comments
   └─> Toggle: generate vibes, detect hooks

3. User starts tagging
   └─> useTagging.startTagging(options)
       └─> api.tagBatch(params)
           └─> POST /api/v1/tag/batch
               └─> TaskManager.create_task('tagging')

4. Tagging executes
   └─> For each file:
       ├─> FastAudioAnalyzer.extract_features() (cached)
       ├─> TagPredictor.predict(features)
       ├─> (Optional) VibeGenerator.generate()
       ├─> (Optional) HookTranscriber.transcribe_and_find_hook()
       ├─> TagManager.write_tags()
       └─> Progress → WebSocket

5. User can pause/resume
   └─> pauseTagging() → POST /api/v1/tasks/{id}/pause
   └─> resumeTagging() → POST /api/v1/tasks/{id}/resume
```

### Refinement Workflow

```
1. User loads directory
   └─> RefineTab.tsx: loadDirectory()
       └─> useRefinement.loadDirectory()
           └─> api.findMp3s(directory)
           └─> For each file: api.readTags()

2. User reviews file
   └─> AudioPlayer plays via cratebot:// protocol
   └─> TagEditor shows current tags
   └─> User edits as needed

3. User approves/skips
   └─> approveAndNext()
       └─> api.writeTags(path, editedTags)
       └─> Move to next file
```

---

## 7. Storage & Persistence

### User Data Directory: `~/.cratebot/`

```
~/.cratebot/
├── config.json              # API key, settings
├── lexicon.json             # Vocabulary mappings & ID3 frame config
├── overrides.db             # SQLite per-track corrections
├── models/
│   └── cratebot.pkl         # Trained ML model (v2.0)
├── feature_cache.db         # SQLite feature cache
├── checkpoints/             # Training checkpoints
├── essentia_models/         # Downloaded Essentia models (~100MB)
├── panns_models/            # Downloaded PANNs models (~300MB)
└── clap_models/             # Downloaded CLAP models (~100MB)
```

### Config File Format

```json
{
  "anthropic_api_key": "sk-ant-..."
}
```

### Lexicon File Format

```json
{
  "genre": {
    "id3_frame": "TCON",
    "mappings": {"House": "Deep House", "Techno": "Detroit Techno"}
  },
  "timing": {
    "id3_frame": "TALB",
    "mappings": {"Peak": "Climax"}
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

### Override Database Schema

```sql
CREATE TABLE overrides (
    audio_hash TEXT PRIMARY KEY,  -- SHA256 of first 30s audio
    tags TEXT,                     -- JSON tags dict
    created_at TIMESTAMP,
    updated_at TIMESTAMP
);
```

### Model File Format

Pickle file containing (version 2.0):
- `genre_classifier`: Trained RandomForest/LightGBM
- `timing_classifier`: Trained classifier (Start/Build/Peak/Sustain/Release)
- `mood_classifier`: Trained classifier (Happy/Dark/Emotional/Aggressive/Dreamy/Groovy)
- `descriptive_classifier`: Multi-label classifier
- `scaler`: StandardScaler (fitted for 184 features)
- `label_encoders`: Dict of LabelEncoders
- `selected_tags`: Training tag selection
- `feature_names`: Feature column names
- `version`: Model format version (2.0)

### Feature Cache Schema

```sql
CREATE TABLE features (
    file_path TEXT,
    mtime REAL,
    cache_version INTEGER,
    feature_vector BLOB,        -- numpy array pickled
    metadata TEXT,              -- JSON
    PRIMARY KEY (file_path, cache_version)
);
```

---

## 8. API Reference

### Request/Response Formats

**Success Response:**
```json
{
  "status": "ok",
  "data": { ... }
}
```

**Error Response:**
```json
{
  "error": {
    "code": "ERROR_CODE",
    "message": "Human readable message",
    "details": { ... }
  }
}
```

**WebSocket Progress:**
```json
{
  "task_id": "abc123",
  "status": "running",
  "progress": 45.5,
  "phase": "tagging",
  "current_item": "track.mp3",
  "current_index": 15,
  "total_items": 100,
  "message": "Processing: track.mp3"
}
```

### Key Endpoints

| Method | Endpoint | Purpose |
|--------|----------|---------|
| GET | `/api/v1/health` | Server health |
| GET | `/api/v1/settings` | Feature availability |
| POST | `/api/v1/settings/api-key` | Store API key |
| GET | `/api/v1/model/info` | Model metadata |
| POST | `/api/v1/model/load` | Load model |
| POST | `/api/v1/train/start` | Start training |
| POST | `/api/v1/tag/batch` | Batch tagging |
| POST | `/api/v1/vibe/file` | Generate vibe |
| GET | `/api/v1/lexicon` | Get lexicon config |
| PUT | `/api/v1/lexicon` | Update lexicon |
| GET | `/api/v1/override/{path}` | Get track override |
| POST | `/api/v1/override` | Save track override |
| POST | `/api/v1/tasks/{id}/pause` | Pause task |
| WS | `/api/v1/ws/progress/{id}` | Progress stream |

---

## 9. Build & Deployment

### Development

```bash
# Terminal 1: Frontend (Vite dev server)
cd desktop
npm run dev

# Terminal 2: Backend (auto-started by Electron in dev)
# Or manually:
cd backend && python run_server.py

# Terminal 3: Electron with hot reload
cd desktop
npm run electron:dev
```

### Production Build

```bash
cd desktop

# Full build (frontend + Electron + installers)
npm run build

# Outputs:
# - release/mac-arm64/CrateBot.app   (macOS ARM)
# - release/mac/CrateBot.app          (macOS Intel)
# - release/CrateBot-3.0.0-arm64.dmg  (macOS installer)
```

### Python Backend Bundling

The Python backend is bundled with the app using PyInstaller:

```bash
# Full rebuild (recommended after dependency changes)
./scripts/build.sh python

# Or manually:
pyinstaller --clean --noconfirm cratebot_server.spec
```

This creates a standalone `cratebot-server` binary (~400MB) that's included in the Electron app resources.

### Known Issues & Fixes

#### SDL 1.2 Crash on macOS ARM64

**Symptom:** App crashes on startup with `libSDL-1.2.0.dylib` abort during `dllinit`.

**Root Cause:** Essentia bundles SDL 1.2 which is incompatible with Apple Silicon Macs.

**Fix:**
```bash
# Remove SDL 1.2 from essentia
rm -f python/venv/lib/python*/site-packages/essentia/.dylibs/libSDL-1.2.0.dylib

# Clear PyInstaller cache
rm -rf ~/Library/Application\ Support/pyinstaller/bincache*

# Rebuild the binary
./scripts/build.sh python
```

#### Server Startup Timeout

**Symptom:** "Server not connected" error, but server eventually works.

**Root Cause:** Server takes 8-15 seconds to start due to ML model loading.

**Fix:** Server timeout is set to 30 seconds in `electron/main.ts`. If models are large, this may need adjustment.

#### First-Time Training

**Symptom:** Can't train a model without loading one first.

**Fix:** Use "Train Custom Model" option in Setup Wizard to skip model loading and go directly to Train tab.

---

## Appendix: File Reference

### Frontend Files
| File | Purpose |
|------|---------|
| `desktop/electron/main.ts` | Electron main process |
| `desktop/electron/preload.ts` | IPC bridge |
| `desktop/src/main.tsx` | React entry |
| `desktop/src/App.tsx` | Root component |
| `desktop/src/api/client.ts` | API client (incl. lexicon/override) |
| `desktop/src/stores/appStore.ts` | Global state |
| `desktop/src/hooks/useTraining.ts` | Training state |
| `desktop/src/hooks/useTagging.ts` | Tagging state |
| `desktop/src/hooks/useRefinement.ts` | Refinement state (4-field taxonomy) |
| `desktop/src/components/TrainTab.tsx` | Training UI |
| `desktop/src/components/TagTab.tsx` | Tagging UI |
| `desktop/src/components/RefineTab.tsx` | Refinement UI |
| `desktop/src/components/SettingsPanel.tsx` | Settings (incl. Lexicon) |
| `desktop/src/components/settings/LexiconEditor.tsx` | Lexicon vocabulary editor |
| `desktop/src/components/refine/TagEditor.tsx` | 4-field tag editor |
| `desktop/src/components/FileQueue.tsx` | File list |

### Backend Files
| File | Purpose |
|------|---------|
| `backend/api_server.py` | FastAPI app |
| `backend/task_manager.py` | Async tasks |
| `backend/models/schemas.py` | Pydantic models |

### Python Core Files
| File | Purpose |
|------|---------|
| `python/src/core/auto_tagger.py` | Main orchestrator |
| `python/src/core/tag_manager.py` | ID3 tag I/O (lexicon-aware) |
| `python/src/core/lexicon.py` | Vocabulary customization |
| `python/src/core/overrides.py` | Per-track corrections |
| `python/src/core/audio_hash.py` | Audio fingerprinting |
| `python/src/core/fast_analyzer.py` | Feature extraction (184 dims) |
| `python/src/core/feature_cache.py` | SQLite cache |
| `python/src/core/essentia_analyzer.py` | Mood features |
| `python/src/core/panns_analyzer.py` | Sound recognition |
| `python/src/core/clap_analyzer.py` | CLAP embeddings |
| `python/src/core/jamendo_analyzer.py` | Jamendo classifiers |
| `python/src/core/vibe_generator.py` | Claude integration |
| `python/src/core/hook_transcriber.py` | Whisper hooks |
| `python/src/core/config.py` | Model path resolution |
| `python/src/core/constants.py` | Taxonomy constants |
| `python/src/models/tag_predictor.py` | ML model (4 classifiers) |
