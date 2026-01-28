"""
CLAP (Contrastive Language-Audio Pretraining) Integration for CrateBot

Extracts 512-dimensional embeddings from the CLAP model trained on
AudioSet + LAION-Audio-630K. These embeddings capture semantic audio
understanding, allowing the model to understand concepts like "dark driving techno"
or "melodic uplifting house" from audio alone.

Reference: LAION-AI CLAP (2023)
https://github.com/LAION-AI/CLAP
"""

import logging
import os
import urllib.request
from pathlib import Path
from typing import Dict, Any, Optional, Callable, List
import numpy as np

from .paths import get_cratebot_dir

logger = logging.getLogger(__name__)

# Scipy compatibility shim for scipy >= 1.13
# laion_clap uses scipy.signal.hann which was moved to scipy.signal.windows.hann
try:
    import scipy.signal
    if not hasattr(scipy.signal, 'hann'):
        from scipy.signal import windows
        scipy.signal.hann = windows.hann
except ImportError:
    pass

# Optional imports with graceful degradation
try:
    import torch
    import librosa
    HAS_TORCH = True
except ImportError:
    HAS_TORCH = False

# CLAP-specific imports
try:
    import laion_clap
    HAS_CLAP = True
except ImportError:
    HAS_CLAP = False

# Constants
CLAP_SAMPLE_RATE = 48000  # Required for CLAP models
CLAP_EMBEDDING_DIM = 512  # CLAP embedding dimension
CLAP_FEATURE_COUNT = 32   # Reduced via statistics (like PANNs)

# Model configuration
# Using the 630k-audioset-best model (best for music understanding)
MODEL_URL = "https://huggingface.co/lukewys/laion_clap/resolve/main/630k-audioset-best.pt"
MODEL_FILENAME = "630k-audioset-best.pt"


class CLAPModelManager:
    """
    Handles CLAP model downloading and path management.

    Models are stored in ~/.cratebot/clap_models/
    """

    def __init__(self, models_dir: Optional[str] = None):
        if models_dir:
            self.models_dir = Path(models_dir)
        else:
            self.models_dir = get_cratebot_dir() / "clap_models"

    def get_model_path(self) -> Path:
        """Get the local path for the CLAP model file."""
        return self.models_dir / MODEL_FILENAME

    def is_model_available(self) -> bool:
        """Check if the model file exists locally."""
        return self.get_model_path().exists()

    def download_model(self, progress_callback: Optional[Callable[[float], None]] = None) -> bool:
        """
        Download the CLAP model.

        Args:
            progress_callback: Optional callback(progress_ratio) for progress updates

        Returns:
            True if successful, False otherwise
        """
        if not HAS_TORCH:
            logger.error("PyTorch not installed. Cannot use CLAP.")
            return False

        self.models_dir.mkdir(parents=True, exist_ok=True)
        model_path = self.get_model_path()

        if model_path.exists():
            return True

        logger.info("Downloading CLAP model (~600MB)...")
        logger.info("  URL: %s", MODEL_URL)
        logger.info("  Destination: %s", model_path)

        try:
            def report_progress(block_num, block_size, total_size):
                if progress_callback and total_size > 0:
                    progress = block_num * block_size / total_size
                    progress_callback(min(1.0, progress))

            urllib.request.urlretrieve(MODEL_URL, str(model_path), reporthook=report_progress)
            logger.info("  Download complete!")
            return True

        except Exception as e:
            logger.error("  Download failed: %s", e)
            if model_path.exists():
                model_path.unlink()
            return False


