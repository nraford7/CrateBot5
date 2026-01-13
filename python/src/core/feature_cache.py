"""
Feature Cache System for CrateBot

SQLite-based persistent cache for audio feature vectors.
Eliminates redundant audio analysis by caching features keyed by:
- File path
- File modification time (to detect changes)
- Analyzer version (to invalidate on updates)

Thread-safe: Uses thread-local connections and write locking.
Expected speedup: 10x+ for repeat operations (training -> tagging -> refinement)
"""

import hashlib
import logging
import os
import pickle
import sqlite3
import threading
from contextlib import contextmanager
from datetime import datetime
from pathlib import Path
from typing import Dict, Any, Optional, Tuple

import numpy as np

from .exceptions import CacheError, CacheReadError, CacheWriteError, CacheCorruptedError
from .constants import CACHE_VERSION, CACHE_MTIME_TOLERANCE
from .paths import get_cratebot_dir

logger = logging.getLogger(__name__)


class FeatureCache:
    """
    SQLite-based cache for audio feature vectors.

    Cache key: (file_path, file_mtime, cache_version)
    Cache value: feature_vector (97 floats) + metadata

    Usage:
        cache = FeatureCache()

        # Check cache before analysis
        cached = cache.get(file_path)
        if cached:
            feature_vector = cached['feature_vector']
        else:
            features = analyzer.extract_features(file_path)
            cache.put(file_path, features)
            feature_vector = features['feature_vector']
    """

    def __init__(self, cache_path: Optional[str] = None):
        """
        Initialize feature cache.

        Args:
            cache_path: Path to SQLite database. Default: ~/.cratebot/feature_cache.db
        """
        if cache_path:
            self.cache_path = Path(cache_path)
        else:
            self.cache_path = get_cratebot_dir() / "feature_cache.db"

        self.cache_path.parent.mkdir(parents=True, exist_ok=True)

        # Thread-safety: thread-local storage for connections
        self._local = threading.local()
        # Lock for serializing write operations
        self._write_lock = threading.Lock()

        self._init_db()

    def _init_db(self):
        """Initialize the SQLite database with WAL mode for better concurrency."""
        conn = sqlite3.connect(str(self.cache_path))
        cursor = conn.cursor()

        # Enable WAL mode for better concurrency (allows concurrent reads during writes)
        cursor.execute("PRAGMA journal_mode=WAL")

        # Create table if not exists
        cursor.execute("""
            CREATE TABLE IF NOT EXISTS features (
                file_path TEXT,
                file_mtime REAL,
                cache_version INTEGER,
                feature_vector BLOB,
                essentia_features BLOB,
                created_at TEXT,
                PRIMARY KEY (file_path, cache_version)
            )
        """)

        # Create index for faster lookups
        cursor.execute("""
            CREATE INDEX IF NOT EXISTS idx_file_path ON features(file_path)
        """)

        conn.commit()
        conn.close()

    @contextmanager
    def _get_connection(self):
        """
        Get a thread-local database connection.

        Each thread gets its own connection to avoid sqlite3.ProgrammingError
        when accessing from multiple threads (e.g., GUI background workers).
        """
        if not hasattr(self._local, 'conn') or self._local.conn is None:
            self._local.conn = sqlite3.connect(
                str(self.cache_path),
                check_same_thread=False,
                timeout=30.0
            )
            # Enable WAL mode on this connection too
            self._local.conn.execute("PRAGMA journal_mode=WAL")

        try:
            yield self._local.conn
        except sqlite3.Error as e:
            logger.error("Database error: %s", e)
            self._local.conn.rollback()
            raise CacheError(f"Database operation failed: {e}") from e

    def _get_file_mtime(self, file_path: str) -> float:
        """Get file modification time."""
        try:
            return os.path.getmtime(file_path)
        except OSError:
            return 0.0

    def get(self, file_path: str) -> Optional[Dict[str, Any]]:
        """
        Get cached features for a file.

        Thread-safe: Uses thread-local database connection.

        Returns None if:
        - File not in cache
        - File has been modified since caching
        - Cache version mismatch

        Args:
            file_path: Path to the audio file

        Returns:
            Dictionary with 'feature_vector' and 'essentia_features', or None
        """
        file_path = os.path.abspath(file_path)
        current_mtime = self._get_file_mtime(file_path)

        with self._get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute("""
                SELECT feature_vector, essentia_features, file_mtime
                FROM features
                WHERE file_path = ? AND cache_version = ?
            """, (file_path, CACHE_VERSION))
            row = cursor.fetchone()

        if row is None:
            return None

        feature_blob, essentia_blob, cached_mtime = row

        # Check if file has been modified
        if abs(current_mtime - cached_mtime) > CACHE_MTIME_TOLERANCE:
            return None

        # Deserialize
        try:
            feature_vector = pickle.loads(feature_blob)
            essentia_features = pickle.loads(essentia_blob) if essentia_blob else {}

            return {
                'feature_vector': feature_vector,
                'essentia_features': essentia_features,
            }
        except (pickle.UnpicklingError, ValueError, TypeError) as e:
            logger.warning("Cache entry corrupted for %s: %s", file_path, e)
            return None
        except Exception as e:
            logger.debug("Unexpected cache read error for %s: %s", file_path, e)
            return None

    def put(self, file_path: str, features: Dict[str, Any]) -> bool:
        """
        Store features in cache.

        Thread-safe: Uses write lock to serialize concurrent writes.

        Args:
            file_path: Path to the audio file
            features: Feature dictionary from analyzer (must contain 'feature_vector')

        Returns:
            True if successfully cached
        """
        file_path = os.path.abspath(file_path)
        current_mtime = self._get_file_mtime(file_path)

        if 'feature_vector' not in features:
            return False

        # Serialize
        feature_blob = pickle.dumps(features['feature_vector'])

        # Extract Essentia-specific features for metadata
        essentia_features = {
            k: v for k, v in features.items()
            if k.startswith('essentia_')
        }
        essentia_blob = pickle.dumps(essentia_features)

        # Use write lock to serialize writes from multiple threads
        with self._write_lock:
            with self._get_connection() as conn:
                cursor = conn.cursor()
                cursor.execute("""
                    INSERT OR REPLACE INTO features
                    (file_path, file_mtime, cache_version, feature_vector, essentia_features, created_at)
                    VALUES (?, ?, ?, ?, ?, ?)
                """, (
                    file_path,
                    current_mtime,
                    CACHE_VERSION,
                    feature_blob,
                    essentia_blob,
                    datetime.now().isoformat()
                ))
                conn.commit()

        return True

    def has(self, file_path: str) -> bool:
        """Check if file is cached (and not stale)."""
        return self.get(file_path) is not None

    def get_stats(self) -> Dict[str, Any]:
        """Get cache statistics. Thread-safe."""
        with self._get_connection() as conn:
            cursor = conn.cursor()

            cursor.execute("SELECT COUNT(*) FROM features WHERE cache_version = ?", (CACHE_VERSION,))
            total = cursor.fetchone()[0]

            cursor.execute("SELECT COUNT(*) FROM features")
            total_all_versions = cursor.fetchone()[0]

        # Get cache size
        cache_size_bytes = os.path.getsize(self.cache_path) if self.cache_path.exists() else 0

        return {
            'cached_files': total,
            'total_entries': total_all_versions,
            'cache_version': CACHE_VERSION,
            'cache_size_mb': cache_size_bytes / (1024 * 1024),
            'cache_path': str(self.cache_path),
        }

    def clear(self, version_only: bool = True) -> int:
        """
        Clear the cache. Thread-safe with write lock.

        Args:
            version_only: If True, only clear current version entries

        Returns:
            Number of entries removed
        """
        with self._write_lock:
            with self._get_connection() as conn:
                cursor = conn.cursor()

                if version_only:
                    cursor.execute("DELETE FROM features WHERE cache_version = ?", (CACHE_VERSION,))
                else:
                    cursor.execute("DELETE FROM features")

                deleted = cursor.rowcount
                conn.commit()

                # Vacuum to reclaim space
                cursor.execute("VACUUM")

        return deleted

    def cleanup_stale(self) -> int:
        """
        Remove entries for files that no longer exist. Thread-safe with write lock.

        Returns:
            Number of entries removed
        """
        # First, get all file paths (read operation)
        with self._get_connection() as conn:
            cursor = conn.cursor()
            cursor.execute("SELECT file_path FROM features")
            rows = cursor.fetchall()

        # Find stale entries
        stale_paths = [fp for (fp,) in rows if not os.path.exists(fp)]

        if not stale_paths:
            return 0

        # Delete stale entries (write operation with lock)
        with self._write_lock:
            with self._get_connection() as conn:
                cursor = conn.cursor()
                for file_path in stale_paths:
                    cursor.execute("DELETE FROM features WHERE file_path = ?", (file_path,))
                conn.commit()
                cursor.execute("VACUUM")

        return len(stale_paths)


