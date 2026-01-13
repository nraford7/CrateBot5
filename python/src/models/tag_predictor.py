import numpy as np
import pickle
import json
import re
import os
import hashlib
import logging
from datetime import datetime
from typing import List, Dict, Any, Tuple, Optional
from difflib import SequenceMatcher
from sklearn.ensemble import RandomForestClassifier, RandomForestRegressor
from sklearn.preprocessing import StandardScaler, LabelEncoder, MultiLabelBinarizer
from sklearn.model_selection import train_test_split
from sklearn.metrics import accuracy_score, f1_score, mean_squared_error
from sklearn.decomposition import PCA
from sklearn.neural_network import MLPRegressor
import joblib

# Handle imports for both package and direct execution contexts
try:
    from ..core.exceptions import ModelError, ModelLoadError, ModelIntegrityError, FeatureDimensionMismatchError
    from ..core.constants import (
        FUZZY_MATCH_THRESHOLD,
        MIN_SAMPLES_PER_CLASS,
        COMMENT_MIN_SCORE,
        COMMENT_CATEGORY_THRESHOLD,
        VOCAL_CONFIDENCE_THRESHOLD,
        EMBEDDING_DIM,
    )
    from ..core.feature_config import FeatureConfig, validate_model_compatibility
except ImportError:
    from core.exceptions import ModelError, ModelLoadError, ModelIntegrityError, FeatureDimensionMismatchError
    from core.constants import (
        FUZZY_MATCH_THRESHOLD,
        MIN_SAMPLES_PER_CLASS,
        COMMENT_MIN_SCORE,
        COMMENT_CATEGORY_THRESHOLD,
        VOCAL_CONFIDENCE_THRESHOLD,
        EMBEDDING_DIM,
    )
    from core.feature_config import FeatureConfig, validate_model_compatibility

logger = logging.getLogger(__name__)

# Model format version - increment when model structure changes
MODEL_FORMAT_VERSION = "2.0"

# Try to import LightGBM for faster/better training
try:
    from lightgbm import LGBMClassifier
    HAS_LIGHTGBM = True
except ImportError:
    HAS_LIGHTGBM = False
    logger.info("LightGBM not installed. Using RandomForest (slower). Install with: pip install lightgbm")


def normalize_tag(tag: str) -> str:
    """Normalize a tag to a standard form for comparison."""
    normalized = tag.lower().strip()
    normalized = re.sub(r'\s+', ' ', normalized)
    return normalized


def find_matching_tag(value: str, valid_tags: List[str]) -> Optional[str]:
    """Find which valid tag matches this value (with fuzzy matching)."""
    if not value:
        return None

    normalized = normalize_tag(value)

    # First check exact normalized match
    for tag in valid_tags:
        if normalize_tag(tag) == normalized:
            return tag

    # Then fuzzy match
    for tag in valid_tags:
        ratio = SequenceMatcher(None, normalized, normalize_tag(tag)).ratio()
        if ratio >= FUZZY_MATCH_THRESHOLD:
            return tag

    return None


# Tag category keywords for auto-categorization
TAG_CATEGORIES = {
    'beats': [
        'beat', 'drum', 'kick', 'snare', 'hihat', 'hi-hat', 'hi hat', 'hats',
        'percussion', 'rhythm', 'four on the floor', '4/4', 'breakbeat',
        'shuffle', 'swing', 'triplet', 'syncopat', 'groove', 'bpm',
        'clap', 'rimshot', 'tom', 'cymbal', 'shaker', 'conga', 'bongo',
        'tribal drum', 'rolling', 'driving beat', 'punchy'
    ],
    'bass': [
        'bass', 'sub', 'low end', 'lowend', '808', 'reese', 'wobble',
        'bassline', 'deep bass', 'rolling bass', 'pluck bass', 'synth bass',
        'acid bass', 'rubber', 'growl'
    ],
    'vibes': [
        'dark', 'bright', 'euphoric', 'melancholic', 'happy', 'sad',
        'energetic', 'chill', 'relaxed', 'intense', 'aggressive', 'soft',
        'dreamy', 'hypnotic', 'uplifting', 'emotional', 'atmospheric',
        'moody', 'groovy', 'funky', 'soulful', 'warm', 'cold', 'raw',
        'smooth', 'gritty', 'ethereal', 'nostalgic', 'futuristic',
        'organic', 'mechanical', 'driving', 'building', 'peak', 'tension',
        'release', 'trippy', 'psychedelic', 'minimal', 'maximal', 'heavy',
        'light', 'deep', 'shallow', 'wide', 'tight', 'loose', 'punchy',
        'bouncy', 'rolling', 'arabic', 'eastern', 'latin', 'african',
        'asian', 'tribal', 'urban', 'underground', 'commercial', 'festival',
        'club', 'afterhours', 'sunrise', 'sunset', 'night', 'day', 'summer',
        'winter', 'spring', 'autumn', 'beach', 'desert', 'forest', 'space'
    ],
    'instruments': [
        'piano', 'synth', 'synthesizer', 'pad', 'lead', 'pluck', 'stab',
        'strings', 'violin', 'cello', 'orchestra', 'brass', 'trumpet',
        'saxophone', 'sax', 'flute', 'guitar', 'acoustic', 'electric',
        'organ', 'keys', 'keyboard', 'arp', 'arpeggio', 'chord', 'melody',
        'riff', 'hook', 'bell', 'chime', 'marimba', 'xylophone', 'harp',
        'fx', 'effect', 'noise', 'texture', 'ambient', 'drone', 'sweep',
        'riser', 'drop', 'impact', 'reverse', 'vocal chop', 'sample'
    ],
    'vocals': [
        'vocal', 'voice', 'singer', 'acapella', 'lyric', 'spoken',
        'male vocal', 'female vocal', 'choir', 'harmony', 'verse', 'chorus',
        'rap', 'mc', 'chant', 'whisper', 'scream', 'shout', 'talk',
        'speech', 'word', 'singing', 'sung', 'no vocal', 'instrumental'
    ]
}


