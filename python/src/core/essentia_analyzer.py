"""
Essentia Pre-trained Model Integration for CrateBot

Extracts high-level semantic audio features using Essentia's pre-trained
TensorFlow models. Features include mood (happy, sad, aggressive, relaxed),
danceability, voice/instrumental detection, and arousal/valence.

These features complement the low-level librosa features for improved
tag prediction accuracy.
"""

import os
import urllib.request
import ssl
from pathlib import Path
from typing import Dict, Any, Optional, List, Callable
import numpy as np

from .paths import get_cratebot_dir
# Optional Essentia import with graceful degradation
try:
    from essentia.standard import MonoLoader, TensorflowPredictMusiCNN, TensorflowPredict2D
    HAS_ESSENTIA = True
except ImportError:
    HAS_ESSENTIA = False

# Constants
ESSENTIA_SAMPLE_RATE = 16000  # Required for MusiCNN models
ESSENTIA_FEATURE_COUNT = 8   # Number of features added to vector

# Model configuration
MODEL_BASE_URL = "https://essentia.upf.edu/models"

MODEL_CONFIGS = {
    'musicnn_embedding': {
        'url': f"{MODEL_BASE_URL}/feature-extractors/musicnn/msd-musicnn-1.pb",
        'filename': 'msd-musicnn-1.pb',
        'output_layer': 'model/dense/BiasAdd',
    },
    'mood_happy': {
        'url': f"{MODEL_BASE_URL}/classification-heads/mood_happy/mood_happy-msd-musicnn-1.pb",
        'filename': 'mood_happy-msd-musicnn-1.pb',
    },
    'mood_sad': {
        'url': f"{MODEL_BASE_URL}/classification-heads/mood_sad/mood_sad-msd-musicnn-1.pb",
        'filename': 'mood_sad-msd-musicnn-1.pb',
    },
    'mood_aggressive': {
        'url': f"{MODEL_BASE_URL}/classification-heads/mood_aggressive/mood_aggressive-msd-musicnn-1.pb",
        'filename': 'mood_aggressive-msd-musicnn-1.pb',
    },
    'mood_relaxed': {
        'url': f"{MODEL_BASE_URL}/classification-heads/mood_relaxed/mood_relaxed-msd-musicnn-1.pb",
        'filename': 'mood_relaxed-msd-musicnn-1.pb',
    },
    'danceability': {
        'url': f"{MODEL_BASE_URL}/classification-heads/danceability/danceability-msd-musicnn-1.pb",
        'filename': 'danceability-msd-musicnn-1.pb',
    },
    'voice_instrumental': {
        'url': f"{MODEL_BASE_URL}/classification-heads/voice_instrumental/voice_instrumental-msd-musicnn-1.pb",
        'filename': 'voice_instrumental-msd-musicnn-1.pb',
    },
    'arousal_valence': {
        'url': f"{MODEL_BASE_URL}/classification-heads/emomusic/emomusic-msd-musicnn-2.pb",
        'filename': 'emomusic-msd-musicnn-2.pb',
    },
}


class EssentiaModelManager:
    """
    Handles Essentia model downloading and path management.

    Models are stored in ~/.cratebot/essentia_models/
    """

    def __init__(self, models_dir: Optional[str] = None):
        """
        Initialize the model manager.

        Args:
            models_dir: Custom directory for models. Defaults to ~/.cratebot/essentia_models/
        """
        if models_dir:
            self.models_dir = Path(models_dir)
        else:
            self.models_dir = get_cratebot_dir() / "essentia_models"

    def get_model_path(self, model_name: str) -> Path:
        """Get the local path for a model file."""
        config = MODEL_CONFIGS.get(model_name, {})
        filename = config.get('filename', f'{model_name}.pb')
        return self.models_dir / filename

    def is_model_available(self, model_name: str) -> bool:
        """Check if a model file exists locally."""
        return self.get_model_path(model_name).exists()

    def all_models_available(self) -> bool:
        """Check if all required models are downloaded."""
        return all(self.is_model_available(name) for name in MODEL_CONFIGS.keys())

    def get_missing_models(self) -> List[str]:
        """Get list of models that need to be downloaded."""
        return [name for name in MODEL_CONFIGS.keys() if not self.is_model_available(name)]

    def get_total_download_size_mb(self) -> float:
        """Estimate total download size in MB."""
        # Approximate sizes based on typical MusiCNN models
        return 85.0  # ~85MB total for all models

    def download_models(self, progress_callback: Optional[Callable[[str, int, int], None]] = None) -> bool:
        """
        Download all missing models.

        Args:
            progress_callback: Optional callback(model_name, current, total) for progress updates

        Returns:
            True if all models downloaded successfully
        """
        missing = self.get_missing_models()
        if not missing:
            return True

        # Create models directory
        self.models_dir.mkdir(parents=True, exist_ok=True)

        # Create SSL context that doesn't verify (for macOS certificate issues)
        ssl_context = ssl.create_default_context()
        ssl_context.check_hostname = False
        ssl_context.verify_mode = ssl.CERT_NONE

        total = len(missing)
        for idx, model_name in enumerate(missing):
            if progress_callback:
                progress_callback(model_name, idx + 1, total)

            config = MODEL_CONFIGS[model_name]
            url = config['url']
            dest_path = self.get_model_path(model_name)

            try:
                # Download with SSL context
                print(f"Downloading {model_name}...")
                req = urllib.request.Request(url, headers={'User-Agent': 'CrateBot/1.0'})
                with urllib.request.urlopen(req, context=ssl_context) as response:
                    with open(dest_path, 'wb') as out_file:
                        out_file.write(response.read())
                print(f"  Saved to {dest_path}")
            except Exception as e:
                print(f"Error downloading {model_name}: {e}")
                # Clean up partial download
                if dest_path.exists():
                    dest_path.unlink()
                return False

        return True

    def clear_models(self) -> int:
        """
        Remove all downloaded models.

        Returns:
            Number of models removed
        """
        count = 0
        for model_name in MODEL_CONFIGS.keys():
            path = self.get_model_path(model_name)
            if path.exists():
                path.unlink()
                count += 1
        return count


