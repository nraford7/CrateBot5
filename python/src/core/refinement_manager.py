"""
Refinement Manager for Audio Tagger

Manages tag refinement sessions where users validate/correct
predictions on a diverse sample of songs to improve model accuracy.
"""

import os
import json
import random
from pathlib import Path
from typing import Dict, List, Optional, Any, Set, Tuple
from dataclasses import dataclass, asdict
from collections import defaultdict
from datetime import datetime


@dataclass
class RefinementItem:
    """Single item in a refinement session."""
    file_path: str
    file_name: str
    predicted_tags: Dict[str, Any]
    confidence_scores: Dict[str, float]
    corrected_tags: Optional[Dict[str, Any]] = None
    approved: bool = False
    skipped: bool = False

    def to_dict(self) -> Dict:
        """Convert to dictionary for JSON serialization."""
        return asdict(self)

    @classmethod
    def from_dict(cls, d: Dict) -> 'RefinementItem':
        """Create from dictionary."""
        return cls(**d)


class DiverseSampler:
    """
    Sample diverse songs across genre/album/comment tags.

    Strategy:
    1. Read all tags from directory
    2. Group files by (genre, album) combinations
    3. Within each group, prioritize different comment tags
    4. Round-robin select from groups until sample_size reached
    """

    def __init__(self, tag_manager):
        """
        Initialize the sampler.

        Args:
            tag_manager: TagManager instance for reading tags
        """
        self.tag_manager = tag_manager

    def sample_diverse(self, directory: str, sample_size: int = 100,
                       recursive: bool = True) -> List[str]:
        """
        Sample songs to maximize tag diversity.

        Args:
            directory: Directory to sample from
            sample_size: Number of songs to sample
            recursive: Whether to search subdirectories

        Returns:
            List of file paths
        """
        # Find all MP3s
        path = Path(directory)
        pattern = '**/*.mp3' if recursive else '*.mp3'
        mp3_files = list(path.glob(pattern))

        if len(mp3_files) <= sample_size:
            return [str(f) for f in mp3_files]

        # Group by genre+album
        groups: Dict[Tuple[str, str], List[Tuple[str, Set[str]]]] = defaultdict(list)

        for mp3_path in mp3_files:
            try:
                tags = self.tag_manager.read_tags(str(mp3_path))
                if not tags:
                    # Still include files without tags
                    groups[('Unknown', 'Unknown')].append((str(mp3_path), set()))
                    continue

                genre = (tags.get('genre', '') or '').strip() or 'Unknown'
                album = (tags.get('album', '') or '').strip() or 'Unknown'

                # Parse comment tags
                comments = tags.get('comments', '')
                if isinstance(comments, list):
                    comments = ' '.join(comments)
                comment_tags = set(c.strip().lower() for c in str(comments).split(',') if c.strip())

                groups[(genre, album)].append((str(mp3_path), comment_tags))

            except Exception:
                # Include file even if we can't read tags
                groups[('Unknown', 'Unknown')].append((str(mp3_path), set()))
                continue

        # Round-robin selection with comment diversity
        selected: List[str] = []
        selected_paths: Set[str] = set()
        selected_comment_tags: Set[str] = set()

        # Convert to list for iteration
        group_list = list(groups.items())
        if not group_list:
            # Fallback to random selection
            random.shuffle(mp3_files)
            return [str(f) for f in mp3_files[:sample_size]]

        group_indices = {key: 0 for key, _ in group_list}

        # Keep iterating until we have enough samples
        max_iterations = len(mp3_files) * 2  # Safety limit
        iteration = 0

        while len(selected) < sample_size and iteration < max_iterations:
            iteration += 1
            made_progress = False

            for (genre, album), files in group_list:
                if len(selected) >= sample_size:
                    break

                idx = group_indices[(genre, album)]
                if idx >= len(files):
                    continue

                # Find file with most new comment tags (look ahead up to 5)
                best_file = None
                best_new_tags = -1
                best_idx = idx

                for i in range(idx, min(idx + 5, len(files))):
                    file_path, file_comments = files[i]
                    if file_path in selected_paths:
                        continue
                    new_tags = len(file_comments - selected_comment_tags)
                    if new_tags > best_new_tags:
                        best_new_tags = new_tags
                        best_file = file_path
                        best_idx = i

                if best_file and best_file not in selected_paths:
                    selected.append(best_file)
                    selected_paths.add(best_file)
                    _, file_comments = files[best_idx]
                    selected_comment_tags.update(file_comments)
                    group_indices[(genre, album)] = best_idx + 1
                    made_progress = True

            if not made_progress:
                # If stuck, add remaining files randomly
                remaining = [str(f) for f in mp3_files if str(f) not in selected_paths]
                if remaining:
                    random.shuffle(remaining)
                    for f in remaining:
                        if len(selected) >= sample_size:
                            break
                        selected.append(f)
                        selected_paths.add(f)
                break

        return selected[:sample_size]


