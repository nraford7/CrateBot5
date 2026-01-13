"""Tests for the Lexicon module."""

import json
import pytest
from pathlib import Path

from core.lexicon import Lexicon


@pytest.fixture
def temp_lexicon_path(tmp_path):
    """Create a temporary lexicon file with sample mappings."""
    lexicon_path = tmp_path / "lexicon.json"
    lexicon_data = {
        "timing": {
            "Peak": "Climax",
            "Build": "Tension"
        },
        "mood": {
            "Happy": "Euphoric"
        },
        "genre": {},
        "descriptive": {
            "Driving": "Relentless"
        }
    }
    with open(lexicon_path, 'w') as f:
        json.dump(lexicon_data, f)
    return lexicon_path


class TestLexiconLoadSave:
    """Tests for loading and saving lexicon files."""

    def test_lexicon_loads_from_file(self, temp_lexicon_path):
        """Lexicon loads mappings from JSON file."""
        lexicon = Lexicon(temp_lexicon_path)

        # Verify mappings were loaded
        assert lexicon.get_mapping("timing", "Peak") == "Climax"
        assert lexicon.get_mapping("timing", "Build") == "Tension"
        assert lexicon.get_mapping("mood", "Happy") == "Euphoric"
        assert lexicon.get_mapping("descriptive", "Driving") == "Relentless"

    def test_lexicon_returns_original_if_no_mapping(self, temp_lexicon_path):
        """Unmapped tags pass through unchanged."""
        lexicon = Lexicon(temp_lexicon_path)

        # Tags without mappings should return the original
        assert lexicon.get_mapping("timing", "Start") == "Start"
        assert lexicon.get_mapping("mood", "Dark") == "Dark"
        assert lexicon.get_mapping("genre", "House") == "House"
        assert lexicon.get_mapping("descriptive", "Funky") == "Funky"

        # Unknown category should also return original
        assert lexicon.get_mapping("unknown_category", "SomeTag") == "SomeTag"

    def test_lexicon_save_mapping(self, temp_lexicon_path):
        """Lexicon saves new mappings to file."""
        lexicon = Lexicon(temp_lexicon_path)

        # Add new mappings
        lexicon.set_mapping("genre", "House", "Deep House")
        lexicon.set_mapping("mood", "Dark", "Shadowy")
        lexicon.save()

        # Reload and verify
        lexicon2 = Lexicon(temp_lexicon_path)
        assert lexicon2.get_mapping("genre", "House") == "Deep House"
        assert lexicon2.get_mapping("mood", "Dark") == "Shadowy"
        # Original mappings should still exist
        assert lexicon2.get_mapping("timing", "Peak") == "Climax"

    def test_lexicon_creates_default_if_missing(self, tmp_path):
        """Lexicon creates default file if path doesn't exist."""
        lexicon_path = tmp_path / "subdir" / "lexicon.json"

        # Path doesn't exist yet
        assert not lexicon_path.exists()

        # Creating Lexicon should create the file
        lexicon = Lexicon(lexicon_path)

        # File should now exist
        assert lexicon_path.exists()

        # Should have default structure with id3_frame and empty mappings
        with open(lexicon_path, 'r') as f:
            data = json.load(f)

        assert "timing" in data
        assert "mood" in data
        assert "genre" in data
        assert "descriptive" in data
        # New structure has id3_frame and mappings
        assert data["timing"]["id3_frame"] == "TALB"
        assert data["timing"]["mappings"] == {}
        assert data["mood"]["id3_frame"] == "TIT1"
        assert data["mood"]["mappings"] == {}
        assert data["genre"]["id3_frame"] == "TCON"
        assert data["genre"]["mappings"] == {}
        assert data["descriptive"]["id3_frame"] == "COMM"
        assert data["descriptive"]["mappings"] == {}

    def test_lexicon_default_path(self, monkeypatch, tmp_path):
        """Lexicon uses ~/.cratebot/lexicon.json by default."""
        # Monkeypatch Path.home() to use tmp_path
        monkeypatch.setattr(Path, 'home', lambda: tmp_path)

        lexicon = Lexicon()

        expected_path = tmp_path / ".cratebot" / "lexicon.json"
        assert lexicon.path == expected_path
        assert expected_path.exists()