class EssentiaAnalyzer:
    """
    Extract high-level audio features using Essentia pre-trained models.

    Features extracted:
    - Mood: happy, sad, aggressive, relaxed (0-1 probability each)
    - Danceability: 0-1 probability
    - Voice/Instrumental: 0-1 (1 = voice, 0 = instrumental)
    - Arousal: 1-9 scale (energy/intensity)
    - Valence: 1-9 scale (positive/negative mood)

    When Essentia is not available, returns default neutral values.
    """

    # Default values when Essentia unavailable or extraction fails
    DEFAULT_FEATURES = {
        'essentia_mood_happy': 0.5,
        'essentia_mood_sad': 0.5,
        'essentia_mood_aggressive': 0.5,
        'essentia_mood_relaxed': 0.5,
        'essentia_danceability': 0.5,
        'essentia_voice_instrumental': 0.5,
        'essentia_arousal': 5.0,  # Middle of 1-9 scale
        'essentia_valence': 5.0,  # Middle of 1-9 scale
    }

    def __init__(self, models_dir: Optional[str] = None, auto_load: bool = True):
        """
        Initialize the Essentia analyzer.

        Args:
            models_dir: Custom directory for models
            auto_load: Whether to automatically load models if available
        """
        self.model_manager = EssentiaModelManager(models_dir)
        self._models_loaded = False
        self._embedding_model = None
        self._classifier_models = {}

        if auto_load and self.is_available:
            self._load_models()

    @property
    def is_available(self) -> bool:
        """Check if Essentia analysis is available."""
        return HAS_ESSENTIA and self.model_manager.all_models_available()

    @property
    def is_essentia_installed(self) -> bool:
        """Check if essentia-tensorflow package is installed."""
        return HAS_ESSENTIA

    @property
    def are_models_downloaded(self) -> bool:
        """Check if all models are downloaded."""
        return self.model_manager.all_models_available()

    def _load_models(self) -> bool:
        """Load all Essentia models into memory."""
        if not HAS_ESSENTIA:
            return False

        if not self.model_manager.all_models_available():
            return False

        if self._models_loaded:
            return True

        try:
            # Load embedding model
            embedding_path = str(self.model_manager.get_model_path('musicnn_embedding'))
            self._embedding_model = TensorflowPredictMusiCNN(
                graphFilename=embedding_path,
                output='model/dense/BiasAdd'
            )

            # Load classifier models
            classifier_names = [
                'mood_happy', 'mood_sad', 'mood_aggressive', 'mood_relaxed',
                'danceability', 'voice_instrumental', 'arousal_valence'
            ]

            for name in classifier_names:
                model_path = str(self.model_manager.get_model_path(name))
                self._classifier_models[name] = TensorflowPredict2D(
                    graphFilename=model_path,
                    output='model/Softmax' if name != 'arousal_valence' else 'model/Identity'
                )

            self._models_loaded = True
            return True

        except Exception as e:
            print(f"Error loading Essentia models: {e}")
            self._models_loaded = False
            return False

    def extract_features(self, audio_path: str) -> Dict[str, Any]:
        """
        Extract Essentia features from an audio file.

        Args:
            audio_path: Path to the audio file

        Returns:
            Dictionary with feature names and values
        """
        if not self.is_available:
            features = self._get_default_features()
            features['essentia_available'] = False
            features['essentia_status'] = 'not_installed' if not HAS_ESSENTIA else 'models_missing'
            return features

        # Ensure models are loaded
        if not self._models_loaded:
            if not self._load_models():
                features = self._get_default_features()
                features['essentia_available'] = False
                features['essentia_status'] = 'load_failed'
                return features

        try:
            # Load audio at 16kHz for MusiCNN
            audio = MonoLoader(filename=audio_path, sampleRate=ESSENTIA_SAMPLE_RATE)()

            # Get MusiCNN embeddings
            embeddings = self._embedding_model(audio)

            # Run mood classifiers
            features = {}

            # Mood Happy (probability of "happy" class)
            happy_pred = self._classifier_models['mood_happy'](embeddings)
            features['essentia_mood_happy'] = float(np.mean(happy_pred[:, 0]))

            # Mood Sad
            sad_pred = self._classifier_models['mood_sad'](embeddings)
            features['essentia_mood_sad'] = float(np.mean(sad_pred[:, 0]))

            # Mood Aggressive
            aggressive_pred = self._classifier_models['mood_aggressive'](embeddings)
            features['essentia_mood_aggressive'] = float(np.mean(aggressive_pred[:, 0]))

            # Mood Relaxed
            relaxed_pred = self._classifier_models['mood_relaxed'](embeddings)
            features['essentia_mood_relaxed'] = float(np.mean(relaxed_pred[:, 0]))

            # Danceability
            dance_pred = self._classifier_models['danceability'](embeddings)
            features['essentia_danceability'] = float(np.mean(dance_pred[:, 0]))

            # Voice/Instrumental (1 = voice, 0 = instrumental)
            voice_pred = self._classifier_models['voice_instrumental'](embeddings)
            features['essentia_voice_instrumental'] = float(np.mean(voice_pred[:, 0]))

            # Arousal/Valence (regression, outputs 2 values)
            av_pred = self._classifier_models['arousal_valence'](embeddings)
            # Average across time frames
            av_mean = np.mean(av_pred, axis=0)
            features['essentia_arousal'] = float(av_mean[0]) if len(av_mean) > 0 else 5.0
            features['essentia_valence'] = float(av_mean[1]) if len(av_mean) > 1 else 5.0

            # Clamp arousal/valence to expected range [1, 9]
            features['essentia_arousal'] = max(1.0, min(9.0, features['essentia_arousal']))
            features['essentia_valence'] = max(1.0, min(9.0, features['essentia_valence']))

            features['essentia_available'] = True
            features['essentia_status'] = 'ok'

            return features

        except Exception as e:
            print(f"Warning: Essentia feature extraction failed for {audio_path}: {e}")
            features = self._get_default_features()
            features['essentia_available'] = False
            features['essentia_status'] = f'extraction_failed: {str(e)}'
            return features

    def _get_default_features(self) -> Dict[str, Any]:
        """Get default feature values."""
        return self.DEFAULT_FEATURES.copy()

    def get_feature_vector(self, features: Dict[str, Any]) -> np.ndarray:
        """
        Convert Essentia features to a normalized numpy array for the feature vector.

        All values are normalized to 0-1 range.

        Args:
            features: Dictionary of Essentia features

        Returns:
            numpy array of 8 float values
        """
        return np.array([
            features.get('essentia_mood_happy', 0.5),
            features.get('essentia_mood_sad', 0.5),
            features.get('essentia_mood_aggressive', 0.5),
            features.get('essentia_mood_relaxed', 0.5),
            features.get('essentia_danceability', 0.5),
            features.get('essentia_voice_instrumental', 0.5),
            features.get('essentia_arousal', 5.0) / 9.0,  # Normalize 1-9 to ~0-1
            features.get('essentia_valence', 5.0) / 9.0,  # Normalize 1-9 to ~0-1
        ], dtype=np.float32)

    def download_models(self, progress_callback: Optional[Callable[[str, int, int], None]] = None) -> bool:
        """
        Download Essentia models.

        Args:
            progress_callback: Optional callback(model_name, current, total)

        Returns:
            True if successful
        """
        return self.model_manager.download_models(progress_callback)

    def get_status(self) -> Dict[str, Any]:
        """Get detailed status information."""
        return {
            'essentia_installed': HAS_ESSENTIA,
            'models_downloaded': self.model_manager.all_models_available(),
            'models_loaded': self._models_loaded,
            'missing_models': self.model_manager.get_missing_models(),
            'models_dir': str(self.model_manager.models_dir),
            'is_available': self.is_available,
        }


def is_essentia_available() -> bool:
    """Quick check if Essentia analysis is available."""
    if not HAS_ESSENTIA:
        return False
    manager = EssentiaModelManager()
    return manager.all_models_available()


def get_essentia_status() -> str:
    """Get human-readable Essentia status string."""
    if not HAS_ESSENTIA:
        return "Not installed (pip install essentia-tensorflow)"
    manager = EssentiaModelManager()
    if manager.all_models_available():
        return "Available"
    missing = len(manager.get_missing_models())
    return f"Models needed ({missing} to download)"
