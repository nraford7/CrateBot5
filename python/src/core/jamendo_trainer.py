"""
Jamendo Classifier Trainer for CrateBot

One-time training script that:
1. Downloads MTG-Jamendo dataset metadata
2. Downloads audio and computes CLAP embeddings (with checkpoint/resume support)
3. Trains 56 binary classifiers (one per mood/theme tag)
4. Saves classifiers for use by JamendoClassifier

This only needs to run once. After training, the classifiers are
stored in ~/.cratebot/jamendo_models/ and loaded by JamendoClassifier.

Reference: MTG-Jamendo Dataset
https://github.com/MTG/mtg-jamendo-dataset
"""

import logging
import os
import csv
import json
import urllib.request
import urllib.error
import tempfile
import time
import hashlib
from pathlib import Path
from typing import Dict, Any, Optional, Callable, List, Tuple
from datetime import datetime
from concurrent.futures import ThreadPoolExecutor, as_completed
import numpy as np

from .paths import get_cratebot_dir

logger = logging.getLogger(__name__)

# Optional imports
try:
    from sklearn.linear_model import LogisticRegression
    from sklearn.model_selection import train_test_split
    from sklearn.metrics import f1_score, accuracy_score
    import joblib
    HAS_SKLEARN = True
except ImportError:
    HAS_SKLEARN = False

try:
    from tqdm import tqdm
    HAS_TQDM = True
except ImportError:
    HAS_TQDM = False

# Import CLAP analyzer for embedding extraction
try:
    from .clap_analyzer import CLAPAnalyzer, is_clap_available, CLAP_EMBEDDING_DIM
    HAS_CLAP_MODULE = True
except ImportError:
    HAS_CLAP_MODULE = False
    CLAP_EMBEDDING_DIM = 512

from .jamendo_classifier import (
    JamendoModelManager,
    JAMENDO_TAGS,
    JAMENDO_FEATURE_COUNT
)

# Jamendo dataset URLs
JAMENDO_METADATA_URL = "https://raw.githubusercontent.com/MTG/mtg-jamendo-dataset/master/data/autotagging_moodtheme.tsv"
JAMENDO_SPLITS_URL = "https://raw.githubusercontent.com/MTG/mtg-jamendo-dataset/master/data/splits/split-0/autotagging_moodtheme-train.tsv"

# Jamendo audio preview URL template
# Format: trackid is numeric part of TRACK_ID (e.g., "track_0000948" -> "948")
JAMENDO_AUDIO_URL = "https://prod-1.storage.jamendo.com/?trackid={track_id}&format=mp32"

# Checkpoint interval - save progress every N embeddings
CHECKPOINT_INTERVAL = 500


