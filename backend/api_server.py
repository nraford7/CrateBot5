"""
CrateBot FastAPI Server.
REST API + WebSocket for the Electron frontend.
"""
import gc
import os
import sys
import json
import asyncio
import logging
import importlib
import threading
from pathlib import Path
from typing import Dict, List, Optional, Any
from datetime import datetime
from contextlib import asynccontextmanager

from fastapi import FastAPI, HTTPException, WebSocket, WebSocketDisconnect, BackgroundTasks, Request, APIRouter
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.exceptions import RequestValidationError

# Add paths for imports
# Parent for backend.* imports, python/ for src.* imports
project_root = Path(__file__).parent.parent
sys.path.insert(0, str(project_root))
sys.path.insert(0, str(project_root / "python"))
sys.path.insert(0, str(project_root / "python" / "src"))

from pydantic import BaseModel
from backend.models.schemas import (
    # Training
    TrainingRequest,
    TrainingStatus,
    TrainingResult,
    SelectedTags,
    DiscoveredTags,
    # Tagging
    TaggingRequest,
    TaggingBatchRequest,
    TaggingResult,
    TaggingResultStatus,
    PredictedTags,
    # Model
    ModelInfo,
    ModelLoadRequest,
    # Vibe
    VibeRequest,
    VibeBatchRequest,
    VibeResult,
    VibeResultStatus,
    # Settings
    APIKeyRequest,
    SettingsResponse,
    # Common
    TaskStatus,
    ProgressUpdate,
    ErrorResponse,
    ErrorBody,
    ScanTagsRequest,
    ReadTagsRequest,
    WriteTagsRequest,
    TagsResponse,
    CheckpointInfo,
)
from backend.task_manager import task_manager, TaskStatus as TMTaskStatus
from core.lexicon import Lexicon
from core.overrides import OverrideStore
from core.audio_hash import compute_audio_hash
from core.utils import matches_selected_tag
from core.constants import ACTUAL_GENRE_VALUES, DEFAULT_GENRE_FOR_TIMING
from core.tag_scanner import normalize_tag
from core.paths import get_cratebot_dir
from core.taxonomy import transform_raw_tags_to_taxonomy, has_any_valid_tag  # CrateBot4

# Configure logging (console + file under CRATEBOT_HOME/logs)
root_logger = logging.getLogger()
root_logger.setLevel(logging.INFO)
logger = logging.getLogger(__name__)

log_dir = get_cratebot_dir() / "logs"
log_dir.mkdir(parents=True, exist_ok=True)
log_file = log_dir / "cratebot-server.log"
file_handler = logging.FileHandler(log_file, encoding="utf-8")
file_handler.setFormatter(logging.Formatter("%(asctime)s %(levelname)s:%(name)s:%(message)s"))
if not any(
    isinstance(handler, logging.FileHandler) and getattr(handler, "baseFilename", "") == str(log_file)
    for handler in root_logger.handlers
):
    root_logger.addHandler(file_handler)

if not root_logger.handlers:
    logging.basicConfig(level=logging.INFO)

# Pydantic models for lexicon
class LexiconUpdate(BaseModel):
    category: str
    id3_frame: Optional[str] = None
    mappings: Optional[Dict[str, str]] = None


class OverrideRequest(BaseModel):
    file_path: str
    tags: Dict[str, Any]


# Global instances (initialized on startup)
auto_tagger = None
auto_tagger_loading = False
tag_manager = None
tag_manager_error: Optional[str] = None
lexicon = Lexicon()
override_store = OverrideStore()
config_path = get_cratebot_dir() / "config.json"


def load_config() -> Dict[str, Any]:
    """Load config from ~/.cratebot/config.json"""
    if config_path.exists():
        try:
            with open(config_path, 'r') as f:
                data = json.load(f)
                if isinstance(data, dict):
                    return data
                logger.warning(f"Config file is not a dict, ignoring: {type(data)}")
                return {}
        except json.JSONDecodeError as e:
            logger.warning(f"Config file has invalid JSON, ignoring: {e}")
            return {}
        except IOError as e:
            logger.warning(f"Could not read config file: {e}")
            return {}
    return {}


def save_config(config: Dict[str, Any]) -> None:
    """Save config to ~/.cratebot/config.json"""
    config_path.parent.mkdir(parents=True, exist_ok=True)
    with open(config_path, 'w') as f:
        json.dump(config, f, indent=2)


def _import_core(module_name: str):
    last_error: Optional[Exception] = None
    for prefix in ("core", "src.core"):
        try:
            return importlib.import_module(f"{prefix}.{module_name}")
        except Exception as exc:
            last_error = exc
    raise last_error or ImportError(f"Unable to import {module_name}")


def ensure_tag_manager() -> Optional["TagManager"]:
    """Lazily initialize TagManager to avoid heavy imports at startup."""
    global tag_manager, tag_manager_error
    if tag_manager is None:
        try:
            tag_manager = _import_core("tag_manager").TagManager()
            tag_manager_error = None
        except Exception as e:
            tag_manager_error = str(e)
            logger.exception("Failed to initialize TagManager")
            tag_manager = None
    return tag_manager


