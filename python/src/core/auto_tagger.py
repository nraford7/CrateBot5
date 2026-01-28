import os
import logging
from typing import List, Dict, Any, Optional
from pathlib import Path
from tqdm import tqdm
import numpy as np

from .fast_analyzer import FastAudioAnalyzer, ParallelFeatureExtractor  # CrateBot4: Added parallel extraction
from .feature_cache import FeatureCache, CachedAnalyzer  # Feature caching (10x for repeats)
from .tag_manager import TagManager
from .tag_scanner import TagScanner, TagSelector
from .review_manager import ReviewManager, TagStatus
from .utils import matches_selected_tag
from .constants import MIN_TRAINING_SAMPLES, LIKENESS_SIGMOID_CENTER, ANALYSIS_DURATION_CACHED, ACTUAL_GENRE_VALUES, DEFAULT_GENRE_FOR_TIMING
from .tag_scanner import normalize_tag
from .vibe_generator import CachedVibeGenerator, is_vibe_available, get_vibe_status
from .panns_analyzer import PANNsAnalyzer, is_panns_available
from .hook_transcriber import CachedHookTranscriber, is_hook_transcription_available, get_hook_transcription_status
from .exceptions import (
    AudioTaggerError,
    ModelNotLoadedError,
    InsufficientTrainingDataError,
)
from .lexicon import Lexicon
from .overrides import OverrideStore
from .audio_hash import compute_audio_hash
from .taxonomy import transform_raw_tags_to_taxonomy, has_any_valid_tag  # CrateBot4: Centralized taxonomy
from ..models.tag_predictor import TagPredictor

logger = logging.getLogger(__name__)


