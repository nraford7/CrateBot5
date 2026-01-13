"""
Input validation utilities for Audio Tagger.

Provides validation functions for common inputs at API boundaries.
"""

import os
from pathlib import Path
from typing import Optional, List


class ValidationError(Exception):
    """Invalid input provided to Audio Tagger."""
    pass


def validate_directory(path: str, must_exist: bool = True) -> Path:
    """
    Validate a directory path.

    Args:
        path: Directory path to validate
        must_exist: If True, directory must exist

    Returns:
        Validated Path object

    Raises:
        ValidationError: If validation fails
    """
    if not path:
        raise ValidationError("Directory path cannot be empty")

    p = Path(path).expanduser().resolve()

    if must_exist:
        if not p.exists():
            raise ValidationError(f"Directory does not exist: {path}")
        if not p.is_dir():
            raise ValidationError(f"Path is not a directory: {path}")

    return p


def validate_file(
    path: str,
    extensions: Optional[List[str]] = None,
    must_exist: bool = True
) -> Path:
    """
    Validate a file path.

    Args:
        path: File path to validate
        extensions: Optional list of allowed extensions (e.g., ['.mp3', '.wav'])
        must_exist: If True, file must exist

    Returns:
        Validated Path object

    Raises:
        ValidationError: If validation fails
    """
    if not path:
        raise ValidationError("File path cannot be empty")

    p = Path(path).expanduser().resolve()

    if must_exist:
        if not p.exists():
            raise ValidationError(f"File does not exist: {path}")
        if not p.is_file():
            raise ValidationError(f"Path is not a file: {path}")

    if extensions:
        # Normalize extensions to lowercase with leading dot
        normalized_extensions = [
            ext.lower() if ext.startswith('.') else f'.{ext.lower()}'
            for ext in extensions
        ]
        if p.suffix.lower() not in normalized_extensions:
            raise ValidationError(
                f"Invalid file type: {p.suffix}. Expected one of: {extensions}"
            )

    return p


def validate_audio_file(path: str) -> Path:
    """
    Validate an audio file path.

    Args:
        path: Audio file path to validate

    Returns:
        Validated Path object

    Raises:
        ValidationError: If validation fails
    """
    return validate_file(path, extensions=['.mp3', '.wav', '.flac', '.m4a', '.aac', '.ogg'])


def validate_model_path(path: str, must_exist: bool = True) -> Path:
    """
    Validate a model file path.

    Args:
        path: Model file path to validate
        must_exist: If True, model file must exist

    Returns:
        Validated Path object

    Raises:
        ValidationError: If validation fails
    """
    return validate_file(path, extensions=['.pkl'], must_exist=must_exist)


def validate_test_size(value: float) -> float:
    """
    Validate test_size parameter for train/test split.

    Args:
        value: Test size ratio (0.0-1.0)

    Returns:
        Validated test size

    Raises:
        ValidationError: If validation fails
    """
    if not isinstance(value, (int, float)):
        raise ValidationError(f"test_size must be a number, got: {type(value).__name__}")

    if not 0.0 < value < 1.0:
        raise ValidationError(f"test_size must be between 0 and 1 (exclusive), got: {value}")

    return float(value)


def validate_threshold(value: float, name: str = "threshold") -> float:
    """
    Validate a threshold value (0.0-1.0).

    Args:
        value: Threshold value
        name: Name for error messages

    Returns:
        Validated threshold

    Raises:
        ValidationError: If validation fails
    """
    if not isinstance(value, (int, float)):
        raise ValidationError(f"{name} must be a number, got: {type(value).__name__}")

    if not 0.0 <= value <= 1.0:
        raise ValidationError(f"{name} must be between 0 and 1, got: {value}")

    return float(value)


def validate_positive_int(value: int, name: str = "value") -> int:
    """
    Validate a positive integer.

    Args:
        value: Integer value
        name: Name for error messages

    Returns:
        Validated integer

    Raises:
        ValidationError: If validation fails
    """
    if not isinstance(value, int):
        raise ValidationError(f"{name} must be an integer, got: {type(value).__name__}")

    if value <= 0:
        raise ValidationError(f"{name} must be positive, got: {value}")

    return value


def validate_api_key(api_key: Optional[str], name: str = "API key") -> str:
    """
    Validate an API key is present and non-empty.

    Args:
        api_key: API key string
        name: Name for error messages

    Returns:
        Validated API key

    Raises:
        ValidationError: If validation fails
    """
    if not api_key:
        raise ValidationError(f"{name} is required but not provided")

    if not isinstance(api_key, str):
        raise ValidationError(f"{name} must be a string")

    api_key = api_key.strip()
    if not api_key:
        raise ValidationError(f"{name} cannot be empty")

    return api_key
