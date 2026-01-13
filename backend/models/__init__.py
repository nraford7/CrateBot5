# CrateBot API Models
from .schemas import (
    # Training
    TrainingRequest,
    TrainingStatus,
    TrainingProgress,
    TrainingResult,
    SelectedTags,
    DiscoveredTags,
    # Tagging
    TaggingRequest,
    TaggingBatchRequest,
    TaggingResult,
    TagsToWrite,
    PredictedTags,
    # Model
    ModelInfo,
    ModelLoadRequest,
    # Vibe
    VibeRequest,
    VibeBatchRequest,
    VibeResult,
    # Settings
    APIKeyRequest,
    SettingsResponse,
    # Common
    TaskStatus,
    ProgressUpdate,
    FileInfo,
    ErrorResponse,
)

__all__ = [
    "TrainingRequest",
    "TrainingStatus",
    "TrainingProgress",
    "TrainingResult",
    "SelectedTags",
    "DiscoveredTags",
    "TaggingRequest",
    "TaggingBatchRequest",
    "TaggingResult",
    "TagsToWrite",
    "PredictedTags",
    "ModelInfo",
    "ModelLoadRequest",
    "VibeRequest",
    "VibeBatchRequest",
    "VibeResult",
    "APIKeyRequest",
    "SettingsResponse",
    "TaskStatus",
    "ProgressUpdate",
    "FileInfo",
    "ErrorResponse",
]