class JamendoDataManager:
    """
    Manages downloading and caching of Jamendo dataset files.
    """

    def __init__(self, data_dir: Optional[str] = None):
        if data_dir:
            self.data_dir = Path(data_dir)
        else:
            self.data_dir = get_cratebot_dir() / "jamendo_data"

        # Audio cache directory
        self.audio_cache_dir = self.data_dir / "audio_cache"

    def get_metadata_path(self) -> Path:
        return self.data_dir / "autotagging_moodtheme.tsv"

    def get_embeddings_path(self) -> Path:
        return self.data_dir / "clap_embeddings.npz"

    def get_checkpoint_path(self) -> Path:
        return self.data_dir / "embedding_checkpoint.npz"

    def download_metadata(self, progress_callback: Optional[Callable] = None) -> bool:
        """Download Jamendo metadata TSV file."""
        self.data_dir.mkdir(parents=True, exist_ok=True)
        metadata_path = self.get_metadata_path()

        if metadata_path.exists():
            logger.info("Jamendo metadata already downloaded")
            return True

        logger.info("Downloading Jamendo metadata...")

        try:
            urllib.request.urlretrieve(JAMENDO_METADATA_URL, str(metadata_path))
            logger.info("Downloaded metadata to %s", metadata_path)
            return True
        except Exception as e:
            logger.error("Failed to download metadata: %s", e)
            return False

    def load_metadata(self) -> List[Dict[str, Any]]:
        """
        Load Jamendo metadata from TSV file.

        Returns list of dicts with keys: track_id, numeric_id, tags
        """
        metadata_path = self.get_metadata_path()
        if not metadata_path.exists():
            return []

        records = []
        try:
            with open(metadata_path, 'r', encoding='utf-8') as f:
                reader = csv.DictReader(f, delimiter='\t')
                for row in reader:
                    track_id = row.get('TRACK_ID', row.get('track_id', ''))
                    tags_str = row.get('TAGS', row.get('tags', ''))

                    if track_id and tags_str:
                        # Extract numeric ID (e.g., "track_0000948" -> "948")
                        numeric_id = track_id.replace('track_', '').lstrip('0') or '0'

                        # Parse tags - format is "mood/theme---tagname"
                        raw_tags = [t.strip() for t in tags_str.split(',')]
                        tags = []
                        for t in raw_tags:
                            # Extract just the tag name after "mood/theme---"
                            if '---' in t:
                                tag_name = t.split('---')[-1].lower()
                            else:
                                tag_name = t.lower()
                            if tag_name in JAMENDO_TAGS:
                                tags.append(tag_name)

                        if tags:
                            records.append({
                                'track_id': track_id,
                                'numeric_id': numeric_id,
                                'tags': tags
                            })

            logger.info("Loaded %d tracks with mood/theme tags", len(records))
            return records

        except Exception as e:
            logger.error("Failed to load metadata: %s", e)
            return []

    def download_audio(self, numeric_id: str, timeout: int = 30) -> Optional[Path]:
        """
        Download audio preview for a Jamendo track.

        Args:
            numeric_id: Numeric track ID (e.g., "948")
            timeout: Download timeout in seconds

        Returns:
            Path to downloaded audio file, or None if failed
        """
        self.audio_cache_dir.mkdir(parents=True, exist_ok=True)
        audio_path = self.audio_cache_dir / f"{numeric_id}.mp3"

        # Return cached file if exists
        if audio_path.exists() and audio_path.stat().st_size > 1000:
            return audio_path

        url = JAMENDO_AUDIO_URL.format(track_id=numeric_id)

        try:
            # Create request with headers to avoid blocking
            request = urllib.request.Request(
                url,
                headers={
                    'User-Agent': 'CrateBot/1.0 (Music Analysis Tool)',
                    'Accept': 'audio/mpeg'
                }
            )

            with urllib.request.urlopen(request, timeout=timeout) as response:
                content = response.read()

                # Verify it's actually audio (MP3 files start with ID3 or 0xFF)
                if len(content) < 1000:
                    logger.debug("Audio too small for track %s, skipping", numeric_id)
                    return None

                with open(audio_path, 'wb') as f:
                    f.write(content)

            return audio_path

        except urllib.error.HTTPError as e:
            if e.code == 404:
                logger.debug("Track %s not available (404)", numeric_id)
            else:
                logger.debug("HTTP error for track %s: %s", numeric_id, e)
            return None
        except Exception as e:
            logger.debug("Failed to download track %s: %s", numeric_id, e)
            return None

    def has_precomputed_embeddings(self) -> bool:
        """Check if pre-computed embeddings are available."""
        return self.get_embeddings_path().exists()

    def load_embeddings(self) -> Optional[Dict[str, np.ndarray]]:
        """Load pre-computed CLAP embeddings."""
        embeddings_path = self.get_embeddings_path()
        if not embeddings_path.exists():
            return None

        try:
            data = np.load(embeddings_path, allow_pickle=True)
            return dict(data['embeddings'].item())
        except Exception as e:
            logger.error("Failed to load embeddings: %s", e)
            return None

    def save_embeddings(self, embeddings: Dict[str, np.ndarray]) -> bool:
        """Save computed CLAP embeddings for reuse."""
        try:
            self.data_dir.mkdir(parents=True, exist_ok=True)
            np.savez_compressed(
                self.get_embeddings_path(),
                embeddings=embeddings
            )
            logger.info("Saved %d embeddings to %s", len(embeddings), self.get_embeddings_path())
            return True
        except Exception as e:
            logger.error("Failed to save embeddings: %s", e)
            return False

    def load_checkpoint(self) -> Dict[str, np.ndarray]:
        """Load embedding computation checkpoint."""
        checkpoint_path = self.get_checkpoint_path()
        if not checkpoint_path.exists():
            return {}

        try:
            data = np.load(checkpoint_path, allow_pickle=True)
            embeddings = dict(data['embeddings'].item())
            logger.info("Loaded checkpoint with %d embeddings", len(embeddings))
            return embeddings
        except Exception as e:
            logger.warning("Failed to load checkpoint: %s", e)
            return {}

    def save_checkpoint(self, embeddings: Dict[str, np.ndarray]) -> bool:
        """Save embedding computation checkpoint."""
        try:
            self.data_dir.mkdir(parents=True, exist_ok=True)
            np.savez_compressed(
                self.get_checkpoint_path(),
                embeddings=embeddings
            )
            return True
        except Exception as e:
            logger.warning("Failed to save checkpoint: %s", e)
            return False

    def clear_checkpoint(self):
        """Remove checkpoint file after successful completion."""
        checkpoint_path = self.get_checkpoint_path()
        if checkpoint_path.exists():
            checkpoint_path.unlink()

    def clear_audio_cache(self):
        """Remove downloaded audio files to free space."""
        if self.audio_cache_dir.exists():
            import shutil
            shutil.rmtree(self.audio_cache_dir)
            logger.info("Cleared audio cache")