class RefinementSession:
    """
    Manages a tag refinement session.

    A session consists of:
    - A list of sampled files with predictions
    - Current position in the list
    - User approvals/corrections for each file
    """

    def __init__(self, data_dir: str = None):
        """
        Initialize the refinement session.

        Args:
            data_dir: Directory for storing session data
        """
        if data_dir is None:
            data_dir = Path(__file__).parent.parent.parent / "data"
        self.data_dir = Path(data_dir)
        self.session_file = self.data_dir / "refinement_session.json"

        self.items: List[RefinementItem] = []
        self.current_index: int = 0
        self.session_start: Optional[str] = None
        self._load()

    def _load(self) -> None:
        """Load existing session if available."""
        if self.session_file.exists():
            try:
                with open(self.session_file, 'r') as f:
                    data = json.load(f)
                    self.items = [RefinementItem.from_dict(item) for item in data.get('items', [])]
                    self.current_index = data.get('current_index', 0)
                    self.session_start = data.get('session_start')
            except (json.JSONDecodeError, KeyError, TypeError) as e:
                print(f"Warning: Could not load refinement session: {e}")
                self.items = []
                self.current_index = 0
                self.session_start = None

    def _save(self) -> None:
        """Save session state."""
        self.data_dir.mkdir(parents=True, exist_ok=True)
        data = {
            'items': [item.to_dict() for item in self.items],
            'current_index': self.current_index,
            'session_start': self.session_start,
            'last_updated': datetime.now().isoformat(),
        }
        with open(self.session_file, 'w') as f:
            json.dump(data, f, indent=2)

    def start_new_session(self, file_paths: List[str], predictor,
                          progress_callback=None) -> int:
        """
        Start a new refinement session with fresh predictions.

        Args:
            file_paths: List of file paths to include
            predictor: TagPredictor instance for predictions
            progress_callback: Optional callback(current, total) for progress

        Returns:
            Number of files successfully processed
        """
        # Import here to avoid circular imports
        import sys
        import os
        sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
        from core.feature_cache import CachedAnalyzer  # Use cached fast analyzer

        self.items = []
        self.current_index = 0
        self.session_start = datetime.now().isoformat()

        # Use CachedAnalyzer: 30s analysis + caching = ~10x faster
        analyzer = CachedAnalyzer(duration=30.0)
        total = len(file_paths)

        for idx, file_path in enumerate(file_paths):
            if progress_callback:
                progress_callback(idx + 1, total)

            try:
                # Extract features and predict (ignoring existing tags)
                features = analyzer.extract_features(file_path)
                predicted_tags = predictor.predict_tags(features)

                item = RefinementItem(
                    file_path=file_path,
                    file_name=os.path.basename(file_path),
                    predicted_tags={
                        'genre': predicted_tags.get('genre'),
                        'album': predicted_tags.get('album'),
                        'comments': predicted_tags.get('comments'),
                        # Include embeddings for likeness score calculation
                        '_comments_embedding': predicted_tags.get('_comments_embedding'),
                        '_overall_embedding': predicted_tags.get('_overall_embedding'),
                    },
                    confidence_scores={
                        'genre': predicted_tags.get('_genre_confidence', 0),
                        'album': predicted_tags.get('_album_confidence', 0),
                        'comments_top': max(predicted_tags.get('_comment_scores', {}).values(), default=0),
                    },
                )
                self.items.append(item)

            except Exception as e:
                print(f"Error processing {file_path}: {e}")
                continue

        self._save()
        return len(self.items)

    def get_current_item(self) -> Optional[RefinementItem]:
        """Get current item for review."""
        if 0 <= self.current_index < len(self.items):
            return self.items[self.current_index]
        return None

    def approve_current(self) -> bool:
        """
        Approve current item's predictions.

        Returns:
            True if successful
        """
        item = self.get_current_item()
        if item:
            item.approved = True
            item.skipped = False
            self._save()
            return True
        return False

    def correct_current(self, corrected_tags: Dict[str, Any]) -> bool:
        """
        Apply corrections to current item.

        Args:
            corrected_tags: Dictionary with corrected genre, album, comments

        Returns:
            True if successful
        """
        item = self.get_current_item()
        if item:
            item.corrected_tags = corrected_tags
            item.approved = True
            item.skipped = False
            self._save()
            return True
        return False

    def skip_current(self) -> bool:
        """
        Skip current item.

        Returns:
            True if successful
        """
        item = self.get_current_item()
        if item:
            item.skipped = True
            item.approved = False
            self._save()
            return True
        return False

    def next_item(self) -> Optional[RefinementItem]:
        """Move to next item."""
        if self.current_index < len(self.items) - 1:
            self.current_index += 1
            self._save()
        return self.get_current_item()

    def prev_item(self) -> Optional[RefinementItem]:
        """Move to previous item."""
        if self.current_index > 0:
            self.current_index -= 1
            self._save()
        return self.get_current_item()

    def go_to_item(self, index: int) -> Optional[RefinementItem]:
        """
        Go to a specific item.

        Args:
            index: Zero-based index

        Returns:
            The item at that index or None
        """
        if 0 <= index < len(self.items):
            self.current_index = index
            self._save()
            return self.get_current_item()
        return None

    def get_progress(self) -> Tuple[int, int, int]:
        """
        Get session progress.

        Returns:
            Tuple of (current_position, total_items, reviewed_count)
        """
        reviewed = sum(1 for item in self.items if item.approved or item.skipped)
        return self.current_index + 1, len(self.items), reviewed

    def get_training_additions(self) -> List[Dict[str, Any]]:
        """
        Get approved/corrected items for retraining.

        Returns:
            List of dictionaries with file_path, tags, and metadata
        """
        additions = []
        for item in self.items:
            if item.approved and not item.skipped:
                tags = item.corrected_tags if item.corrected_tags else item.predicted_tags
                additions.append({
                    'file_path': item.file_path,
                    'tags': tags,
                    'source': 'refinement',
                    'was_corrected': item.corrected_tags is not None,
                })
        return additions

    def clear_session(self) -> None:
        """Clear the current session."""
        self.items = []
        self.current_index = 0
        self.session_start = None
        if self.session_file.exists():
            try:
                self.session_file.unlink()
            except Exception:
                pass

    def has_active_session(self) -> bool:
        """Check if there's an active session."""
        return len(self.items) > 0

    def get_stats(self) -> Dict[str, int]:
        """
        Get session statistics.

        Returns:
            Dictionary with counts
        """
        approved = sum(1 for item in self.items if item.approved and not item.skipped)
        corrected = sum(1 for item in self.items if item.corrected_tags is not None)
        skipped = sum(1 for item in self.items if item.skipped)
        pending = len(self.items) - approved - skipped

        return {
            'total': len(self.items),
            'approved': approved,
            'corrected': corrected,
            'skipped': skipped,
            'pending': pending,
            'current_index': self.current_index,
        }