class CLAPAnalyzer:
    """
    Extract audio embeddings using CLAP model.

    The CLAP model produces 512-dimensional embeddings that capture
    semantic audio understanding. These are reduced via statistics to
    CLAP_FEATURE_COUNT dimensions for efficiency.
    """

    def __init__(self, models_dir: Optional[str] = None, auto_load: bool = True):
        """
        Initialize the CLAP analyzer.

        Args:
            models_dir: Custom directory for model storage
            auto_load: Whether to load model immediately if available
        """
        self.model_manager = CLAPModelManager(models_dir)
        self.model = None
        self.device = None

        if auto_load and self.is_available():
            self._load_model()

    def is_available(self) -> bool:
        """Check if CLAP is available and model is downloaded."""
        return HAS_TORCH and HAS_CLAP and self.model_manager.is_model_available()

    def get_status(self) -> str:
        """Get human-readable status."""
        if not HAS_TORCH:
            return "PyTorch not installed"
        if not HAS_CLAP:
            return "laion-clap not installed (pip install laion-clap)"
        if not self.model_manager.is_model_available():
            return "Model not downloaded"
        if self.model is None:
            return "Model not loaded"
        return "Available"

    def download_model(self, progress_callback: Optional[Callable[[float], None]] = None) -> bool:
        """Download the CLAP model if not present."""
        return self.model_manager.download_model(progress_callback)

    def _load_model(self) -> bool:
        """Load the CLAP model into memory."""
        if not self.is_available():
            return False

        try:
            model_path = str(self.model_manager.get_model_path())

            # Use hardware config for device selection if available
            try:
                from .hardware_config import get_hardware_config
                self.device = get_hardware_config().device
            except ImportError:
                # Fallback: CUDA > MPS (Apple Silicon) > CPU
                if torch.cuda.is_available():
                    self.device = 'cuda'
                elif hasattr(torch.backends, 'mps') and torch.backends.mps.is_available():
                    self.device = 'mps'
                else:
                    self.device = 'cpu'

            # Load CLAP model
            # CLAP expects to load on CPU first, then can be moved
            # 630k-audioset-best.pt uses HTSAT-tiny architecture (768 dim)
            self.model = laion_clap.CLAP_Module(enable_fusion=False, amodel='HTSAT-tiny')
            self.model.load_ckpt(model_path)

            # Move to appropriate device
            if self.device != 'cpu':
                self.model = self.model.to(self.device)

            self.model.eval()

            logger.info("CLAP model loaded on %s", self.device)
            return True

        except Exception as e:
            logger.error("Failed to load CLAP model: %s", e)
            self.model = None
            return False

    def extract_embedding(self, audio_path: str) -> Optional[np.ndarray]:
        """
        Extract the 512-dimensional embedding from an audio file.

        Args:
            audio_path: Path to audio file

        Returns:
            numpy array of shape (512,) or None if extraction fails
        """
        if self.model is None:
            if not self._load_model():
                return None

        try:
            # Load audio at CLAP sample rate
            waveform, sr = librosa.load(audio_path, sr=CLAP_SAMPLE_RATE, mono=True, duration=60)

            # CLAP expects a list of audio arrays
            audio_data = [waveform]

            # Get embedding
            with torch.no_grad():
                embedding = self.model.get_audio_embedding_from_data(
                    x=audio_data,
                    use_tensor=False
                )

            # embedding shape is (1, 512), flatten to (512,)
            return embedding.flatten()

        except Exception as e:
            logger.error("CLAP embedding extraction failed for %s: %s", audio_path, e)
            return None

    def get_text_embedding(self, text: str) -> Optional[np.ndarray]:
        """
        Get embedding for a text description (useful for similarity search).

        Args:
            text: Text description like "dark driving techno"

        Returns:
            numpy array of shape (512,) or None if extraction fails
        """
        if self.model is None:
            if not self._load_model():
                return None

        try:
            with torch.no_grad():
                embedding = self.model.get_text_embedding([text], use_tensor=False)
            return embedding.flatten()
        except Exception as e:
            logger.error("CLAP text embedding failed for '%s': %s", text, e)
            return None

    def compute_similarity(self, audio_path: str, descriptions: List[str]) -> Dict[str, float]:
        """
        Compute similarity between audio and text descriptions.

        This is CLAP's superpower - understanding audio in terms of
        natural language descriptions.

        Args:
            audio_path: Path to audio file
            descriptions: List of text descriptions to compare

        Returns:
            Dict mapping description to similarity score (0-1)
        """
        audio_embedding = self.extract_embedding(audio_path)
        if audio_embedding is None:
            return {desc: 0.0 for desc in descriptions}

        results = {}
        for desc in descriptions:
            text_embedding = self.get_text_embedding(desc)
            if text_embedding is not None:
                # Cosine similarity
                similarity = np.dot(audio_embedding, text_embedding) / (
                    np.linalg.norm(audio_embedding) * np.linalg.norm(text_embedding)
                )
                # Convert to 0-1 range (cosine similarity is -1 to 1)
                results[desc] = float((similarity + 1) / 2)
            else:
                results[desc] = 0.0

        return results

    def extract_features(self, audio_path: str) -> Dict[str, Any]:
        """
        Extract CLAP features for integration with AudioAnalyzer.

        Returns a dict with the embedding and reduced features.
        """
        embedding = self.extract_embedding(audio_path)

        if embedding is None:
            return self._get_default_features()

        # Store full embedding and compute statistics for feature vector
        features = {
            'clap_embedding': embedding,
            'clap_available': True,
        }

        # Compute statistics from embedding for the feature vector
        # This reduces 512 dims to CLAP_FEATURE_COUNT dims
        features.update(self._compute_embedding_stats(embedding))

        return features

    def _compute_embedding_stats(self, embedding: np.ndarray) -> Dict[str, float]:
        """
        Compute summary statistics from the CLAP embedding.

        We divide the 512-dim embedding into segments and compute
        statistics, reducing to CLAP_FEATURE_COUNT dimensions.
        """
        stats = {}

        # Divide embedding into 8 segments, compute 4 stats each = 32 features
        segment_size = len(embedding) // 8

        for i in range(8):
            segment = embedding[i * segment_size:(i + 1) * segment_size]
            stats[f'clap_seg{i}_mean'] = float(np.mean(segment))
            stats[f'clap_seg{i}_std'] = float(np.std(segment))
            stats[f'clap_seg{i}_max'] = float(np.max(segment))
            stats[f'clap_seg{i}_energy'] = float(np.sum(segment ** 2) / len(segment))

        return stats

    def _get_default_features(self) -> Dict[str, Any]:
        """Return default features when CLAP is not available."""
        features = {
            'clap_embedding': None,
            'clap_available': False,
        }

        # Add default stats
        for i in range(8):
            features[f'clap_seg{i}_mean'] = 0.0
            features[f'clap_seg{i}_std'] = 0.0
            features[f'clap_seg{i}_max'] = 0.0
            features[f'clap_seg{i}_energy'] = 0.0

        return features

    def get_feature_vector(self, features: Dict[str, Any]) -> np.ndarray:
        """
        Extract CLAP portion of feature vector from features dict.

        Returns array of shape (CLAP_FEATURE_COUNT,) = (32,)
        """
        vector = []

        for i in range(8):
            vector.append(float(features.get(f'clap_seg{i}_mean', 0.0)))
            vector.append(float(features.get(f'clap_seg{i}_std', 0.0)))
            vector.append(float(features.get(f'clap_seg{i}_max', 0.0)))
            vector.append(float(features.get(f'clap_seg{i}_energy', 0.0)))

        return np.array(vector, dtype=np.float32)


def is_clap_available() -> bool:
    """Quick check if CLAP can be used."""
    return HAS_TORCH and HAS_CLAP


def get_clap_status() -> str:
    """Get human-readable CLAP status."""
    if not HAS_TORCH:
        return "PyTorch not installed"
    if not HAS_CLAP:
        return "Not installed (pip install laion-clap)"

    manager = CLAPModelManager()
    if not manager.is_model_available():
        return "Model not downloaded"

    return "Available"
