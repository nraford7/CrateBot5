"""
Fast Audio Analyzer for Training

Optimized audio feature extraction for model training:
- Samples from 33% into track (skips intro, captures main section)
- 45 second duration for representative sample
- Cached HPSS (computed once, reused)
- Skip chromaprint (not needed for ML training)
- Single audio load with resampling for Essentia
- Multiprocessing support

Expected speedup: ~8x compared to regular analyzer
"""

import librosa
import numpy as np
from typing import Dict, Any, Optional, List, Tuple
from scipy import stats
from concurrent.futures import ProcessPoolExecutor, as_completed
import multiprocessing
import os

# Import Essentia analyzer (now includes MTG-Jamendo mood/theme: 8 basic + 56 Jamendo = 64 features)
from .essentia_analyzer import EssentiaAnalyzer, ESSENTIA_FEATURE_COUNT, HAS_ESSENTIA

# Import PANNs analyzer for sound detection
try:
    from .panns_analyzer import PANNsAnalyzer, is_panns_available
    HAS_PANNS = is_panns_available()
except ImportError:
    HAS_PANNS = False

# Import CLAP analyzer for semantic audio embeddings
try:
    from .clap_analyzer import CLAPAnalyzer, is_clap_available, CLAP_FEATURE_COUNT
    HAS_CLAP = is_clap_available()
except ImportError:
    HAS_CLAP = False
    CLAP_FEATURE_COUNT = 32

# Note: Jamendo CLAP classifier removed - Essentia MTG-Jamendo model provides
# the same 56 mood/theme features, trained on real data by the MTG team.

# PANNs feature labels we care about for DJ music
# These are the exact labels from AudioSet that we'll extract scores for
PANNS_GENRE_LABELS = [
    'House music', 'Techno', 'Disco', 'Funk', 'Soul music', 'Jazz',
    'Hip hop music', 'Reggae', 'Electronic music', 'Trance music',
    'Ambient music', 'Dubstep', 'Drum and bass', 'Afrobeat'
]
PANNS_INSTRUMENT_LABELS = [
    'Piano', 'Synthesizer', 'Guitar', 'Bass guitar', 'Organ',
    'Keyboard (musical)', 'String section', 'Brass instrument'
]
PANNS_DRUM_LABELS = [
    'Drum machine', 'Drum kit', 'Hi-hat', 'Snare drum', 'Bass drum'
]
PANNS_VOCAL_LABELS = [
    'Singing', 'Male singing', 'Female singing'
]
PANNS_MOOD_LABELS = [
    'Happy music', 'Sad music'
]

# Total PANNs features: 14 + 8 + 5 + 3 + 2 = 32 (matches panns_analyzer.py)
PANNS_FEATURE_COUNT = (len(PANNS_GENRE_LABELS) + len(PANNS_INSTRUMENT_LABELS) +
                       len(PANNS_DRUM_LABELS) + len(PANNS_VOCAL_LABELS) +
                       len(PANNS_MOOD_LABELS))