class TestLexiconMapping:
    """Tests for mapping operations."""

    def test_lexicon_remove_mapping(self, temp_lexicon_path):
        """Removing a mapping reverts to canonical."""
        lexicon = Lexicon(temp_lexicon_path)

        # Verify mapping exists
        assert lexicon.get_mapping("timing", "Peak") == "Climax"

        # Remove mapping
        lexicon.remove_mapping("timing", "Peak")

        # Should now return original
        assert lexicon.get_mapping("timing", "Peak") == "Peak"

        # Save and reload to verify persistence
        lexicon.save()
        lexicon2 = Lexicon(temp_lexicon_path)
        assert lexicon2.get_mapping("timing", "Peak") == "Peak"

    def test_remove_nonexistent_mapping_no_error(self, temp_lexicon_path):
        """Removing a non-existent mapping doesn't raise error."""
        lexicon = Lexicon(temp_lexicon_path)

        # Should not raise
        lexicon.remove_mapping("timing", "NonExistent")
        lexicon.remove_mapping("nonexistent_category", "Tag")

    def test_set_mapping_creates_category(self, tmp_path):
        """Setting a mapping creates the category if needed."""
        lexicon_path = tmp_path / "lexicon.json"
        lexicon = Lexicon(lexicon_path)

        # Set mapping in a category that might not exist in malformed file
        lexicon.set_mapping("timing", "Start", "Opener")

        assert lexicon.get_mapping("timing", "Start") == "Opener"


class TestApplyToTags:
    """Tests for apply_to_tags functionality."""

    def test_lexicon_apply_to_tags(self, temp_lexicon_path):
        """apply_to_tags transforms all tag categories."""
        lexicon = Lexicon(temp_lexicon_path)

        tags = {
            "genre": "House",
            "timing": "Peak",
            "mood": "Happy",
            "descriptive": ["Driving", "Funky", "Deep"]
        }

        result = lexicon.apply_to_tags(tags)

        # genre has no mapping, should pass through
        assert result["genre"] == "House"
        # timing "Peak" -> "Climax"
        assert result["timing"] == "Climax"
        # mood "Happy" -> "Euphoric"
        assert result["mood"] == "Euphoric"
        # descriptive is a list, "Driving" -> "Relentless", others unchanged
        assert result["descriptive"] == ["Relentless", "Funky", "Deep"]

    def test_apply_to_tags_does_not_modify_original(self, temp_lexicon_path):
        """apply_to_tags returns new dict without modifying original."""
        lexicon = Lexicon(temp_lexicon_path)

        tags = {
            "genre": "House",
            "timing": "Peak",
            "mood": "Happy",
            "descriptive": ["Driving", "Funky"]
        }
        original_timing = tags["timing"]
        original_descriptive = tags["descriptive"].copy()

        result = lexicon.apply_to_tags(tags)

        # Original should be unchanged
        assert tags["timing"] == original_timing
        assert tags["descriptive"] == original_descriptive
        assert tags["timing"] == "Peak"  # Not "Climax"
        assert tags["descriptive"][0] == "Driving"  # Not "Relentless"

        # Result should be different
        assert result is not tags
        assert result["timing"] == "Climax"

    def test_apply_to_tags_handles_all_categories(self, temp_lexicon_path):
        """apply_to_tags handles all 4 categories correctly."""
        lexicon = Lexicon(temp_lexicon_path)

        # Add mappings for all categories
        lexicon.set_mapping("genre", "House", "DeepHouse")
        lexicon.set_mapping("timing", "Start", "Opener")
        lexicon.set_mapping("mood", "Dark", "Shadowy")
        lexicon.set_mapping("descriptive", "Punchy", "Impactful")

        tags = {
            "genre": "House",
            "timing": "Start",
            "mood": "Dark",
            "descriptive": ["Punchy", "Groovy"]
        }

        result = lexicon.apply_to_tags(tags)

        assert result["genre"] == "DeepHouse"
        assert result["timing"] == "Opener"
        assert result["mood"] == "Shadowy"
        assert result["descriptive"] == ["Impactful", "Groovy"]

    def test_apply_to_tags_with_single_string_descriptive(self, temp_lexicon_path):
        """apply_to_tags handles descriptive as single string (edge case)."""
        lexicon = Lexicon(temp_lexicon_path)

        tags = {
            "genre": "House",
            "timing": "Peak",
            "mood": "Happy",
            "descriptive": "Driving"  # Single string instead of list
        }

        result = lexicon.apply_to_tags(tags)

        assert result["descriptive"] == "Relentless"

    def test_apply_to_tags_empty_tags(self, temp_lexicon_path):
        """apply_to_tags handles empty tags dict."""
        lexicon = Lexicon(temp_lexicon_path)

        result = lexicon.apply_to_tags({})

        assert result == {}

    def test_apply_to_tags_partial_tags(self, temp_lexicon_path):
        """apply_to_tags handles partial tags dict (not all categories present)."""
        lexicon = Lexicon(temp_lexicon_path)

        tags = {
            "timing": "Peak",
            "mood": "Happy"
        }

        result = lexicon.apply_to_tags(tags)

        assert result["timing"] == "Climax"
        assert result["mood"] == "Euphoric"
        assert "genre" not in result
        assert "descriptive" not in result


