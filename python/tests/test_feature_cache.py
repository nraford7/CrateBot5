"""
Tests for feature_cache.py - SQLite feature caching.
"""

import pytest
import numpy as np
import os
import tempfile


class TestFeatureCache:
    """Tests for FeatureCache class."""

    def test_cache_put_and_get(self, temp_cache_db, mock_feature_vector):
        """Should store and retrieve features."""
        from core.feature_cache import FeatureCache

        cache = FeatureCache(cache_path=temp_cache_db)

        # Create a temp file to use as "audio file"
        with tempfile.NamedTemporaryFile(suffix='.mp3', delete=False) as f:
            f.write(b'fake audio data')
            temp_file = f.name

        try:
            features = {'feature_vector': mock_feature_vector}

            # Store
            result = cache.put(temp_file, features)
            assert result is True

            # Retrieve
            cached = cache.get(temp_file)

            assert cached is not None
            assert 'feature_vector' in cached
            np.testing.assert_array_almost_equal(
                cached['feature_vector'],
                mock_feature_vector
            )
        finally:
            os.unlink(temp_file)

    def test_cache_miss_returns_none(self, temp_cache_db):
        """Should return None for uncached files."""
        from core.feature_cache import FeatureCache

        cache = FeatureCache(cache_path=temp_cache_db)

        result = cache.get("/nonexistent/file.mp3")

        assert result is None

    def test_cache_invalidation_on_file_change(self, temp_cache_db, mock_feature_vector):
        """Should invalidate cache when file is modified."""
        from core.feature_cache import FeatureCache
        import time

        cache = FeatureCache(cache_path=temp_cache_db)

        with tempfile.NamedTemporaryFile(suffix='.mp3', delete=False) as f:
            f.write(b'original data')
            temp_file = f.name

        try:
            features = {'feature_vector': mock_feature_vector}
            cache.put(temp_file, features)

            # Verify cached
            assert cache.get(temp_file) is not None

            # Modify file (change mtime)
            time.sleep(1.1)  # Ensure mtime changes
            with open(temp_file, 'wb') as f:
                f.write(b'modified data')

            # Cache should be invalidated
            result = cache.get(temp_file)
            assert result is None

        finally:
            os.unlink(temp_file)

    def test_cache_has_method(self, temp_cache_db, mock_feature_vector):
        """has() method should work correctly."""
        from core.feature_cache import FeatureCache

        cache = FeatureCache(cache_path=temp_cache_db)

        with tempfile.NamedTemporaryFile(suffix='.mp3', delete=False) as f:
            f.write(b'test data')
            temp_file = f.name

        try:
            assert cache.has(temp_file) is False

            features = {'feature_vector': mock_feature_vector}
            cache.put(temp_file, features)

            assert cache.has(temp_file) is True

        finally:
            os.unlink(temp_file)

    def test_cache_stats(self, temp_cache_db, mock_feature_vector):
        """get_stats() should return cache information."""
        from core.feature_cache import FeatureCache

        cache = FeatureCache(cache_path=temp_cache_db)

        stats = cache.get_stats()

        assert 'cached_files' in stats
        assert 'cache_version' in stats
        assert 'cache_path' in stats

    def test_cache_clear(self, temp_cache_db, mock_feature_vector):
        """clear() should remove cached entries."""
        from core.feature_cache import FeatureCache

        cache = FeatureCache(cache_path=temp_cache_db)

        with tempfile.NamedTemporaryFile(suffix='.mp3', delete=False) as f:
            f.write(b'test data')
            temp_file = f.name

        try:
            features = {'feature_vector': mock_feature_vector}
            cache.put(temp_file, features)

            assert cache.has(temp_file) is True

            cache.clear()

            assert cache.has(temp_file) is False

        finally:
            os.unlink(temp_file)


class TestCachedAnalyzer:
    """Tests for CachedAnalyzer wrapper class."""

    def test_cached_analyzer_uses_cache(self, temp_cache_db, test_audio_path):
        """CachedAnalyzer should use cache on second call."""
        from core.feature_cache import CachedAnalyzer, FeatureCache

        cache = FeatureCache(cache_path=temp_cache_db)
        analyzer = CachedAnalyzer(cache=cache, duration=30.0)

        # First call - cache miss
        features1 = analyzer.extract_features(str(test_audio_path))
        stats1 = analyzer.get_cache_stats()

        assert stats1['cache_misses'] == 1
        assert stats1['cache_hits'] == 0

        # Second call - cache hit
        features2 = analyzer.extract_features(str(test_audio_path))
        stats2 = analyzer.get_cache_stats()

        assert stats2['cache_hits'] == 1

        # Features should be equivalent
        np.testing.assert_array_almost_equal(
            features1['feature_vector'],
            features2['feature_vector']
        )

    def test_force_recompute_bypasses_cache(self, temp_cache_db, test_audio_path):
        """force_recompute=True should bypass cache."""
        from core.feature_cache import CachedAnalyzer, FeatureCache

        cache = FeatureCache(cache_path=temp_cache_db)
        analyzer = CachedAnalyzer(cache=cache, duration=30.0)

        # First call
        analyzer.extract_features(str(test_audio_path))

        # Second call with force_recompute
        analyzer.extract_features(str(test_audio_path), force_recompute=True)

        stats = analyzer.get_cache_stats()

        # Should have 2 misses (both computed fresh)
        assert stats['cache_misses'] == 2