class FastAudioAnalyzer:
    """
    Optimized audio feature extraction for training.

    Optimizations:
    - Samples from 33% into track (skips intro, captures main section)
    - 45 second duration for representative sample
    - Single HPSS computation - 1.5x speedup
    - Skip chromaprint - 1.5x speedup
    - Shared Essentia analyzer
    - PANNs sound detection for instrument/genre classification

    CrateBot4: Uses lazy model loading for faster startup.
    """

    # Feature vector breakdown:
    # - 57 base librosa (MFCC, spectral, chroma, contrast, tonnetz, rhythmic, harmonic, timbral, dynamic)
    # - 583 Essentia (8 basic + 56 MTG-Jamendo mood/theme + 519 Discogs genre/style)
    # - 32 PANNs (14 genres + 8 instruments + 5 drums + 3 vocals + 2 mood)
    # - 32 CLAP (8 segments × 4 statistics from 512-dim embedding)
    # Total: 57 + 583 + 32 + 32 = 704 features
    # Note: MTG-Jamendo mood/theme is included in Essentia (56 tags), no need for separate CLAP-based classifier
    FEATURE_VECTOR_SIZE = 57 + ESSENTIA_FEATURE_COUNT + PANNS_FEATURE_COUNT + CLAP_FEATURE_COUNT

    def __init__(self, sample_rate: int = 22050, duration: float = 45.0,
                 offset_percent: float = 0.33, use_panns: bool = True,
                 use_clap: bool = True, lazy_load: bool = True):
        """
        Initialize fast analyzer.

        Args:
            sample_rate: Sample rate for librosa (default 22050)
            duration: Duration in seconds to analyze (default 45s)
            offset_percent: Start position as percentage of track (default 0.33 = 33%)
            use_panns: Whether to use PANNs for sound detection (default True)
            use_clap: Whether to use CLAP for semantic embeddings (default True)
            lazy_load: CrateBot4 - If True (default), use lazy model loading for faster startup
        """
        self.sample_rate = sample_rate
        self.duration = duration
        self.offset_percent = offset_percent
        self.lazy_load = lazy_load

        # CrateBot4: Configure which optional models to use (don't load yet if lazy)
        self.use_panns = use_panns and HAS_PANNS
        self.use_clap = use_clap and HAS_CLAP

        # CrateBot4: Store references (loaded lazily via properties)
        self._essentia_analyzer = None
        self._panns_analyzer = None
        self._clap_analyzer = None

        # For backward compatibility, load immediately if lazy_load=False
        if not lazy_load:
            self._essentia_analyzer = EssentiaAnalyzer(auto_load=True)
            if self.use_panns:
                try:
                    self._panns_analyzer = PANNsAnalyzer(auto_load=True)
                except Exception:
                    self.use_panns = False
            if self.use_clap:
                try:
                    self._clap_analyzer = CLAPAnalyzer(auto_load=True)
                except Exception:
                    self.use_clap = False

    # CrateBot4: Lazy-loaded model properties
    @property
    def essentia_analyzer(self):
        """Lazy-load Essentia analyzer on first access."""
        if self._essentia_analyzer is None:
            from .model_loader import ModelLoader
            self._essentia_analyzer = ModelLoader.get_essentia_analyzer()
            if self._essentia_analyzer is None:
                # Fallback to direct instantiation
                self._essentia_analyzer = EssentiaAnalyzer(auto_load=True)
        return self._essentia_analyzer

    @property
    def panns_analyzer(self):
        """Lazy-load PANNs analyzer on first access."""
        if self._panns_analyzer is None and self.use_panns:
            from .model_loader import ModelLoader
            self._panns_analyzer = ModelLoader.get_panns_analyzer()
            if self._panns_analyzer is None:
                self.use_panns = False
        return self._panns_analyzer

    @property
    def clap_analyzer(self):
        """Lazy-load CLAP analyzer on first access."""
        if self._clap_analyzer is None and self.use_clap:
            from .model_loader import ModelLoader
            self._clap_analyzer = ModelLoader.get_clap_analyzer()
            if self._clap_analyzer is None:
                self.use_clap = False
        return self._clap_analyzer

    def extract_features(self, audio_path: str) -> Dict[str, Any]:
        """
        Extract features with optimizations for training speed.

        Samples from 33% into the track to skip intro and capture
        the main section of the song.
        """
        try:
            # Get total duration first to calculate offset
            total_duration = librosa.get_duration(path=audio_path)

            # Calculate offset (33% into track by default)
            offset_seconds = total_duration * self.offset_percent

            # Ensure we don't run past the end of the track
            # If track is too short, start from beginning
            if offset_seconds + self.duration > total_duration:
                if total_duration <= self.duration:
                    # Track is shorter than sample duration - use whole track from start
                    offset_seconds = 0.0
                else:
                    # Adjust offset so we don't run past end
                    offset_seconds = max(0, total_duration - self.duration)

            # Load audio from calculated offset
            y, sr = librosa.load(audio_path, sr=self.sample_rate,
                                 offset=offset_seconds, duration=self.duration)

            if len(y) == 0:
                raise ValueError("Audio file is empty or corrupted")

            features = {}

            # ===== COMPUTE HPSS ONCE (major optimization) =====
            try:
                y_harmonic, y_percussive = librosa.effects.hpss(y)
            except Exception:
                y_harmonic = y
                y_percussive = np.zeros_like(y)

            # ===== ORIGINAL FEATURES (with error handling) =====
            try:
                features['mfcc'] = self._extract_mfcc(y, sr)
            except Exception:
                features['mfcc'] = np.zeros(13)

            try:
                features['spectral_centroid'] = self._extract_spectral_centroid(y, sr)
            except Exception:
                features['spectral_centroid'] = 0.0

            try:
                features['spectral_rolloff'] = self._extract_spectral_rolloff(y, sr)
            except Exception:
                features['spectral_rolloff'] = 0.0

            try:
                features['zero_crossing_rate'] = self._extract_zcr(y)
            except Exception:
                features['zero_crossing_rate'] = 0.0

            try:
                features['tempo'] = self._extract_tempo(y, sr)
            except Exception:
                features['tempo'] = 120.0

            try:
                features['chroma'] = self._extract_chroma(y, sr)
            except Exception:
                features['chroma'] = np.zeros(12)

            try:
                features['spectral_contrast'] = self._extract_spectral_contrast(y, sr)
            except Exception:
                features['spectral_contrast'] = np.zeros(7)

            try:
                features['tonnetz'] = self._extract_tonnetz(y, sr)
            except Exception:
                features['tonnetz'] = np.zeros(6)

            try:
                features['rms_energy'] = self._extract_rms(y)
            except Exception:
                features['rms_energy'] = 0.0

            # ===== PHASE 2: ENHANCED FEATURES (using cached HPSS) =====

            # Rhythmic features
            try:
                rhythmic = self._extract_rhythmic_features(y, sr, y_harmonic, y_percussive)
                features.update(rhythmic)
            except Exception:
                features['onset_strength_mean'] = 0.0
                features['onset_strength_std'] = 0.0
                features['tempo_stability'] = 0.5
                features['percussion_ratio'] = 0.5

            # Harmonic features (using cached HPSS)
            try:
                harmonic = self._extract_harmonic_features(y, sr, y_harmonic)
                features.update(harmonic)
            except Exception:
                features['estimated_key'] = 0.0
                features['key_mode'] = 0.5
                features['harmonic_ratio'] = 0.5

            # Enhanced timbral features
            try:
                timbral = self._extract_enhanced_timbral(y, sr)
                features.update(timbral)
            except Exception:
                features['spectral_flatness'] = 0.0
                features['spectral_bandwidth'] = 0.0
                features['spectral_rolloff_std'] = 0.0

            # Dynamic features
            try:
                dynamic = self._extract_dynamic_features(y, sr)
                features.update(dynamic)
            except Exception:
                features['dynamic_range'] = 0.0
                features['energy_entropy'] = 0.0
                features['rms_std'] = 0.0
                features['loudness_variation'] = 0.0

            # ===== PHASE 3: ESSENTIA FEATURES =====
            try:
                essentia_features = self.essentia_analyzer.extract_features(audio_path)
                features.update(essentia_features)
            except Exception as e:
                features.update(self.essentia_analyzer._get_default_features())
                features['essentia_available'] = False
                features['essentia_status'] = f'extraction_failed: {str(e)}'

            # ===== PHASE 4: PANNS SOUND DETECTION =====
            try:
                panns_features = self._extract_panns_features(audio_path)
                features.update(panns_features)
            except Exception as e:
                features.update(self._get_default_panns_features())
                features['panns_available'] = False
                features['panns_status'] = f'extraction_failed: {str(e)}'

            # ===== PHASE 5: CLAP SEMANTIC EMBEDDINGS =====
            try:
                clap_features = self._extract_clap_features(audio_path)
                features.update(clap_features)
            except Exception as e:
                features.update(self._get_default_clap_features())
                features['clap_available'] = False
                features['clap_status'] = f'extraction_failed: {str(e)}'

            # Note: Jamendo mood/theme features are included in Essentia (56 MTG-Jamendo tags)
            # No separate CLAP-based Jamendo classifier needed.

            # Skip chromaprint for training (not needed for ML)
            features['fingerprint'] = None

            # Create feature vector
            feature_vector = self._create_feature_vector(features)
            features['feature_vector'] = feature_vector

            return features

        except Exception as e:
            raise Exception(f"Error extracting features from {audio_path}: {str(e)}")

    def _extract_mfcc(self, y: np.ndarray, sr: int, n_mfcc: int = 13) -> np.ndarray:
        mfcc = librosa.feature.mfcc(y=y, sr=sr, n_mfcc=n_mfcc)
        return np.mean(mfcc.T, axis=0)

    def _extract_spectral_centroid(self, y: np.ndarray, sr: int) -> float:
        return float(np.mean(librosa.feature.spectral_centroid(y=y, sr=sr)))

    def _extract_spectral_rolloff(self, y: np.ndarray, sr: int) -> float:
        return float(np.mean(librosa.feature.spectral_rolloff(y=y, sr=sr)))

    def _extract_zcr(self, y: np.ndarray) -> float:
        return float(np.mean(librosa.feature.zero_crossing_rate(y)))

    def _extract_tempo(self, y: np.ndarray, sr: int) -> float:
        tempo, _ = librosa.beat.beat_track(y=y, sr=sr)
        return float(tempo)

    def _extract_chroma(self, y: np.ndarray, sr: int) -> np.ndarray:
        chroma = librosa.feature.chroma_stft(y=y, sr=sr)
        return np.mean(chroma.T, axis=0)

    def _extract_spectral_contrast(self, y: np.ndarray, sr: int) -> np.ndarray:
        spectral_contrast = librosa.feature.spectral_contrast(y=y, sr=sr)
        return np.mean(spectral_contrast.T, axis=0)

    def _extract_tonnetz(self, y: np.ndarray, sr: int) -> np.ndarray:
        tonnetz = librosa.feature.tonnetz(y=y, sr=sr)
        return np.mean(tonnetz.T, axis=0)

    def _extract_rms(self, y: np.ndarray) -> float:
        return float(np.mean(librosa.feature.rms(y=y)))

    def _extract_rhythmic_features(self, y: np.ndarray, sr: int,
                                    y_harmonic: np.ndarray, y_percussive: np.ndarray) -> Dict[str, float]:
        """Extract rhythmic features using pre-computed HPSS."""
        # Onset strength envelope
        onset_env = librosa.onset.onset_strength(y=y, sr=sr)
        onset_mean = float(np.mean(onset_env))
        onset_std = float(np.std(onset_env))

        # Tempo stability
        tempogram = librosa.feature.tempogram(onset_envelope=onset_env, sr=sr)
        tempo_strengths = np.mean(tempogram, axis=1)
        if np.sum(tempo_strengths) > 0:
            tempo_entropy = stats.entropy(tempo_strengths / np.sum(tempo_strengths))
            tempo_stability = float(1.0 / (1.0 + tempo_entropy))
        else:
            tempo_stability = 0.5

        # Percussion ratio (using pre-computed HPSS)
        harmonic_energy = float(np.sum(y_harmonic ** 2))
        percussive_energy = float(np.sum(y_percussive ** 2))
        total_energy = harmonic_energy + percussive_energy
        if total_energy > 0:
            percussion_ratio = percussive_energy / total_energy
        else:
            percussion_ratio = 0.5

        return {
            'onset_strength_mean': onset_mean,
            'onset_strength_std': onset_std,
            'tempo_stability': tempo_stability,
            'percussion_ratio': float(percussion_ratio)
        }

    def _extract_harmonic_features(self, y: np.ndarray, sr: int,
                                    y_harmonic: np.ndarray) -> Dict[str, float]:
        """Extract harmonic features using pre-computed HPSS."""
        # Key detection
        chroma = librosa.feature.chroma_cqt(y=y, sr=sr)
        chroma_mean = np.mean(chroma, axis=1)
        estimated_key = int(np.argmax(chroma_mean))

        # Major/minor mode
        major_profile = np.array([6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88])
        minor_profile = np.array([6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17])

        major_rotated = np.roll(major_profile, estimated_key)
        minor_rotated = np.roll(minor_profile, estimated_key)

        major_corr = float(np.corrcoef(chroma_mean, major_rotated)[0, 1])
        minor_corr = float(np.corrcoef(chroma_mean, minor_rotated)[0, 1])

        if major_corr + minor_corr > 0:
            key_mode = (major_corr + 1) / ((major_corr + 1) + (minor_corr + 1))
        else:
            key_mode = 0.5

        # Harmonic ratio (using pre-computed HPSS)
        harmonic_energy = float(np.sum(y_harmonic ** 2))
        total_energy = float(np.sum(y ** 2))
        if total_energy > 0:
            harmonic_ratio = harmonic_energy / total_energy
        else:
            harmonic_ratio = 0.5

        return {
            'estimated_key': float(estimated_key) / 11.0,
            'key_mode': float(key_mode),
            'harmonic_ratio': float(harmonic_ratio)
        }

    def _extract_enhanced_timbral(self, y: np.ndarray, sr: int) -> Dict[str, float]:
        """Extract enhanced timbral features."""
        flatness = librosa.feature.spectral_flatness(y=y)
        spectral_flatness = float(np.mean(flatness))

        bandwidth = librosa.feature.spectral_bandwidth(y=y, sr=sr)
        spectral_bandwidth = float(np.mean(bandwidth))

        rolloff = librosa.feature.spectral_rolloff(y=y, sr=sr)
        spectral_rolloff_std = float(np.std(rolloff))

        return {
            'spectral_flatness': spectral_flatness,
            'spectral_bandwidth': spectral_bandwidth,
            'spectral_rolloff_std': spectral_rolloff_std
        }

    def _extract_dynamic_features(self, y: np.ndarray, sr: int) -> Dict[str, float]:
        """Extract dynamic range and energy features."""
        rms = librosa.feature.rms(y=y)[0]
        rms_safe = np.maximum(rms, 1e-10)

        rms_db = librosa.amplitude_to_db(rms_safe)
        dynamic_range = float(np.max(rms_db) - np.min(rms_db))

        rms_norm = rms / (np.sum(rms) + 1e-10)
        energy_entropy = float(stats.entropy(rms_norm + 1e-10))
        energy_entropy = min(1.0, energy_entropy / 5.0)

        rms_std = float(np.std(rms))

        rms_mean = np.mean(rms)
        if rms_mean > 0:
            loudness_variation = float(rms_std / rms_mean)
        else:
            loudness_variation = 0.0

        return {
            'dynamic_range': dynamic_range,
            'energy_entropy': energy_entropy,
            'rms_std': rms_std,
            'loudness_variation': min(1.0, loudness_variation)
        }

    def _extract_panns_features(self, audio_path: str) -> Dict[str, float]:
        """
        Extract PANNs sound detection scores for specific labels.

        Returns scores for genres, instruments, drums, vocals, and mood labels
        that are most relevant for DJ music classification.
        """
        if not self.use_panns or self.panns_analyzer is None:
            return self._get_default_panns_features()

        try:
            from panns_inference import labels as audioset_labels

            # Get all predictions from PANNs
            waveform, sr = librosa.load(audio_path, sr=32000, mono=True, duration=60)
            waveform = waveform[np.newaxis, :]

            import torch
            if self.panns_analyzer.device == 'mps':
                audio_tensor = torch.from_numpy(waveform).float().to('mps')
                with torch.no_grad():
                    self.panns_analyzer.model.model.eval()
                    output_dict = self.panns_analyzer.model.model(audio_tensor, None)
                predictions = output_dict['clipwise_output'].data.cpu().numpy()[0]
            else:
                clipwise_output, _ = self.panns_analyzer.model.inference(waveform)
                predictions = clipwise_output[0]

            # Build label to index map
            label_to_idx = {label: idx for idx, label in enumerate(audioset_labels)}

            # Extract scores for our target labels
            features = {'panns_available': True}

            # Genre scores
            for label in PANNS_GENRE_LABELS:
                key = f'panns_genre_{label.lower().replace(" ", "_")}'
                if label in label_to_idx:
                    features[key] = float(predictions[label_to_idx[label]])
                else:
                    features[key] = 0.0

            # Instrument scores
            for label in PANNS_INSTRUMENT_LABELS:
                key = f'panns_inst_{label.lower().replace(" ", "_").replace("(", "").replace(")", "")}'
                if label in label_to_idx:
                    features[key] = float(predictions[label_to_idx[label]])
                else:
                    features[key] = 0.0

            # Drum scores
            for label in PANNS_DRUM_LABELS:
                key = f'panns_drum_{label.lower().replace(" ", "_")}'
                if label in label_to_idx:
                    features[key] = float(predictions[label_to_idx[label]])
                else:
                    features[key] = 0.0

            # Vocal scores
            for label in PANNS_VOCAL_LABELS:
                key = f'panns_vocal_{label.lower().replace(" ", "_")}'
                if label in label_to_idx:
                    features[key] = float(predictions[label_to_idx[label]])
                else:
                    features[key] = 0.0

            # Mood scores
            for label in PANNS_MOOD_LABELS:
                key = f'panns_mood_{label.lower().replace(" ", "_")}'
                if label in label_to_idx:
                    features[key] = float(predictions[label_to_idx[label]])
                else:
                    features[key] = 0.0

            return features

        except Exception as e:
            features = self._get_default_panns_features()
            features['panns_status'] = f'extraction_failed: {str(e)}'
            return features

    def _get_default_panns_features(self) -> Dict[str, float]:
        """Return default (zero) PANNs features when unavailable."""
        features = {'panns_available': False}

        for label in PANNS_GENRE_LABELS:
            key = f'panns_genre_{label.lower().replace(" ", "_")}'
            features[key] = 0.0

        for label in PANNS_INSTRUMENT_LABELS:
            key = f'panns_inst_{label.lower().replace(" ", "_").replace("(", "").replace(")", "")}'
            features[key] = 0.0

        for label in PANNS_DRUM_LABELS:
            key = f'panns_drum_{label.lower().replace(" ", "_")}'
            features[key] = 0.0

        for label in PANNS_VOCAL_LABELS:
            key = f'panns_vocal_{label.lower().replace(" ", "_")}'
            features[key] = 0.0

        for label in PANNS_MOOD_LABELS:
            key = f'panns_mood_{label.lower().replace(" ", "_")}'
            features[key] = 0.0

        return features

    def _get_panns_feature_vector(self, features: Dict[str, Any]) -> np.ndarray:
        """Extract PANNs portion of feature vector."""
        vector = []

        # Same order as labels defined at top
        for label in PANNS_GENRE_LABELS:
            key = f'panns_genre_{label.lower().replace(" ", "_")}'
            vector.append(float(features.get(key, 0.0)))

        for label in PANNS_INSTRUMENT_LABELS:
            key = f'panns_inst_{label.lower().replace(" ", "_").replace("(", "").replace(")", "")}'
            vector.append(float(features.get(key, 0.0)))

        for label in PANNS_DRUM_LABELS:
            key = f'panns_drum_{label.lower().replace(" ", "_")}'
            vector.append(float(features.get(key, 0.0)))

        for label in PANNS_VOCAL_LABELS:
            key = f'panns_vocal_{label.lower().replace(" ", "_")}'
            vector.append(float(features.get(key, 0.0)))

        for label in PANNS_MOOD_LABELS:
            key = f'panns_mood_{label.lower().replace(" ", "_")}'
            vector.append(float(features.get(key, 0.0)))

        return np.array(vector, dtype=np.float32)

    def _extract_clap_features(self, audio_path: str) -> Dict[str, Any]:
        """Extract CLAP semantic audio embeddings."""
        if not self.use_clap or self.clap_analyzer is None:
            return self._get_default_clap_features()

        return self.clap_analyzer.extract_features(audio_path)

    def _get_default_clap_features(self) -> Dict[str, Any]:
        """Return default CLAP features when not available."""
        if self.clap_analyzer is not None:
            return self.clap_analyzer._get_default_features()

        features = {
            'clap_embedding': None,
            'clap_available': False,
        }
        for i in range(8):
            features[f'clap_seg{i}_mean'] = 0.0
            features[f'clap_seg{i}_std'] = 0.0
            features[f'clap_seg{i}_max'] = 0.0
            features[f'clap_seg{i}_energy'] = 0.0
        return features

    def _get_clap_feature_vector(self, features: Dict[str, Any]) -> np.ndarray:
        """Extract CLAP portion of feature vector."""
        if self.clap_analyzer is not None:
            return self.clap_analyzer.get_feature_vector(features)

        vector = []
        for i in range(8):
            vector.append(float(features.get(f'clap_seg{i}_mean', 0.0)))
            vector.append(float(features.get(f'clap_seg{i}_std', 0.0)))
            vector.append(float(features.get(f'clap_seg{i}_max', 0.0)))
            vector.append(float(features.get(f'clap_seg{i}_energy', 0.0)))
        return np.array(vector, dtype=np.float32)

    def _create_feature_vector(self, features: Dict[str, Any]) -> np.ndarray:
        """Create a flat feature vector from all extracted features."""
        flattened_features = []

        # MFCC (13 values)
        if isinstance(features.get('mfcc'), np.ndarray):
            mfcc_values = features['mfcc'].flatten()[:13]
            flattened_features.extend(mfcc_values.tolist())
            if len(mfcc_values) < 13:
                flattened_features.extend([0.0] * (13 - len(mfcc_values)))
        else:
            flattened_features.extend([0.0] * 13)

        # Single spectral (5 values)
        flattened_features.append(float(features.get('spectral_centroid', 0.0)))
        flattened_features.append(float(features.get('spectral_rolloff', 0.0)))
        flattened_features.append(float(features.get('zero_crossing_rate', 0.0)))
        flattened_features.append(float(features.get('tempo', 120.0)))
        flattened_features.append(float(features.get('rms_energy', 0.0)))

        # Chroma (12 values)
        if isinstance(features.get('chroma'), np.ndarray):
            chroma_values = features['chroma'].flatten()[:12]
            flattened_features.extend(chroma_values.tolist())
            if len(chroma_values) < 12:
                flattened_features.extend([0.0] * (12 - len(chroma_values)))
        else:
            flattened_features.extend([0.0] * 12)

        # Spectral contrast (7 values)
        if isinstance(features.get('spectral_contrast'), np.ndarray):
            contrast_values = features['spectral_contrast'].flatten()[:7]
            flattened_features.extend(contrast_values.tolist())
            if len(contrast_values) < 7:
                flattened_features.extend([0.0] * (7 - len(contrast_values)))
        else:
            flattened_features.extend([0.0] * 7)

        # Tonnetz (6 values)
        if isinstance(features.get('tonnetz'), np.ndarray):
            tonnetz_values = features['tonnetz'].flatten()[:6]
            flattened_features.extend(tonnetz_values.tolist())
            if len(tonnetz_values) < 6:
                flattened_features.extend([0.0] * (6 - len(tonnetz_values)))
        else:
            flattened_features.extend([0.0] * 6)

        # Rhythmic (4 values)
        flattened_features.append(float(features.get('onset_strength_mean', 0.0)))
        flattened_features.append(float(features.get('onset_strength_std', 0.0)))
        flattened_features.append(float(features.get('tempo_stability', 0.5)))
        flattened_features.append(float(features.get('percussion_ratio', 0.5)))

        # Harmonic (3 values)
        flattened_features.append(float(features.get('estimated_key', 0.0)))
        flattened_features.append(float(features.get('key_mode', 0.5)))
        flattened_features.append(float(features.get('harmonic_ratio', 0.5)))

        # Timbral (3 values)
        flattened_features.append(float(features.get('spectral_flatness', 0.0)))
        flattened_features.append(float(features.get('spectral_bandwidth', 0.0)))
        flattened_features.append(float(features.get('spectral_rolloff_std', 0.0)))

        # Dynamic (4 values)
        flattened_features.append(float(features.get('dynamic_range', 0.0)))
        flattened_features.append(float(features.get('energy_entropy', 0.0)))
        flattened_features.append(float(features.get('rms_std', 0.0)))
        flattened_features.append(float(features.get('loudness_variation', 0.0)))

        # Essentia (583 values: 8 basic + 56 MTG-Jamendo mood/theme + 519 Discogs genre/style)
        essentia_vec = self.essentia_analyzer.get_feature_vector(features)
        flattened_features.extend(essentia_vec.tolist())

        # PANNs (32 values: 14 genres + 8 instruments + 5 drums + 3 vocals + 2 mood)
        panns_vec = self._get_panns_feature_vector(features)
        flattened_features.extend(panns_vec.tolist())

        # CLAP (32 values: 8 segments × 4 statistics)
        clap_vec = self._get_clap_feature_vector(features)
        flattened_features.extend(clap_vec.tolist())

        # Note: Jamendo mood/theme is already included in Essentia (56 MTG-Jamendo tags)

        # Clean and convert
        clean_features = []
        for val in flattened_features:
            if isinstance(val, (int, float, np.number)):
                fval = float(val)
                if np.isnan(fval) or np.isinf(fval):
                    clean_features.append(0.0)
                else:
                    clean_features.append(fval)
            else:
                clean_features.append(0.0)

        return np.array(clean_features, dtype=np.float32)


