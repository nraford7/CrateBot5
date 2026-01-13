"""
Pydantic models for CrateBot API.
Defines request/response schemas for all endpoints.
"""
from datetime import datetime
from enum import Enum
from typing import Dict, List, Optional, Any
from pydantic import BaseModel, Field


# =============================================================================
# Common Models
# =============================================================================

class TaskStatus(str, Enum):
    """Status of a long-running task."""
    PENDING = "pending"
    RUNNING = "running"
    COMPLETED = "completed"
    FAILED = "failed"
    CANCELLED = "cancelled"
    PAUSED = "paused"


class ProgressUpdate(BaseModel):
    """Real-time progress update for WebSocket."""
    task_id: str
    task_type: str  # "training", "tagging", "vibe"
    status: TaskStatus
    progress: float = Field(ge=0, le=100, description="Percentage complete")
    current_item: Optional[str] = None
    current_index: int = 0
    total_items: int = 0
    message: Optional[str] = None
    timestamp: datetime = Field(default_factory=datetime.utcnow)


class FileInfo(BaseModel):
    """Information about a single file."""
    path: str
    filename: str
    size_bytes: Optional[int] = None
    duration_seconds: Optional[float] = None
    existing_tags: Optional[Dict[str, Any]] = None


class ErrorDetail(BaseModel):
    """Details for error response."""
    field: Optional[str] = None
    reason: Optional[str] = None


class ErrorBody(BaseModel):
    """Standard error body per API contract."""
    code: str
    message: str
    details: Optional[ErrorDetail] = None


class ErrorResponse(BaseModel):
    """Standard error response wrapper per API contract."""
    error: ErrorBody


# =============================================================================
# Training Models
# =============================================================================

class SelectedTags(BaseModel):
    """Tags selected for training."""
    genre: List[str] = Field(default_factory=list)
    timing: List[str] = Field(default_factory=list)
    mood: List[str] = Field(default_factory=list)
    descriptive: List[str] = Field(default_factory=list)


class DiscoveredTags(BaseModel):
    """Tags discovered during directory scan."""
    genre: Dict[str, Any] = Field(default_factory=dict)
    timing: Dict[str, Any] = Field(default_factory=dict)
    mood: Dict[str, Any] = Field(default_factory=dict)
    descriptive: Dict[str, Any] = Field(default_factory=dict)
    total_files: int = 0


class TrainingRequest(BaseModel):
    """Request to start training."""
    training_dir: str
    output_model_path: str = "models/cratebot.pkl"
    selected_tags: SelectedTags
    test_size: float = Field(default=0.2, ge=0.1, le=0.5)
    resume_from_checkpoint: Optional[str] = None
    tag_sources: Optional[Dict[str, Optional[str]]] = None


class TrainingStatus(BaseModel):
    """Current training status."""
    task_id: str
    status: TaskStatus
    progress: float = Field(ge=0, le=100)
    phase: str = "idle"  # "scanning", "extracting", "training", "saving"
    current_file: Optional[str] = None
    files_processed: int = 0
    total_files: int = 0
    samples_collected: int = 0
    eta_seconds: Optional[float] = None
    started_at: Optional[datetime] = None
    error: Optional[str] = None


class TrainingProgress(BaseModel):
    """Detailed training progress for UI."""
    phase: str
    phase_progress: float = Field(ge=0, le=100)
    overall_progress: float = Field(ge=0, le=100)
    current_file: Optional[str] = None
    files_processed: int = 0
    total_files: int = 0
    samples_collected: int = 0
    training_metrics: Optional[Dict[str, float]] = None
    log_messages: List[str] = Field(default_factory=list)


class TrainingResult(BaseModel):
    """Training completion result."""
    success: bool
    model_path: Optional[str] = None
    selected_tags: Optional[SelectedTags] = None
    metrics: Optional[Dict[str, Any]] = None
    duration_seconds: float = 0
    samples_trained: int = 0
    error: Optional[str] = None


# =============================================================================
# Tagging Models
# =============================================================================

class TagsToWrite(BaseModel):
    """Which tags to write during tagging."""
    genre: bool = True
    album: bool = True
    comments: bool = True
    mood: bool = True
    likeness: bool = True


