"""
Tests for overrides.py - SQLite override storage.
"""

import pytest
import os
from pathlib import Path


@pytest.fixture
def temp_db_path(temp_dir):
    """Create a temporary database path for override tests."""
    return Path(temp_dir) / "test_overrides.db"


class TestOverrideStore:
    """Tests for OverrideStore class."""

    def test_override_store_set_and_get(self, temp_db_path):
        """Store and retrieve overrides by audio hash."""
        from core.overrides import OverrideStore

        store = OverrideStore(path=temp_db_path)

        audio_hash = "abc123def456"
        tags = {"genre": "Techno", "mood": "Dark", "energy": 0.8}

        store.set_override(audio_hash, tags)
        result = store.get_override(audio_hash)

        assert result is not None
        assert result == tags
        assert result["genre"] == "Techno"
        assert result["mood"] == "Dark"
        assert result["energy"] == 0.8

    def test_override_store_returns_none_if_missing(self, temp_db_path):
        """Returns None for unknown hashes."""
        from core.overrides import OverrideStore

        store = OverrideStore(path=temp_db_path)

        result = store.get_override("nonexistent_hash")

        assert result is None

    def test_override_store_update_existing(self, temp_db_path):
        """Updates overwrite existing overrides."""
        from core.overrides import OverrideStore

        store = OverrideStore(path=temp_db_path)

        audio_hash = "update_test_hash"
        original_tags = {"genre": "House", "mood": "Happy"}
        updated_tags = {"genre": "Techno", "mood": "Dark", "energy": 0.9}

        # Set original
        store.set_override(audio_hash, original_tags)
        assert store.get_override(audio_hash) == original_tags

        # Update with new tags
        store.set_override(audio_hash, updated_tags)
        result = store.get_override(audio_hash)

        assert result == updated_tags
        assert result["genre"] == "Techno"
        assert result["energy"] == 0.9

    def test_override_store_delete(self, temp_db_path):
        """Delete removes override."""
        from core.overrides import OverrideStore

        store = OverrideStore(path=temp_db_path)

        audio_hash = "delete_test_hash"
        tags = {"genre": "Minimal", "mood": "Hypnotic"}

        # Set and verify
        store.set_override(audio_hash, tags)
        assert store.get_override(audio_hash) is not None

        # Delete and verify gone
        store.delete_override(audio_hash)
        result = store.get_override(audio_hash)

        assert result is None

    def test_override_store_persists(self, temp_db_path):
        """Overrides persist across instances."""
        from core.overrides import OverrideStore

        audio_hash = "persist_test_hash"
        tags = {"genre": "Deep House", "mood": "Groovy", "timing": "Peak"}

        # Create first instance and store data
        store1 = OverrideStore(path=temp_db_path)
        store1.set_override(audio_hash, tags)

        # Create new instance with same path
        store2 = OverrideStore(path=temp_db_path)
        result = store2.get_override(audio_hash)

        assert result is not None
        assert result == tags

    def test_override_store_list_overrides(self, temp_db_path):
        """List all overrides returns all stored entries."""
        from core.overrides import OverrideStore

        store = OverrideStore(path=temp_db_path)

        # Store multiple overrides
        overrides_data = [
            ("hash1", {"genre": "House"}),
            ("hash2", {"genre": "Techno", "mood": "Dark"}),
            ("hash3", {"genre": "Minimal", "energy": 0.5}),
        ]

        for audio_hash, tags in overrides_data:
            store.set_override(audio_hash, tags)

        # List all
        result = store.list_overrides()

        assert len(result) == 3
        result_dict = {h: t for h, t in result}
        assert result_dict["hash1"] == {"genre": "House"}
        assert result_dict["hash2"] == {"genre": "Techno", "mood": "Dark"}
        assert result_dict["hash3"] == {"genre": "Minimal", "energy": 0.5}

    def test_override_store_default_path(self, temp_dir, monkeypatch):
        """Default path is ~/.cratebot/overrides.db."""
        from core.overrides import OverrideStore

        # Monkeypatch home directory to temp_dir for isolation
        fake_home = Path(temp_dir) / "fake_home"
        fake_home.mkdir()
        monkeypatch.setattr(Path, "home", lambda: fake_home)

        store = OverrideStore()

        expected_path = fake_home / ".cratebot" / "overrides.db"
        assert store.path == expected_path
        assert store.path.parent.exists()

    def test_override_store_creates_parent_directories(self, temp_dir):
        """Parent directories are created if they don't exist."""
        from core.overrides import OverrideStore

        nested_path = Path(temp_dir) / "nested" / "dirs" / "overrides.db"

        store = OverrideStore(path=nested_path)

        assert nested_path.parent.exists()
        assert store.path == nested_path

    def test_override_store_handles_complex_tags(self, temp_db_path):
        """Handles complex tag structures with nested data."""
        from core.overrides import OverrideStore

        store = OverrideStore(path=temp_db_path)

        audio_hash = "complex_tags_hash"
        complex_tags = {
            "genre": "Techno",
            "sub_genres": ["Minimal", "Dub"],
            "moods": {"primary": "Dark", "secondary": "Hypnotic"},
            "energy": 0.75,
            "bpm": 128,
            "tags_list": ["Driving", "Rolling", "Deep"],
        }

        store.set_override(audio_hash, complex_tags)
        result = store.get_override(audio_hash)

        assert result == complex_tags
        assert result["sub_genres"] == ["Minimal", "Dub"]
        assert result["moods"]["primary"] == "Dark"
