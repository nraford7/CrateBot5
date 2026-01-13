import librosa
import librosa.util.exceptions
import numpy as np
from typing import Dict, Any, Optional, Tuple
import acoustid
from pydub import AudioSegment
from pydub.exceptions import CouldntDecodeError
import tempfile
import os
import logging
from scipy import stats

from .exceptions import AudioAnalysisError, AudioLoadError, FeatureExtractionError

# Set up logging
logger = logging.getLogger(__name__)

# Try to import chromaprint, but don't fail if it's not available
try:
    import chromaprint
    HAS_CHROMAPRINT = True
except ImportError:
    HAS_CHROMAPRINT = False

# Import Essentia analyzer (optional dependency)
from .essentia_analyzer import EssentiaAnalyzer, ESSENTIA_FEATURE_COUNT, HAS_ESSENTIA

# Import PANNs analyzer (optional dependency)
from .panns_analyzer import PANNsAnalyzer, PANNS_FEATURE_COUNT, is_panns_available

# Import CLAP analyzer (optional dependency)
try:
    from .clap_analyzer import CLAPAnalyzer, CLAP_FEATURE_COUNT, is_clap_available
    HAS_CLAP = is_clap_available()
except ImportError:
    HAS_CLAP = False
    CLAP_FEATURE_COUNT = 32

# Import Jamendo classifier (optional dependency)
try:
    from .jamendo_classifier import JamendoClassifier, JAMENDO_FEATURE_COUNT, is_jamendo_available
    HAS_JAMENDO = is_jamendo_available()
except ImportError:
    HAS_JAMENDO = False
    JAMENDO_FEATURE_COUNT = 56


