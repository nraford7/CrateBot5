"""
Lazy Model Loading Manager for CrateBot4

Singleton pattern for heavy ML model instances (PANNs, CLAP, Essentia).
Models are loaded on first use, not on initialization, providing:
- Faster startup times (models loaded only when needed)
- Shared instances across analyzer objects (no duplicate memory)
- Thread-safe lazy initialization

Usage:
    # Instead of:
    panns = PANNsAnalyzer(auto_load=True)  # Blocks for 2-5 seconds

    # Use:
    panns = ModelLoader.get_panns_analyzer()  # Instant if already loaded
"""

import logging
import threading
from typing import Optional, Dict, Any

logger = logging.getLogger(__name__)


class ModelLoader:
    """
    Singleton manager for lazy-loaded ML models.

    Provides thread-safe lazy initialization of heavy model instances
    that are shared across the application.
    """

    # Class-level storage for model instances
    _instances: Dict[str, Any] = {}
    _lock = threading.Lock()
    _loading: Dict[str, bool] = {}

    @classmethod
    def get_panns_analyzer(cls) -> Optional[Any]:
        """
        Get or create PANNs analyzer instance.

        Returns:
            PANNsAnalyzer instance, or None if unavailable
        """
        return cls._get_or_create('panns', cls._create_panns)

    @classmethod
    def get_clap_analyzer(cls) -> Optional[Any]:
        """
        Get or create CLAP analyzer instance.

        Returns:
            CLAPAnalyzer instance, or None if unavailable
        """
        return cls._get_or_create('clap', cls._create_clap)

    @classmethod
    def get_jamendo_classifier(cls) -> Optional[Any]:
        """
        Get or create Jamendo classifier instance.

        Returns:
            JamendoClassifier instance, or None if unavailable
        """
        return cls._get_or_create('jamendo', cls._create_jamendo)

    @classmethod
    def get_essentia_analyzer(cls) -> Optional[Any]:
        """
        Get or create Essentia analyzer instance.

        Returns:
            EssentiaAnalyzer instance, or None if unavailable
        """
        return cls._get_or_create('essentia', cls._create_essentia)

    @classmethod
    def _get_or_create(cls, key: str, factory) -> Optional[Any]:
        """
        Thread-safe lazy initialization with double-checked locking.

        Args:
            key: Instance key
            factory: Factory function to create instance

        Returns:
            Instance, or None if creation failed
        """
        # Fast path: already loaded
        if key in cls._instances:
            return cls._instances[key]

        # Slow path: need to load
        with cls._lock:
            # Double-check inside lock
            if key in cls._instances:
                return cls._instances[key]

            # Check if another thread is loading
            if cls._loading.get(key):
                logger.debug("Waiting for %s model to finish loading...", key)
                # Could implement wait/notify, but for simplicity just return None
                return None

            cls._loading[key] = True

        try:
            logger.info("Loading %s model (first use)...", key)
            instance = factory()
            if instance is not None:
                with cls._lock:
                    cls._instances[key] = instance
                logger.info("Loaded %s model successfully", key)
            return instance
        except Exception as e:
            logger.warning("Failed to load %s model: %s", key, e)
            return None
        finally:
            with cls._lock:
                cls._loading[key] = False

    @classmethod
    def _create_panns(cls) -> Optional[Any]:
        """Create PANNs analyzer instance."""
        try:
            from .panns_analyzer import PANNsAnalyzer, is_panns_available
            if not is_panns_available():
                return None
            return PANNsAnalyzer(auto_load=True)
        except ImportError:
            return None
        except Exception as e:
            logger.error("Error creating PANNs analyzer: %s", e)
            return None

    @classmethod
    def _create_clap(cls) -> Optional[Any]:
        """Create CLAP analyzer instance."""
        try:
            from .clap_analyzer import CLAPAnalyzer, is_clap_available
            if not is_clap_available():
                return None
            return CLAPAnalyzer(auto_load=True)
        except ImportError:
            return None
        except Exception as e:
            logger.error("Error creating CLAP analyzer: %s", e)
            return None

    @classmethod
    def _create_jamendo(cls) -> Optional[Any]:
        """Create Jamendo classifier instance."""
        try:
            from .jamendo_classifier import JamendoClassifier, is_jamendo_available
            if not is_jamendo_available():
                return None
            return JamendoClassifier(auto_load=True)
        except ImportError:
            return None
        except Exception as e:
            logger.error("Error creating Jamendo classifier: %s", e)
            return None

    @classmethod
    def _create_essentia(cls) -> Optional[Any]:
        """Create Essentia analyzer instance."""
        try:
            from .essentia_analyzer import EssentiaAnalyzer
            return EssentiaAnalyzer(auto_load=True)
        except ImportError:
            return None
        except Exception as e:
            logger.error("Error creating Essentia analyzer: %s", e)
            return None

    @classmethod
    def preload_all(cls, include_optional: bool = True) -> Dict[str, bool]:
        """
        Preload all models (useful for background initialization).

        Args:
            include_optional: Whether to load optional models (PANNs, CLAP, Jamendo)

        Returns:
            Dict mapping model name to success status
        """
        results = {}

        # Always load Essentia (required)
        results['essentia'] = cls.get_essentia_analyzer() is not None

        if include_optional:
            results['panns'] = cls.get_panns_analyzer() is not None
            results['clap'] = cls.get_clap_analyzer() is not None
            results['jamendo'] = cls.get_jamendo_classifier() is not None

        return results

    @classmethod
    def is_loaded(cls, key: str) -> bool:
        """Check if a model is already loaded."""
        return key in cls._instances

    @classmethod
    def get_loaded_models(cls) -> list:
        """Get list of currently loaded model names."""
        return list(cls._instances.keys())

    @classmethod
    def unload(cls, key: str) -> bool:
        """
        Unload a model to free memory.

        Args:
            key: Model key ('panns', 'clap', 'jamendo', 'essentia')

        Returns:
            True if model was unloaded
        """
        with cls._lock:
            if key in cls._instances:
                del cls._instances[key]
                logger.info("Unloaded %s model", key)
                return True
            return False

    @classmethod
    def unload_all(cls) -> None:
        """Unload all models to free memory."""
        with cls._lock:
            keys = list(cls._instances.keys())
            for key in keys:
                del cls._instances[key]
            logger.info("Unloaded all models: %s", keys)

    @classmethod
    def get_memory_usage(cls) -> Dict[str, str]:
        """
        Get approximate memory usage of loaded models.

        Returns:
            Dict mapping model name to memory estimate
        """
        estimates = {
            'panns': '~500MB',
            'clap': '~500MB',
            'jamendo': '~10MB',
            'essentia': '~50MB',
        }

        return {
            key: estimates.get(key, 'unknown')
            for key in cls._instances.keys()
        }


def preload_models_in_background() -> None:
    """
    Start loading models in a background thread.

    Call this during application startup for faster first prediction.
    """
    import threading

    def _load():
        logger.info("Background model preloading started...")
        results = ModelLoader.preload_all(include_optional=True)
        loaded = [k for k, v in results.items() if v]
        logger.info("Background model preloading complete: %s", loaded)

    thread = threading.Thread(target=_load, daemon=True)
    thread.start()
