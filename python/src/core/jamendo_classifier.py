"""
Jamendo Auxiliary Classifier for CrateBot

Provides 56 mood/theme predictions trained on the MTG-Jamendo dataset (55K tracks).
These predictions are used as additional features for the main tagging model,
adding structured semantic information from a large external dataset.

The classifiers use CLAP embeddings as input features, making them efficient
and consistent with the rest of the feature extraction pipeline.

Reference: MTG-Jamendo Dataset (2019)
https://github.com/MTG/mtg-jamendo-dataset
"""

import logging
import os
import json
from pathlib import Path
from typing import Dict, Any, Optional, Callable, List
import numpy as np

from .paths import get_cratebot_dir

logger = logging.getLogger(__name__)

# Optional imports
try:
    import joblib
    HAS_JOBLIB = True
except ImportError:
    HAS_JOBLIB = False

# Jamendo mood/theme tags (56 total)
# These are the tags from the MTG-Jamendo dataset mood/theme subset
JAMENDO_TAGS = [
    'action', 'adventure', 'advertising', 'background', 'ballad', 'calm',
    'children', 'christmas', 'commercial', 'cool', 'corporate', 'dark',
    'deep', 'documentary', 'dramatic', 'dream', 'emotional', 'energetic',
    'epic', 'fast', 'film', 'fun', 'funny', 'game', 'groovy', 'happy',
    'heavy', 'holiday', 'hopeful', 'inspiring', 'love', 'meditative',
    'melancholic', 'melodic', 'motivational', 'movie', 'nature', 'party',
    'positive', 'powerful', 'relaxing', 'retro', 'romantic', 'sad', 'sexy',
    'slow', 'soft', 'soundscape', 'space', 'sport', 'summer', 'trailer',
    'travel', 'upbeat', 'uplifting'
]

# Feature count = number of tags
JAMENDO_FEATURE_COUNT = len(JAMENDO_TAGS)  # 56

# Model filename
CLASSIFIERS_FILENAME = "jamendo_classifiers.pkl"
METADATA_FILENAME = "jamendo_metadata.json"


class JamendoModelManager:
    """
    Handles Jamendo classifier storage and path management.

    Classifiers are stored in ~/.cratebot/jamendo_models/
    """

    def __init__(self, models_dir: Optional[str] = None):
        if models_dir:
            self.models_dir = Path(models_dir)
        else:
            self.models_dir = get_cratebot_dir() / "jamendo_models"

    def get_classifiers_path(self) -> Path:
        """Get the local path for the trained classifiers."""
        return self.models_dir / CLASSIFIERS_FILENAME

    def get_metadata_path(self) -> Path:
        """Get the local path for classifier metadata."""
        return self.models_dir / METADATA_FILENAME

    def is_model_available(self) -> bool:
        """Check if trained classifiers exist locally."""
        return self.get_classifiers_path().exists()

    def save_classifiers(self, classifiers: Dict, metadata: Dict) -> bool:
        """
        Save trained classifiers and metadata.

        Args:
            classifiers: Dict mapping tag name to trained classifier
            metadata: Training metadata (accuracy, etc.)

        Returns:
            True if successful
        """
        try:
            self.models_dir.mkdir(parents=True, exist_ok=True)

            # Save classifiers
            joblib.dump(classifiers, self.get_classifiers_path())

            # Save metadata
            with open(self.get_metadata_path(), 'w') as f:
                json.dump(metadata, f, indent=2)

            logger.info("Saved Jamendo classifiers to %s", self.models_dir)
            return True

        except Exception as e:
            logger.error("Failed to save Jamendo classifiers: %s", e)
            return False

    def load_classifiers(self) -> Optional[Dict]:
        """Load trained classifiers from disk."""
        if not self.is_model_available():
            return None

        try:
            return joblib.load(self.get_classifiers_path())
        except Exception as e:
            logger.error("Failed to load Jamendo classifiers: %s", e)
            return None

    def load_metadata(self) -> Optional[Dict]:
        """Load classifier metadata."""
        metadata_path = self.get_metadata_path()
        if not metadata_path.exists():
            return None

        try:
            with open(metadata_path, 'r') as f:
                return json.load(f)
        except Exception as e:
            logger.error("Failed to load Jamendo metadata: %s", e)
            return None


