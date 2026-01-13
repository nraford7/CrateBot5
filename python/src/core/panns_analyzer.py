"""
PANNs (Pretrained Audio Neural Networks) Integration for CrateBot

Extracts high-dimensional embeddings (2048-dim) from the CNN14 model trained on
AudioSet (2M+ clips). These embeddings capture rich audio semantics and
significantly improve tagging accuracy.

Reference: Kong et al., "PANNs: Large-Scale Pretrained Audio Neural Networks
for Audio Pattern Recognition" (2020)
"""

import logging
import os
import urllib.request
import warnings
from pathlib import Path
from typing import Dict, Any, Optional, Callable, List, Tuple
import numpy as np

from .paths import get_cratebot_dir

logger = logging.getLogger(__name__)

# Optional imports with graceful degradation
try:
    import torch
    import librosa
    HAS_TORCH = True
except ImportError:
    HAS_TORCH = False

# PANNs-specific imports
try:
    from panns_inference import AudioTagging
    HAS_PANNS = True
except ImportError:
    HAS_PANNS = False

# Constants
PANNS_SAMPLE_RATE = 32000  # Required for PANNs models
PANNS_EMBEDDING_DIM = 2048  # CNN14 embedding dimension
PANNS_FEATURE_COUNT = 32    # We'll use PCA to reduce from 2048 to 32 for efficiency

# Model configuration
MODEL_URL = "https://zenodo.org/record/3987831/files/Cnn14_mAP%3D0.431.pth"
MODEL_FILENAME = "Cnn14_mAP=0.431.pth"


class PANNsModelManager:
    """
    Handles PANNs model downloading and path management.

    Models are stored in ~/.cratebot/panns_models/
    """

    def __init__(self, models_dir: Optional[str] = None):
        if models_dir:
            self.models_dir = Path(models_dir)
        else:
            self.models_dir = get_cratebot_dir() / "panns_models"

    def get_model_path(self) -> Path:
        """Get the local path for the PANNs model file."""
        return self.models_dir / MODEL_FILENAME

    def is_model_available(self) -> bool:
        """Check if the model file exists locally."""
        return self.get_model_path().exists()

    def download_model(self, progress_callback: Optional[Callable[[float], None]] = None) -> bool:
        """
        Download the PANNs CNN14 model.

        Args:
            progress_callback: Optional callback(progress_ratio) for progress updates

        Returns:
            True if successful, False otherwise
        """
        if not HAS_TORCH:
            logger.error("PyTorch not installed. Cannot use PANNs.")
            return False

        self.models_dir.mkdir(parents=True, exist_ok=True)
        model_path = self.get_model_path()

        if model_path.exists():
            return True

        logger.info("Downloading PANNs CNN14 model (~300MB)...")
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