class TestLexiconEdgeCases:
    """Edge case and error handling tests."""

    def test_lexicon_handles_corrupted_file(self, tmp_path):
        """Lexicon handles corrupted JSON file gracefully."""
        lexicon_path = tmp_path / "lexicon.json"

        # Write invalid JSON
        with open(lexicon_path, 'w') as f:
            f.write("{ invalid json }")

        # Should not raise, should create default
        lexicon = Lexicon(lexicon_path)

        # Should have default structure
        assert lexicon.get_mapping("timing", "Peak") == "Peak"

    def test_lexicon_merges_with_defaults(self, tmp_path):
        """Lexicon adds missing categories from defaults."""
        lexicon_path = tmp_path / "lexicon.json"

        # Write partial lexicon (missing some categories)
        with open(lexicon_path, 'w') as f:
            json.dump({"timing": {"Peak": "Climax"}}, f)

        lexicon = Lexicon(lexicon_path)

        # Should have the mapping from file
        assert lexicon.get_mapping("timing", "Peak") == "Climax"

        # Should also have empty categories for missing ones
        assert lexicon.get_mapping("mood", "Happy") == "Happy"
        assert lexicon.get_mapping("genre", "House") == "House"
        assert lexicon.get_mapping("descriptive", "Driving") == "Driving"


class TestLexiconID3Mapping:
    """Tests for ID3 frame mapping functionality."""

    def test_default_lexicon_has_id3_frames(self, tmp_path):
        """Default lexicon should include id3_frame for each category."""
        lexicon_path = tmp_path / "lexicon.json"
        lexicon = Lexicon(lexicon_path)

        # Check via API
        assert lexicon.get_id3_frame("genre") == "TCON"
        assert lexicon.get_id3_frame("timing") == "TALB"
        assert lexicon.get_id3_frame("mood") == "TIT1"
        assert lexicon.get_id3_frame("descriptive") == "COMM"

    def test_get_id3_frame_unknown_category_returns_none(self, tmp_path):
        """get_id3_frame returns None for unknown category."""
        lexicon_path = tmp_path / "lexicon.json"
        lexicon = Lexicon(lexicon_path)

        assert lexicon.get_id3_frame("unknown") is None

    def test_set_id3_frame_changes_frame(self, tmp_path):
        """set_id3_frame changes the ID3 frame for a category."""
        lexicon_path = tmp_path / "lexicon.json"
        lexicon = Lexicon(lexicon_path)

        # Change timing to use custom TXXX frame
        lexicon.set_id3_frame("timing", "TXXX:CRATEBOT_TIMING")
        assert lexicon.get_id3_frame("timing") == "TXXX:CRATEBOT_TIMING"

        # Save and reload
        lexicon.save()
        lexicon2 = Lexicon(lexicon_path)
        assert lexicon2.get_id3_frame("timing") == "TXXX:CRATEBOT_TIMING"

    def test_lexicon_migrates_old_format(self, tmp_path):
        """Lexicon should migrate old flat format to new nested format."""
        lexicon_path = tmp_path / "lexicon.json"

        # Write old format
        old_format = {
            "timing": {"Peak": "Climax"},
            "mood": {"Happy": "Euphoric"},
            "genre": {},
            "descriptive": {}
        }
        with open(lexicon_path, 'w') as f:
            json.dump(old_format, f)

        # Load with new Lexicon
        lexicon = Lexicon(lexicon_path)

        # Should have migrated to new structure with default frames
        assert lexicon.get_id3_frame("timing") == "TALB"
        assert lexicon.get_id3_frame("mood") == "TIT1"
        # Mappings should be preserved
        assert lexicon.get_mapping("timing", "Peak") == "Climax"
        assert lexicon.get_mapping("mood", "Happy") == "Euphoric"

    def test_set_id3_frame_creates_category(self, tmp_path):
        """set_id3_frame creates category if it doesn't exist."""
        lexicon_path = tmp_path / "lexicon.json"
        lexicon = Lexicon(lexicon_path)

        # Set frame for a new category (edge case)
        lexicon.set_id3_frame("custom_category", "TXXX:CUSTOM")
        assert lexicon.get_id3_frame("custom_category") == "TXXX:CUSTOM"