class JamendoClassifier:
    """
    Predict Jamendo mood/theme tags from CLAP embeddings.

    Uses pre-trained classifiers (trained via JamendoTrainer) to predict
    56 mood/theme probabilities, which are used as features for the main model.
    """

    def __init__(self, models_dir: Optional[str] = None, auto_load: bool = True):
        """
        Initialize the Jamendo classifier.

        Args:
            models_dir: Custom directory for model storage
            auto_load: Whether to load classifiers immediately if available
        """
        self.model_manager = JamendoModelManager(models_dir)
        self.classifiers = None
        self.metadata = None

        if auto_load and self.is_available():
            self._load_classifiers()

    def is_available(self) -> bool:
        """Check if Jamendo classifiers are available."""
        return HAS_JOBLIB and self.model_manager.is_model_available()

    def get_status(self) -> str:
        """Get human-readable status."""
        if not HAS_JOBLIB:
            return "joblib not installed"
        if not self.model_manager.is_model_available():
            return "Classifiers not trained (run: cratebot train-jamendo)"
        if self.classifiers is None:
            return "Classifiers not loaded"
        return f"Available ({len(self.classifiers)} tags)"

    def _load_classifiers(self) -> bool:
        """Load trained classifiers into memory."""
        if not self.is_available():
            return False

        try:
            self.classifiers = self.model_manager.load_classifiers()
            self.metadata = self.model_manager.load_metadata()

            if self.classifiers is None:
                return False

            logger.info("Loaded Jamendo classifiers for %d tags", len(self.classifiers))
            return True

        except Exception as e:
            logger.error("Failed to load Jamendo classifiers: %s", e)
            self.classifiers = None
            return False

    def predict(self, clap_embedding: np.ndarray) -> Dict[str, float]:
        """
        Predict Jamendo tag probabilities from a CLAP embedding.

        Args:
            clap_embedding: 512-dimensional CLAP embedding

        Returns:
            Dict mapping tag name to probability (0-1)
        """
        if self.classifiers is None:
            if not self._load_classifiers():
                return {tag: 0.5 for tag in JAMENDO_TAGS}

        predictions = {}
        embedding_2d = clap_embedding.reshape(1, -1)

        for tag in JAMENDO_TAGS:
            if tag in self.classifiers:
                clf = self.classifiers[tag]
                try:
                    # Get probability of positive class
                    proba = clf.predict_proba(embedding_2d)[0]
                    # Handle both binary (2 classes) and edge cases
                    if len(proba) >= 2:
                        predictions[tag] = float(proba[1])
                    else:
                        predictions[tag] = float(proba[0])
                except Exception as e:
                    logger.debug("Prediction failed for tag '%s': %s", tag, e)
                    predictions[tag] = 0.5
            else:
                predictions[tag] = 0.5

        return predictions

    def predict_from_features(self, features: Dict[str, Any]) -> Dict[str, float]:
        """
        Predict Jamendo tags from a features dict containing CLAP embedding.

        Args:
            features: Dict with 'clap_embedding' key

        Returns:
            Dict mapping tag name to probability
        """
        clap_embedding = features.get('clap_embedding')

        if clap_embedding is None:
            return {tag: 0.5 for tag in JAMENDO_TAGS}

        return self.predict(clap_embedding)

    def extract_features(self, audio_path: str, features: Dict[str, Any]) -> Dict[str, Any]:
        """
        Extract Jamendo features for integration with AudioAnalyzer.

        Uses CLAP embedding from features dict to predict tag probabilities.

        Args:
            audio_path: Path to audio file (not used, for API consistency)
            features: Dict containing 'clap_embedding'

        Returns:
            Dict with jamendo predictions
        """
        predictions = self.predict_from_features(features)

        result = {
            'jamendo_available': self.classifiers is not None,
        }

        # Add each tag prediction
        for tag in JAMENDO_TAGS:
            result[f'jamendo_{tag}'] = predictions.get(tag, 0.5)

        return result

    def _get_default_features(self) -> Dict[str, Any]:
        """Return default features when Jamendo classifiers are not available."""
        features = {
            'jamendo_available': False,
        }

        # Add default predictions (0.5 = neutral)
        for tag in JAMENDO_TAGS:
            features[f'jamendo_{tag}'] = 0.5

        return features

    def get_feature_vector(self, features: Dict[str, Any]) -> np.ndarray:
        """
        Extract Jamendo portion of feature vector from features dict.

        Returns array of shape (JAMENDO_FEATURE_COUNT,) = (56,)
        """
        vector = []

        for tag in JAMENDO_TAGS:
            vector.append(float(features.get(f'jamendo_{tag}', 0.5)))

        return np.array(vector, dtype=np.float32)

    def get_top_predictions(
        self,
        features: Dict[str, Any],
        top_k: int = 10,
        threshold: float = 0.5
    ) -> List[tuple]:
        """
        Get top Jamendo tag predictions from features.

        Args:
            features: Dict with jamendo_* keys
            top_k: Maximum number of tags to return
            threshold: Minimum probability threshold

        Returns:
            List of (tag, probability) tuples, sorted by probability
        """
        predictions = []

        for tag in JAMENDO_TAGS:
            prob = features.get(f'jamendo_{tag}', 0.0)
            if prob >= threshold:
                predictions.append((tag, prob))

        predictions.sort(key=lambda x: x[1], reverse=True)
        return predictions[:top_k]

    def format_predictions(self, features: Dict[str, Any], threshold: float = 0.6) -> str:
        """
        Format Jamendo predictions as readable string.

        Args:
            features: Dict with jamendo_* keys
            threshold: Minimum probability to include

        Returns:
            Formatted string like "happy, energetic, upbeat"
        """
        top_tags = self.get_top_predictions(features, top_k=5, threshold=threshold)
        if not top_tags:
            return "No strong predictions"
        return ", ".join(tag for tag, _ in top_tags)


def is_jamendo_available() -> bool:
    """Quick check if Jamendo classifiers can be used."""
    manager = JamendoModelManager()
    return HAS_JOBLIB and manager.is_model_available()


def get_jamendo_status() -> str:
    """Get human-readable Jamendo status."""
    if not HAS_JOBLIB:
        return "joblib not installed"

    manager = JamendoModelManager()
    if not manager.is_model_available():
        return "Classifiers not trained (run: cratebot train-jamendo)"

    metadata = manager.load_metadata()
    if metadata:
        return f"Available ({metadata.get('num_tags', 56)} tags, trained {metadata.get('trained_date', 'unknown')})"

    return "Available"