class PANNsAnalyzer:
    """
    Extract audio embeddings using PANNs CNN14 model.

    The CNN14 model produces 2048-dimensional embeddings that capture
    rich audio semantics. These are reduced via PCA to PANNS_FEATURE_COUNT
    dimensions for efficiency while retaining most information.
    """

    def __init__(self, models_dir: Optional[str] = None, auto_load: bool = True):
        """
        Initialize the PANNs analyzer.

        Args:
            models_dir: Custom directory for model storage
            auto_load: Whether to load model immediately if available
        """
        self.model_manager = PANNsModelManager(models_dir)
        self.model = None
        self.device = None
        self._pca = None
        self._pca_fitted = False

        if auto_load and self.is_available():
            self._load_model()

    def is_available(self) -> bool:
        """Check if PANNs is available and model is downloaded."""
        return HAS_TORCH and HAS_PANNS and self.model_manager.is_model_available()

    def get_status(self) -> str:
        """Get human-readable status."""
        if not HAS_TORCH:
            return "PyTorch not installed"
        if not HAS_PANNS:
            return "panns_inference not installed (pip install panns-inference)"
        if not self.model_manager.is_model_available():
            return "Model not downloaded"
        if self.model is None:
            return "Model not loaded"
        return "Available"

    def download_model(self, progress_callback: Optional[Callable[[float], None]] = None) -> bool:
        """Download the PANNs model if not present."""
        return self.model_manager.download_model(progress_callback)

    def _load_model(self) -> bool:
        """Load the PANNs model into memory."""
        if not self.is_available():
            return False

        try:
            model_path = str(self.model_manager.get_model_path())
            # Device selection: CUDA > MPS (Apple Silicon) > CPU
            if torch.cuda.is_available():
                self.device = 'cuda'
            elif hasattr(torch.backends, 'mps') and torch.backends.mps.is_available():
                self.device = 'mps'
            else:
                self.device = 'cpu'

            # Suppress the benign "No network created" warning from panns_inference
            with warnings.catch_warnings():
                warnings.filterwarnings('ignore', message='.*No network created.*')
                # Also suppress logging warnings from panns_inference
                panns_logger = logging.getLogger('panns_inference')
                original_level = panns_logger.level
                panns_logger.setLevel(logging.ERROR)
                try:
                    # panns_inference only supports 'cuda' or 'cpu', so load on CPU first
                    # then manually move to MPS if available
                    load_device = 'cuda' if self.device == 'cuda' else 'cpu'
                    self.model = AudioTagging(checkpoint_path=model_path, device=load_device)

                    # Move model to MPS if that's our target device
                    if self.device == 'mps':
                        self.model.model = self.model.model.to('mps')
                finally:
                    panns_logger.setLevel(original_level)

            logger.info("PANNs model loaded on %s", self.device)
            return True
        except Exception as e:
            logger.error("Failed to load PANNs model: %s", e)
            self.model = None
            return False

    def extract_embedding(self, audio_path: str) -> Optional[np.ndarray]:
        """
        Extract the 2048-dimensional embedding from an audio file.

        Args:
            audio_path: Path to audio file

        Returns:
            numpy array of shape (2048,) or None if extraction fails
        """
        if self.model is None:
            if not self._load_model():
                return None

        try:
            # Load audio at PANNs sample rate
            waveform, sr = librosa.load(audio_path, sr=PANNS_SAMPLE_RATE, mono=True, duration=60)

            # PANNs expects (batch, samples) shape
            waveform = waveform[np.newaxis, :]

            # For MPS, we need to handle inference manually since panns_inference
            # doesn't know about MPS
            if self.device == 'mps':
                audio_tensor = torch.from_numpy(waveform).float().to('mps')
                with torch.no_grad():
                    self.model.model.eval()
                    output_dict = self.model.model(audio_tensor, None)
                embedding = output_dict['embedding'].data.cpu().numpy()
            else:
                # Use standard inference for CUDA/CPU
                _, embedding = self.model.inference(waveform)

            # embedding shape is (1, 2048), flatten to (2048,)
            return embedding.flatten()

        except Exception as e:
            logger.error("PANNs embedding extraction failed for %s: %s", audio_path, e)
            return None

    def detect_sounds(
        self,
        audio_path: str,
        threshold: float = 0.1,
        top_k: int = 20
    ) -> Dict[str, Any]:
        """
        Detect sounds/instruments/genres in an audio file.

        Returns the top detected AudioSet labels with their confidence scores.

        Args:
            audio_path: Path to audio file
            threshold: Minimum confidence threshold (0-1)
            top_k: Maximum number of labels to return

        Returns:
            Dict with categorized detections:
            {
                'instruments': [('Piano', 0.85), ('Synthesizer', 0.72), ...],
                'genres': [('House music', 0.65), ...],
                'vocals': [('Female singing', 0.45), ...],
                'mood': [('Happy music', 0.33), ...],
                'drums': [('Drum machine', 0.78), ('Hi-hat', 0.65), ...],
                'all_detections': [(label, score), ...],
            }
        """
        if self.model is None:
            if not self._load_model():
                return self._get_empty_detections()

        try:
            from panns_inference import labels as audioset_labels

            # Load audio at PANNs sample rate
            waveform, sr = librosa.load(audio_path, sr=PANNS_SAMPLE_RATE, mono=True, duration=60)
            waveform = waveform[np.newaxis, :]

            # Get predictions
            if self.device == 'mps':
                audio_tensor = torch.from_numpy(waveform).float().to('mps')
                with torch.no_grad():
                    self.model.model.eval()
                    output_dict = self.model.model(audio_tensor, None)
                clipwise_output = output_dict['clipwise_output'].data.cpu().numpy()
            else:
                clipwise_output, _ = self.model.inference(waveform)

            # Get top predictions
            predictions = clipwise_output[0]  # Shape: (527,)

            # Get indices sorted by score
            sorted_indices = np.argsort(predictions)[::-1]

            # Build categorized results
            results = {
                'instruments': [],
                'genres': [],
                'vocals': [],
                'mood': [],
                'drums': [],
                'all_detections': [],
            }

            # Category definitions
            instrument_keywords = [
                'piano', 'guitar', 'bass', 'synthesizer', 'organ', 'keyboard',
                'string', 'violin', 'cello', 'brass', 'horn', 'trumpet',
                'saxophone', 'flute', 'harmonica', 'accordion', 'harp'
            ]
            genre_keywords = [
                'house music', 'techno', 'disco', 'electronic', 'funk', 'soul',
                'jazz', 'hip hop', 'reggae', 'dubstep', 'trance', 'ambient',
                'afrobeat', 'dance music', 'electronica', 'rock', 'pop'
            ]
            vocal_keywords = [
                'singing', 'vocal', 'speech', 'male', 'female', 'choir', 'rapping'
            ]
            mood_keywords = [
                'happy music', 'sad music', 'angry music', 'exciting music',
                'tender music', 'scary music'
            ]
            drum_keywords = [
                'drum', 'hi-hat', 'snare', 'kick', 'cymbal', 'percussion',
                'beat', 'tom'
            ]

            count = 0
            for idx in sorted_indices:
                if count >= top_k:
                    break

                score = float(predictions[idx])
                if score < threshold:
                    break

                label = audioset_labels[idx]
                label_lower = label.lower()

                # Skip non-music labels
                skip_labels = ['speech', 'crowd', 'applause', 'silence', 'noise',
                               'static', 'hum', 'buzz', 'crackle']
                if any(skip in label_lower for skip in skip_labels):
                    continue

                results['all_detections'].append((label, score))
                count += 1

                # Categorize
                if any(kw in label_lower for kw in instrument_keywords):
                    results['instruments'].append((label, score))
                elif any(kw in label_lower for kw in drum_keywords):
                    results['drums'].append((label, score))
                elif any(kw in label_lower for kw in genre_keywords):
                    results['genres'].append((label, score))
                elif any(kw in label_lower for kw in vocal_keywords):
                    results['vocals'].append((label, score))
                elif any(kw in label_lower for kw in mood_keywords):
                    results['mood'].append((label, score))

            return results

        except Exception as e:
            logger.error("PANNs sound detection failed for %s: %s", audio_path, e)
            return self._get_empty_detections()

    def _get_empty_detections(self) -> Dict[str, Any]:
        """Return empty detections structure."""
        return {
            'instruments': [],
            'genres': [],
            'vocals': [],
            'mood': [],
            'drums': [],
            'all_detections': [],
        }

    def format_detections(self, detections: Dict[str, Any], min_score: float = 0.15) -> str:
        """
        Format detections as a readable string.

        Args:
            detections: Output from detect_sounds()
            min_score: Minimum score to include in formatted output

        Returns:
            Formatted string like:
            "Instruments: Piano, Synthesizer | Drums: Drum machine, Hi-hat | Vocals: Female singing"
        """
        parts = []

        # Instruments
        instruments = [label for label, score in detections['instruments'] if score >= min_score]
        if instruments:
            parts.append(f"Instruments: {', '.join(instruments[:4])}")

        # Drums
        drums = [label for label, score in detections['drums'] if score >= min_score]
        if drums:
            parts.append(f"Drums: {', '.join(drums[:3])}")

        # Vocals
        vocals = [label for label, score in detections['vocals'] if score >= min_score]
        if vocals:
            # Simplify vocal labels
            vocal_simple = []
            for v in vocals[:2]:
                if 'female' in v.lower():
                    vocal_simple.append('Female vocal')
                elif 'male' in v.lower():
                    vocal_simple.append('Male vocal')
                elif 'singing' in v.lower():
                    vocal_simple.append('Vocals')
                else:
                    vocal_simple.append(v)
            parts.append(f"Vocals: {', '.join(vocal_simple)}")

        # Genres
        genres = [label for label, score in detections['genres'] if score >= min_score]
        if genres:
            parts.append(f"Style: {', '.join(genres[:2])}")

        # Mood
        moods = [label.replace(' music', '') for label, score in detections['mood'] if score >= min_score]
        if moods:
            parts.append(f"Mood: {', '.join(moods[:2])}")

        return ' | '.join(parts) if parts else 'No clear detections'

    def extract_features(self, audio_path: str) -> Dict[str, Any]:
        """
        Extract PANNs features for integration with AudioAnalyzer.

        Returns a dict with the embedding and reduced features.
        """
        embedding = self.extract_embedding(audio_path)

        if embedding is None:
            return self._get_default_features()

        # Store full embedding and compute statistics for feature vector
        features = {
            'panns_embedding': embedding,
            'panns_available': True,
        }

        # Compute statistics from embedding for the feature vector
        # This reduces 2048 dims to PANNS_FEATURE_COUNT dims
        features.update(self._compute_embedding_stats(embedding))

        return features

    def _compute_embedding_stats(self, embedding: np.ndarray) -> Dict[str, float]:
        """
        Compute summary statistics from the PANNs embedding.

        We divide the 2048-dim embedding into segments and compute
        statistics, reducing to PANNS_FEATURE_COUNT dimensions.
        """
        stats = {}

        # Divide embedding into 8 segments, compute 4 stats each = 32 features
        segment_size = len(embedding) // 8

        for i in range(8):
            segment = embedding[i * segment_size:(i + 1) * segment_size]
            stats[f'panns_seg{i}_mean'] = float(np.mean(segment))
            stats[f'panns_seg{i}_std'] = float(np.std(segment))
            stats[f'panns_seg{i}_max'] = float(np.max(segment))
            stats[f'panns_seg{i}_energy'] = float(np.sum(segment ** 2) / len(segment))

        return stats

    def _get_default_features(self) -> Dict[str, Any]:
        """Return default features when PANNs is not available."""
        features = {
            'panns_embedding': None,
            'panns_available': False,
        }

        # Add default stats
        for i in range(8):
            features[f'panns_seg{i}_mean'] = 0.0
            features[f'panns_seg{i}_std'] = 0.0
            features[f'panns_seg{i}_max'] = 0.0
            features[f'panns_seg{i}_energy'] = 0.0

        return features

    def get_feature_vector(self, features: Dict[str, Any]) -> np.ndarray:
        """
        Extract PANNs portion of feature vector from features dict.

        Returns array of shape (PANNS_FEATURE_COUNT,) = (32,)
        """
        vector = []

        for i in range(8):
            vector.append(float(features.get(f'panns_seg{i}_mean', 0.0)))
            vector.append(float(features.get(f'panns_seg{i}_std', 0.0)))
            vector.append(float(features.get(f'panns_seg{i}_max', 0.0)))
            vector.append(float(features.get(f'panns_seg{i}_energy', 0.0)))

        return np.array(vector, dtype=np.float32)


def is_panns_available() -> bool:
    """Quick check if PANNs can be used."""
    return HAS_TORCH and HAS_PANNS


def get_panns_status() -> str:
    """Get human-readable PANNs status."""
    if not HAS_TORCH:
        return "PyTorch not installed"
    if not HAS_PANNS:
        return "Not installed (pip install panns-inference)"

    manager = PANNsModelManager()
    if not manager.is_model_available():
        return "Model not downloaded"

    return "Available"
