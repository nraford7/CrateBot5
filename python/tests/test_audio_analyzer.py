"""
Tests for audio_analyzer.py - Audio feature extraction.
"""

import pytest
import numpy as np


class TestAudioAnalyzer:
    """Tests for AudioAnalyzer class."""

    def test_feature_vector_dimensions(self, test_audio_path):
        """Feature vector should match FEATURE_VECTOR_SIZE."""
        from core.audio_analyzer import AudioAnalyzer

        analyzer = AudioAnalyzer()
        features = analyzer.extract_features(str(test_audio_path))

        assert 'feature_vector' in features
        assert features['feature_vector'].shape == (AudioAnalyzer.FEATURE_VECTOR_SIZE,), \
            f"Expected {AudioAnalyzer.FEATURE_VECTOR_SIZE} dimensions, got {features['feature_vector'].shape}"

    def test_feature_vector_dtype(self, test_audio_path):
        """Feature vector should be float32."""
        from core.audio_analyzer import AudioAnalyzer

        analyzer = AudioAnalyzer()
        features = analyzer.extract_features(str(test_audio_path))

        assert features['feature_vector'].dtype == np.float32

    def test_feature_vector_no_nan(self, test_audio_path):
        """Feature vector should contain no NaN values."""
        from core.audio_analyzer import AudioAnalyzer

        analyzer = AudioAnalyzer()
        features = analyzer.extract_features(str(test_audio_path))

        assert not np.isnan(features['feature_vector']).any(), \
            "Feature vector contains NaN values"

    def test_feature_vector_no_inf(self, test_audio_path):
        """Feature vector should contain no infinite values."""
        from core.audio_analyzer import AudioAnalyzer

        analyzer = analyzer = AudioAnalyzer()
        features = analyzer.extract_features(str(test_audio_path))

        assert not np.isinf(features['feature_vector']).any(), \
            "Feature vector contains infinite values"

    def test_tempo_extraction(self, test_audio_path):
        """Tempo should be a reasonable BPM value."""
        from core.audio_analyzer import AudioAnalyzer

        analyzer = AudioAnalyzer()
        features = analyzer.extract_features(str(test_audio_path))

        assert 'tempo' in features
        # Most electronic music is 60-180 BPM
        assert 30 <= features['tempo'] <= 250, \
            f"Tempo {features['tempo']} seems unreasonable"

    def test_file_not_found_raises_error(self):
        """Should raise an error for non-existent file."""
        from core.audio_analyzer import AudioAnalyzer

        analyzer = AudioAnalyzer()

        with pytest.raises(Exception):
            analyzer.extract_features("/nonexistent/path/audio.mp3")

    def test_mfcc_features_present(self, test_audio_path):
        """MFCC features should be extracted."""
        from core.audio_analyzer import AudioAnalyzer

        analyzer = AudioAnalyzer()
        features = analyzer.extract_features(str(test_audio_path))

        assert 'mfcc' in features
        assert len(features['mfcc']) == 13

    def test_chroma_features_present(self, test_audio_path):
        """Chroma features should be extracted."""
        from core.audio_analyzer import AudioAnalyzer

        analyzer = AudioAnalyzer()
        features = analyzer.extract_features(str(test_audio_path))

        assert 'chroma' in features
        assert len(features['chroma']) == 12


class TestFastAudioAnalyzer:
    """Tests for FastAudioAnalyzer class."""

    def test_fast_analyzer_dimensions(self, test_audio_path):
        """Fast analyzer should produce same dimensions as full analyzer."""
        from core.fast_analyzer import FastAudioAnalyzer

        analyzer = FastAudioAnalyzer(duration=30.0)
        features = analyzer.extract_features(str(test_audio_path))

        assert 'feature_vector' in features
        assert features['feature_vector'].shape == (FastAudioAnalyzer.FEATURE_VECTOR_SIZE,)

    def test_fast_analyzer_no_nan(self, test_audio_path):
        """Fast analyzer feature vector should contain no NaN values."""
        from core.fast_analyzer import FastAudioAnalyzer

        analyzer = FastAudioAnalyzer(duration=30.0)
        features = analyzer.extract_features(str(test_audio_path))

        assert not np.isnan(features['feature_vector']).any()
