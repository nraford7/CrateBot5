"""Lexicon module for mapping canonical tags to user-preferred vocabulary."""

import json
from pathlib import Path
from typing import Optional

from .paths import get_cratebot_dir

class Lexicon:
    """Maps canonical tags to user-preferred vocabulary.

    Allows users to customize tag vocabulary without retraining the model.
    For example, a user who prefers "Climax" over "Peak" can set that mapping.
    """

    DEFAULT_LEXICON = {
        "genre": {
            "id3_frame": "TCON",
            "mappings": {},
        },
        "timing": {
            "id3_frame": "TALB",
            "mappings": {},
        },
        "mood": {
            "id3_frame": "TIT1",
            "mappings": {},
        },
        "descriptive": {
            "id3_frame": "COMM",
            "mappings": {},
        },
    }

    def __init__(self, path: Optional[Path] = None):
        """Initialize lexicon from file path.

        Args:
            path: Path to lexicon JSON file. Defaults to ~/.cratebot/lexicon.json
        """
        if path is None:
            self.path = get_cratebot_dir() / "lexicon.json"
        else:
            self.path = Path(path)
        self._lexicon = self._load()

    def _load(self) -> dict:
        """Load lexicon from file, migrating old format if needed.

        Creates parent directories and default file if they don't exist.
        Automatically migrates old flat format to new nested format.

        Returns:
            The lexicon dictionary.
        """
        if self.path.exists():
            try:
                with open(self.path, 'r') as f:
                    loaded = json.load(f)
                # Detect and migrate old format
                loaded = self._migrate_if_needed(loaded)
                # Ensure all categories exist (merge with defaults)
                for category, defaults in self.DEFAULT_LEXICON.items():
                    if category not in loaded:
                        loaded[category] = dict(defaults)
                return loaded
            except (json.JSONDecodeError, IOError):
                return self._create_default()
        else:
            return self._create_default()

    def _migrate_if_needed(self, data: dict) -> dict:
        """Migrate old flat format to new nested format.

        Old format: {"timing": {"Peak": "Climax"}}
        New format: {"timing": {"id3_frame": "TALB", "mappings": {"Peak": "Climax"}}}

        Args:
            data: Loaded lexicon data (may be old or new format).

        Returns:
            Lexicon data in new format.
        """
        migrated = {}
        for category, value in data.items():
            if category in self.DEFAULT_LEXICON:
                if isinstance(value, dict) and "id3_frame" in value:
                    # Already new format
                    migrated[category] = value
                else:
                    # Old format - value is the mappings dict directly
                    migrated[category] = {
                        "id3_frame": self.DEFAULT_LEXICON[category]["id3_frame"],
                        "mappings": value if isinstance(value, dict) else {},
                    }
            else:
                # Unknown category, preserve as-is
                migrated[category] = value
        return migrated

    def _create_default(self) -> dict:
        """Create default lexicon file and return default dict."""
        # Create parent directories if needed
        self.path.parent.mkdir(parents=True, exist_ok=True)
        # Create default file
        default = {k: dict(v) for k, v in self.DEFAULT_LEXICON.items()}
        with open(self.path, 'w') as f:
            json.dump(default, f, indent=2)
        return default

    def get_id3_frame(self, category: str) -> Optional[str]:
        """Get the ID3 frame for a category.

        Args:
            category: The tag category (timing, mood, genre, descriptive).

        Returns:
            The ID3 frame name (e.g., 'TCON', 'TALB', 'TXXX:CUSTOM'), or None if unknown.
        """
        if category not in self._lexicon:
            return None
        return self._lexicon[category].get("id3_frame")

    def set_id3_frame(self, category: str, frame: str) -> None:
        """Set the ID3 frame for a category.

        Args:
            category: The tag category (timing, mood, genre, descriptive).
            frame: The ID3 frame name (e.g., 'TCON', 'TXXX:CRATEBOT_TIMING').
        """
        if category not in self._lexicon:
            self._lexicon[category] = {"id3_frame": frame, "mappings": {}}
        else:
            self._lexicon[category]["id3_frame"] = frame

    def get_mapping(self, category: str, canonical_tag: str) -> str:
        """Get user vocabulary for a canonical tag.

        Args:
            category: The tag category (timing, mood, genre, descriptive).
            canonical_tag: The canonical tag name.

        Returns:
            The user's preferred name, or the original if unmapped.
        """
        if category not in self._lexicon:
            return canonical_tag
        mappings = self._lexicon[category].get("mappings", {})
        return mappings.get(canonical_tag, canonical_tag)

    def set_mapping(self, category: str, canonical_tag: str, user_tag: str) -> None:
        """Set a mapping from canonical to user vocabulary.

        Args:
            category: The tag category (timing, mood, genre, descriptive).
            canonical_tag: The canonical tag name.
            user_tag: The user's preferred name.
        """
        if category not in self._lexicon:
            self._lexicon[category] = {
                "id3_frame": self.DEFAULT_LEXICON.get(category, {}).get("id3_frame", "TXXX"),
                "mappings": {},
            }
        self._lexicon[category]["mappings"][canonical_tag] = user_tag

    def remove_mapping(self, category: str, canonical_tag: str) -> None:
        """Remove a mapping, reverting to canonical.

        Args:
            category: The tag category (timing, mood, genre, descriptive).
            canonical_tag: The canonical tag name to unmap.
        """
        if category in self._lexicon:
            mappings = self._lexicon[category].get("mappings", {})
            if canonical_tag in mappings:
                del mappings[canonical_tag]

    def save(self) -> None:
        """Save lexicon to file."""
        self.path.parent.mkdir(parents=True, exist_ok=True)
        with open(self.path, 'w') as f:
            json.dump(self._lexicon, f, indent=2)

    def apply_to_tags(self, tags: dict) -> dict:
        """Apply lexicon mappings to a tags dict.

        Args:
            tags: Dictionary with keys like 'genre', 'timing', 'mood', 'descriptive'.
                  The 'descriptive' value should be a list of tags.

        Returns:
            New dict with mapped values. Original dict is not modified.
        """
        result = {}
        for category, value in tags.items():
            if category == "descriptive":
                # Descriptive is a list of tags
                if isinstance(value, list):
                    result[category] = [
                        self.get_mapping(category, tag) for tag in value
                    ]
                else:
                    # Handle case where descriptive might be a single string
                    result[category] = self.get_mapping(category, value)
            else:
                # Single value categories (genre, timing, mood)
                result[category] = self.get_mapping(category, value)
        return result