def _extract_single_file(args: Tuple[str, int, float]) -> Optional[Dict[str, Any]]:
    """
    Worker function for parallel feature extraction.
    Called by ProcessPoolExecutor.
    """
    file_path, sample_rate, duration = args
    try:
        analyzer = FastAudioAnalyzer(sample_rate=sample_rate, duration=duration)
        features = analyzer.extract_features(file_path)
        return {
            'file_path': file_path,
            'features': features,
            'feature_vector': features['feature_vector'],
            'success': True
        }
    except Exception as e:
        return {
            'file_path': file_path,
            'error': str(e),
            'success': False
        }


class ParallelFeatureExtractor:
    """
    Parallel feature extraction using multiprocessing.

    Provides ~4x speedup on 4-core machines, ~8x on 8-core.
    Uses hardware configuration from HardwareConfig.
    """

    def __init__(self, n_workers: int = None, sample_rate: int = 22050, duration: float = 30.0):
        """
        Initialize parallel extractor.

        Args:
            n_workers: Number of worker processes. Default: from HardwareConfig
            sample_rate: Audio sample rate
            duration: Duration in seconds to analyze
        """
        if n_workers is None:
            try:
                from .hardware_config import get_hardware_config
                n_workers = get_hardware_config().num_workers
            except ImportError:
                n_workers = max(1, multiprocessing.cpu_count() - 1)
        self.n_workers = n_workers
        self.sample_rate = sample_rate
        self.duration = duration

    def extract_batch(self, file_paths: List[str],
                      progress_callback: Optional[callable] = None) -> List[Dict[str, Any]]:
        """
        Extract features from multiple files in parallel.

        Args:
            file_paths: List of audio file paths
            progress_callback: Optional callback(completed, total, file_path)

        Returns:
            List of feature dictionaries
        """
        results = []
        args = [(fp, self.sample_rate, self.duration) for fp in file_paths]

        with ProcessPoolExecutor(max_workers=self.n_workers) as executor:
            futures = {executor.submit(_extract_single_file, arg): arg[0] for arg in args}

            for i, future in enumerate(as_completed(futures)):
                file_path = futures[future]
                try:
                    result = future.result()
                    results.append(result)
                except Exception as e:
                    results.append({
                        'file_path': file_path,
                        'error': str(e),
                        'success': False
                    })

                if progress_callback:
                    progress_callback(i + 1, len(file_paths), file_path)

        # Sort results back to original order
        path_to_result = {r['file_path']: r for r in results}
        return [path_to_result[fp] for fp in file_paths if fp in path_to_result]