def ensure_auto_tagger(default_model: Optional[Path] = None) -> Optional["AutoTagger"]:
    """Lazily initialize AutoTagger (optionally with a default model)."""
    global auto_tagger, auto_tagger_loading
    if auto_tagger is not None or auto_tagger_loading:
        return auto_tagger

    auto_tagger_loading = True
    try:
        AutoTagger = _import_core("auto_tagger").AutoTagger
        if default_model and default_model.exists():
            auto_tagger = AutoTagger(str(default_model))
        else:
            auto_tagger = AutoTagger()
    except Exception as e:
        logger.error("Failed to initialize AutoTagger: %s", e)
        auto_tagger = None
    finally:
        auto_tagger_loading = False
    return auto_tagger


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Startup and shutdown events."""
    global auto_tagger_loading

    logger.info("Starting CrateBot API server...")

    # Load API key from config into environment for this session
    config = load_config()
    if config.get("anthropic_api_key"):
        os.environ["ANTHROPIC_API_KEY"] = config["anthropic_api_key"]
        logger.info("Loaded Anthropic API key from config")

    # Import core modules
    auto_tagger_loading = False

    # Load default model in the background to avoid blocking startup.
    default_model = get_cratebot_dir() / "models" / "cratebot.pkl"
    if default_model.exists():
        logger.info("Default model found; loading in background...")

        def load_default_model():
            try:
                ensure_auto_tagger(default_model=default_model)
                if auto_tagger is not None and auto_tagger.model_loaded:
                    logger.info("Loaded default model: %s", default_model)
            except Exception as e:
                logger.error("Failed to load default model: %s", e)

        threading.Thread(target=load_default_model, daemon=True).start()
    else:
        logger.info("No default model found; starting without model")

    yield

    # Shutdown
    logger.info("Shutting down CrateBot API server...")
    task_manager.shutdown()


# Create FastAPI app
app = FastAPI(
    title="CrateBot API",
    description="Audio tagging and vibe generation API for DJs",
    version="1.0.0",
    lifespan=lifespan,
)

# Configure CORS for local Swift app
# Note: allow_credentials=True requires specific origins, not "*"
ALLOWED_ORIGINS = [
    "http://localhost:8742",
    "http://127.0.0.1:8742",
    "app://.",  # Electron/Tauri apps
]

# Allow additional origins from environment
if os.environ.get("CRATEBOT_CORS_ORIGINS"):
    ALLOWED_ORIGINS.extend(os.environ["CRATEBOT_CORS_ORIGINS"].split(","))

app.add_middleware(
    CORSMiddleware,
    allow_origins=ALLOWED_ORIGINS,
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "DELETE", "OPTIONS"],
    allow_headers=["Content-Type", "Authorization"],
)

# Create v1 API router
v1_router = APIRouter(prefix="/api/v1")


# =============================================================================
# Exception Handlers (Standard Error Responses)
# =============================================================================

def make_error_response(code: str, message: str, status_code: int = 400) -> JSONResponse:
    """Create a standard error response per API contract."""
    return JSONResponse(
        status_code=status_code,
        content={"error": {"code": code, "message": message}}
    )


@app.exception_handler(HTTPException)
async def http_exception_handler(request: Request, exc: HTTPException):
    """Convert HTTPException to standard error format."""
    return make_error_response(
        code=f"HTTP_{exc.status_code}",
        message=str(exc.detail),
        status_code=exc.status_code
    )


@app.exception_handler(RequestValidationError)
async def validation_exception_handler(request: Request, exc: RequestValidationError):
    """Convert validation errors to standard error format."""
    errors = exc.errors()
    if errors:
        first_error = errors[0]
        field = ".".join(str(loc) for loc in first_error.get("loc", []))
        message = first_error.get("msg", "Validation error")
        return JSONResponse(
            status_code=422,
            content={
                "error": {
                    "code": "VALIDATION_ERROR",
                    "message": message,
                    "details": {"field": field}
                }
            }
        )
    return make_error_response("VALIDATION_ERROR", "Request validation failed", 422)


@app.exception_handler(Exception)
async def general_exception_handler(request: Request, exc: Exception):
    """Catch-all for unhandled exceptions."""
    logger.exception(f"Unhandled exception: {exc}")
    return make_error_response(
        code="INTERNAL_ERROR",
        message="An internal error occurred",
        status_code=500
    )


# =============================================================================
# WebSocket Connection Manager
# =============================================================================

class ConnectionManager:
    """Manages WebSocket connections for progress updates."""

    def __init__(self):
        self.active_connections: Dict[str, List[WebSocket]] = {}

    async def connect(self, websocket: WebSocket, task_id: str):
        await websocket.accept()
        if task_id not in self.active_connections:
            self.active_connections[task_id] = []
        self.active_connections[task_id].append(websocket)

    def disconnect(self, websocket: WebSocket, task_id: str):
        if task_id in self.active_connections:
            try:
                self.active_connections[task_id].remove(websocket)
            except ValueError:
                pass

    async def broadcast(self, task_id: str, message: Dict):
        if task_id in self.active_connections:
            for connection in self.active_connections[task_id]:
                try:
                    await connection.send_json(message)
                except Exception:
                    pass


ws_manager = ConnectionManager()


# =============================================================================
# Health & Info Endpoints
# =============================================================================

@app.get("/")
async def root():
    """Health check endpoint."""
    return {"status": "ok", "service": "CrateBot API", "version": "1.0.0"}


@app.get("/api/v1/health")
async def health_check():
    """Detailed health check."""
    ensure_tag_manager()
    return {
        "status": "ok",
        "model_loaded": auto_tagger is not None and auto_tagger.model_loaded,
        "model_loading": auto_tagger_loading,
        "tag_manager_ready": tag_manager is not None,
        "tag_manager_error": tag_manager_error,
    }


# =============================================================================
# Settings Endpoints
# =============================================================================

@app.get("/api/v1/settings", response_model=SettingsResponse)
async def get_settings():
    """Get current settings."""
    config = load_config()

    # Check vibe availability
    try:
        from core.vibe_generator import is_vibe_available, get_vibe_status
        vibe_available = is_vibe_available()
        vibe_status = get_vibe_status()
    except Exception as e:
        vibe_available = False
        vibe_status = f"Unavailable ({e.__class__.__name__})"

    # Check hook availability
    try:
        from core.hook_transcriber import is_hook_transcription_available, get_hook_transcription_status
        hook_available = is_hook_transcription_available()
        hook_status = get_hook_transcription_status()
    except Exception as e:
        hook_available = False
        hook_status = f"Unavailable ({e.__class__.__name__})"

    # Check PANNs availability
    try:
        from core.panns_analyzer import is_panns_available
        panns_available = is_panns_available()
    except Exception:
        panns_available = False

    return SettingsResponse(
        anthropic_api_key_set=bool(config.get("anthropic_api_key")),
        models_directory=str(get_cratebot_dir() / "models"),
        cache_directory=str(get_cratebot_dir() / "cache"),
        vibe_available=vibe_available,
        vibe_status=vibe_status,
        hook_available=hook_available,
        hook_status=hook_status,
        panns_available=panns_available,
    )


@app.post("/api/v1/settings/api-key")
async def set_api_key(request: APIKeyRequest):
    """Set Anthropic API key."""
    config = load_config()
    config["anthropic_api_key"] = request.api_key
    save_config(config)

    # Also set in environment for current session
    os.environ["ANTHROPIC_API_KEY"] = request.api_key

    return {"status": "ok", "message": "API key saved"}


# =============================================================================
# Lexicon Endpoints
# =============================================================================

@app.get("/api/v1/lexicon")
async def get_lexicon():
    """Get current lexicon configuration."""
    return {
        "categories": {
            category: {
                "id3_frame": lexicon.get_id3_frame(category),
                "mappings": lexicon._lexicon.get(category, {}).get("mappings", {})
            }
            for category in ["genre", "timing", "mood", "descriptive"]
        }
    }


@app.put("/api/v1/lexicon")
async def update_lexicon(update: LexiconUpdate):
    """Update lexicon configuration."""
    if update.id3_frame is not None:
        lexicon.set_id3_frame(update.category, update.id3_frame)
    if update.mappings is not None:
        for canonical, user_value in update.mappings.items():
            if user_value:
                lexicon.set_mapping(update.category, canonical, user_value)
            else:
                lexicon.remove_mapping(update.category, canonical)
    lexicon.save()
    return {"status": "ok"}


# =============================================================================
# Override Endpoints
# =============================================================================

@app.post("/api/v1/override")
async def save_override(request: OverrideRequest):
    """Save a per-track correction."""
    try:
        audio_hash = compute_audio_hash(request.file_path)
        override_store.set(audio_hash, request.tags)
        return {"status": "ok", "hash": audio_hash}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/api/v1/override/{file_path:path}")
async def get_override(file_path: str):
    """Get override for a file if it exists."""
    try:
        audio_hash = compute_audio_hash(file_path)
        tags = override_store.get(audio_hash)
        return {"has_override": tags is not None, "tags": tags, "hash": audio_hash}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# =============================================================================
# Model Endpoints
# =============================================================================

@app.get("/api/v1/model/info", response_model=ModelInfo)
async def get_model_info():
    """Get information about the currently loaded model."""
    if auto_tagger is None:
        return ModelInfo(loaded=False)

    if not auto_tagger.model_loaded:
        return ModelInfo(loaded=False)

    predictor = auto_tagger.predictor
    selected_tags = predictor.selected_tags or {}
    # Check both auto_tagger and predictor for model_path
    model_path = getattr(auto_tagger, '_model_path', None) or getattr(predictor, 'model_path', None)

    # Derive model name from path (filename without extension)
    model_name = None
    if model_path:
        # Handle bundled:// protocol
        if model_path.startswith('bundled://'):
            model_name = model_path.replace('bundled://', '')
        else:
            # Extract filename without extension
            basename = os.path.basename(model_path)
            model_name = os.path.splitext(basename)[0]

    return ModelInfo(
        loaded=True,
        path=model_path,
        name=model_name,
        version=getattr(predictor, 'model_version', None),
        selected_tags=SelectedTags(
            genre=selected_tags.get('genre', []),
            timing=selected_tags.get('timing', []),
            mood=selected_tags.get('mood', selected_tags.get('album', [])),
            descriptive=selected_tags.get('descriptive', selected_tags.get('comments', [])),
        ),
        feature_count=len(predictor.feature_names) if predictor.feature_names else None,
    )


@app.post("/api/v1/model/load")
async def load_model(request: ModelLoadRequest):
    """Load a model from disk."""
    global auto_tagger

    # Expand ~ to home directory
    model_path = os.path.expanduser(request.model_path)

    if not os.path.exists(model_path):
        raise HTTPException(status_code=404, detail=f"Model not found: {model_path}")

    try:
        from core.auto_tagger import AutoTagger
        auto_tagger = AutoTagger(model_path)
        return {"status": "ok", "message": f"Model loaded: {model_path}"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/api/v1/model/list")
async def list_models():
    """List available models."""
    models_dir = get_cratebot_dir() / "models"
    models = []

    if models_dir.exists():
        for model_path in models_dir.glob("*.pkl"):
            stat = model_path.stat()
            models.append({
                "name": model_path.stem,
                "path": str(model_path),
                "size_bytes": stat.st_size,
                "modified_at": datetime.fromtimestamp(stat.st_mtime).isoformat(),
            })

    return {"models": models}


# =============================================================================
# Tag Scanning Endpoints
# =============================================================================

@app.post("/api/v1/scan/tags")
async def scan_tags(request: ScanTagsRequest):
    """Scan a directory for existing tags."""
    manager = ensure_tag_manager()
    if manager is None:
        raise HTTPException(status_code=503, detail="Tag manager not initialized")

    # Expand ~ to home directory
    directory = os.path.expanduser(request.directory)

    if not os.path.isdir(directory):
        raise HTTPException(status_code=404, detail=f"Directory not found: {directory}")

    try:
        logger.info(
            "Scan tags request: directory=%s recursive=%s tag_sources=%s",
            directory,
            request.recursive,
            request.tag_sources,
        )
        from core.tag_scanner import TagScanner
        scanner = TagScanner(manager)
        discovered = scanner.scan_directory(directory, recursive=request.recursive, tag_sources=request.tag_sources)

        # Convert list of tuples to dict for frontend compatibility.
        # tag_scanner returns: {'genre': {'values': [('Rock', 10), ...], 'total_files': 5}, ...}
        # Frontend expects: {'genre': {'values': {'Rock': 10, ...}}, ...}
        def convert_values(category_data):
            if isinstance(category_data, dict) and 'values' in category_data:
                values = category_data['values']
                if isinstance(values, list):
                    # Convert list of tuples to dict
                    return {'values': dict(values), 'total_files': category_data.get('total_files', 0)}
                if isinstance(values, dict):
                    return {'values': values, 'total_files': category_data.get('total_files', 0)}
            return {'values': {}, 'total_files': 0}

        response = DiscoveredTags(
            genre=convert_values(discovered.get('genre', {})),
            timing=convert_values(discovered.get('timing', {})),
            mood=convert_values(discovered.get('mood', {})),
            descriptive=convert_values(discovered.get('descriptive', {})),
            total_files=discovered.get('total_mp3s', discovered.get('total_files', 0)),
        )
        logger.info(
            "Scan tags result: total_files=%s genre=%d timing=%d mood=%d descriptive=%d",
            response.total_files,
            len(response.genre.get('values', {})),
            len(response.timing.get('values', {})),
            len(response.mood.get('values', {})),
            len(response.descriptive.get('values', {})),
        )
        return response
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# =============================================================================
# Training Endpoints
# =============================================================================

@app.post("/api/v1/train/start")
async def start_training(request: TrainingRequest, background_tasks: BackgroundTasks):
    """Start a training job. CrateBot4: Added pre-validation and auto-reload."""
    # CrateBot4: Pre-training validation - fail fast before expensive operations
    if not os.path.isdir(request.training_dir):
        raise HTTPException(status_code=404, detail=f"Directory not found: {request.training_dir}")

    # CrateBot4: Check if directory has MP3 files
    mp3_files_check = list(Path(request.training_dir).glob('**/*.mp3'))
    if len(mp3_files_check) == 0:
        raise HTTPException(
            status_code=400,
            detail=f"No MP3 files found in {request.training_dir}. Please select a directory containing MP3 files."
        )

    # CrateBot4: Check if selected tags are valid
    total_selected = (
        len(request.selected_tags.genre) +
        len(request.selected_tags.timing) +
        len(request.selected_tags.mood) +
        len(request.selected_tags.descriptive)
    )
    if total_selected == 0:
        raise HTTPException(
            status_code=400,
            detail="No tags selected for training. Please select at least one tag from the tag selection dialog."
        )

    # CrateBot5: Validate required ML models are available (fail fast)
    try:
        from core.training_validator import validate_training_requirements
        validation = validate_training_requirements(
            require_panns=True,
            require_clap=True,
            require_jamendo=False,
            require_essentia=False,
            verbose=False
        )
        if not validation.all_passed:
            missing = [f.name for f in validation.required_failures]
            fixes = [f.fix_command for f in validation.required_failures if f.fix_command]
            detail = f"Required ML models not available: {', '.join(missing)}. "
            if fixes:
                detail += f"Run: {fixes[0]}"
            raise HTTPException(status_code=400, detail=detail)
    except ImportError as e:
        logger.warning("Could not import training_validator: %s", e)

    # Create task
    task_id = task_manager.create_task("training")

    # Run training in background
    async def run_training():
        def training_wrapper(progress_callback):
            """Wrapper that calls the training with progress updates."""
            from core.auto_tagger import AutoTagger
            from core.training_checkpoint import TrainingCheckpoint

            # CrateBot5: Auto-optimize hardware settings before training
            try:
                from core.auto_optimize import optimize_for_hardware
                logger.info("Auto-optimizing hardware settings...")
                profile = optimize_for_hardware(verbose=False, apply_env=True)
                logger.info(
                    "Hardware optimized: %d workers, %d threads, device=%s, batch=%d",
                    profile.recommended_workers,
                    profile.recommended_torch_threads,
                    profile.recommended_device,
                    profile.recommended_batch_size
                )
            except Exception as e:
                logger.warning("Auto-optimization failed (continuing anyway): %s", e)

            # Create fresh tagger for training
            tagger = AutoTagger(use_cache=True)

            selected_tags = {
                'genre': request.selected_tags.genre,
                'timing': request.selected_tags.timing,
                'mood': request.selected_tags.mood,
                'descriptive': request.selected_tags.descriptive,
            }

            # Debug: Log selected tags
            logger.info(
                "Training with selected_tags: genre=%d timing=%d mood=%d descriptive=%d",
                len(selected_tags['genre']),
                len(selected_tags['timing']),
                len(selected_tags['mood']),
                len(selected_tags['descriptive']),
            )

            progress_callback(phase="collecting", progress=0, message="Starting training...")

            # Collect training data with progress
            training_data = []
            mp3_files = list(Path(request.training_dir).glob('**/*.mp3'))
            total_files = len(mp3_files)

            tag_sources = request.tag_sources or {}
            use_timing_frame = bool(tag_sources.get('timing_frame'))
            actual_genres_normalized = {normalize_tag(g) for g in ACTUAL_GENRE_VALUES}

            class FrameLexicon:
                def __init__(self, mapping: Dict[str, Optional[str]]):
                    self.mapping = mapping

                def get_id3_frame(self, category: str) -> Optional[str]:
                    return self.mapping.get(category)

            lexicon = None
            if tag_sources:
                lexicon = FrameLexicon({
                    'genre': tag_sources.get('genre_frame'),
                    'timing': tag_sources.get('timing_frame'),
                    'mood': tag_sources.get('mood_frame'),
                    'descriptive': tag_sources.get('comments_frame'),
                })

            # CrateBot4: Use centralized taxonomy transformation (eliminates duplicated code)
            for i, mp3_path in enumerate(mp3_files):
                if i % 10 == 0:
                    progress_callback(
                        phase="collecting",
                        progress=(i / total_files) * 50,
                        current_item=mp3_path.name,
                        current_index=i,
                        total_items=total_files,
                        message=f"Extracting features: {mp3_path.name}"
                    )

                try:
                    raw_tags = tagger.tag_manager.read_tags(str(mp3_path), lexicon=lexicon)
                    if not raw_tags:
                        continue

                    # CrateBot4: Use centralized taxonomy transformation
                    training_tags = transform_raw_tags_to_taxonomy(
                        raw_tags,
                        tag_sources=tag_sources,
                        lexicon=lexicon
                    )

                    # CrateBot4: Use centralized validation
                    if not has_any_valid_tag(training_tags, selected_tags):
                        if i < 50:
                            logger.debug(
                                "No match for %s: genre='%s' timing='%s' mood='%s' descriptive='%s'",
                                mp3_path.name,
                                training_tags.get('genre', ''),
                                training_tags.get('timing', ''),
                                training_tags.get('mood', ''),
                                training_tags.get('descriptive', '')[:50],
                            )
                        continue

                    features = tagger.analyzer.extract_features(str(mp3_path))
                    # Only store what's needed for training to avoid memory accumulation
                    # The full features dict contains large numpy arrays that would consume
                    # excessive memory when processing thousands of files
                    training_data.append({
                        'file_path': str(mp3_path),
                        'file_name': mp3_path.name,
                        'tags': training_tags,
                        'feature_vector': features['feature_vector'],
                    })
                    # Explicitly clear features to help garbage collection
                    del features

                    # Periodic garbage collection to prevent memory accumulation
                    # when processing large music libraries
                    if i > 0 and i % 50 == 0:
                        gc.collect()

                except Exception as e:
                    logger.warning(f"Error processing {mp3_path}: {e}")
                    continue

            if len(training_data) < 50:
                raise ValueError(f"Only {len(training_data)} valid samples. Need at least 50.")

            progress_callback(
                phase="training",
                progress=50,
                message=f"Training model with {len(training_data)} samples..."
            )

            # Train model
            results = tagger.predictor.train(training_data, selected_tags, test_size=request.test_size)

            progress_callback(phase="saving", progress=90, message="Saving model...")

            # Save model - expand ~ to home directory
            output_path = os.path.expanduser(request.output_model_path)
            os.makedirs(os.path.dirname(output_path), exist_ok=True)
            tagger.predictor.save_model(output_path)

            # CrateBot4: Auto-reload model into global auto_tagger
            global auto_tagger
            try:
                if auto_tagger is None:
                    from core.auto_tagger import AutoTagger
                    auto_tagger = AutoTagger(output_path)
                else:
                    auto_tagger.predictor.load_model(output_path)
                    auto_tagger.model_loaded = True
                    auto_tagger._model_path = output_path
                logger.info("Auto-loaded trained model into global auto_tagger: %s", output_path)
                progress_callback(phase="complete", progress=100, message="Training complete! Model loaded and ready for tagging.")
            except Exception as e:
                logger.warning("Failed to auto-load model: %s. User can manually load.", e)
                progress_callback(phase="complete", progress=100, message="Training complete! Note: Please load the model manually.")

            return {
                'success': True,
                'model_path': output_path,
                'samples_trained': len(training_data),
                'metrics': results,
                'auto_loaded': auto_tagger is not None and auto_tagger.model_loaded,  # CrateBot4
            }

        try:
            result = await task_manager.run_task(task_id, training_wrapper)
            return result
        except Exception as e:
            logger.error(f"Training failed: {e}")
            return {'success': False, 'error': str(e)}

    background_tasks.add_task(run_training)

    return {"task_id": task_id, "status": "started"}


@app.get("/api/v1/train/status/{task_id}", response_model=TrainingStatus)
async def get_training_status(task_id: str):
    """Get training task status."""
    task = task_manager.get_task(task_id)
    if not task:
        raise HTTPException(status_code=404, detail=f"Task not found: {task_id}")

    return TrainingStatus(
        task_id=task_id,
        status=TaskStatus(task.status.value),
        progress=task.progress.progress,
        phase=task.progress.phase,
        current_file=task.progress.current_item,
        files_processed=task.progress.current_index,
        total_files=task.progress.total_items,
        samples_collected=task.progress.metrics.get('samples', 0),
        started_at=task.started_at,
        error=task.error,
    )


@app.post("/api/v1/train/cancel/{task_id}")
async def cancel_training(task_id: str):
    """Cancel a training task."""
    if task_manager.cancel_task(task_id):
        return {"status": "ok", "message": "Cancellation requested"}
    raise HTTPException(status_code=400, detail="Cannot cancel task")


@app.get("/api/v1/train/checkpoints")
async def list_checkpoints():
    """List available training checkpoints."""
    checkpoint_dir = get_cratebot_dir() / "checkpoints"
    checkpoints = []

    if checkpoint_dir.exists():
        for meta_file in checkpoint_dir.glob("checkpoint_*.json"):
            try:
                with open(meta_file, 'r') as f:
                    meta = json.load(f)
                    checkpoints.append(CheckpointInfo(
                        session_id=meta.get('session_id', ''),
                        training_dir=meta.get('training_dir', ''),
                        samples_processed=meta.get('samples_processed', 0),
                        total_files=meta.get('total_files', 0),
                        selected_tags=SelectedTags(
                            genre=meta.get('selected_tags', {}).get('genre', []),
                            timing=meta.get('selected_tags', {}).get('timing', []),
                            mood=meta.get('selected_tags', {}).get('mood', meta.get('selected_tags', {}).get('album', [])),
                            descriptive=meta.get('selected_tags', {}).get('descriptive', meta.get('selected_tags', {}).get('comments', [])),
                        ),
                        last_updated=datetime.fromisoformat(meta.get('last_updated', datetime.utcnow().isoformat())),
                    ))
            except (json.JSONDecodeError, KeyError) as e:
                logger.warning(f"Invalid checkpoint: {meta_file}: {e}")
                continue

    return {"checkpoints": checkpoints}


# =============================================================================
# Tagging Endpoints
# =============================================================================

@app.post("/api/v1/tag/file", response_model=TaggingResult)
async def tag_single_file(request: TaggingRequest):
    """Tag a single file."""
    if auto_tagger is None or not auto_tagger.model_loaded:
        raise HTTPException(status_code=503, detail="No model loaded")

    if not os.path.exists(request.file_path):
        raise HTTPException(status_code=404, detail=f"File not found: {request.file_path}")

    try:
        tags_to_write = {
            'genre': request.tags_to_write.genre,
            'album': request.tags_to_write.album,
            'comments': request.tags_to_write.comments,
            'mood': request.tags_to_write.mood,
            'likeness': request.tags_to_write.likeness,
        }

        result = auto_tagger.tag_file(
            request.file_path,
            overwrite=request.overwrite,
            dry_run=request.dry_run,
            silent=True,
            tags_to_write=tags_to_write,
        )

        predicted = result.get('tags', result)
        return TaggingResult(
            file_path=request.file_path,
            filename=os.path.basename(request.file_path),
            status=TaggingResultStatus(result.get('status', 'tagged')),
            predicted_tags=PredictedTags(
                genre=predicted.get('genre'),
                album=predicted.get('album'),
                comments=predicted.get('comments'),
                mood=predicted.get('mood'),
                genre_confidence=predicted.get('_genre_confidence'),
                album_confidence=predicted.get('_album_confidence'),
            ),
            flag_reasons=result.get('flag_reasons', []),
        )

    except Exception as e:
        return TaggingResult(
            file_path=request.file_path,
            filename=os.path.basename(request.file_path),
            status=TaggingResultStatus.FAILED,
            error=str(e),
        )


@app.post("/api/v1/tag/batch")
async def tag_batch(request: TaggingBatchRequest, background_tasks: BackgroundTasks):
    """Start a batch tagging job."""
    if auto_tagger is None or not auto_tagger.model_loaded:
        raise HTTPException(status_code=503, detail="No model loaded")

    task_id = task_manager.create_task("tagging")

    async def run_batch_tagging():
        def tagging_wrapper(progress_callback):
            # Initialize vibe/hook generators if requested
            vibe_generator = None
            hook_transcriber = None

            if request.generate_vibes:
                try:
                    from core.vibe_generator import CachedVibeGenerator, is_vibe_available
                    if is_vibe_available():
                        vibe_generator = CachedVibeGenerator()
                except ImportError:
                    logger.warning("Vibe generator not available")

            if request.generate_hooks:
                try:
                    from core.hook_transcriber import CachedHookTranscriber, is_hook_transcription_available
                    if is_hook_transcription_available():
                        hook_transcriber = CachedHookTranscriber()
                except ImportError:
                    logger.warning("Hook transcriber not available")

            results = []
            total = len(request.file_paths)

            for i, file_path in enumerate(request.file_paths):
                progress_callback(
                    phase="tagging",
                    progress=(i / total) * 100,
                    current_item=os.path.basename(file_path),
                    current_index=i,
                    total_items=total,
                )

                try:
                    tags_to_write = {
                        'genre': request.tags_to_write.genre,
                        'album': request.tags_to_write.album,
                        'comments': request.tags_to_write.comments,
                        'mood': request.tags_to_write.mood,
                        'likeness': request.tags_to_write.likeness,
                    }

                    result = auto_tagger.tag_file(
                        file_path,
                        overwrite=request.overwrite,
                        dry_run=request.dry_run,
                        silent=True,
                        tags_to_write=tags_to_write,
                    )

                    file_result = {
                        'file_path': file_path,
                        'status': result.get('status', 'tagged'),
                        'tags': result.get('tags', result),
                    }

                    # Generate vibe if requested
                    if vibe_generator and result.get('status') != 'failed':
                        try:
                            vibe_result = auto_tagger.generate_vibe(
                                file_path,
                                overwrite=request.overwrite,
                                dry_run=request.dry_run,
                                silent=True,
                                vibe_generator=vibe_generator,
                                hook_transcriber=hook_transcriber,
                                skip_hook=not request.generate_hooks,
                            )
                            file_result['vibe'] = vibe_result.get('vibe')
                            file_result['description'] = vibe_result.get('description')
                            if request.generate_hooks:
                                file_result['hook'] = vibe_result.get('hook')
                        except Exception as e:
                            logger.warning(f"Vibe generation failed for {file_path}: {e}")

                    results.append(file_result)

                except Exception as e:
                    results.append({
                        'file_path': file_path,
                        'status': 'failed',
                        'error': str(e),
                    })

            progress_callback(phase="complete", progress=100)
            return results

        try:
            return await task_manager.run_task(task_id, tagging_wrapper)
        except Exception as e:
            logger.error(f"Batch tagging failed: {e}")
            return []

    background_tasks.add_task(run_batch_tagging)

    return {"task_id": task_id, "status": "started", "total_files": len(request.file_paths)}


@app.post("/api/v1/tag/cancel/{task_id}")
async def cancel_tagging(task_id: str):
    """Cancel a tagging task."""
    if task_manager.cancel_task(task_id):
        return {"status": "ok", "message": "Cancellation requested"}
    raise HTTPException(status_code=400, detail="Cannot cancel task")


# =============================================================================
# Vibe Generation Endpoints
# =============================================================================

@app.post("/api/v1/vibe/file", response_model=VibeResult)
async def generate_vibe_single(request: VibeRequest):
    """Generate vibe for a single file."""
    if auto_tagger is None:
        raise HTTPException(status_code=503, detail="AutoTagger not initialized")

    if not os.path.exists(request.file_path):
        raise HTTPException(status_code=404, detail=f"File not found: {request.file_path}")

    try:
        result = auto_tagger.generate_vibe(
            request.file_path,
            overwrite=request.overwrite,
            dry_run=request.dry_run,
            silent=True,
            skip_hook=request.skip_hook,
        )

        return VibeResult(
            file_path=request.file_path,
            filename=os.path.basename(request.file_path),
            status=VibeResultStatus(result.get('status', 'failed')),
            vibe=result.get('vibe'),
            description=result.get('description'),
            scene=result.get('scene'),
            scene_confidence=result.get('scene_confidence'),
            hook=result.get('hook'),
            hook_occurrences=result.get('hook_occurrences', 0),
            detections=result.get('detections'),
            error=result.get('error'),
        )

    except Exception as e:
        return VibeResult(
            file_path=request.file_path,
            filename=os.path.basename(request.file_path),
            status=VibeResultStatus.FAILED,
            error=str(e),
        )


@app.post("/api/v1/vibe/batch")
async def generate_vibe_batch(request: VibeBatchRequest, background_tasks: BackgroundTasks):
    """Start batch vibe generation."""
    if auto_tagger is None:
        raise HTTPException(status_code=503, detail="AutoTagger not initialized")

    task_id = task_manager.create_task("vibe")

    async def run_batch_vibe():
        def vibe_wrapper(progress_callback):
            from core.vibe_generator import CachedVibeGenerator, is_vibe_available
            from core.hook_transcriber import CachedHookTranscriber, is_hook_transcription_available

            if not is_vibe_available():
                raise ValueError("Vibe generation not available - check API key")

            vibe_generator = CachedVibeGenerator()
            hook_transcriber = None
            if not request.skip_hook and is_hook_transcription_available():
                hook_transcriber = CachedHookTranscriber()

            results = []
            total = len(request.file_paths)

            for i, file_path in enumerate(request.file_paths):
                progress_callback(
                    phase="generating",
                    progress=(i / total) * 100,
                    current_item=os.path.basename(file_path),
                    current_index=i,
                    total_items=total,
                )

                try:
                    result = auto_tagger.generate_vibe(
                        file_path,
                        overwrite=request.overwrite,
                        dry_run=request.dry_run,
                        silent=True,
                        vibe_generator=vibe_generator,
                        hook_transcriber=hook_transcriber,
                        skip_hook=request.skip_hook,
                    )
                    results.append(result)

                except Exception as e:
                    results.append({
                        'file_path': file_path,
                        'status': 'failed',
                        'error': str(e),
                    })

            progress_callback(phase="complete", progress=100)
            return results

        try:
            return await task_manager.run_task(task_id, vibe_wrapper)
        except Exception as e:
            logger.error(f"Batch vibe generation failed: {e}")
            return []

    background_tasks.add_task(run_batch_vibe)

    return {"task_id": task_id, "status": "started", "total_files": len(request.file_paths)}


# =============================================================================
# Tag Read/Write Endpoints
# =============================================================================

@app.post("/api/v1/tags/read", response_model=TagsResponse)
async def read_tags(request: ReadTagsRequest):
    """Read tags from a file."""
    manager = ensure_tag_manager()
    if manager is None:
        raise HTTPException(status_code=503, detail="Tag manager not initialized")

    if not os.path.exists(request.file_path):
        raise HTTPException(status_code=404, detail=f"File not found: {request.file_path}")

    try:
        tags = manager.read_tags(request.file_path, lexicon=lexicon)
        return TagsResponse(file_path=request.file_path, tags=tags or {})
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/api/v1/tags/write")
async def write_tags(request: WriteTagsRequest):
    """Write tags to a file."""
    manager = ensure_tag_manager()
    if manager is None:
        raise HTTPException(status_code=503, detail="Tag manager not initialized")

    if not os.path.exists(request.file_path):
        raise HTTPException(status_code=404, detail=f"File not found: {request.file_path}")

    try:
        manager.write_tags(request.file_path, request.tags, overwrite=request.overwrite, lexicon=lexicon)
        return {"status": "ok", "message": "Tags written"}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# =============================================================================
# Task Status Endpoints
# =============================================================================

@app.post("/api/v1/tasks/{task_id}/pause")
async def pause_task(task_id: str):
    """Pause a running task."""
    if task_manager.pause_task(task_id):
        return {"status": "ok", "message": "Task paused"}
    raise HTTPException(status_code=400, detail="Cannot pause task")


@app.post("/api/v1/tasks/{task_id}/resume")
async def resume_task(task_id: str):
    """Resume a paused task."""
    if task_manager.resume_task(task_id):
        return {"status": "ok", "message": "Task resumed"}
    raise HTTPException(status_code=400, detail="Cannot resume task")


@app.get("/api/v1/tasks/{task_id}")
async def get_task_status(task_id: str):
    """Get status of any task."""
    task = task_manager.get_task(task_id)
    if not task:
        raise HTTPException(status_code=404, detail=f"Task not found: {task_id}")

    return {
        "task_id": task.task_id,
        "task_type": task.task_type,
        "status": task.status.value,
        "progress": task.progress.progress,
        "phase": task.progress.phase,
        "current_item": task.progress.current_item,
        "current_index": task.progress.current_index,
        "total_items": task.progress.total_items,
        "message": task.progress.message,
        "result": task.result,
        "error": task.error,
        "created_at": task.created_at.isoformat() if task.created_at else None,
        "started_at": task.started_at.isoformat() if task.started_at else None,
        "completed_at": task.completed_at.isoformat() if task.completed_at else None,
        "logs": task.log_messages[-50:],  # Last 50 log messages
    }


@app.get("/api/v1/tasks")
async def list_tasks(task_type: Optional[str] = None):
    """List all tasks."""
    tasks = task_manager.list_tasks(task_type)
    return {
        "tasks": [
            {
                "task_id": t.task_id,
                "task_type": t.task_type,
                "status": t.status.value,
                "progress": t.progress.progress,
                "created_at": t.created_at.isoformat() if t.created_at else None,
            }
            for t in tasks
        ]
    }


# =============================================================================
# WebSocket Endpoint for Progress
# =============================================================================

@app.websocket("/api/v1/ws/progress/{task_id}")
async def websocket_progress(websocket: WebSocket, task_id: str):
    """WebSocket endpoint for real-time progress updates."""
    await ws_manager.connect(websocket, task_id)

    # Create async queue for receiving updates
    update_queue: asyncio.Queue = asyncio.Queue()
    task_manager.subscribe_async(task_id, update_queue)

    try:
        # Send current state immediately
        task = task_manager.get_task(task_id)
        if task:
            await websocket.send_json({
                "task_id": task.task_id,
                "status": task.status.value,
                "progress": task.progress.progress,
                "phase": task.progress.phase,
                "current_item": task.progress.current_item,
                "current_index": task.progress.current_index,
                "total_items": task.progress.total_items,
                "message": task.progress.message,
            })

        # Run two concurrent tasks: receive client messages and send updates
        async def receive_messages():
            """Handle incoming WebSocket messages (ping/pong)."""
            while True:
                try:
                    data = await asyncio.wait_for(websocket.receive_text(), timeout=30)
                    if data == "ping":
                        await websocket.send_text("pong")
                except asyncio.TimeoutError:
                    await websocket.send_text("heartbeat")
                except WebSocketDisconnect:
                    break

        async def send_updates():
            """Forward task updates to WebSocket."""
            while True:
                try:
                    update = await asyncio.wait_for(update_queue.get(), timeout=1.0)
                    await websocket.send_json(update)

                    # Stop if task completed
                    if update.get("status") in ("completed", "failed", "cancelled"):
                        break
                except asyncio.TimeoutError:
                    # Check if task still exists and is active
                    task = task_manager.get_task(task_id)
                    if not task or task.status.value in ("completed", "failed", "cancelled"):
                        break
                except Exception:
                    break

        # Run both tasks concurrently, stop when either completes
        done, pending = await asyncio.wait(
            [asyncio.create_task(receive_messages()), asyncio.create_task(send_updates())],
            return_when=asyncio.FIRST_COMPLETED
        )
        for p in pending:
            p.cancel()

    finally:
        task_manager.unsubscribe_async(task_id, update_queue)
        ws_manager.disconnect(websocket, task_id)


# =============================================================================
# File Browser Endpoints
# =============================================================================

@app.get("/api/v1/files/browse")
async def browse_directory(path: str = "~"):
    """Browse directory contents."""
    dir_path = Path(path).expanduser()

    if not dir_path.exists():
        raise HTTPException(status_code=404, detail=f"Path not found: {path}")

    if not dir_path.is_dir():
        raise HTTPException(status_code=400, detail=f"Not a directory: {path}")

    items = []
    try:
        for item in sorted(dir_path.iterdir()):
            item_info = {
                "name": item.name,
                "path": str(item),
                "is_dir": item.is_dir(),
            }

            if item.is_file():
                item_info["size_bytes"] = item.stat().st_size
                item_info["extension"] = item.suffix.lower()

            items.append(item_info)

    except PermissionError:
        raise HTTPException(status_code=403, detail=f"Permission denied: {path}")

    return {
        "path": str(dir_path),
        "parent": str(dir_path.parent),
        "items": items,
    }


@app.get("/api/v1/files/mp3s")
async def find_mp3s(directory: str, recursive: bool = True):
    """Find all MP3 files in a directory."""
    dir_path = Path(directory).expanduser()

    if not dir_path.exists():
        raise HTTPException(status_code=404, detail=f"Directory not found: {directory}")

    pattern = "**/*.mp3" if recursive else "*.mp3"
    mp3_files = []

    for mp3_path in dir_path.glob(pattern):
        mp3_files.append({
            "path": str(mp3_path),
            "name": mp3_path.name,
            "size_bytes": mp3_path.stat().st_size,
        })

    return {"directory": str(dir_path), "files": mp3_files, "count": len(mp3_files)}


# =============================================================================
# Migration Endpoints
# =============================================================================

@app.get("/api/v1/migration/detect")
async def detect_migration():
    """Detect if migration from tkinter version is needed."""
    try:
        from backend.migration import detect_legacy_data
        return detect_legacy_data()
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/api/v1/migration/run")
async def run_migration(create_backup: bool = True):
    """Run migration from tkinter version."""
    try:
        from backend.migration import run_migration
        result = run_migration(create_backup_first=create_backup)
        return result.to_dict()
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.get("/api/v1/migration/backups")
async def list_migration_backups():
    """List available migration backups."""
    try:
        from backend.migration import list_backups
        return {"backups": list_backups()}
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


@app.post("/api/v1/migration/restore")
async def restore_migration_backup(backup_path: str):
    """Restore from a migration backup."""
    try:
        from backend.migration import restore_backup
        success = restore_backup(backup_path)
        if success:
            return {"status": "ok", "message": "Backup restored successfully"}
        else:
            raise HTTPException(status_code=500, detail="Restore failed")
    except Exception as e:
        raise HTTPException(status_code=500, detail=str(e))


# =============================================================================
# Main Entry Point
# =============================================================================

def main():
    """Run the API server."""
    import uvicorn
    uvicorn.run(
        "backend.api_server:app",
        host="127.0.0.1",
        port=8742,
        reload=False,
        log_level="info",
    )


if __name__ == "__main__":
    main()