def categorize_tag(tag: str) -> str:
    """Determine which category a tag belongs to."""
    tag_lower = tag.lower()

    # Check each category's keywords
    for category, keywords in TAG_CATEGORIES.items():
        for keyword in keywords:
            if keyword in tag_lower:
                return category

    # Default to vibes if no match
    return 'vibes'


def has_vocals_indicator(tag: str) -> Optional[bool]:
    """Check if tag indicates presence or absence of vocals."""
    tag_lower = tag.lower()

    # Negative indicators
    no_vocal_keywords = ['no vocal', 'no voice', 'instrumental', 'no singing']
    for kw in no_vocal_keywords:
        if kw in tag_lower:
            return False

    # Positive indicators
    vocal_keywords = ['vocal', 'voice', 'singer', 'singing', 'lyric', 'acapella',
                      'male vocal', 'female vocal', 'choir', 'rap', 'spoken']
    for kw in vocal_keywords:
        if kw in tag_lower:
            return True

    return None


class TagPredictor:
    def __init__(self):
        self.models = {}
        self.scalers = {}
        self.encoders = {}
        self.selected_tags = None
        self.feature_names = None
        self.embedding_dim = EMBEDDING_DIM  # Dimension for synthesis embeddings
        self.model_path = None  # Path to loaded model file
        self.feature_config = None  # CrateBot4: Track feature configuration for compatibility

    def train(self, training_data: List[Dict], selected_tags: Dict[str, List[str]],
              test_size: float = 0.2, random_state: int = 42,
              min_samples_per_class: int = MIN_SAMPLES_PER_CLASS) -> Dict[str, Any]:
        """
        Train the model with four separate classifiers:
        - Genre: single-class (House, Techno, etc.)
        - Timing: single-class (Start, Build, Peak, Sustain, Release)
        - Mood: single-class (Happy, Dark, Emotional, etc.)
        - Descriptive: multi-label (sonic characteristics)

        Args:
            training_data: List of dicts with 'feature_vector' and 'tags'
            selected_tags: Dict of tag types to list of valid tags
            test_size: Fraction of data to use for testing
            random_state: Random seed for reproducibility
            min_samples_per_class: Minimum samples required per class (default 10)
        """
        self.selected_tags = selected_tags
        self.min_samples_per_class = min_samples_per_class

        # CrateBot4: Capture current feature configuration for model compatibility
        self.feature_config = FeatureConfig.from_current_environment()
        logger.info(
            "Feature config: PANNs=%s, CLAP=%s, Jamendo=%s (total=%d features)",
            self.feature_config.has_panns,
            self.feature_config.has_clap,
            self.feature_config.has_jamendo,
            self.feature_config.total_features()
        )

        # Report training backend
        if HAS_LIGHTGBM:
            logger.info("Using LightGBM (fast gradient boosting)")
        else:
            logger.info("Using RandomForest (install lightgbm for faster training)")

        # Prepare feature matrix
        X = np.array([item['feature_vector'] for item in training_data])

        # Scale features
        self.scalers['features'] = StandardScaler()
        X_scaled = self.scalers['features'].fit_transform(X)

        results = {
            'training_samples': len(training_data),
            'features_used': X.shape[1],
        }

        # Train Genre classifier (single-class)
        if selected_tags.get('genre'):
            genre_results = self._train_single_class(
                X_scaled, training_data, 'genre', selected_tags['genre'],
                test_size, random_state, min_samples_per_class
            )
            results['genre'] = genre_results

        # Train Timing classifier (single-class) - was "album"
        if selected_tags.get('timing'):
            timing_results = self._train_single_class(
                X_scaled, training_data, 'timing', selected_tags['timing'],
                test_size, random_state, min_samples_per_class
            )
            results['timing'] = timing_results

        # Train Mood classifier (single-class) - NEW
        if selected_tags.get('mood'):
            mood_results = self._train_single_class(
                X_scaled, training_data, 'mood', selected_tags['mood'],
                test_size, random_state, min_samples_per_class
            )
            results['mood'] = mood_results

        # Train Descriptive classifier (multi-label) - was "comments"
        if selected_tags.get('descriptive'):
            descriptive_results = self._train_multi_label(
                X_scaled, training_data, selected_tags['descriptive'],
                test_size, random_state, tag_key='descriptive'
            )
            results['descriptive'] = descriptive_results

        # Train Descriptive Synthesis (embedding for tag combinations) - was "comments_synthesis"
        if selected_tags.get('descriptive'):
            synthesis_results = self._train_descriptive_synthesis(
                X_scaled, training_data, selected_tags['descriptive'],
                test_size, random_state
            )
            results['descriptive_synthesis'] = synthesis_results

        # Train Overall Likeness (unified embedding across all tags)
        overall_results = self._train_overall_likeness(
            X_scaled, training_data, selected_tags,
            test_size, random_state
        )
        results['overall_likeness'] = overall_results

        return results

    def _train_single_class(self, X: np.ndarray, training_data: List[Dict],
                            tag_type: str, valid_tags: List[str],
                            test_size: float, random_state: int,
                            min_samples_per_class: int = MIN_SAMPLES_PER_CLASS) -> Dict[str, Any]:
        """Train a single-class classifier for Genre or Album."""
        logger.info("Training %s classifier...", tag_type)

        # Extract labels (with fuzzy matching)
        y = []
        valid_indices = []

        for idx, item in enumerate(training_data):
            tags = item['tags']
            value = tags.get(tag_type, '').strip()

            # Handle combo tags (e.g., "Build, Sustain") - use only the FIRST tag
            if ',' in value:
                value = value.split(',')[0].strip()

            matched_tag = find_matching_tag(value, valid_tags)
            if matched_tag:
                y.append(matched_tag)
                valid_indices.append(idx)

        if len(y) < 10:
            logger.warning("Only %d samples for %s, skipping...", len(y), tag_type)
            return {'status': 'skipped', 'reason': 'insufficient_samples'}

        X_filtered = X[valid_indices]
        y = np.array(y)

        # Filter out classes with fewer than min_samples_per_class
        unique_classes, class_counts = np.unique(y, return_counts=True)
        rare_classes = unique_classes[class_counts < min_samples_per_class]
        kept_classes = unique_classes[class_counts >= min_samples_per_class]

        if len(rare_classes) > 0:
            logger.info("Removing %d tags with <%d samples: %s%s",
                        len(rare_classes), min_samples_per_class,
                        list(rare_classes)[:5], '...' if len(rare_classes) > 5 else '')
            logger.info("Keeping %d tags with %d+ samples", len(kept_classes), min_samples_per_class)
            # Keep only samples from classes with enough members
            valid_class_mask = np.isin(y, kept_classes)
            X_filtered = X_filtered[valid_class_mask]
            y = y[valid_class_mask]

            if len(y) < 10:
                logger.warning("Only %d samples remaining for %s after filtering, skipping...", len(y), tag_type)
                return {'status': 'skipped', 'reason': 'insufficient_samples_after_filter'}

        # Encode labels
        self.encoders[tag_type] = LabelEncoder()
        y_encoded = self.encoders[tag_type].fit_transform(y)

        # Split data - use stratified split if we have multiple classes
        use_stratify = len(np.unique(y_encoded)) > 1
        X_train, X_test, y_train, y_test = train_test_split(
            X_filtered, y_encoded, test_size=test_size, random_state=random_state,
            stratify=y_encoded if use_stratify else None
        )

        # Train model - use LightGBM if available (faster & often more accurate)
        if HAS_LIGHTGBM:
            self.models[tag_type] = LGBMClassifier(
                n_estimators=200,
                max_depth=8,
                learning_rate=0.1,
                num_leaves=31,
                class_weight='balanced',
                random_state=random_state,
                n_jobs=-1,
                verbose=-1  # Suppress LightGBM output
            )
        else:
            self.models[tag_type] = RandomForestClassifier(
                n_estimators=100,
                max_depth=12,
                min_samples_split=5,
                random_state=random_state,
                class_weight='balanced'
            )
        self.models[tag_type].fit(X_train, y_train)

        # Evaluate
        y_pred = self.models[tag_type].predict(X_test)
        accuracy = accuracy_score(y_test, y_pred)

        logger.info("%s accuracy: %.3f", tag_type.capitalize(), accuracy)
        logger.debug("%s classes: %s", tag_type, list(self.encoders[tag_type].classes_))

        return {
            'status': 'trained',
            'accuracy': accuracy,
            'classes': list(self.encoders[tag_type].classes_),
            'train_samples': len(X_train),
            'test_samples': len(X_test),
        }

    def _train_multi_label(self, X: np.ndarray, training_data: List[Dict],
                           valid_tags: List[str], test_size: float,
                           random_state: int, tag_key: str = 'descriptive') -> Dict[str, Any]:
        """Train a multi-label classifier for Descriptive tags (was Comments)."""
        logger.info("Training %s classifier (multi-label)...", tag_key)

        # Extract labels (comma-separated, with fuzzy matching)
        y_labels = []
        valid_indices = []

        for idx, item in enumerate(training_data):
            tags = item['tags']
            comments = tags.get(tag_key, '')

            if isinstance(comments, list):
                comments = ' '.join(comments)

            # Split by comma
            comment_tags = [c.strip() for c in comments.split(',') if c.strip()]
            # Filter to only selected tags (with fuzzy matching)
            filtered_tags = []
            for t in comment_tags:
                matched = find_matching_tag(t, valid_tags)
                if matched and matched not in filtered_tags:
                    filtered_tags.append(matched)

            if filtered_tags:
                y_labels.append(filtered_tags)
                valid_indices.append(idx)

        if len(y_labels) < 10:
            logger.warning("Only %d samples for %s, skipping...", len(y_labels), tag_key)
            return {'status': 'skipped', 'reason': 'insufficient_samples'}

        X_filtered = X[valid_indices]

        # Binarize labels
        self.encoders[tag_key] = MultiLabelBinarizer(classes=valid_tags)
        y_binary = self.encoders[tag_key].fit_transform(y_labels)

        # Split data
        X_train, X_test, y_train, y_test = train_test_split(
            X_filtered, y_binary, test_size=test_size, random_state=random_state
        )

        # Train one classifier per label - using parallel processing for speed
        self.models[tag_key] = {}
        label_scores = {}

        def train_single_label(tag, idx, X_train, y_train, X_test, y_test, random_state):
            """Train a single label classifier (for parallel execution)."""
            y_col = y_train[:, idx]

            # Skip if not enough positive samples
            if np.sum(y_col) < 3:
                return tag, None, None, f"only {np.sum(y_col)} samples"

            # Use LightGBM if available (faster & often more accurate)
            if HAS_LIGHTGBM:
                model = LGBMClassifier(
                    n_estimators=100,
                    max_depth=6,
                    learning_rate=0.1,
                    num_leaves=31,
                    class_weight='balanced',
                    random_state=random_state,
                    n_jobs=1,  # Single thread per label (parallelism is at label level)
                    verbose=-1
                )
            else:
                model = RandomForestClassifier(
                    n_estimators=50,
                    max_depth=10,
                    min_samples_split=3,
                    random_state=random_state,
                    class_weight='balanced'
                )
            model.fit(X_train, y_col)

            # Evaluate
            y_pred = model.predict(X_test)
            y_test_col = y_test[:, idx]
            f1 = f1_score(y_test_col, y_pred, zero_division=0) if np.sum(y_test_col) > 0 else 0.0

            return tag, model, f1, None

        # CrateBot4: Parallel training across all labels using processes (not threads)
        # Using processes escapes the GIL for better CPU utilization (~1.5-2x speedup)
        from joblib import Parallel, delayed
        import multiprocessing

        n_jobs = min(multiprocessing.cpu_count(), len(valid_tags))
        logger.info("Training %d labels in parallel (using %d workers, process-based)...", len(valid_tags), n_jobs)

        # Note: prefer="processes" requires data to be picklable (sklearn models are)
        results = Parallel(n_jobs=n_jobs, prefer="processes")(
            delayed(train_single_label)(tag, idx, X_train, y_train, X_test, y_test, random_state)
            for idx, tag in enumerate(valid_tags)
        )

        # Collect results
        for tag, model, f1, skip_reason in results:
            if skip_reason:
                logger.debug("Skipping '%s' - %s", tag, skip_reason)
            elif model is not None:
                self.models[tag_key][tag] = model
                if f1 is not None:
                    label_scores[tag] = f1
                    logger.debug("  '%s': F1=%.3f", tag, f1)

        avg_f1 = np.mean(list(label_scores.values())) if label_scores else 0

        logger.info("Average F1 score: %.3f", avg_f1)
        logger.info("Trained %d %s tag classifiers", len(self.models[tag_key]), tag_key)

        return {
            'status': 'trained',
            'avg_f1': avg_f1,
            'label_scores': label_scores,
            'num_labels': len(self.models[tag_key]),
            'train_samples': len(X_train),
            'test_samples': len(X_test),
        }

    def _train_descriptive_synthesis(self, X: np.ndarray, training_data: List[Dict],
                                       valid_tags: List[str], test_size: float,
                                       random_state: int) -> Dict[str, Any]:
        """
        Train a model that learns to predict descriptive tag combinations as an embedding.
        This allows finding songs with similar character profiles.
        """
        logger.info("Training descriptive synthesis (combination embedding)...")

        # Build target: multi-hot encoding of descriptive tags (with fuzzy matching)
        y_labels = []
        valid_indices = []

        for idx, item in enumerate(training_data):
            tags = item['tags']
            descriptive = tags.get('descriptive', '')

            if isinstance(descriptive, list):
                descriptive = ' '.join(descriptive)

            desc_tags = [c.strip() for c in descriptive.split(',') if c.strip()]
            filtered_tags = []
            for t in desc_tags:
                matched = find_matching_tag(t, valid_tags)
                if matched and matched not in filtered_tags:
                    filtered_tags.append(matched)

            if filtered_tags:
                y_labels.append(filtered_tags)
                valid_indices.append(idx)

        if len(y_labels) < 10:
            logger.warning("Insufficient samples for descriptive synthesis, skipping...")
            return {'status': 'skipped', 'reason': 'insufficient_samples'}

        X_filtered = X[valid_indices]

        # Create multi-hot encoding as target embedding
        mlb = MultiLabelBinarizer(classes=valid_tags)
        y_multi_hot = mlb.fit_transform(y_labels)

        # Reduce dimensionality of target for embedding
        if y_multi_hot.shape[1] > self.embedding_dim:
            pca = PCA(n_components=self.embedding_dim, random_state=random_state)
            y_embedding = pca.fit_transform(y_multi_hot.astype(float))
            self.models['descriptive_synthesis_pca'] = pca
        else:
            y_embedding = y_multi_hot.astype(float)
            self.models['descriptive_synthesis_pca'] = None

        # Split data
        X_train, X_test, y_train, y_test = train_test_split(
            X_filtered, y_embedding, test_size=test_size, random_state=random_state
        )

        # Train neural network to predict embedding from audio features
        self.models['descriptive_synthesis'] = MLPRegressor(
            hidden_layer_sizes=(128, 64, 32),
            activation='relu',
            max_iter=500,
            random_state=random_state,
            early_stopping=True,
            validation_fraction=0.1
        )
        self.models['descriptive_synthesis'].fit(X_train, y_train)

        # Evaluate
        y_pred = self.models['descriptive_synthesis'].predict(X_test)
        mse = mean_squared_error(y_test, y_pred)

        logger.info("Descriptive synthesis MSE: %.4f", mse)
        logger.info("Embedding dimension: %d", y_embedding.shape[1])

        return {
            'status': 'trained',
            'mse': mse,
            'embedding_dim': y_embedding.shape[1],
            'train_samples': len(X_train),
            'test_samples': len(X_test),
        }

    def _train_overall_likeness(self, X: np.ndarray, training_data: List[Dict],
                                 selected_tags: Dict[str, List[str]],
                                 test_size: float, random_state: int) -> Dict[str, Any]:
        """
        Train a unified embedding model that combines Genre + Timing + Mood + Descriptive.
        This allows sorting songs by overall similarity across all dimensions.
        """
        logger.info("Training overall likeness (unified embedding)...")

        # Build combined target vector for each song (with fuzzy matching)
        genre_tags = selected_tags.get('genre', [])
        timing_tags = selected_tags.get('timing', [])
        mood_tags = selected_tags.get('mood', [])
        descriptive_tags = selected_tags.get('descriptive', [])

        y_combined = []
        valid_indices = []

        for idx, item in enumerate(training_data):
            tags = item['tags']
            combined_vec = []

            # One-hot for genre (with fuzzy matching)
            genre = tags.get('genre', '').strip()
            matched_genre = find_matching_tag(genre, genre_tags)
            genre_vec = [1.0 if g == matched_genre else 0.0 for g in genre_tags]
            combined_vec.extend(genre_vec)

            # One-hot for timing (with fuzzy matching) - was "album"
            timing = tags.get('timing', '').strip()
            matched_timing = find_matching_tag(timing, timing_tags)
            timing_vec = [1.0 if t == matched_timing else 0.0 for t in timing_tags]
            combined_vec.extend(timing_vec)

            # One-hot for mood (with fuzzy matching) - NEW
            mood = tags.get('mood', '').strip()
            matched_mood = find_matching_tag(mood, mood_tags)
            mood_vec = [1.0 if m == matched_mood else 0.0 for m in mood_tags]
            combined_vec.extend(mood_vec)

            # Multi-hot for descriptive (with fuzzy matching) - was "comments"
            descriptive = tags.get('descriptive', '')
            if isinstance(descriptive, list):
                descriptive = ' '.join(descriptive)
            desc_items = [c.strip() for c in descriptive.split(',') if c.strip()]
            matched_descriptive = set()
            for c in desc_items:
                matched = find_matching_tag(c, descriptive_tags)
                if matched:
                    matched_descriptive.add(matched)
            descriptive_vec = [1.0 if c in matched_descriptive else 0.0 for c in descriptive_tags]
            combined_vec.extend(descriptive_vec)

            # Only include if has at least some tags
            if sum(combined_vec) > 0:
                y_combined.append(combined_vec)
                valid_indices.append(idx)

        if len(y_combined) < 10:
            logger.warning("Insufficient samples for overall likeness, skipping...")
            return {'status': 'skipped', 'reason': 'insufficient_samples'}

        X_filtered = X[valid_indices]
        y_combined = np.array(y_combined)

        # Reduce dimensionality for embedding
        target_dim = min(self.embedding_dim, y_combined.shape[1])
        if y_combined.shape[1] > target_dim:
            pca = PCA(n_components=target_dim, random_state=random_state)
            y_embedding = pca.fit_transform(y_combined)
            self.models['overall_pca'] = pca
        else:
            y_embedding = y_combined
            self.models['overall_pca'] = None

        # Store the combined vector structure for later use
        self.models['overall_structure'] = {
            'genre_tags': genre_tags,
            'timing_tags': timing_tags,
            'mood_tags': mood_tags,
            'descriptive_tags': descriptive_tags,
            'genre_dim': len(genre_tags),
            'timing_dim': len(timing_tags),
            'mood_dim': len(mood_tags),
            'descriptive_dim': len(descriptive_tags),
        }

        # Split data
        X_train, X_test, y_train, y_test = train_test_split(
            X_filtered, y_embedding, test_size=test_size, random_state=random_state
        )

        # Train neural network
        self.models['overall_likeness'] = MLPRegressor(
            hidden_layer_sizes=(128, 64, 32),
            activation='relu',
            max_iter=500,
            random_state=random_state,
            early_stopping=True,
            validation_fraction=0.1
        )
        self.models['overall_likeness'].fit(X_train, y_train)

        # Evaluate
        y_pred = self.models['overall_likeness'].predict(X_test)
        mse = mean_squared_error(y_test, y_pred)

        logger.info("Overall likeness MSE: %.4f", mse)
        logger.info("Combined embedding dimension: %d", y_embedding.shape[1])
        logger.info("Structure: %d genre + %d timing + %d mood + %d descriptive",
                   len(genre_tags), len(timing_tags), len(mood_tags), len(descriptive_tags))

        return {
            'status': 'trained',
            'mse': mse,
            'embedding_dim': y_embedding.shape[1],
            'total_tags': len(genre_tags) + len(timing_tags) + len(mood_tags) + len(descriptive_tags),
            'train_samples': len(X_train),
            'test_samples': len(X_test),
        }

    def predict_tags(self, features: Dict[str, Any], num_descriptive: int = 7) -> Dict[str, Any]:
        """
        Predict tags for a single audio file.

        Returns dict with structure:
        {
            "genre": {"value": "House", "confidence": 0.85},
            "timing": {"value": "Peak", "confidence": 0.78},
            "mood": {"value": "Happy", "confidence": 0.72},
            "descriptive": {"tags": ["Driving", "Melodic", "Punchy"]},
            "_comments_embedding": [...],  # for backwards compat
            "_overall_embedding": [...],
        }
        """
        feature_vector = features['feature_vector'].reshape(1, -1)

        # CrateBot4: Validate feature dimensions match model expectations
        if self.feature_config is not None:
            expected_dim = self.feature_config.total_features()
            actual_dim = feature_vector.shape[1]
            if actual_dim != expected_dim:
                raise FeatureDimensionMismatchError(expected_dim, actual_dim, self.feature_config)

        feature_scaled = self.scalers['features'].transform(feature_vector)

        predicted_tags = {}

        # Predict Genre (single-class)
        if 'genre' in self.models:
            genre_proba = self.models['genre'].predict_proba(feature_scaled)[0]
            best_idx = np.argmax(genre_proba)
            predicted_tags['genre'] = {
                'value': self.encoders['genre'].classes_[best_idx],
                'confidence': float(genre_proba[best_idx])
            }

        # Predict Timing (single-class) - was "album"
        if 'timing' in self.models:
            timing_proba = self.models['timing'].predict_proba(feature_scaled)[0]
            best_idx = np.argmax(timing_proba)
            predicted_tags['timing'] = {
                'value': self.encoders['timing'].classes_[best_idx],
                'confidence': float(timing_proba[best_idx])
            }

        # Predict Mood (single-class) - NEW
        if 'mood' in self.models:
            mood_proba = self.models['mood'].predict_proba(feature_scaled)[0]
            best_idx = np.argmax(mood_proba)
            predicted_tags['mood'] = {
                'value': self.encoders['mood'].classes_[best_idx],
                'confidence': float(mood_proba[best_idx])
            }

        # Predict Descriptive (multi-label) with categorization - was "comments"
        if 'descriptive' in self.models and self.models['descriptive']:
            desc_scores = {}

            for tag, model in self.models['descriptive'].items():
                proba = model.predict_proba(feature_scaled)[0]
                # Get probability of positive class
                if len(proba) > 1:
                    score = proba[1]
                else:
                    score = proba[0]
                desc_scores[tag] = float(score)

            # Categorize and select top tags from each category
            categorized = {
                'beats': [],
                'bass': [],
                'vibes': [],
                'instruments': [],
                'vocals': []
            }

            # Sort all by score
            sorted_desc = sorted(desc_scores.items(), key=lambda x: -x[1])

            # Categorize each tag
            for tag, score in sorted_desc:
                if score < COMMENT_MIN_SCORE:  # Skip very low confidence
                    continue
                category = categorize_tag(tag)
                categorized[category].append((tag, score))

            # Build structured output in order: beats, bass, vibes, instruments, vocals
            structured_tags = []

            # Beats: 1-2 tags
            for tag, score in categorized['beats'][:2]:
                if score > COMMENT_CATEGORY_THRESHOLD:
                    structured_tags.append(tag)

            # Bass: 1 tag
            for tag, score in categorized['bass'][:1]:
                if score > COMMENT_CATEGORY_THRESHOLD:
                    structured_tags.append(tag)

            # Vibes: 2-4 tags
            for tag, score in categorized['vibes'][:4]:
                if score > COMMENT_CATEGORY_THRESHOLD:
                    structured_tags.append(tag)

            # Instruments: 3-5 tags
            for tag, score in categorized['instruments'][:5]:
                if score > COMMENT_CATEGORY_THRESHOLD:
                    structured_tags.append(tag)

            # Vocals: determine yes/no based on vocal tags
            has_vocals = None
            for tag, score in categorized['vocals']:
                if score > VOCAL_CONFIDENCE_THRESHOLD:
                    indicator = has_vocals_indicator(tag)
                    if indicator is not None:
                        has_vocals = indicator
                        break

            # Add vocal indicator
            if has_vocals is True:
                structured_tags.append("Vocals")
            elif has_vocals is False:
                structured_tags.append("Instrumental")
            elif categorized['vocals'] and categorized['vocals'][0][1] > 0.5:
                # If uncertain but high score, check the tag itself
                top_vocal_tag = categorized['vocals'][0][0]
                if has_vocals_indicator(top_vocal_tag) is False:
                    structured_tags.append("Instrumental")
                else:
                    structured_tags.append("Vocals")

            # Store structured output with new format
            predicted_tags['descriptive'] = {
                'tags': structured_tags
            }
            predicted_tags['_descriptive_scores'] = {tag: score for tag, score in sorted_desc}
            predicted_tags['_categorized'] = {
                cat: [(t, s) for t, s in tags[:5]]
                for cat, tags in categorized.items()
            }

        # Generate Descriptive Synthesis embedding (for character profile similarity)
        if 'descriptive_synthesis' in self.models:
            synthesis_embedding = self.models['descriptive_synthesis'].predict(feature_scaled)[0]
            predicted_tags['_comments_embedding'] = synthesis_embedding.tolist()  # Keep for backwards compat

        # Generate Overall Likeness embedding (for total similarity)
        if 'overall_likeness' in self.models:
            overall_embedding = self.models['overall_likeness'].predict(feature_scaled)[0]
            predicted_tags['_overall_embedding'] = overall_embedding.tolist()

        return predicted_tags

    def get_comments_similarity(self, embedding1: List[float], embedding2: List[float]) -> float:
        """Calculate similarity between two songs based on their comment profiles."""
        vec1 = np.array(embedding1)
        vec2 = np.array(embedding2)
        distance = np.linalg.norm(vec1 - vec2)
        similarity = 1.0 / (1.0 + distance)
        return float(similarity)

    def get_overall_similarity(self, embedding1: List[float], embedding2: List[float]) -> float:
        """Calculate overall similarity between two songs."""
        vec1 = np.array(embedding1)
        vec2 = np.array(embedding2)
        distance = np.linalg.norm(vec1 - vec2)
        similarity = 1.0 / (1.0 + distance)
        return float(similarity)

    def save_model(self, model_path: str) -> None:
        """
        Save the trained model to disk with integrity metadata.

        Creates two files:
        - model_path: The model data (pickle/joblib)
        - model_path.meta.json: Metadata including SHA256 hash for integrity verification

        Args:
            model_path: Path to save the model file
        """
        model_data = {
            'format_version': MODEL_FORMAT_VERSION,
            'created_at': datetime.now().isoformat(),
            'models': self.models,
            'scalers': self.scalers,
            'encoders': self.encoders,
            'selected_tags': self.selected_tags,
            # CrateBot4: Store feature configuration for compatibility validation
            'feature_config': self.feature_config.to_dict() if self.feature_config else None,
        }

        # Save model with joblib (uses pickle internally but with compression)
        with open(model_path, 'wb') as f:
            joblib.dump(model_data, f, protocol=4)

        # Generate integrity hash
        with open(model_path, 'rb') as f:
            file_hash = hashlib.sha256(f.read()).hexdigest()

        # Save metadata for integrity verification
        meta_path = model_path + '.meta.json'
        metadata = {
            'format_version': MODEL_FORMAT_VERSION,
            'created_at': model_data['created_at'],
            'sha256': file_hash,
            'file_size': os.path.getsize(model_path),
            'selected_tags_summary': {
                'genre_count': len(self.selected_tags.get('genre', [])),
                'timing_count': len(self.selected_tags.get('timing', [])),
                'mood_count': len(self.selected_tags.get('mood', [])),
                'descriptive_count': len(self.selected_tags.get('descriptive', [])),
            },
            # CrateBot4: Include feature config in metadata
            'feature_config': self.feature_config.to_dict() if self.feature_config else None,
        }
        with open(meta_path, 'w') as f:
            json.dump(metadata, f, indent=2)

        logger.info("Model saved to %s", model_path)
        logger.debug("Model metadata saved to %s", meta_path)

    def load_model(self, model_path: str, verify_integrity: bool = True) -> None:
        """
        Load a trained model from disk with optional integrity verification.

        Args:
            model_path: Path to the model file
            verify_integrity: If True (default), verify SHA256 hash if metadata exists

        Raises:
            ModelLoadError: If the model file cannot be loaded
            ModelIntegrityError: If integrity verification fails
        """
        if not os.path.exists(model_path):
            raise ModelLoadError(f"Model file not found: {model_path}")

        meta_path = model_path + '.meta.json'

        # Verify integrity if metadata exists and verification is enabled
        if verify_integrity and os.path.exists(meta_path):
            try:
                with open(meta_path, 'r') as f:
                    metadata = json.load(f)

                # Check file hash
                with open(model_path, 'rb') as f:
                    actual_hash = hashlib.sha256(f.read()).hexdigest()

                expected_hash = metadata.get('sha256')
                if expected_hash and actual_hash != expected_hash:
                    raise ModelIntegrityError(expected_hash, actual_hash)

                logger.debug("Model integrity verified (SHA256 match)")

            except json.JSONDecodeError as e:
                logger.warning("Could not read model metadata: %s", e)
            except ModelIntegrityError:
                raise  # Re-raise integrity errors

        # Load the model
        try:
            with open(model_path, 'rb') as f:
                model_data = joblib.load(f)
        except (pickle.UnpicklingError, EOFError, KeyError) as e:
            raise ModelLoadError(f"Could not load model from {model_path}: {e}") from e

        # Check format version
        saved_version = model_data.get('format_version', '1.0')
        if saved_version != MODEL_FORMAT_VERSION:
            logger.warning(
                "Model format version mismatch: expected %s, got %s. May have compatibility issues.",
                MODEL_FORMAT_VERSION, saved_version
            )

        self.models = model_data['models']
        self.scalers = model_data['scalers']
        self.encoders = model_data['encoders']
        self.selected_tags = model_data['selected_tags']
        self.model_path = model_path  # Store path for later reference

        # CrateBot4: Load and validate feature configuration
        feature_config_data = model_data.get('feature_config')
        if feature_config_data:
            self.feature_config = FeatureConfig.from_dict(feature_config_data)

            # Validate compatibility with current environment
            warnings = validate_model_compatibility(self.feature_config)
            for warning in warnings:
                logger.warning(warning)

            logger.info(
                "Model feature config: PANNs=%s, CLAP=%s, Jamendo=%s (total=%d features)",
                self.feature_config.has_panns,
                self.feature_config.has_clap,
                self.feature_config.has_jamendo,
                self.feature_config.total_features()
            )
        else:
            # Legacy model without feature config
            logger.warning(
                "Model has no feature configuration metadata. "
                "This is a legacy model (pre-CrateBot4). Feature compatibility cannot be validated."
            )
            self.feature_config = None

        logger.info("Model loaded from %s", model_path)