class PredictedTags(BaseModel):
    """Predicted tags for a file."""
    genre: Optional[str] = None
    album: Optional[str] = None
    comments: Optional[str] = None
    mood: Optional[str] = None
    genre_confidence: Optional[float] = None
    album_confidence: Optional[float] = None
    comment_likeness: Optional[float] = None
    overall_likeness: Optional[float] = None


class TaggingRequest(BaseModel):
    """Request to tag a single file."""
    file_path: str
    overwrite: bool = False
    dry_run: bool = False
    tags_to_write: TagsToWrite = Field(default_factory=TagsToWrite)


class TaggingBatchRequest(BaseModel):
    """Request to tag multiple files."""
    file_paths: List[str]
    overwrite: bool = False
    dry_run: bool = False
    tags_to_write: TagsToWrite = Field(default_factory=TagsToWrite)
    generate_vibes: bool = False
    generate_hooks: bool = False


class TaggingResultStatus(str, Enum):
    """Status of a single file tagging."""
    TAGGED = "tagged"
    REVIEW = "review"
    SKIPPED = "skipped"
    FAILED = "failed"


class TaggingResult(BaseModel):
    """Result of tagging a single file."""
    file_path: str
    filename: str
    status: TaggingResultStatus
    predicted_tags: Optional[PredictedTags] = None
    vibe: Optional[str] = None
    description: Optional[str] = None
    hook: Optional[str] = None
    flag_reasons: List[str] = Field(default_factory=list)
    error: Optional[str] = None


# =============================================================================
# Model Management
# =============================================================================

class ModelInfo(BaseModel):
    """Information about a loaded model."""
    loaded: bool = False
    path: Optional[str] = None
    name: Optional[str] = None
    created_at: Optional[datetime] = None
    version: Optional[str] = None
    selected_tags: Optional[SelectedTags] = None
    feature_count: Optional[int] = None
    training_samples: Optional[int] = None


class ModelLoadRequest(BaseModel):
    """Request to load a model."""
    model_path: str


# =============================================================================
# Vibe Generation Models
# =============================================================================

class VibeRequest(BaseModel):
    """Request to generate vibe for a single file."""
    file_path: str
    overwrite: bool = False
    dry_run: bool = False
    skip_hook: bool = False


class VibeBatchRequest(BaseModel):
    """Request to generate vibes for multiple files."""
    file_paths: List[str]
    overwrite: bool = False
    dry_run: bool = False
    skip_hook: bool = False


class VibeResultStatus(str, Enum):
    """Status of vibe generation."""
    TAGGED = "tagged"
    SKIPPED = "skipped"
    UNAVAILABLE = "unavailable"
    FAILED = "failed"


class VibeResult(BaseModel):
    """Result of vibe generation."""
    file_path: str
    filename: str
    status: VibeResultStatus
    vibe: Optional[str] = None
    description: Optional[str] = None
    scene: Optional[str] = None
    scene_confidence: Optional[float] = None
    hook: Optional[str] = None
    hook_occurrences: int = 0
    detections: Optional[str] = None
    error: Optional[str] = None


# =============================================================================
# Settings Models
# =============================================================================

class APIKeyRequest(BaseModel):
    """Request to set API key."""
    api_key: str


class SettingsResponse(BaseModel):
    """Current settings."""
    anthropic_api_key_set: bool = False
    models_directory: str = ""
    cache_directory: str = ""
    vibe_available: bool = False
    vibe_status: str = ""
    hook_available: bool = False
    hook_status: str = ""
    panns_available: bool = False


# =============================================================================
# Tag Scanning Models
# =============================================================================

class ScanTagsRequest(BaseModel):
    """Request to scan directory for tags."""
    directory: str
    recursive: bool = True
    tag_sources: Optional[Dict[str, Optional[str]]] = None


# =============================================================================
# Tag Reading/Writing Models
# =============================================================================

class ReadTagsRequest(BaseModel):
    """Request to read tags from a file."""
    file_path: str


class WriteTagsRequest(BaseModel):
    """Request to write tags to a file."""
    file_path: str
    tags: Dict[str, Any]
    overwrite: bool = True


class TagsResponse(BaseModel):
    """Response with file tags."""
    file_path: str
    tags: Dict[str, Any]


# =============================================================================
# Checkpoint Models
# =============================================================================

class CheckpointInfo(BaseModel):
    """Information about a training checkpoint."""
    session_id: str
    training_dir: str
    samples_processed: int
    total_files: int
    selected_tags: SelectedTags
    last_updated: datetime
    can_resume: bool = True