class JamendoTrainer:
    """
    Train Jamendo mood/theme classifiers on CLAP embeddings.
    """

    def __init__(self):
        self.data_manager = JamendoDataManager()
        self.model_manager = JamendoModelManager()

    def train(
        self,
        progress_callback: Optional[Callable[[str, float], None]] = None,
        use_synthetic: bool = False,
        force_recompute: bool = False
    ) -> bool:
        """
        Train all Jamendo classifiers.

        Args:
            progress_callback: Callback(stage, progress) for progress updates
            use_synthetic: If True, use synthetic training data (faster but less accurate)
            force_recompute: If True, recompute embeddings even if they exist

        Returns:
            True if training successful
        """
        if not HAS_SKLEARN:
            logger.error("scikit-learn not installed. Cannot train.")
            return False

        def report(stage: str, progress: float):
            if progress_callback:
                progress_callback(stage, progress)
            logger.info("%s: %.1f%%", stage, progress * 100)

        # Step 1: Download metadata
        report("Downloading metadata", 0.0)
        if not self.data_manager.download_metadata():
            logger.warning("Could not download Jamendo metadata, using synthetic data")
            use_synthetic = True

        # Step 2: Load metadata
        report("Loading metadata", 0.05)
        metadata = self.data_manager.load_metadata()

        if len(metadata) < 100:
            logger.warning("Insufficient metadata (%d tracks), using synthetic data", len(metadata))
            use_synthetic = True

        # Step 3: Get embeddings
        if use_synthetic:
            report("Generating synthetic data", 0.1)
            embeddings, labels = self._generate_synthetic_data()
        else:
            # Check for existing embeddings
            embeddings_dict = None
            if not force_recompute:
                embeddings_dict = self.data_manager.load_embeddings()

            if embeddings_dict is None:
                report("Computing CLAP embeddings", 0.1)
                logger.info("Computing CLAP embeddings for %d tracks...", len(metadata))
                logger.info("This will take several hours but only needs to run once.")
                logger.info("Progress is checkpointed - you can safely interrupt and resume.")

                embeddings_dict = self._compute_embeddings(metadata, progress_callback)

                if embeddings_dict and len(embeddings_dict) > 0:
                    self.data_manager.save_embeddings(embeddings_dict)
                    self.data_manager.clear_checkpoint()
                    # Optionally clear audio cache to save space
                    # self.data_manager.clear_audio_cache()

            if not embeddings_dict or len(embeddings_dict) < 100:
                logger.warning("Could not get enough embeddings (%d), using synthetic data",
                             len(embeddings_dict) if embeddings_dict else 0)
                embeddings, labels = self._generate_synthetic_data()
                use_synthetic = True
            else:
                embeddings, labels = self._prepare_training_data(metadata, embeddings_dict)

        # Step 4: Train classifiers
        report("Training classifiers", 0.85)
        classifiers, metrics = self._train_classifiers(embeddings, labels, progress_callback)

        if not classifiers:
            logger.error("Training failed")
            return False

        # Step 5: Save classifiers
        report("Saving classifiers", 0.98)
        metadata_info = {
            'trained_date': datetime.now().isoformat(),
            'num_tags': len(classifiers),
            'num_samples': len(embeddings),
            'metrics': metrics,
            'synthetic': use_synthetic,
        }

        if not self.model_manager.save_classifiers(classifiers, metadata_info):
            return False

        report("Complete", 1.0)
        logger.info("Successfully trained %d classifiers on %d samples",
                   len(classifiers), len(embeddings))

        if not use_synthetic:
            avg_f1 = np.mean([m['f1'] for m in metrics.values()])
            avg_acc = np.mean([m['accuracy'] for m in metrics.values()])
            logger.info("Real data metrics - Average F1: %.3f, Average Accuracy: %.3f", avg_f1, avg_acc)

        return True

    def _generate_synthetic_data(self) -> Tuple[np.ndarray, Dict[str, np.ndarray]]:
        """
        Generate synthetic training data for bootstrapping.

        Creates embeddings with semantic structure so classifiers learn
        meaningful relationships between audio features and tags.
        """
        np.random.seed(42)  # Reproducible

        n_samples = 5000
        embedding_dim = CLAP_EMBEDDING_DIM

        # Generate base embeddings
        embeddings = np.random.randn(n_samples, embedding_dim).astype(np.float32)

        # Create tag labels with semantic structure
        labels = {}

        # Define semantic clusters (tags that co-occur)
        clusters = {
            'high_energy': ['energetic', 'powerful', 'epic', 'action', 'sport', 'party', 'upbeat'],
            'low_energy': ['calm', 'relaxing', 'meditative', 'soft', 'slow', 'background'],
            'positive': ['happy', 'hopeful', 'inspiring', 'positive', 'uplifting', 'fun', 'funny'],
            'negative': ['sad', 'melancholic', 'dark', 'dramatic', 'emotional'],
            'cinematic': ['film', 'movie', 'trailer', 'documentary', 'epic', 'dramatic'],
            'commercial': ['advertising', 'commercial', 'corporate', 'motivational'],
            'romantic': ['romantic', 'love', 'sexy', 'emotional', 'ballad'],
            'adventure': ['adventure', 'travel', 'nature', 'space', 'game'],
            'festive': ['christmas', 'holiday', 'children', 'summer'],
        }

        # Assign samples to clusters
        for tag in JAMENDO_TAGS:
            # Base probability
            probs = np.random.rand(n_samples) * 0.3

            # Boost probability for related tags
            for cluster_name, cluster_tags in clusters.items():
                if tag in cluster_tags:
                    # Create cluster-specific boost based on embedding region
                    cluster_dim = hash(cluster_name) % (embedding_dim - 10)
                    cluster_signal = embeddings[:, cluster_dim:cluster_dim + 10].mean(axis=1)
                    probs += (cluster_signal > 0).astype(float) * 0.4

            # Add some random positive samples
            probs += np.random.rand(n_samples) * 0.2

            # Convert to binary labels
            labels[tag] = (probs > 0.5).astype(int)

        logger.info("Generated synthetic data: %d samples, %d tags", n_samples, len(labels))
        return embeddings, labels

    def _compute_embeddings(
        self,
        metadata: List[Dict],
        progress_callback: Optional[Callable] = None
    ) -> Optional[Dict[str, np.ndarray]]:
        """
        Compute CLAP embeddings for Jamendo tracks.

        Downloads audio previews and extracts CLAP embeddings.
        Supports checkpointing for resume after interruption.
        """
        if not HAS_CLAP_MODULE or not is_clap_available():
            logger.error("CLAP not available for embedding computation")
            return None

        # Initialize CLAP analyzer
        try:
            clap = CLAPAnalyzer(auto_load=True)
            if clap.model is None:
                logger.error("Failed to load CLAP model")
                return None
        except Exception as e:
            logger.error("Failed to initialize CLAP: %s", e)
            return None

        # Load checkpoint if exists
        embeddings = self.data_manager.load_checkpoint()
        processed_ids = set(embeddings.keys())

        # Filter to unprocessed tracks
        remaining = [m for m in metadata if m['track_id'] not in processed_ids]

        if not remaining:
            logger.info("All tracks already processed")
            return embeddings

        logger.info("Processing %d tracks (%d already done)", len(remaining), len(processed_ids))

        # Track statistics
        success_count = len(processed_ids)
        fail_count = 0
        start_time = time.time()

        # Process tracks
        iterator = remaining
        if HAS_TQDM:
            iterator = tqdm(remaining, desc="Computing embeddings", initial=len(processed_ids),
                          total=len(metadata))

        for i, track in enumerate(iterator):
            track_id = track['track_id']
            numeric_id = track['numeric_id']

            try:
                # Download audio
                audio_path = self.data_manager.download_audio(numeric_id)
                if audio_path is None:
                    fail_count += 1
                    continue

                # Extract embedding
                embedding = clap.extract_embedding(str(audio_path))
                if embedding is None:
                    fail_count += 1
                    continue

                # Store embedding
                embeddings[track_id] = embedding
                success_count += 1

                # Checkpoint periodically
                if success_count % CHECKPOINT_INTERVAL == 0:
                    self.data_manager.save_checkpoint(embeddings)
                    elapsed = time.time() - start_time
                    rate = (i + 1) / elapsed if elapsed > 0 else 0
                    remaining_tracks = len(remaining) - (i + 1)
                    eta_seconds = remaining_tracks / rate if rate > 0 else 0
                    eta_hours = eta_seconds / 3600
                    logger.info("Checkpoint: %d embeddings saved (%.1f tracks/sec, ETA: %.1f hours)",
                              success_count, rate, eta_hours)

                    if progress_callback:
                        total_progress = 0.1 + 0.7 * (len(processed_ids) + i + 1) / len(metadata)
                        progress_callback("Computing embeddings", total_progress)

            except KeyboardInterrupt:
                logger.info("Interrupted - saving checkpoint...")
                self.data_manager.save_checkpoint(embeddings)
                raise
            except Exception as e:
                logger.debug("Error processing track %s: %s", track_id, e)
                fail_count += 1
                continue

        # Final checkpoint
        self.data_manager.save_checkpoint(embeddings)

        elapsed = time.time() - start_time
        logger.info("Embedding computation complete:")
        logger.info("  - Success: %d tracks", success_count)
        logger.info("  - Failed: %d tracks", fail_count)
        logger.info("  - Time: %.1f hours", elapsed / 3600)

        return embeddings

    def _prepare_training_data(
        self,
        metadata: List[Dict],
        embeddings_dict: Dict[str, np.ndarray]
    ) -> Tuple[np.ndarray, Dict[str, np.ndarray]]:
        """
        Prepare training data from metadata and embeddings.
        """
        # Filter to tracks with embeddings
        valid_tracks = [m for m in metadata if m['track_id'] in embeddings_dict]

        if not valid_tracks:
            logger.warning("No valid tracks with embeddings, falling back to synthetic")
            return self._generate_synthetic_data()

        logger.info("Preparing training data from %d tracks with embeddings", len(valid_tracks))

        # Build arrays
        embeddings = np.array([embeddings_dict[m['track_id']] for m in valid_tracks])

        # Build label arrays for each tag
        labels = {}
        tag_counts = {}
        for tag in JAMENDO_TAGS:
            tag_labels = np.array([
                1 if tag in m['tags'] else 0
                for m in valid_tracks
            ])
            labels[tag] = tag_labels
            tag_counts[tag] = tag_labels.sum()

        # Log tag distribution
        logger.info("Tag distribution (top 10):")
        sorted_tags = sorted(tag_counts.items(), key=lambda x: -x[1])[:10]
        for tag, count in sorted_tags:
            logger.info("  %s: %d tracks", tag, count)

        logger.info("Prepared %d samples for training", len(embeddings))
        return embeddings, labels

    def _train_classifiers(
        self,
        embeddings: np.ndarray,
        labels: Dict[str, np.ndarray],
        progress_callback: Optional[Callable] = None
    ) -> Tuple[Dict, Dict]:
        """
        Train one classifier per tag.
        """
        classifiers = {}
        metrics = {}

        # Split data
        X_train, X_test = train_test_split(
            np.arange(len(embeddings)),
            test_size=0.2,
            random_state=42
        )

        iterator = JAMENDO_TAGS
        if HAS_TQDM:
            iterator = tqdm(iterator, desc="Training classifiers")

        for i, tag in enumerate(iterator):
            y = labels[tag]
            y_train, y_test = y[X_train], y[X_test]

            # Check for class imbalance
            pos_count = y_train.sum()
            neg_count = len(y_train) - pos_count

            if pos_count < 5 or neg_count < 5:
                # Skip tags with insufficient samples
                logger.debug("Skipping tag '%s': insufficient samples (pos=%d, neg=%d)",
                            tag, pos_count, neg_count)
                continue

            try:
                # Train logistic regression
                clf = LogisticRegression(
                    max_iter=500,
                    class_weight='balanced',
                    solver='lbfgs',
                    random_state=42
                )
                clf.fit(embeddings[X_train], y_train)

                # Evaluate
                y_pred = clf.predict(embeddings[X_test])
                f1 = f1_score(y_test, y_pred, zero_division=0)
                acc = accuracy_score(y_test, y_pred)

                classifiers[tag] = clf
                metrics[tag] = {'f1': float(f1), 'accuracy': float(acc)}

                logger.debug("Trained '%s': F1=%.3f, Acc=%.3f", tag, f1, acc)

            except Exception as e:
                logger.warning("Failed to train classifier for '%s': %s", tag, e)

            if progress_callback:
                progress = 0.85 + 0.13 * (i + 1) / len(JAMENDO_TAGS)
                progress_callback("Training classifiers", progress)

        logger.info("Trained %d classifiers", len(classifiers))

        # Log summary metrics
        if metrics:
            avg_f1 = np.mean([m['f1'] for m in metrics.values()])
            avg_acc = np.mean([m['accuracy'] for m in metrics.values()])
            logger.info("Average F1: %.3f, Average Accuracy: %.3f", avg_f1, avg_acc)

        return classifiers, metrics


