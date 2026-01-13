"""
Custom exceptions for CrateBot.

This module provides specific exception classes for different error conditions,
enabling precise error handling and clearer debugging.
"""


class CrateBotError(Exception):
    """Base exception for all CrateBot errors."""
    pass


# Backward compatibility alias
AudioTaggerError = CrateBotError


# =============================================================================
# Audio Analysis Exceptions
# =============================================================================

class AudioAnalysisError(CrateBotError):
    """Error during audio feature extraction."""
    pass


class AudioLoadError(AudioAnalysisError):
    """Error loading audio file."""
    pass


class FeatureExtractionError(AudioAnalysisError):
    """Error extracting a specific audio feature."""

    def __init__(self, feature_name: str, message: str = None):
        self.feature_name = feature_name
        msg = f"Failed to extract '{feature_name}'"
        if message:
            msg += f": {message}"
        super().__init__(msg)


# =============================================================================
# Model Exceptions
# =============================================================================

class ModelError(CrateBotError):
    """Base exception for model-related errors."""
    pass


class ModelNotLoadedError(ModelError):
    """Attempted prediction without a loaded model."""
    pass


class ModelLoadError(ModelError):
    """Error loading a model from disk."""
    pass


class ModelIntegrityError(ModelError):
    """Model failed integrity verification."""

    def __init__(self, expected_hash: str = None, actual_hash: str = None):
        self.expected_hash = expected_hash
        self.actual_hash = actual_hash
        msg = "Model integrity check failed"
        if expected_hash and actual_hash:
            msg += f". Expected {expected_hash[:16]}..., got {actual_hash[:16]}..."
        super().__init__(msg)


class InsufficientTrainingDataError(ModelError):
    """Not enough training data provided."""

    def __init__(self, required: int, provided: int):
        self.required = required
        self.provided = provided
        super().__init__(
            f"Insufficient training data. Required: {required}, provided: {provided}"
        )


class FeatureDimensionMismatchError(ModelError):
    """Feature vector dimensions don't match model expectations."""

    def __init__(self, expected: int, actual: int, config: object = None):
        self.expected = expected
        self.actual = actual
        self.config = config

        msg = f"Feature dimension mismatch: model expects {expected} features, but got {actual}."
        if config:
            msg += (
                f" Model was trained with: PANNs={getattr(config, 'has_panns', '?')}, "
                f"CLAP={getattr(config, 'has_clap', '?')}, "
                f"Jamendo={getattr(config, 'has_jamendo', '?')}."
            )
        super().__init__(msg)


# =============================================================================
# Tag Management Exceptions
# =============================================================================

class TagError(CrateBotError):
    """Base exception for tag-related errors."""
    pass


class TagReadError(TagError):
    """Error reading ID3 tags from a file."""
    pass


class TagWriteError(TagError):
    """Error writing ID3 tags to a file."""
    pass


# =============================================================================
# Cache Exceptions
# =============================================================================

class CacheError(CrateBotError):
    """Base exception for cache-related errors."""
    pass


class CacheReadError(CacheError):
    """Error reading from the feature cache."""
    pass


class CacheWriteError(CacheError):
    """Error writing to the feature cache."""
    pass


class CacheCorruptedError(CacheError):
    """Cache data is corrupted or incompatible."""
    pass


# =============================================================================
# API/External Service Exceptions
# =============================================================================

class ExternalServiceError(CrateBotError):
    """Error from an external service (API, etc.)."""
    pass


class APIError(ExternalServiceError):
    """Error from an API call."""
    pass


class APIKeyMissingError(APIError):
    """API key is missing or not configured."""

    def __init__(self, service_name: str):
        self.service_name = service_name
        super().__init__(f"API key not configured for {service_name}")


class APIRateLimitError(APIError):
    """API rate limit exceeded."""
    pass


# =============================================================================
# Validation Exceptions
# =============================================================================

class ValidationError(CrateBotError):
    """Invalid input provided."""
    pass


class FileNotFoundValidationError(ValidationError):
    """File does not exist."""
    pass


class InvalidFileTypeError(ValidationError):
    """File type is not supported."""

    def __init__(self, file_path: str, expected_types: list):
        self.file_path = file_path
        self.expected_types = expected_types
        super().__init__(
            f"Invalid file type for '{file_path}'. Expected: {expected_types}"
        )
