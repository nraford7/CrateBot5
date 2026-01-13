"""
Training Checkpoint Manager

Handles saving and loading training checkpoints to allow:
- Resume training after cancellation
- Pause/resume functionality
- Recovery from crashes

Checkpoints are saved every N files (default 100) and include:
- Extracted features for processed files
- File paths of remaining files
- Selected tags configuration
- Training metadata
"""

import hashlib
import json
import logging
import os
import pickle
from datetime import datetime
from pathlib import Path
from typing import Dict, Any, List, Optional, Tuple

from .paths import get_cratebot_dir

logger = logging.getLogger(__name__)
class TrainingCheckpoint:
    """
    Manages training checkpoints for feature extraction.

    Checkpoint files are stored in ~/.cratebot/checkpoints/
    """

    def __init__(self, checkpoint_dir: Optional[str] = None):
        """
        Initialize checkpoint manager.

        Args:
            checkpoint_dir: Directory for checkpoints. Default: ~/.cratebot/checkpoints/
        """
        if checkpoint_dir:
            self.checkpoint_dir = Path(checkpoint_dir)
        else:
            self.checkpoint_dir = get_cratebot_dir() / "checkpoints"

        self.checkpoint_dir.mkdir(parents=True, exist_ok=True)

    def _get_session_id(self, training_dir: str, selected_tags: Dict[str, List[str]]) -> str:
        """
        Generate a unique session ID based on training configuration.

        This allows having separate checkpoints for different training runs.
        """
        # Create a hash of the training directory and selected tags
        config_str = f"{training_dir}|{json.dumps(selected_tags, sort_keys=True)}"
        return hashlib.md5(config_str.encode()).hexdigest()[:12]

    def _get_checkpoint_path(self, session_id: str) -> Path:
        """Get the checkpoint file path for a session."""
        return self.checkpoint_dir / f"checkpoint_{session_id}.pkl"

    def _get_metadata_path(self, session_id: str) -> Path:
        """Get the metadata file path for a session."""
        return self.checkpoint_dir / f"checkpoint_{session_id}.json"

    def save_checkpoint(self, training_dir: str, selected_tags: Dict[str, List[str]],
                        training_data: List[Dict], all_files: List[str],
                        processed_files: set, metadata: Optional[Dict] = None) -> str:
        """
        Save a training checkpoint.

        Args:
            training_dir: The training directory path
            selected_tags: Dictionary of selected tags for training
            training_data: List of extracted feature dictionaries
            all_files: Complete list of all MP3 files to process
            processed_files: Set of file paths that have been processed
            metadata: Optional additional metadata (e.g., timing info)

        Returns:
            Session ID of the saved checkpoint
        """
        session_id = self._get_session_id(training_dir, selected_tags)

        # Save the heavy data (features) to pickle
        checkpoint_data = {
            'training_data': training_data,
            'processed_files': list(processed_files),
            'all_files': all_files,
        }

        checkpoint_path = self._get_checkpoint_path(session_id)
        with open(checkpoint_path, 'wb') as f:
            pickle.dump(checkpoint_data, f)

        # Save metadata to JSON (human readable)
        meta = {
            'session_id': session_id,
            'training_dir': training_dir,
            'selected_tags': selected_tags,
            'total_files': len(all_files),
            'processed_count': len(processed_files),
            'samples_collected': len(training_data),
            'last_updated': datetime.now().isoformat(),
            'checkpoint_path': str(checkpoint_path),
        }

        if metadata:
            meta.update(metadata)

        metadata_path = self._get_metadata_path(session_id)
        with open(metadata_path, 'w') as f:
            json.dump(meta, f, indent=2)

        return session_id

    def load_checkpoint(self, training_dir: str,
                        selected_tags: Dict[str, List[str]]) -> Optional[Dict[str, Any]]:
        """
        Load an existing checkpoint if available.

        Args:
            training_dir: The training directory path
            selected_tags: Dictionary of selected tags for training

        Returns:
            Checkpoint data or None if no checkpoint exists
        """
        session_id = self._get_session_id(training_dir, selected_tags)
        checkpoint_path = self._get_checkpoint_path(session_id)
        metadata_path = self._get_metadata_path(session_id)

        if not checkpoint_path.exists():
            return None

        try:
            # Load heavy data
            with open(checkpoint_path, 'rb') as f:
                checkpoint_data = pickle.load(f)

            # Load metadata
            metadata = {}
            if metadata_path.exists():
                with open(metadata_path, 'r') as f:
                    metadata = json.load(f)

            return {
                'session_id': session_id,
                'training_data': checkpoint_data['training_data'],
                'processed_files': set(checkpoint_data['processed_files']),
                'all_files': checkpoint_data['all_files'],
                'metadata': metadata,
            }

        except Exception as e:
            logger.error("Error loading checkpoint: %s", e)
            return None

    def has_checkpoint(self, training_dir: str,
                       selected_tags: Dict[str, List[str]]) -> bool:
        """Check if a checkpoint exists for this training configuration."""
        session_id = self._get_session_id(training_dir, selected_tags)
        return self._get_checkpoint_path(session_id).exists()

    def get_checkpoint_info(self, training_dir: str,
                            selected_tags: Dict[str, List[str]]) -> Optional[Dict[str, Any]]:
        """
        Get checkpoint metadata without loading the full data.

        Useful for displaying resume information to the user.
        """
        session_id = self._get_session_id(training_dir, selected_tags)
        metadata_path = self._get_metadata_path(session_id)

        if not metadata_path.exists():
            return None

        try:
            with open(metadata_path, 'r') as f:
                return json.load(f)
        except Exception:
            return None

    def delete_checkpoint(self, training_dir: str,
                          selected_tags: Dict[str, List[str]]) -> bool:
        """
        Delete a checkpoint for a training configuration.

        Args:
            training_dir: The training directory path
            selected_tags: Dictionary of selected tags

        Returns:
            True if checkpoint was deleted, False if it didn't exist
        """
        session_id = self._get_session_id(training_dir, selected_tags)
        checkpoint_path = self._get_checkpoint_path(session_id)
        metadata_path = self._get_metadata_path(session_id)

        deleted = False
        if checkpoint_path.exists():
            checkpoint_path.unlink()
            deleted = True
        if metadata_path.exists():
            metadata_path.unlink()
            deleted = True

        return deleted

    def list_checkpoints(self) -> List[Dict[str, Any]]:
        """
        List all available checkpoints.

        Returns:
            List of checkpoint metadata dictionaries
        """
        checkpoints = []

        for meta_file in self.checkpoint_dir.glob("checkpoint_*.json"):
            try:
                with open(meta_file, 'r') as f:
                    metadata = json.load(f)
                    checkpoints.append(metadata)
            except Exception:
                continue

        # Sort by last updated (newest first)
        checkpoints.sort(key=lambda x: x.get('last_updated', ''), reverse=True)
        return checkpoints

    def cleanup_old_checkpoints(self, max_age_days: int = 7) -> int:
        """
        Remove checkpoints older than specified days.

        Args:
            max_age_days: Maximum age in days

        Returns:
            Number of checkpoints removed
        """
        from datetime import datetime, timedelta

        cutoff = datetime.now() - timedelta(days=max_age_days)
        removed = 0

        for meta_file in self.checkpoint_dir.glob("checkpoint_*.json"):
            try:
                with open(meta_file, 'r') as f:
                    metadata = json.load(f)

                last_updated = datetime.fromisoformat(metadata.get('last_updated', ''))
                if last_updated < cutoff:
                    session_id = metadata.get('session_id')
                    checkpoint_path = self._get_checkpoint_path(session_id)

                    if checkpoint_path.exists():
                        checkpoint_path.unlink()
                    meta_file.unlink()
                    removed += 1

            except Exception:
                continue

        return removed