class AudioAnalyzer:
    """
    Enhanced audio feature extraction for music analysis.

    Feature vector composition (184 dimensions):
    - MFCC: 13 values (timbre)
    - Single spectral: 5 values (centroid, rolloff, zcr, tempo, rms)
    - Chroma: 12 values (pitch classes)
    - Spectral contrast: 7 values (frequency band contrasts)
    - Tonnetz: 6 values (harmonic relationships)
    - Rhythmic: 4 values (onset strength, tempo stability, percussion ratio)
    - Harmonic: 3 values (key, mode, harmonic ratio)
    - Timbral: 3 values (flatness, bandwidth, rolloff variability)
    - Dynamic: 4 values (dynamic range, energy stats)
    - Essentia: 8 values (mood, danceability, vocals, arousal/valence)
    - PANNs: 32 values (pre-trained audio neural network embeddings)
    - CLAP: 32 values (semantic audio embeddings)
    - Jamendo: 55 values (mood/theme predictions)
    """

    # Feature vector size: 57 librosa + 8 essentia + 32 PANNs + 32 CLAP + 55 Jamendo = 184 total
    FEATURE_VECTOR_SIZE = 57 + ESSENTIA_FEATURE_COUNT + PANNS_FEATURE_COUNT + CLAP_FEATURE_COUNT + JAMENDO_FEATURE_COUNT

    def __init__(self, sample_rate: int = 22050):
        self.sample_rate = sample_rate
        # Initialize Essentia analyzer (optional, graceful degradation)
        self.essentia_analyzer = EssentiaAnalyzer(auto_load=True)
        # Initialize PANNs analyzer (optional, graceful degradation)
        self.panns_analyzer = PANNsAnalyzer(auto_load=True)
        # Initialize CLAP analyzer (optional, graceful degradation)
        self.clap_analyzer = CLAPAnalyzer(auto_load=True) if HAS_CLAP else None
        # Initialize Jamendo classifier (optional, graceful degradation)
        self.jamendo_classifier = JamendoClassifier(auto_load=True) if HAS_JAMENDO else None

    def extract_features(self, audio_path: str) -> Dict[str, Any]:
        """
        Extract audio features from an audio file.

        Args:
            audio_path: Path to the audio file

        Returns:
            Dictionary containing all extracted features and a 97-dim feature vector

        Raises:
            AudioLoadError: If the audio file cannot be loaded
            AudioAnalysisError: If feature extraction fails completely
        """
        # Load audio file
        try:
            y, sr = librosa.load(audio_path, sr=self.sample_rate, duration=60)
        except FileNotFoundError:
            raise AudioLoadError(f"Audio file not found: {audio_path}")
        except (librosa.util.exceptions.ParameterError, Exception) as e:
            raise AudioLoadError(f"Cannot load audio file {audio_path}: {e}")

        # Handle edge cases
        if len(y) == 0:
            raise AudioLoadError(f"Audio file is empty or corrupted: {audio_path}")

        features = {}

        # ===== ORIGINAL FEATURES =====

        # Extract each feature with specific error handling
        try:
            features['mfcc'] = self._extract_mfcc(y, sr)
        except (librosa.util.exceptions.ParameterError, ValueError) as e:
            logger.warning("MFCC extraction failed: %s", e)
            features['mfcc'] = np.zeros(13)

        try:
            features['spectral_centroid'] = self._extract_spectral_centroid(y, sr)
        except (librosa.util.exceptions.ParameterError, ValueError) as e:
            logger.warning("Spectral centroid extraction failed: %s", e)
            features['spectral_centroid'] = 0.0

        try:
            features['spectral_rolloff'] = self._extract_spectral_rolloff(y, sr)
        except (librosa.util.exceptions.ParameterError, ValueError) as e:
            logger.warning("Spectral rolloff extraction failed: %s", e)
            features['spectral_rolloff'] = 0.0

        try:
            features['zero_crossing_rate'] = self._extract_zcr(y)
        except (librosa.util.exceptions.ParameterError, ValueError) as e:
            logger.warning("Zero crossing rate extraction failed: %s", e)
            features['zero_crossing_rate'] = 0.0

        try:
            features['tempo'] = self._extract_tempo(y, sr)
        except (librosa.util.exceptions.ParameterError, ValueError) as e:
            logger.warning("Tempo extraction failed: %s", e)
            features['tempo'] = 120.0

        try:
            features['chroma'] = self._extract_chroma(y, sr)
        except (librosa.util.exceptions.ParameterError, ValueError) as e:
            logger.warning("Chroma extraction failed: %s", e)
            features['chroma'] = np.zeros(12)

        try:
            features['spectral_contrast'] = self._extract_spectral_contrast(y, sr)
        except (librosa.util.exceptions.ParameterError, ValueError) as e:
            logger.warning("Spectral contrast extraction failed: %s", e)
            features['spectral_contrast'] = np.zeros(7)

        try:
            features['tonnetz'] = self._extract_tonnetz(y, sr)
        except (librosa.util.exceptions.ParameterError, ValueError) as e:
            logger.warning("Tonnetz extraction failed: %s", e)
            features['tonnetz'] = np.zeros(6)

        try:
            features['rms_energy'] = self._extract_rms(y)
        except (librosa.util.exceptions.ParameterError, ValueError) as e:
            logger.warning("RMS energy extraction failed: %s", e)
            features['rms_energy'] = 0.0

        # ===== PHASE 2: ENHANCED FEATURES =====

        # Compute HPSS once and reuse (major optimization)
        try:
            y_harmonic, y_percussive = librosa.effects.hpss(y)
        except (librosa.util.exceptions.ParameterError, ValueError) as e:
            logger.warning("HPSS computation failed: %s", e)
            y_harmonic = y
            y_percussive = np.zeros_like(y)

        # Rhythmic features (using cached HPSS)
        try:
            rhythmic = self._extract_rhythmic_features(y, sr, y_harmonic, y_percussive)
            features.update(rhythmic)
        except (ValueError, FloatingPointError) as e:
            logger.warning("Rhythmic feature extraction failed: %s", e)
            features['onset_strength_mean'] = 0.0
            features['onset_strength_std'] = 0.0
            features['tempo_stability'] = 0.0
            features['percussion_ratio'] = 0.5

        # Harmonic features (using cached HPSS)
        try:
            harmonic = self._extract_harmonic_features(y, sr, y_harmonic)
            features.update(harmonic)
        except (ValueError, FloatingPointError) as e:
            logger.warning("Harmonic feature extraction failed: %s", e)
            features['estimated_key'] = 0
            features['key_mode'] = 0.5
            features['harmonic_ratio'] = 0.5

        # Enhanced timbral features
        try:
            timbral = self._extract_enhanced_timbral(y, sr)
            features.update(timbral)
        except (librosa.util.exceptions.ParameterError, ValueError) as e:
            logger.warning("Timbral feature extraction failed: %s", e)
            features['spectral_flatness'] = 0.0
            features['spectral_bandwidth'] = 0.0
            features['spectral_rolloff_std'] = 0.0

        # Dynamic features
        try:
            dynamic = self._extract_dynamic_features(y, sr)
            features.update(dynamic)
        except (ValueError, FloatingPointError) as e:
            logger.warning("Dynamic feature extraction failed: %s", e)
            features['dynamic_range'] = 0.0
            features['energy_entropy'] = 0.0
            features['rms_std'] = 0.0
            features['loudness_variation'] = 0.0

        # ===== PHASE 3: ESSENTIA HIGH-LEVEL FEATURES =====
        try:
            essentia_features = self.essentia_analyzer.extract_features(audio_path)
            features.update(essentia_features)
        except Exception as e:
            # Essentia is optional - use defaults if it fails
            logger.debug("Essentia feature extraction failed (optional): %s", e)
            features.update(self.essentia_analyzer._get_default_features())
            features['essentia_available'] = False
            features['essentia_status'] = f'extraction_failed: {str(e)}'

        # ===== PHASE 4: PANNS PRE-TRAINED EMBEDDINGS =====
        try:
            panns_features = self.panns_analyzer.extract_features(audio_path)
            features.update(panns_features)
        except Exception as e:
            # PANNs is optional - use defaults if it fails
            logger.debug("PANNs feature extraction failed (optional): %s", e)
            features.update(self.panns_analyzer._get_default_features())
            features['panns_available'] = False
            features['panns_status'] = f'extraction_failed: {str(e)}'

        # ===== PHASE 5: CLAP SEMANTIC EMBEDDINGS =====
        try:
            if self.clap_analyzer is not None:
                clap_features = self.clap_analyzer.extract_features(audio_path)
                features.update(clap_features)
            else:
                features.update(self._get_default_clap_features())
        except Exception as e:
            logger.debug("CLAP feature extraction failed (optional): %s", e)
            features.update(self._get_default_clap_features())
            features['clap_available'] = False
            features['clap_status'] = f'extraction_failed: {str(e)}'

        # ===== PHASE 6: JAMENDO MOOD PREDICTIONS =====
        try:
            if self.jamendo_classifier is not None:
                jamendo_features = self.jamendo_classifier.extract_features(audio_path, features)
                features.update(jamendo_features)
            else:
                features.update(self._get_default_jamendo_features())
        except Exception as e:
            logger.debug("Jamendo prediction failed (optional): %s", e)
            features.update(self._get_default_jamendo_features())
            features['jamendo_available'] = False
            features['jamendo_status'] = f'extraction_failed: {str(e)}'

        features['fingerprint'] = self._get_chromaprint(audio_path)

        feature_vector = self._create_feature_vector(features)
        features['feature_vector'] = feature_vector

        return features
    
    def _extract_mfcc(self, y: np.ndarray, sr: int, n_mfcc: int = 13) -> np.ndarray:
        mfcc = librosa.feature.mfcc(y=y, sr=sr, n_mfcc=n_mfcc)
        return np.mean(mfcc.T, axis=0)
    
    def _extract_spectral_centroid(self, y: np.ndarray, sr: int) -> float:
        spectral_centroid = librosa.feature.spectral_centroid(y=y, sr=sr)
        return np.mean(spectral_centroid)
    
    def _extract_spectral_rolloff(self, y: np.ndarray, sr: int) -> float:
        spectral_rolloff = librosa.feature.spectral_rolloff(y=y, sr=sr)
        return np.mean(spectral_rolloff)
    
    def _extract_zcr(self, y: np.ndarray) -> float:
        zcr = librosa.feature.zero_crossing_rate(y)
        return np.mean(zcr)
    
    def _extract_tempo(self, y: np.ndarray, sr: int) -> float:
        tempo, _ = librosa.beat.beat_track(y=y, sr=sr)
        return tempo
    
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
        rms = librosa.feature.rms(y=y)
        return np.mean(rms)

    # ===== PHASE 2: ENHANCED FEATURE EXTRACTION =====

    def _extract_rhythmic_features(self, y: np.ndarray, sr: int,
                                    y_harmonic: np.ndarray, y_percussive: np.ndarray) -> Dict[str, float]:
        """
        Extract rhythmic features for beat/percussion analysis.

        Args:
            y: Audio signal
            sr: Sample rate
            y_harmonic: Pre-computed harmonic component from HPSS
            y_percussive: Pre-computed percussive component from HPSS

        Returns:
            onset_strength_mean: Average attack intensity
            onset_strength_std: Variability in attacks
            tempo_stability: How consistent the tempo is (0-1)
            percussion_ratio: Ratio of percussive to harmonic content (0-1)
        """
        # Onset strength envelope
        onset_env = librosa.onset.onset_strength(y=y, sr=sr)
        onset_mean = float(np.mean(onset_env))
        onset_std = float(np.std(onset_env))

        # Tempo stability - compare multiple tempo estimates
        # Use tempogram to analyze tempo consistency
        tempogram = librosa.feature.tempogram(onset_envelope=onset_env, sr=sr)
        tempo_strengths = np.mean(tempogram, axis=1)
        # Stability is how peaked the tempo distribution is (higher = more stable)
        if np.sum(tempo_strengths) > 0:
            tempo_entropy = stats.entropy(tempo_strengths / np.sum(tempo_strengths))
            # Normalize to 0-1 range (lower entropy = more stable)
            tempo_stability = float(1.0 / (1.0 + tempo_entropy))
        else:
            tempo_stability = 0.5

        # Percussion ratio using pre-computed HPSS
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
        """
        Extract harmonic features for key/mood analysis.

        Args:
            y: Audio signal
            sr: Sample rate
            y_harmonic: Pre-computed harmonic component from HPSS

        Returns:
            estimated_key: Pitch class (0-11, where 0=C, 1=C#, etc.)
            key_mode: Major (1) vs minor (0), with values in between for ambiguity
            harmonic_ratio: Ratio of harmonic to total content (0-1)
        """
        # Key detection using chroma features
        chroma = librosa.feature.chroma_cqt(y=y, sr=sr)
        chroma_mean = np.mean(chroma, axis=1)

        # Find the strongest pitch class (estimated key)
        estimated_key = int(np.argmax(chroma_mean))

        # Estimate major/minor mode using Krumhansl-Schmuckler key profiles
        # Simplified: compare to major and minor templates
        major_profile = np.array([6.35, 2.23, 3.48, 2.33, 4.38, 4.09, 2.52, 5.19, 2.39, 3.66, 2.29, 2.88])
        minor_profile = np.array([6.33, 2.68, 3.52, 5.38, 2.60, 3.53, 2.54, 4.75, 3.98, 2.69, 3.34, 3.17])

        # Rotate profiles to match estimated key
        major_rotated = np.roll(major_profile, estimated_key)
        minor_rotated = np.roll(minor_profile, estimated_key)

        # Correlation with profiles
        major_corr = float(np.corrcoef(chroma_mean, major_rotated)[0, 1])
        minor_corr = float(np.corrcoef(chroma_mean, minor_rotated)[0, 1])

        # Mode score: 1 = definitely major, 0 = definitely minor
        if major_corr + minor_corr > 0:
            key_mode = (major_corr + 1) / ((major_corr + 1) + (minor_corr + 1))
        else:
            key_mode = 0.5

        # Harmonic ratio using pre-computed HPSS
        harmonic_energy = float(np.sum(y_harmonic ** 2))
        total_energy = float(np.sum(y ** 2))
        if total_energy > 0:
            harmonic_ratio = harmonic_energy / total_energy
        else:
            harmonic_ratio = 0.5

        return {
            'estimated_key': float(estimated_key) / 11.0,  # Normalize to 0-1
            'key_mode': float(key_mode),
            'harmonic_ratio': float(harmonic_ratio)
        }

    def _extract_enhanced_timbral(self, y: np.ndarray, sr: int) -> Dict[str, float]:
        """
        Extract enhanced timbral features.

        Returns:
            spectral_flatness: How noise-like vs tonal (0=tonal, 1=noisy)
            spectral_bandwidth: Width of the spectrum
            spectral_rolloff_std: Variability in brightness over time
        """
        # Spectral flatness (Wiener entropy)
        flatness = librosa.feature.spectral_flatness(y=y)
        spectral_flatness = float(np.mean(flatness))

        # Spectral bandwidth
        bandwidth = librosa.feature.spectral_bandwidth(y=y, sr=sr)
        spectral_bandwidth = float(np.mean(bandwidth))

        # Spectral rolloff variability (how much brightness changes)
        rolloff = librosa.feature.spectral_rolloff(y=y, sr=sr)
        spectral_rolloff_std = float(np.std(rolloff))

        return {
            'spectral_flatness': spectral_flatness,
            'spectral_bandwidth': spectral_bandwidth,
            'spectral_rolloff_std': spectral_rolloff_std
        }

    def _extract_dynamic_features(self, y: np.ndarray, sr: int) -> Dict[str, float]:
        """
        Extract dynamic range and energy features.

        Returns:
            dynamic_range: Difference between loud and quiet parts (dB)
            energy_entropy: How evenly distributed the energy is over time
            rms_std: Variability in loudness
            loudness_variation: Coefficient of variation in RMS
        """
        # RMS energy over time
        rms = librosa.feature.rms(y=y)[0]

        # Avoid log of zero
        rms_safe = np.maximum(rms, 1e-10)

        # Dynamic range in dB
        rms_db = librosa.amplitude_to_db(rms_safe)
        dynamic_range = float(np.max(rms_db) - np.min(rms_db))

        # Energy entropy - how evenly distributed the energy is
        rms_norm = rms / (np.sum(rms) + 1e-10)
        energy_entropy = float(stats.entropy(rms_norm + 1e-10))
        # Normalize to roughly 0-1 range
        energy_entropy = min(1.0, energy_entropy / 5.0)

        # RMS standard deviation
        rms_std = float(np.std(rms))

        # Coefficient of variation (normalized variability)
        rms_mean = np.mean(rms)
        if rms_mean > 0:
            loudness_variation = float(rms_std / rms_mean)
        else:
            loudness_variation = 0.0

        return {
            'dynamic_range': dynamic_range,
            'energy_entropy': energy_entropy,
            'rms_std': rms_std,
            'loudness_variation': min(1.0, loudness_variation)  # Cap at 1
        }

    def _get_chromaprint(self, audio_path: str) -> Optional[str]:
        """Generate chromaprint fingerprint for audio file."""
        try:
            audio = AudioSegment.from_mp3(audio_path)

            with tempfile.NamedTemporaryFile(suffix='.wav', delete=False) as temp_wav:
                audio.export(temp_wav.name, format='wav')
                temp_wav_path = temp_wav.name

            try:
                duration, fingerprint = acoustid.fingerprint_file(temp_wav_path)
                return fingerprint
            finally:
                os.unlink(temp_wav_path)

        except CouldntDecodeError as e:
            logger.debug("Could not decode audio for chromaprint: %s", e)
            return None
        except (acoustid.FingerprintGenerationError, OSError) as e:
            logger.debug("Chromaprint generation failed: %s", e)
            return None
        except Exception as e:
            # Chromaprint is optional, log and continue
            logger.debug("Chromaprint unavailable: %s", e)
            return None
    
    def _create_feature_vector(self, features: Dict[str, Any]) -> np.ndarray:
        """
        Create a flat feature vector from all extracted features.

        Feature vector composition (97 dimensions):
        - MFCC: 13 values
        - Single spectral: 5 values (centroid, rolloff, zcr, tempo, rms)
        - Chroma: 12 values
        - Spectral contrast: 7 values
        - Tonnetz: 6 values
        - Rhythmic: 4 values (onset mean/std, tempo stability, percussion ratio)
        - Harmonic: 3 values (key, mode, harmonic ratio)
        - Timbral: 3 values (flatness, bandwidth, rolloff std)
        - Dynamic: 4 values (dynamic range, energy entropy, rms std, loudness var)
        - Essentia: 8 values (mood happy/sad/aggressive/relaxed, danceability,
                             voice/instrumental, arousal, valence)
        - PANNs: 32 values (pre-trained CNN14 embedding statistics)
        """
        flattened_features = []

        # ===== ORIGINAL FEATURES (43 values) =====

        # Add MFCC features (13 values)
        if isinstance(features.get('mfcc'), np.ndarray):
            mfcc_values = features['mfcc'].flatten()
            if len(mfcc_values) >= 13:
                flattened_features.extend(mfcc_values[:13].tolist())
            else:
                flattened_features.extend(mfcc_values.tolist())
                flattened_features.extend([0.0] * (13 - len(mfcc_values)))
        else:
            flattened_features.extend([0.0] * 13)

        # Add single-value spectral features (5 values)
        flattened_features.append(float(features.get('spectral_centroid', 0.0)))
        flattened_features.append(float(features.get('spectral_rolloff', 0.0)))
        flattened_features.append(float(features.get('zero_crossing_rate', 0.0)))
        flattened_features.append(float(features.get('tempo', 120.0)))
        flattened_features.append(float(features.get('rms_energy', 0.0)))

        # Add chroma features (12 values)
        if isinstance(features.get('chroma'), np.ndarray):
            chroma_values = features['chroma'].flatten()
            if len(chroma_values) >= 12:
                flattened_features.extend(chroma_values[:12].tolist())
            else:
                flattened_features.extend(chroma_values.tolist())
                flattened_features.extend([0.0] * (12 - len(chroma_values)))
        else:
            flattened_features.extend([0.0] * 12)

        # Add spectral contrast (7 values)
        if isinstance(features.get('spectral_contrast'), np.ndarray):
            contrast_values = features['spectral_contrast'].flatten()
            if len(contrast_values) >= 7:
                flattened_features.extend(contrast_values[:7].tolist())
            else:
                flattened_features.extend(contrast_values.tolist())
                flattened_features.extend([0.0] * (7 - len(contrast_values)))
        else:
            flattened_features.extend([0.0] * 7)

        # Add tonnetz features (6 values)
        if isinstance(features.get('tonnetz'), np.ndarray):
            tonnetz_values = features['tonnetz'].flatten()
            if len(tonnetz_values) >= 6:
                flattened_features.extend(tonnetz_values[:6].tolist())
            else:
                flattened_features.extend(tonnetz_values.tolist())
                flattened_features.extend([0.0] * (6 - len(tonnetz_values)))
        else:
            flattened_features.extend([0.0] * 6)

        # ===== PHASE 2: ENHANCED FEATURES (14 values) =====

        # Rhythmic features (4 values)
        flattened_features.append(float(features.get('onset_strength_mean', 0.0)))
        flattened_features.append(float(features.get('onset_strength_std', 0.0)))
        flattened_features.append(float(features.get('tempo_stability', 0.5)))
        flattened_features.append(float(features.get('percussion_ratio', 0.5)))

        # Harmonic features (3 values)
        flattened_features.append(float(features.get('estimated_key', 0.0)))
        flattened_features.append(float(features.get('key_mode', 0.5)))
        flattened_features.append(float(features.get('harmonic_ratio', 0.5)))

        # Enhanced timbral features (3 values)
        flattened_features.append(float(features.get('spectral_flatness', 0.0)))
        flattened_features.append(float(features.get('spectral_bandwidth', 0.0)))
        flattened_features.append(float(features.get('spectral_rolloff_std', 0.0)))

        # Dynamic features (4 values)
        flattened_features.append(float(features.get('dynamic_range', 0.0)))
        flattened_features.append(float(features.get('energy_entropy', 0.0)))
        flattened_features.append(float(features.get('rms_std', 0.0)))
        flattened_features.append(float(features.get('loudness_variation', 0.0)))

        # ===== PHASE 3: ESSENTIA FEATURES (8 values) =====
        essentia_vec = self.essentia_analyzer.get_feature_vector(features)
        flattened_features.extend(essentia_vec.tolist())

        # ===== PHASE 4: PANNS FEATURES (32 values) =====
        panns_vec = self.panns_analyzer.get_feature_vector(features)
        flattened_features.extend(panns_vec.tolist())

        # ===== PHASE 5: CLAP FEATURES (32 values) =====
        clap_vec = self._get_clap_feature_vector(features)
        flattened_features.extend(clap_vec.tolist())

        # ===== PHASE 6: JAMENDO FEATURES (56 values) =====
        jamendo_vec = self._get_jamendo_feature_vector(features)
        flattened_features.extend(jamendo_vec.tolist())

        # Convert to numpy array with consistent dtype
        # Ensure all values are floats and handle NaN/inf
        clean_features = []
        for val in flattened_features:
            if isinstance(val, (int, float, np.number)):
                fval = float(val)
                # Replace NaN or inf with 0
                if np.isnan(fval) or np.isinf(fval):
                    clean_features.append(0.0)
                else:
                    clean_features.append(fval)
            else:
                clean_features.append(0.0)

        result = np.array(clean_features, dtype=np.float32)

        # Verify expected size
        if len(result) != self.FEATURE_VECTOR_SIZE:
            logger.warning(
                "Feature vector size mismatch: expected %d, got %d. Padding/truncating.",
                self.FEATURE_VECTOR_SIZE, len(result)
            )
            if len(result) < self.FEATURE_VECTOR_SIZE:
                # Pad with zeros
                result = np.pad(result, (0, self.FEATURE_VECTOR_SIZE - len(result)))
            else:
                # Truncate
                result = result[:self.FEATURE_VECTOR_SIZE]

        return result

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

    def _get_default_jamendo_features(self) -> Dict[str, Any]:
        """Return default Jamendo features when not available."""
        if self.jamendo_classifier is not None:
            return self.jamendo_classifier._get_default_features()

        from .jamendo_classifier import JAMENDO_TAGS
        features = {'jamendo_available': False}
        for tag in JAMENDO_TAGS:
            features[f'jamendo_{tag}'] = 0.5
        return features

    def _get_jamendo_feature_vector(self, features: Dict[str, Any]) -> np.ndarray:
        """Extract Jamendo portion of feature vector."""
        if self.jamendo_classifier is not None:
            return self.jamendo_classifier.get_feature_vector(features)

        from .jamendo_classifier import JAMENDO_TAGS
        vector = []
        for tag in JAMENDO_TAGS:
            vector.append(float(features.get(f'jamendo_{tag}', 0.5)))
        return np.array(vector, dtype=np.float32)