class AutoTagger:
    def __init__(self, model_path: Optional[str] = None, use_cache: bool = True,
                 lexicon_path: Optional[str] = None, override_db_path: Optional[str] = None):
        """
        Initialize AutoTagger with optimized analysis.

        Args:
            model_path: Path to trained model file
            use_cache: Whether to use feature caching (default True for speed)
            lexicon_path: Path to lexicon JSON file for vocabulary customization.
                         If None, uses default ~/.cratebot/lexicon.json
            override_db_path: Path to override database. If None, uses default
                             ~/.cratebot/overrides.db
        """
        # Use CachedAnalyzer for speed (cache + fast analysis)
        if use_cache:
            self.analyzer = CachedAnalyzer(duration=ANALYSIS_DURATION_CACHED)
        else:
            self.analyzer = FastAudioAnalyzer(duration=ANALYSIS_DURATION_CACHED)

        self.tag_manager = TagManager()
        self.predictor = TagPredictor()
        self.use_cache = use_cache
        self.lexicon = Lexicon(path=lexicon_path)
        self.override_store = OverrideStore(path=override_db_path)
        self._model_path = None  # Track loaded model path

        if model_path and os.path.exists(model_path):
            self.predictor.load_model(model_path)
            self._model_path = model_path  # Store the path
            self.model_loaded = True
        else:
            self.model_loaded = False

    def train_from_directory(self, training_dir: str,
                             output_model_path: str = "models/cratebot.pkl",
                             test_size: float = 0.2,
                             skip_validation: bool = False) -> Dict[str, Any]:
        """
        Train a model with interactive tag selection.

        Flow:
        0. Validate all required components are ready (PANNs, CLAP, etc.)
        1. Scan all MP3s to discover tags
        2. Let user select which tags to train on
        3. Collect audio features for files with valid tags
        4. Train the model

        Args:
            training_dir: Directory containing MP3 files with tags
            output_model_path: Where to save the trained model
            test_size: Fraction of data for testing (default 0.2)
            skip_validation: If True, skip pre-training validation (NOT RECOMMENDED)
        """
        from rich.console import Console
        console = Console()

        # Step 0a: Auto-optimize hardware settings
        from .auto_optimize import optimize_for_hardware
        console.print("\n[bold cyan]Step 0a: Optimizing for hardware...[/bold cyan]")
        optimize_for_hardware(verbose=True, apply_env=True)

        # Step 0b: Pre-training validation (FAIL FAST if components missing)
        if not skip_validation:
            from .training_validator import validate_training_requirements
            console.print("\n[bold cyan]Step 0b: Validating training requirements...[/bold cyan]")
            validation = validate_training_requirements(
                require_panns=True,
                require_clap=True,
                require_jamendo=False,  # Optional
                require_essentia=False,  # Optional
                verbose=True
            )
            validation.raise_if_failed()

        # Step 1: Scan for tags
        console.print("\n[bold cyan]Step 1: Scanning for tags...[/bold cyan]")
        scanner = TagScanner(self.tag_manager)
        discovered_tags = scanner.scan_directory(training_dir)

        # Show summary
        console.print(f"\n[green]Tag Discovery Summary:[/green]")
        console.print(f"  Genre values: {len(discovered_tags['genre']['values'])}")
        console.print(f"  Album values: {len(discovered_tags['album']['values'])}")
        console.print(f"  Comment tags: {len(discovered_tags['comments']['values'])}")

        # Step 2: Interactive tag selection
        console.print("\n[bold cyan]Step 2: Select tags for training...[/bold cyan]")
        selector = TagSelector()
        selected_tags = selector.interactive_select(discovered_tags)

        if not any(selected_tags.values()):
            raise ValueError("No tags selected for training")

        # Step 3: Collect training data
        console.print("\n[bold cyan]Step 3: Collecting audio features...[/bold cyan]")
        training_data = self._collect_training_data(training_dir, selected_tags)

        if len(training_data) < MIN_TRAINING_SAMPLES:
            raise ValueError(f"Only {len(training_data)} valid samples found. Need at least {MIN_TRAINING_SAMPLES}.")

        console.print(f"\n[green]Collected {len(training_data)} training samples[/green]")

        # Step 4: Train the model
        console.print("\n[bold cyan]Step 4: Training model...[/bold cyan]")
        results = self.predictor.train(training_data, selected_tags, test_size=test_size)

        # Save the model
        os.makedirs(os.path.dirname(output_model_path), exist_ok=True)
        self.predictor.save_model(output_model_path)
        self.model_loaded = True

        results['selected_tags'] = selected_tags
        return results

    def train_from_directory_resume(self, training_dir: str,
                                     output_model_path: str = "models/cratebot.pkl",
                                     test_size: float = 0.2,
                                     skip_validation: bool = False) -> Dict[str, Any]:
        """
        Train a model using tag selections from the most recent checkpoint.

        This is useful for retraining with new features (like PANNs) without
        re-selecting tags interactively.

        Flow:
        0. Validate all required components are ready
        1. Find most recent checkpoint for this training directory
        2. Use its selected_tags
        3. Re-extract features (will use new feature vector)
        4. Train the model

        Args:
            training_dir: Directory containing MP3 files with tags
            output_model_path: Where to save the trained model
            test_size: Fraction of data for testing (default 0.2)
            skip_validation: If True, skip pre-training validation (NOT RECOMMENDED)
        """
        from rich.console import Console
        from .training_checkpoint import TrainingCheckpoint
        import json
        from pathlib import Path as P

        console = Console()

        # Step 0a: Auto-optimize hardware settings
        from .auto_optimize import optimize_for_hardware
        console.print("\n[bold cyan]Step 0a: Optimizing for hardware...[/bold cyan]")
        optimize_for_hardware(verbose=True, apply_env=True)

        # Step 0b: Pre-training validation (FAIL FAST if components missing)
        if not skip_validation:
            from .training_validator import validate_training_requirements
            console.print("\n[bold cyan]Step 0b: Validating training requirements...[/bold cyan]")
            validation = validate_training_requirements(
                require_panns=True,
                require_clap=True,
                require_jamendo=False,
                require_essentia=False,
                verbose=True
            )
            validation.raise_if_failed()

        # Find most recent checkpoint for this directory
        checkpoint_dir = P.home() / ".cratebot" / "checkpoints"
        checkpoints = []

        for meta_file in checkpoint_dir.glob("checkpoint_*.json"):
            try:
                with open(meta_file, 'r') as f:
                    meta = json.load(f)
                    if meta.get('training_dir') == training_dir:
                        checkpoints.append(meta)
            except (json.JSONDecodeError, OSError, KeyError) as e:
                logger.debug("Skipping invalid checkpoint %s: %s", meta_file, e)
                continue

        if not checkpoints:
            raise ValueError(f"No checkpoint found for training directory: {training_dir}")

        # Sort by last_updated (newest first) and get the most recent
        checkpoints.sort(key=lambda x: x.get('last_updated', ''), reverse=True)
        latest = checkpoints[0]

        selected_tags = latest.get('selected_tags', {})
        if not any(selected_tags.values()):
            raise ValueError("Checkpoint has no selected tags")

        console.print(f"\n[bold cyan]Using checkpoint: {latest.get('session_id')}[/bold cyan]")
        console.print(f"  Last updated: {latest.get('last_updated')}")
        console.print(f"  Genre tags: {len(selected_tags.get('genre', []))}")
        console.print(f"  Album tags: {len(selected_tags.get('album', []))}")
        console.print(f"  Comment tags: {len(selected_tags.get('comments', []))}")

        # Collect training data with new features
        console.print("\n[bold cyan]Extracting features with new feature vector...[/bold cyan]")
        training_data = self._collect_training_data(training_dir, selected_tags)

        if len(training_data) < MIN_TRAINING_SAMPLES:
            raise ValueError(f"Only {len(training_data)} valid samples found. Need at least {MIN_TRAINING_SAMPLES}.")

        console.print(f"\n[green]Collected {len(training_data)} training samples[/green]")

        # Train the model
        console.print("\n[bold cyan]Training model...[/bold cyan]")
        results = self.predictor.train(training_data, selected_tags, test_size=test_size)

        # Save the model
        os.makedirs(os.path.dirname(output_model_path), exist_ok=True)
        self.predictor.save_model(output_model_path)
        self.model_loaded = True

        results['selected_tags'] = selected_tags
        return results

    def _collect_training_data(self, directory_path: str,
                               selected_tags: Dict[str, List[str]]) -> List[Dict]:
        """
        Collect audio features for files that have at least one selected tag.

        Uses new taxonomy:
        - genre: actual genres (from Genre ID3 tag, filtered by ACTUAL_GENRE_VALUES)
        - timing: timing values (from Genre ID3 tag, if not a genre)
        - mood: from Album ID3 tag
        - descriptive: from Comments ID3 tag

        CrateBot4: Uses centralized taxonomy transformation and parallel feature extraction.
        """
        path = Path(directory_path)
        mp3_files = sorted([str(f) for f in path.glob('**/*.mp3')])

        training_data = []

        # CrateBot4: Phase 1 - Pre-filter files by tags (fast I/O scan)
        # This avoids extracting features for files that won't be used
        logger.info("Phase 1: Scanning %d files for matching tags...", len(mp3_files))
        valid_files_with_tags = []

        for mp3_path in tqdm(mp3_files, desc="Scanning tags"):
            try:
                raw_tags = self.tag_manager.read_tags(mp3_path, lexicon=self.lexicon)
                if not raw_tags:
                    continue

                # CrateBot4: Use centralized taxonomy transformation
                tags = transform_raw_tags_to_taxonomy(raw_tags, lexicon=self.lexicon)

                # Check if file has at least one selected tag
                if has_any_valid_tag(tags, selected_tags):
                    valid_files_with_tags.append((mp3_path, tags))

            except Exception as e:
                logger.debug("Error reading tags from %s: %s", mp3_path, e)
                continue

        logger.info("Found %d files with matching tags (%.1f%% of scanned)",
                    len(valid_files_with_tags),
                    100 * len(valid_files_with_tags) / len(mp3_files) if mp3_files else 0)

        if not valid_files_with_tags:
            return training_data

        # CrateBot4: Phase 2 - Extract features (use parallel if available and not cached)
        logger.info("Phase 2: Extracting features from %d files...", len(valid_files_with_tags))

        for mp3_path, tags in tqdm(valid_files_with_tags, desc="Extracting features"):
            try:
                # Extract audio features (uses cache if available)
                features = self.analyzer.extract_features(mp3_path)

                training_data.append({
                    'file_path': mp3_path,
                    'file_name': os.path.basename(mp3_path),
                    'features': features,
                    'tags': tags,
                    'feature_vector': features['feature_vector'],
                })

            except Exception as e:
                logger.warning("Error extracting features from %s: %s", mp3_path, e)
                continue

        logger.info("Successfully collected %d training samples", len(training_data))
        return training_data

    def _flatten_predictions(self, predicted_tags: Dict[str, Any]) -> Dict[str, Any]:
        """Normalize predictor output to legacy-friendly scalar values."""
        def extract_value(value: Any, key: str) -> Any:
            if isinstance(value, dict):
                if 'value' in value:
                    return value['value']
                if key == 'descriptive' and 'tags' in value:
                    return value['tags']
            return value

        flat: Dict[str, Any] = {}
        for key in ('genre', 'album', 'comments', 'timing', 'mood', 'descriptive'):
            if key in predicted_tags:
                flat[key] = extract_value(predicted_tags[key], key)

        genre_value = predicted_tags.get('genre')
        if isinstance(genre_value, dict) and 'confidence' in genre_value:
            flat['_genre_confidence'] = genre_value['confidence']

        timing_value = predicted_tags.get('timing')
        if isinstance(timing_value, dict) and 'confidence' in timing_value:
            flat['_album_confidence'] = timing_value['confidence']

        if '_descriptive_scores' in predicted_tags and isinstance(predicted_tags['_descriptive_scores'], dict):
            flat['_comment_scores'] = predicted_tags['_descriptive_scores']

        if '_comments_embedding' in predicted_tags:
            flat['_comments_embedding'] = predicted_tags['_comments_embedding']
        if '_overall_embedding' in predicted_tags:
            flat['_overall_embedding'] = predicted_tags['_overall_embedding']

        if 'timing' in flat and 'album' not in flat:
            flat['album'] = flat['timing']
        if 'descriptive' in flat and 'comments' not in flat:
            if isinstance(flat['descriptive'], list):
                flat['comments'] = ', '.join(flat['descriptive'])
            else:
                flat['comments'] = flat['descriptive']

        return flat

    def tag_file(self, mp3_path: str,
                 overwrite: bool = False,
                 dry_run: bool = False,
                 review_manager: Optional[ReviewManager] = None,
                 silent: bool = False,
                 likeness_only: bool = False,
                 tags_to_write: Optional[Dict[str, bool]] = None) -> Dict[str, Any]:
        """
        Tag a single MP3 file using the trained model.

        Args:
            mp3_path: Path to the MP3 file
            overwrite: Whether to overwrite existing tags
            dry_run: If True, don't write tags to file
            review_manager: Optional ReviewManager for confidence-based flagging
            silent: If True, suppress print output
            likeness_only: If True, only write likeness scores (preserve existing tags) [DEPRECATED]
            tags_to_write: Dict specifying which tags to write, e.g.:
                {'genre': True, 'album': True, 'comments': True, 'likeness': True}
                If None, defaults to writing all tags (backwards compatible)

        Returns:
            Dictionary with predictions, status, and flag_reasons
        """
        if not self.model_loaded:
            raise ValueError("No model loaded. Train a model first or load an existing one.")

        if not os.path.exists(mp3_path):
            raise FileNotFoundError(f"File not found: {mp3_path}")

        # Default: write all tags if not specified
        if tags_to_write is None:
            tags_to_write = {'genre': True, 'album': True, 'comments': True, 'mood': True, 'likeness': True}

        # Handle deprecated likeness_only mode
        if likeness_only:
            tags_to_write = {'genre': False, 'album': False, 'comments': False, 'mood': False, 'likeness': True}

        if not silent:
            print(f"Analyzing {os.path.basename(mp3_path)}...")
        features = self.analyzer.extract_features(mp3_path)

        predicted_tags = self.predictor.predict_tags(features)
        flat_predictions = self._flatten_predictions(predicted_tags)

        # Check if should be flagged for review (skip if only writing likeness)
        status = TagStatus.TAGGED.value
        flag_reasons = []
        writing_main_tags = (
            tags_to_write.get('genre')
            or tags_to_write.get('album')
            or tags_to_write.get('comments')
            or tags_to_write.get('mood')
        )

        if review_manager and writing_main_tags:
            should_flag, reasons = review_manager.should_flag_for_review(flat_predictions)
            if should_flag:
                status = TagStatus.REVIEW.value
                flag_reasons = reasons
                review_manager.add_to_queue(mp3_path, flat_predictions, flag_reasons)
                if not silent:
                    print(f"Flagged for review: {', '.join(reasons)}")

        # Write tags based on selection
        if not dry_run and status == TagStatus.TAGGED.value:
            # Write main tags based on selection
            write_tags = {}

            if tags_to_write.get('genre') and 'genre' in flat_predictions:
                write_tags['genre'] = flat_predictions['genre']

            if tags_to_write.get('album'):
                if 'timing' in flat_predictions:
                    write_tags['timing'] = flat_predictions['timing']
                elif 'album' in flat_predictions:
                    write_tags['album'] = flat_predictions['album']

            if tags_to_write.get('comments'):
                if 'descriptive' in flat_predictions:
                    write_tags['descriptive'] = flat_predictions['descriptive']
                elif 'comments' in flat_predictions:
                    write_tags['comments'] = flat_predictions['comments']

            # Also handle new format keys from predictor (timing, mood, descriptive)
            # These get mapped to file tags after lexicon transformation
            if tags_to_write.get('mood') and 'mood' in flat_predictions:
                write_tags['mood'] = flat_predictions['mood']

            # Check for per-track overrides (in canonical vocabulary)
            # Overrides are applied BEFORE lexicon so they can be transformed
            audio_hash = compute_audio_hash(mp3_path)
            override = self.override_store.get_override(audio_hash)
            if override:
                # Apply override values (override is in canonical vocabulary)
                for key, value in override.items():
                    if key in write_tags or key in flat_predictions:
                        write_tags[key] = value
                        # Also update predictions for return value
                        flat_predictions[key] = value

            if write_tags:
                # Apply lexicon mapping to transform canonical tags to user vocabulary
                # This maps keys like 'timing', 'mood', 'genre', 'descriptive'
                write_tags = self.lexicon.apply_to_tags(write_tags)

                # Remap 'timing' to 'album' for file storage (legacy compatibility)
                if 'timing' in write_tags:
                    write_tags['album'] = write_tags.pop('timing')

                self.tag_manager.write_tags(mp3_path, write_tags, overwrite=overwrite, lexicon=self.lexicon)

            # Write likeness scores if selected
            if tags_to_write.get('likeness'):
                comment_likeness = self._compute_likeness_score(flat_predictions.get('_comments_embedding'))
                overall_likeness = self._compute_likeness_score(flat_predictions.get('_overall_embedding'))
                if comment_likeness is not None or overall_likeness is not None:
                    self.tag_manager.write_likeness_scores(
                        mp3_path,
                        comment_likeness=comment_likeness,
                        overall_likeness=overall_likeness
                    )

            if not silent:
                if likeness_only:
                    print(f"Likeness scores written to {os.path.basename(mp3_path)}")
                else:
                    print(f"Tags written to {os.path.basename(mp3_path)}")
        elif not dry_run and status == TagStatus.REVIEW.value:
            if not silent:
                print(f"Tags NOT written (flagged for review)")
        elif dry_run:
            if not silent:
                print(f"Dry run - tags not written to file")

        # Return extended result
        return {
            'tags': flat_predictions,
            'status': status,
            'flag_reasons': flag_reasons,
            # Also include flat access for backward compatibility
            'genre': flat_predictions.get('genre'),
            'album': flat_predictions.get('album'),
            'comments': flat_predictions.get('comments'),
            '_genre_confidence': flat_predictions.get('_genre_confidence'),
            '_album_confidence': flat_predictions.get('_album_confidence'),
        }

    def tag_directory(self, directory_path: str,
                      recursive: bool = True,
                      overwrite: bool = False,
                      dry_run: bool = False,
                      output_report: str = None,
                      review_manager: Optional[ReviewManager] = None) -> List[Dict[str, Any]]:
        """
        Tag all MP3 files in a directory.

        Args:
            directory_path: Path to directory containing MP3 files
            recursive: Whether to search subdirectories
            overwrite: Whether to overwrite existing tags
            dry_run: If True, don't write tags to files
            output_report: Optional path to save JSON report
            review_manager: Optional ReviewManager for confidence-based flagging

        Returns:
            List of result dictionaries for each file
        """
        if not self.model_loaded:
            raise ValueError("No model loaded. Train a model first or load an existing one.")

        mp3_files = self._find_mp3s(directory_path, recursive, check_existing=not overwrite)

        if not mp3_files:
            print("No MP3 files to process")
            return []

        print(f"Found {len(mp3_files)} MP3 files to tag")

        results = []
        tagged_count = 0
        review_count = 0
        failed_count = 0

        for mp3_path in tqdm(mp3_files, desc="Tagging MP3 files"):
            try:
                result = self.tag_file(
                    mp3_path,
                    overwrite=overwrite,
                    dry_run=dry_run,
                    review_manager=review_manager,
                    silent=True
                )

                status = result.get('status', 'tagged')
                results.append({
                    'file': mp3_path,
                    'status': status,
                    'tags': result.get('tags', result),
                    'flag_reasons': result.get('flag_reasons', [])
                })

                if status == TagStatus.TAGGED.value:
                    tagged_count += 1
                elif status == TagStatus.REVIEW.value:
                    review_count += 1

            except Exception as e:
                results.append({
                    'file': mp3_path,
                    'status': 'failed',
                    'error': str(e)
                })
                failed_count += 1

        # Summary
        summary_parts = [f"{tagged_count} tagged"]
        if review_manager and review_count > 0:
            summary_parts.append(f"{review_count} flagged for review")
        if failed_count > 0:
            summary_parts.append(f"{failed_count} failed")
        print(f"\nTagging complete: {', '.join(summary_parts)}")

        if output_report:
            self._save_report(results, output_report)

        return results

    def _find_mp3s(self, directory_path: str,
                   recursive: bool,
                   check_existing: bool) -> List[str]:
        """Find MP3 files to tag."""
        path = Path(directory_path)
        pattern = '**/*.mp3' if recursive else '*.mp3'

        mp3_files = []
        for file_path in path.glob(pattern):
            if check_existing:
                try:
                    tags = self.tag_manager.read_tags(str(file_path), lexicon=self.lexicon)
                    # Skip if already has genre tag (our primary tag)
                    if tags and 'genre' in tags and tags['genre'].strip():
                        continue
                except (OSError, AudioTaggerError) as e:
                    logger.debug("Could not read tags from %s: %s", file_path, e)
                    pass

            mp3_files.append(str(file_path))

        return sorted(mp3_files)

    def _save_report(self, results: List[Dict], output_path: str) -> None:
        """Save tagging report to JSON."""
        import json

        report = {
            'total_files': len(results),
            'tagged': sum(1 for r in results if r['status'] == TagStatus.TAGGED.value),
            'review': sum(1 for r in results if r['status'] == TagStatus.REVIEW.value),
            'failed': sum(1 for r in results if r['status'] == 'failed'),
            'results': results
        }

        with open(output_path, 'w') as f:
            json.dump(report, f, indent=2)

        print(f"Report saved to {output_path}")

    def _compute_likeness_score(self, embedding: Optional[List[float]]) -> Optional[float]:
        """
        Compute a sortable likeness score from an embedding vector.

        Uses the normalized L2 norm of the embedding, scaled to 0.0-1.0.
        This provides a scalar summary that can be used for sorting tracks.

        Args:
            embedding: List of floats representing the embedding vector, or None

        Returns:
            Float between 0.0 and 1.0, or None if embedding is unavailable
        """
        if embedding is None or len(embedding) == 0:
            return None

        # Compute L2 norm
        vec = np.array(embedding)
        norm = np.linalg.norm(vec)

        # Normalize to 0-1 range using sigmoid-like transformation
        # This assumes typical embedding norms are in the range [0, 10]
        # Adjust if needed based on your actual embedding distributions
        score = 1.0 / (1.0 + np.exp(-norm + LIKENESS_SIGMOID_CENTER))

        return float(np.clip(score, 0.0, 1.0))

    def analyze_similarity(self, mp3_path1: str, mp3_path2: str) -> Dict[str, Any]:
        """Compare audio features between two MP3 files."""
        features1 = self.analyzer.extract_features(mp3_path1)
        features2 = self.analyzer.extract_features(mp3_path2)

        vec1 = features1['feature_vector']
        vec2 = features2['feature_vector']

        import numpy as np
        distance = np.linalg.norm(vec1 - vec2)
        similarity = 1.0 / (1.0 + distance)

        tags1 = self.tag_manager.read_tags(mp3_path1, lexicon=self.lexicon)
        tags2 = self.tag_manager.read_tags(mp3_path2, lexicon=self.lexicon)

        return {
            'file1': os.path.basename(mp3_path1),
            'file2': os.path.basename(mp3_path2),
            'feature_distance': float(distance),
            'similarity_score': float(similarity),
            'tags1': tags1,
            'tags2': tags2
        }

    # -------------------------------------------------------------------------
    # Vibe Generation - LLM-powered descriptive tags
    # -------------------------------------------------------------------------

    def generate_vibe(
        self,
        mp3_path: str,
        overwrite: bool = False,
        dry_run: bool = False,
        silent: bool = False,
        vibe_generator: Optional[CachedVibeGenerator] = None,
        hook_transcriber: Optional[CachedHookTranscriber] = None,
        skip_hook: bool = False
    ) -> Dict[str, Any]:
        """
        Generate a vibe tag and description for a single MP3 file using Claude API.

        The vibe is a ~8-12 word evocative tag stored in the Composer (TCOM) tag.
        The description is a natural language sentence stored in the Description (TXXX) tag.
        The vocal hook (if detected) is stored in a custom TXXX:HOOK tag.

        Args:
            mp3_path: Path to the MP3 file
            overwrite: Whether to overwrite existing composer tag
            dry_run: If True, don't write to file
            silent: If True, suppress print output
            vibe_generator: Optional pre-initialized CachedVibeGenerator
            hook_transcriber: Optional pre-initialized CachedHookTranscriber
            skip_hook: If True, skip vocal hook detection

        Returns:
            Dictionary with 'vibe', 'description', 'hook', 'file', and 'status' keys
        """
        if not os.path.exists(mp3_path):
            raise FileNotFoundError(f"File not found: {mp3_path}")

        # Check if vibe generation is available
        if vibe_generator is None:
            if not is_vibe_available():
                return {
                    'file': mp3_path,
                    'status': 'unavailable',
                    'error': get_vibe_status()
                }
            vibe_generator = CachedVibeGenerator()

        # Check existing composer tag
        existing_tags = self.tag_manager.read_tags(mp3_path, lexicon=self.lexicon)
        if not overwrite and existing_tags.get('composer'):
            if not silent:
                print(f"Skipping {os.path.basename(mp3_path)} - already has composer tag")
            return {
                'file': mp3_path,
                'status': 'skipped',
                'vibe': existing_tags['composer'],
                'description': existing_tags.get('description'),
                'hook': existing_tags.get('custom', {}).get('HOOK'),
                'reason': 'already_tagged'
            }

        if not silent:
            print(f"Analyzing {os.path.basename(mp3_path)}...")

        # Extract audio features
        features = self.analyzer.extract_features(mp3_path)

        # Run PANNs sound detection (instruments, genres, drums, vocals)
        detections = None
        detection_string = None
        if is_panns_available():
            try:
                panns = PANNsAnalyzer()
                detections = panns.detect_sounds(mp3_path, threshold=0.08)
                detection_string = panns.format_detections(detections, min_score=0.1)
                if not silent:
                    print(f"  Detected: {detection_string}")
            except Exception as e:
                if not silent:
                    print(f"  PANNs detection failed: {e}")

        # Run vocal transcription (Claude will identify the hook)
        vocal_transcription = None
        vocal_hook_fallback = None  # Fallback from n-gram if Claude fails
        vocal_hook_occurrences = 0
        if not skip_hook:
            # Initialize hook transcriber if not provided
            if hook_transcriber is None and is_hook_transcription_available():
                hook_transcriber = CachedHookTranscriber()

            if hook_transcriber and hook_transcriber.is_available:
                try:
                    if not silent:
                        print(f"  Transcribing vocals...")

                    # Extract artist/title for lyrics verification
                    artist = existing_tags.get('artist', '')
                    title = existing_tags.get('title', '')

                    # Get transcription - Claude will identify hook from this
                    # Pass artist/title to enable lyrics verification
                    hook_result = hook_transcriber.detect_hook(
                        mp3_path,
                        artist=artist,
                        title=title,
                        verify_lyrics=True
                    )

                    if hook_result.transcription:
                        vocal_transcription = hook_result.transcription
                        # Keep n-gram hook as fallback
                        vocal_hook_fallback = hook_result.hook
                        vocal_hook_occurrences = hook_result.occurrences

                        if not silent:
                            preview = vocal_transcription[:80] + "..." if len(vocal_transcription) > 80 else vocal_transcription
                            print(f"  Transcribed: \"{preview}\"")
                            if vocal_hook_fallback:
                                print(f"  N-gram fallback: \"{vocal_hook_fallback}\" ({vocal_hook_occurrences}x)")
                    elif not silent:
                        print(f"  No vocals detected")
                except Exception as e:
                    if not silent:
                        print(f"  Transcription failed: {e}")

        # Generate vibe, description, and scene (Claude identifies hook from transcription)
        try:
            result = vibe_generator.generate_vibe_with_description(
                mp3_path, features, existing_tags,
                detections=detections,
                vocal_hook=vocal_hook_fallback,  # Fallback if Claude doesn't identify hook
                vocal_hook_occurrences=vocal_hook_occurrences,
                vocal_transcription=vocal_transcription  # Claude will pick hook from this
            )
            vibe = result['vibe']
            description = result['description']
            scene = result.get('scene', 'Underground')
            scene_confidence = result.get('scene_confidence', 0.0)
            vocal_hook = result.get('hook')  # Hook identified by Claude (or fallback)
        except Exception as e:
            return {
                'file': mp3_path,
                'status': 'failed',
                'error': str(e)
            }

        if not silent:
            print(f"  Scene: {scene} ({scene_confidence:.0%} confidence)")
            print(f"  Vibe: {vibe}")
            print(f"  Description: {description}")
            if vocal_hook:
                print(f"  Hook (Claude): \"{vocal_hook}\"")

        # Build tags to write
        # Note: PANNs detections are used as context for vibe generation only,
        # not written directly to comments. The trained model predicts comment tags.
        tags_to_write = {
            'composer': vibe,
            'description': description,
            'movement_name': scene,
        }

        # Add vocal hook to Work tag if detected
        if vocal_hook:
            tags_to_write['work'] = vocal_hook

        # Write tags
        if not dry_run:
            self.tag_manager.write_tags(mp3_path, tags_to_write, overwrite=overwrite, lexicon=self.lexicon)
            if not silent:
                written_tags = "Composer, Description, Movement Name"
                if vocal_hook:
                    written_tags += ", Work"
                print(f"  Written to {written_tags}")

        return {
            'file': mp3_path,
            'status': 'tagged',
            'vibe': vibe,
            'description': description,
            'scene': scene,
            'scene_confidence': scene_confidence,
            'detections': detection_string,
            'hook': vocal_hook,
            'hook_occurrences': vocal_hook_occurrences,
        }

    def generate_vibes(
        self,
        directory_path: str,
        recursive: bool = True,
        overwrite: bool = False,
        dry_run: bool = False,
        output_report: str = None,
        skip_hook: bool = False
    ) -> List[Dict[str, Any]]:
        """
        Generate vibe tags and descriptions for all MP3 files in a directory.

        Uses Claude API with caching to minimize API calls. Vibes are stored
        in the Composer (TCOM) tag, descriptions in the Description (TXXX) tag.
        Vocal hooks are stored in TXXX:HOOK tag.

        Args:
            directory_path: Path to directory containing MP3 files
            recursive: Whether to search subdirectories
            overwrite: Whether to overwrite existing composer tags
            dry_run: If True, don't write to files
            output_report: Optional path to save JSON report
            skip_hook: If True, skip vocal hook detection

        Returns:
            List of result dictionaries for each file (includes 'vibe', 'description', 'hook')
        """
        # Check availability first
        if not is_vibe_available():
            print(f"Vibe generation unavailable: {get_vibe_status()}")
            return []

        # Initialize cached generator (shared across all files)
        vibe_generator = CachedVibeGenerator()

        # Initialize hook transcriber if available (shared across all files)
        hook_transcriber = None
        if not skip_hook and is_hook_transcription_available():
            hook_transcriber = CachedHookTranscriber()
            print(f"Hook transcription: {get_hook_transcription_status()}")
        elif not skip_hook:
            print(f"Hook transcription unavailable: {get_hook_transcription_status()}")

        # Find MP3 files
        mp3_files = self._find_mp3s_for_vibe(directory_path, recursive, check_existing=not overwrite)

        if not mp3_files:
            print("No MP3 files to process")
            return []

        print(f"Found {len(mp3_files)} MP3 files for vibe generation")

        results = []
        tagged_count = 0
        skipped_count = 0
        failed_count = 0
        hooks_found = 0

        for mp3_path in tqdm(mp3_files, desc="Generating vibes"):
            try:
                result = self.generate_vibe(
                    mp3_path,
                    overwrite=overwrite,
                    dry_run=dry_run,
                    silent=True,
                    vibe_generator=vibe_generator,
                    hook_transcriber=hook_transcriber,
                    skip_hook=skip_hook
                )

                results.append(result)
                status = result.get('status', 'unknown')

                if status == 'tagged':
                    tagged_count += 1
                    if result.get('hook'):
                        hooks_found += 1
                elif status == 'skipped':
                    skipped_count += 1
                else:
                    failed_count += 1

            except Exception as e:
                results.append({
                    'file': mp3_path,
                    'status': 'failed',
                    'error': str(e)
                })
                failed_count += 1

        # Summary
        stats = vibe_generator.get_stats()
        summary_parts = [f"{tagged_count} vibes + descriptions generated"]
        if hooks_found > 0:
            summary_parts.append(f"{hooks_found} hooks detected")
        if skipped_count > 0:
            summary_parts.append(f"{skipped_count} skipped")
        if failed_count > 0:
            summary_parts.append(f"{failed_count} failed")
        summary_parts.append(f"(API calls: {stats['api_calls']}, cache hits: {stats['cache_hits']})")

        print(f"\nVibe generation complete: {', '.join(summary_parts)}")

        if output_report:
            self._save_vibe_report(results, output_report)

        return results

    def _find_mp3s_for_vibe(
        self,
        directory_path: str,
        recursive: bool,
        check_existing: bool
    ) -> List[str]:
        """Find MP3 files for vibe generation."""
        path = Path(directory_path)
        pattern = '**/*.mp3' if recursive else '*.mp3'

        mp3_files = []
        for file_path in path.glob(pattern):
            if check_existing:
                try:
                    tags = self.tag_manager.read_tags(str(file_path), lexicon=self.lexicon)
                    # Skip if already has composer tag (vibe)
                    if tags and 'composer' in tags and tags['composer'].strip():
                        continue
                except (OSError, AudioTaggerError) as e:
                    logger.debug("Could not read tags from %s: %s", file_path, e)
                    pass

            mp3_files.append(str(file_path))

        return sorted(mp3_files)

    def _save_vibe_report(self, results: List[Dict], output_path: str) -> None:
        """Save vibe generation report to JSON."""
        import json

        report = {
            'total_files': len(results),
            'tagged': sum(1 for r in results if r['status'] == 'tagged'),
            'skipped': sum(1 for r in results if r['status'] == 'skipped'),
            'failed': sum(1 for r in results if r['status'] == 'failed'),
            'results': results
        }

        with open(output_path, 'w') as f:
            json.dump(report, f, indent=2)

        print(f"Vibe report saved to {output_path}")
