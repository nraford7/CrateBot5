"""
Review Manager for Audio Tagger

Manages the review queue for low-confidence predictions and
provides a feedback loop for model improvement.
"""

import json
import logging
import os
from pathlib import Path
from typing import Dict, List, Optional, Any, Tuple
from datetime import datetime
from enum import Enum
from dataclasses import dataclass, asdict

from .constants import (
    GENRE_CONFIDENCE_THRESHOLD,
    ALBUM_CONFIDENCE_THRESHOLD,
    COMMENTS_CONFIDENCE_THRESHOLD,
)

logger = logging.getLogger(__name__)


class TagStatus(Enum):
    """Status values for tagged files."""
    TAGGED = "tagged"           # High confidence, tags written
    REVIEW = "review"           # Low confidence, needs human review
    CONFIRMED = "confirmed"     # Human reviewed and approved
    CORRECTED = "corrected"     # Human reviewed and fixed
    SKIPPED = "skipped"         # User skipped for later


@dataclass
class ReviewItem:
    """Single item in the review queue."""
    file_path: str
    file_name: str
    status: TagStatus
    predicted_tags: Dict[str, Any]      # genre, album, comments
    confidence_scores: Dict[str, float]  # genre_conf, album_conf, comments_top
    corrected_tags: Optional[Dict[str, Any]] = None
    review_timestamp: Optional[str] = None
    flag_reasons: Optional[List[str]] = None

    def to_dict(self) -> Dict:
        """Convert to dictionary for JSON serialization."""
        d = asdict(self)
        d['status'] = self.status.value
        return d

    @classmethod
    def from_dict(cls, d: Dict) -> 'ReviewItem':
        """Create from dictionary."""
        d = d.copy()
        d['status'] = TagStatus(d['status'])
        return cls(**d)


class ConfidenceThresholds:
    """Configurable confidence thresholds for flagging predictions."""
    GENRE_MIN = GENRE_CONFIDENCE_THRESHOLD
    ALBUM_MIN = ALBUM_CONFIDENCE_THRESHOLD
    COMMENTS_MIN = COMMENTS_CONFIDENCE_THRESHOLD  # For top comment tag score