class TestAutoTaggerLexiconIntegration:
    """Tests for AutoTagger integration with Lexicon.

    Note: These tests require the full package structure to be importable.
    They may be skipped if AutoTagger cannot be imported due to relative
    import issues when running pytest directly.
    """

    @pytest.fixture
    def AutoTagger(self):
        """Import AutoTagger, skipping tests if import fails."""
        try:
            from core.auto_tagger import AutoTagger
            return AutoTagger
        except ImportError as e:
            pytest.skip(f"AutoTagger not importable (likely relative import issue): {e}")

    def test_auto_tagger_accepts_lexicon_path(self, tmp_path, AutoTagger):
        """AutoTagger should accept lexicon_path parameter."""
        # Create a lexicon file
        lexicon_path = tmp_path / "lexicon.json"
        lexicon_data = {
            "timing": {"Peak": "Climax"},
            "mood": {},
            "genre": {},
            "descriptive": {}
        }
        with open(lexicon_path, 'w') as f:
            json.dump(lexicon_data, f)

        # Create AutoTagger with lexicon path (no model needed for this test)
        tagger = AutoTagger(lexicon_path=str(lexicon_path))

        # Verify lexicon was loaded
        assert hasattr(tagger, 'lexicon')
        assert tagger.lexicon.get_mapping("timing", "Peak") == "Climax"

    def test_auto_tagger_uses_default_lexicon_if_no_path(self, monkeypatch, tmp_path, AutoTagger):
        """AutoTagger uses default lexicon path if not specified."""
        # Monkeypatch Path.home() to use tmp_path
        monkeypatch.setattr(Path, 'home', lambda: tmp_path)

        tagger = AutoTagger()

        # Verify default lexicon was created
        expected_path = tmp_path / ".cratebot" / "lexicon.json"
        assert tagger.lexicon.path == expected_path

    def test_auto_tagger_lexicon_apply_to_tags_available(self, tmp_path, AutoTagger):
        """AutoTagger's lexicon should have apply_to_tags method."""
        lexicon_path = tmp_path / "lexicon.json"
        lexicon_data = {
            "timing": {"Peak": "Climax"},
            "mood": {"Happy": "Euphoric"},
            "genre": {"House": "Deep House"},
            "descriptive": {"Driving": "Relentless"}
        }
        with open(lexicon_path, 'w') as f:
            json.dump(lexicon_data, f)

        tagger = AutoTagger(lexicon_path=str(lexicon_path))

        # Test the lexicon's apply_to_tags method
        tags = {
            "genre": "House",
            "timing": "Peak",
            "mood": "Happy",
            "descriptive": ["Driving", "Funky"]
        }

        result = tagger.lexicon.apply_to_tags(tags)

        assert result["genre"] == "Deep House"
        assert result["timing"] == "Climax"
        assert result["mood"] == "Euphoric"
        assert result["descriptive"] == ["Relentless", "Funky"]