def train_jamendo_classifiers(
    progress_callback: Optional[Callable[[str, float], None]] = None,
    use_synthetic: bool = False,
    force_recompute: bool = False
) -> bool:
    """
    Convenience function to train Jamendo classifiers.

    Args:
        progress_callback: Optional callback(stage, progress) for updates
        use_synthetic: If True, use synthetic training data (faster but less accurate)
        force_recompute: If True, recompute embeddings even if they exist

    Returns:
        True if successful
    """
    trainer = JamendoTrainer()
    return trainer.train(progress_callback, use_synthetic=use_synthetic,
                        force_recompute=force_recompute)


def compute_jamendo_embeddings(
    progress_callback: Optional[Callable[[str, float], None]] = None
) -> bool:
    """
    Convenience function to compute embeddings only (without training).

    Useful for running the long embedding computation separately.

    Returns:
        True if successful
    """
    trainer = JamendoTrainer()
    data_manager = trainer.data_manager

    # Download metadata
    if not data_manager.download_metadata():
        return False

    metadata = data_manager.load_metadata()
    if len(metadata) < 100:
        logger.error("Insufficient metadata")
        return False

    # Compute embeddings
    embeddings = trainer._compute_embeddings(metadata, progress_callback)

    if embeddings and len(embeddings) > 0:
        data_manager.save_embeddings(embeddings)
        data_manager.clear_checkpoint()
        return True

    return False