class ReviewManager:
    """Manages the review queue and persistence."""

    def __init__(self, data_dir: str = None):
        """
        Initialize the review manager.

        Args:
            data_dir: Directory for storing review data. Defaults to project data/ folder.
        """
        if data_dir is None:
            data_dir = Path(__file__).parent.parent.parent / "data"
        self.data_dir = Path(data_dir)
        self.review_file = self.data_dir / "review_queue.json"
        self.queue: List[ReviewItem] = []
        self._load()

    def _load(self) -> None:
        """Load review queue from disk."""
        if self.review_file.exists():
            try:
                with open(self.review_file, 'r') as f:
                    data = json.load(f)
                    self.queue = [ReviewItem.from_dict(item) for item in data.get('items', [])]
            except (json.JSONDecodeError, KeyError, TypeError) as e:
                logger.warning("Could not load review queue: %s", e)
                self.queue = []

    def _save(self) -> None:
        """Persist review queue to disk."""
        self.data_dir.mkdir(parents=True, exist_ok=True)
        data = {
            'items': [item.to_dict() for item in self.queue],
            'last_updated': datetime.now().isoformat()
        }
        with open(self.review_file, 'w') as f:
            json.dump(data, f, indent=2)

    def should_flag_for_review(self, predicted_tags: Dict[str, Any]) -> Tuple[bool, List[str]]:
        """
        Check if predictions should be flagged based on confidence scores.

        Args:
            predicted_tags: Dictionary containing predictions and confidence scores

        Returns:
            Tuple of (should_flag, list_of_reasons)
        """
        reasons = []

        # Check genre confidence
        genre_conf = predicted_tags.get('_genre_confidence', 1.0)
        if genre_conf < ConfidenceThresholds.GENRE_MIN:
            reasons.append(f"Genre confidence {genre_conf:.2f} < {ConfidenceThresholds.GENRE_MIN}")

        # Check album confidence
        album_conf = predicted_tags.get('_album_confidence', 1.0)
        if album_conf < ConfidenceThresholds.ALBUM_MIN:
            reasons.append(f"Album confidence {album_conf:.2f} < {ConfidenceThresholds.ALBUM_MIN}")

        # Check comments confidence (top score)
        comment_scores = predicted_tags.get('_comment_scores', {})
        if comment_scores:
            top_score = max(comment_scores.values()) if comment_scores else 0
            if top_score < ConfidenceThresholds.COMMENTS_MIN:
                reasons.append(f"Comments top score {top_score:.2f} < {ConfidenceThresholds.COMMENTS_MIN}")

        return len(reasons) > 0, reasons

    def add_to_queue(self, file_path: str, predicted_tags: Dict[str, Any],
                     flag_reasons: List[str]) -> ReviewItem:
        """
        Add a file to the review queue.

        Args:
            file_path: Path to the audio file
            predicted_tags: Predicted tags with confidence scores
            flag_reasons: List of reasons why it was flagged

        Returns:
            The created ReviewItem
        """
        # Check if already in queue
        for existing in self.queue:
            if existing.file_path == file_path:
                # Update existing item
                existing.predicted_tags = {
                    'genre': predicted_tags.get('genre'),
                    'album': predicted_tags.get('album'),
                    'comments': predicted_tags.get('comments'),
                    # Include embeddings for likeness score calculation
                    '_comments_embedding': predicted_tags.get('_comments_embedding'),
                    '_overall_embedding': predicted_tags.get('_overall_embedding'),
                }
                existing.confidence_scores = {
                    'genre': predicted_tags.get('_genre_confidence', 0),
                    'album': predicted_tags.get('_album_confidence', 0),
                    'comments_top': max(predicted_tags.get('_comment_scores', {}).values(), default=0),
                }
                existing.flag_reasons = flag_reasons
                existing.status = TagStatus.REVIEW
                self._save()
                return existing

        item = ReviewItem(
            file_path=file_path,
            file_name=os.path.basename(file_path),
            status=TagStatus.REVIEW,
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
            flag_reasons=flag_reasons
        )
        self.queue.append(item)
        self._save()
        return item

    def get_pending_reviews(self) -> List[ReviewItem]:
        """Get all items pending review."""
        return [item for item in self.queue if item.status == TagStatus.REVIEW]

    def get_skipped_reviews(self) -> List[ReviewItem]:
        """Get all skipped items."""
        return [item for item in self.queue if item.status == TagStatus.SKIPPED]

    def get_item_by_path(self, file_path: str) -> Optional[ReviewItem]:
        """Get a review item by file path."""
        for item in self.queue:
            if item.file_path == file_path:
                return item
        return None

    def confirm_item(self, file_path: str) -> bool:
        """
        Mark item as confirmed (predictions accepted as-is).

        Args:
            file_path: Path to the file

        Returns:
            True if item was found and updated
        """
        for item in self.queue:
            if item.file_path == file_path and item.status in (TagStatus.REVIEW, TagStatus.SKIPPED):
                item.status = TagStatus.CONFIRMED
                item.review_timestamp = datetime.now().isoformat()
                self._save()
                return True
        return False

    def correct_item(self, file_path: str, corrected_tags: Dict[str, Any]) -> bool:
        """
        Mark item as corrected with new tags.

        Args:
            file_path: Path to the file
            corrected_tags: Dictionary with corrected genre, album, comments

        Returns:
            True if item was found and updated
        """
        for item in self.queue:
            if item.file_path == file_path and item.status in (TagStatus.REVIEW, TagStatus.SKIPPED):
                item.status = TagStatus.CORRECTED
                item.corrected_tags = corrected_tags
                item.review_timestamp = datetime.now().isoformat()
                self._save()
                return True
        return False

    def skip_item(self, file_path: str) -> bool:
        """
        Skip item for later review.

        Args:
            file_path: Path to the file

        Returns:
            True if item was found and updated
        """
        for item in self.queue:
            if item.file_path == file_path and item.status == TagStatus.REVIEW:
                item.status = TagStatus.SKIPPED
                self._save()
                return True
        return False

    def unskip_item(self, file_path: str) -> bool:
        """
        Move skipped item back to review.

        Args:
            file_path: Path to the file

        Returns:
            True if item was found and updated
        """
        for item in self.queue:
            if item.file_path == file_path and item.status == TagStatus.SKIPPED:
                item.status = TagStatus.REVIEW
                self._save()
                return True
        return False

    def get_training_additions(self) -> List[Dict[str, Any]]:
        """
        Get confirmed/corrected items ready for retraining.

        Returns:
            List of dictionaries with file_path, tags, and metadata
        """
        additions = []
        for item in self.queue:
            if item.status in (TagStatus.CONFIRMED, TagStatus.CORRECTED):
                tags = item.corrected_tags if item.corrected_tags else item.predicted_tags
                additions.append({
                    'file_path': item.file_path,
                    'tags': tags,
                    'source': 'review',
                    'original_status': item.status.value,
                    'review_timestamp': item.review_timestamp,
                })
        return additions

    def clear_processed(self) -> int:
        """
        Remove confirmed/corrected items after retraining.

        Returns:
            Number of items removed
        """
        original_count = len(self.queue)
        self.queue = [item for item in self.queue
                      if item.status not in (TagStatus.CONFIRMED, TagStatus.CORRECTED)]
        self._save()
        return original_count - len(self.queue)

    def remove_item(self, file_path: str) -> bool:
        """
        Remove an item from the queue entirely.

        Args:
            file_path: Path to the file

        Returns:
            True if item was found and removed
        """
        for i, item in enumerate(self.queue):
            if item.file_path == file_path:
                del self.queue[i]
                self._save()
                return True
        return False

    def get_stats(self) -> Dict[str, int]:
        """
        Get queue statistics.

        Returns:
            Dictionary with counts for each status
        """
        stats = {status.value: 0 for status in TagStatus}
        for item in self.queue:
            stats[item.status.value] += 1
        stats['total'] = len(self.queue)
        stats['ready_for_training'] = stats['confirmed'] + stats['corrected']
        return stats

    def clear_all(self) -> int:
        """
        Clear the entire queue.

        Returns:
            Number of items removed
        """
        count = len(self.queue)
        self.queue = []
        self._save()
        return count