class CachedAnalyzer:
    """
    Wrapper around FastAudioAnalyzer that uses feature caching.

    Usage:
        analyzer = CachedAnalyzer()
        features = analyzer.extract_features(file_path)  # Uses cache if available
    """

    def __init__(self, cache: Optional[FeatureCache] = None, duration: float = 45.0):
        """
        Initialize cached analyzer.

        Args:
            cache: FeatureCache instance. Creates new one if None.
            duration: Audio duration for analysis (default 45s from 33% into track)
        """
        from .fast_analyzer import FastAudioAnalyzer

        self.cache = cache or FeatureCache()
        self.analyzer = FastAudioAnalyzer(duration=duration)
        self._cache_hits = 0
        self._cache_misses = 0

    def extract_features(self, audio_path: str, force_recompute: bool = False) -> Dict[str, Any]:
        """
        Extract features with caching.

        Args:
            audio_path: Path to audio file
            force_recompute: If True, bypass cache and recompute

        Returns:
            Feature dictionary
        """
        if not force_recompute:
            cached = self.cache.get(audio_path)
            if cached:
                self._cache_hits += 1
                # Reconstruct minimal features dict for compatibility
                return {
                    'feature_vector': cached['feature_vector'],
                    **cached.get('essentia_features', {}),
                    '_from_cache': True,
                }

        # Cache miss - compute features
        self._cache_misses += 1
        features = self.analyzer.extract_features(audio_path)

        # Store in cache
        self.cache.put(audio_path, features)

        return features

    def get_cache_stats(self) -> Dict[str, Any]:
        """Get cache hit/miss statistics."""
        total = self._cache_hits + self._cache_misses
        hit_rate = self._cache_hits / total if total > 0 else 0

        return {
            'cache_hits': self._cache_hits,
            'cache_misses': self._cache_misses,
            'hit_rate': hit_rate,
            **self.cache.get_stats()
        }


# Global cache instance for convenience
_global_cache: Optional[FeatureCache] = None


def get_global_cache() -> FeatureCache:
    """Get or create global feature cache instance."""
    global _global_cache
    if _global_cache is None:
        _global_cache = FeatureCache()
    return _global_cache