def get_remaining_files(all_files: List[str], processed_files: set) -> List[str]:
    """
    Get list of files that still need to be processed.

    Args:
        all_files: Complete list of all files
        processed_files: Set of already processed file paths

    Returns:
        List of files not yet processed
    """
    return [f for f in all_files if f not in processed_files]


def estimate_time_remaining(processed: int, total: int, elapsed_seconds: float) -> Tuple[float, str]:
    """
    Estimate remaining time based on current progress.

    Args:
        processed: Number of files processed
        total: Total number of files
        elapsed_seconds: Time elapsed so far

    Returns:
        Tuple of (seconds_remaining, formatted_string)
    """
    if processed == 0:
        return 0.0, "calculating..."

    rate = processed / elapsed_seconds  # files per second
    remaining = total - processed
    seconds_remaining = remaining / rate if rate > 0 else 0

    # Format as HH:MM:SS
    hours = int(seconds_remaining // 3600)
    minutes = int((seconds_remaining % 3600) // 60)
    seconds = int(seconds_remaining % 60)

    if hours > 0:
        formatted = f"{hours}h {minutes}m {seconds}s"
    elif minutes > 0:
        formatted = f"{minutes}m {seconds}s"
    else:
        formatted = f"{seconds}s"

    return seconds_remaining, formatted
