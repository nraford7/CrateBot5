"""
Feature Configuration Tracking for CrateBot4

Ensures feature vector consistency between training and tagging by tracking
which optional feature extractors were used during model training.

Prevents dimension mismatch crashes when PANNs/CLAP/Jamendo availability changes.
"""

import logging
from dataclasses import dataclass, field
from datetime import datetime
from typing import Optional

import numpy as np

from .constants import CACHE_VERSION

logger = logging.getLogger(__name__)


class FeatureDimensionMismatchError(Exception):
    """Raised when feature vector dimensions don't match model expectations."""

    def __init__(self, expected: int, actual: int, config: 'FeatureConfig'):
        self.expected = expected
        self.actual = actual
        self.config = config

        message = (
            f"Feature dimension mismatch: model expects {expected} features, "
            f"but got {actual}. "
            f"Model was trained with: PANNs={config.has_panns}, "
            f"CLAP={config.has_clap}, Jamendo={config.has_jamendo}. "
            f"Check that the same feature extractors are available."
        )
        super().__init__(message)


@dataclass
class FeatureConfig:
    """
    Feature vector configuration - ensures train/tag compatibility.

    Tracks which optional feature extractors were used during training
    to prevent dimension mismatches during tagging.
    """
    # Base feature counts (always present)
    base_features: int = 57     # librosa features (MFCC, spectral, etc.)
    essentia_features: int = 8  # Essentia high-level features

    # Optional feature counts
    panns_features: int = 32    # PANNs sound detection scores
    clap_features: int = 32     # CLAP semantic embeddings
    jamendo_features: int = 56  # Jamendo mood predictions (actually 55 + 1 status)

    # Which optional extractors were available during training
    has_panns: bool = False
    has_clap: bool = False
    has_jamendo: bool = False

    # Metadata
    cache_version: int = CACHE_VERSION
    created_at: str = field(default_factory=lambda: datetime.now().isoformat())

    def total_features(self) -> int:
        """Calculate expected feature vector dimension."""
        total = self.base_features + self.essentia_features

        # Optional features are always included in the vector,
        # but may be zeros if extractor wasn't available
        total += self.panns_features
        total += self.clap_features
        total += self.jamendo_features

        return total

    def validate_vector(self, feature_vector: np.ndarray) -> None:
        """
        Validate feature vector matches expected dimensions.

        Raises:
            FeatureDimensionMismatchError: If dimensions don't match
        """
        expected = self.total_features()
        actual = len(feature_vector) if feature_vector is not None else 0

        if actual != expected:
            raise FeatureDimensionMismatchError(expected, actual, self)

    def is_compatible_with(self, other: 'FeatureConfig') -> bool:
        """
        Check if another config is compatible with this one.

        Compatible means the feature vectors will have the same dimensions.
        """
        return self.total_features() == other.total_features()

    def get_compatibility_warnings(self, other: 'FeatureConfig') -> list:
        """
        Get list of compatibility warnings when comparing configs.

        Returns list of warning messages for user display.
        """
        warnings = []

        if self.has_panns and not other.has_panns:
            warnings.append(
                "Model was trained with PANNs but it's not currently available. "
                "Install with: pip install panns-inference torch"
            )

        if self.has_clap and not other.has_clap:
            warnings.append(
                "Model was trained with CLAP but it's not currently available. "
                "Install with: pip install msclap"
            )

        if self.has_jamendo and not other.has_jamendo:
            warnings.append(
                "Model was trained with Jamendo classifier but it's not available. "
                "Run: python -m python.src.core.jamendo_trainer train"
            )

        if self.cache_version != other.cache_version:
            warnings.append(
                f"Cache version mismatch: model={self.cache_version}, "
                f"current={other.cache_version}. Feature cache may need clearing."
            )

        return warnings

    def to_dict(self) -> dict:
        """Convert to dictionary for serialization."""
        return {
            'base_features': self.base_features,
            'essentia_features': self.essentia_features,
            'panns_features': self.panns_features,
            'clap_features': self.clap_features,
            'jamendo_features': self.jamendo_features,
            'has_panns': self.has_panns,
            'has_clap': self.has_clap,
            'has_jamendo': self.has_jamendo,
            'cache_version': self.cache_version,
            'created_at': self.created_at,
        }

    @classmethod
    def from_dict(cls, data: dict) -> 'FeatureConfig':
        """Create from dictionary (deserialization)."""
        return cls(
            base_features=data.get('base_features', 57),
            essentia_features=data.get('essentia_features', 8),
            panns_features=data.get('panns_features', 32),
            clap_features=data.get('clap_features', 32),
            jamendo_features=data.get('jamendo_features', 56),
            has_panns=data.get('has_panns', False),
            has_clap=data.get('has_clap', False),
            has_jamendo=data.get('has_jamendo', False),
            cache_version=data.get('cache_version', CACHE_VERSION),
            created_at=data.get('created_at', datetime.now().isoformat()),
        )

    @classmethod
    def from_current_environment(cls) -> 'FeatureConfig':
        """
        Create a FeatureConfig reflecting the current environment.

        Detects which optional feature extractors are available.
        """
        # Check PANNs availability
        try:
            from .panns_analyzer import is_panns_available
            has_panns = is_panns_available()
        except ImportError:
            has_panns = False

        # Check CLAP availability
        try:
            from .clap_analyzer import is_clap_available
            has_clap = is_clap_available()
        except ImportError:
            has_clap = False

        # Check Jamendo availability
        try:
            from .jamendo_classifier import is_jamendo_available
            has_jamendo = is_jamendo_available()
        except ImportError:
            has_jamendo = False

        return cls(
            has_panns=has_panns,
            has_clap=has_clap,
            has_jamendo=has_jamendo,
        )


def validate_model_compatibility(model_config: Optional[FeatureConfig]) -> list:
    """
    Validate that the current environment is compatible with a model's config.

    Args:
        model_config: FeatureConfig from a loaded model, or None

    Returns:
        List of warning messages (empty if fully compatible)
    """
    if model_config is None:
        return ["Model has no feature configuration metadata. Cannot validate compatibility."]

    current_config = FeatureConfig.from_current_environment()
    return model_config.get_compatibility_warnings(current_config)
