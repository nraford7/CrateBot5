"""Tests for training tag matching logic."""
import pytest
import sys
from pathlib import Path

# Add paths for imports
project_root = Path(__file__).parent.parent.parent
sys.path.insert(0, str(project_root))
sys.path.insert(0, str(project_root / "python" / "src"))


class TestTrainingTagMatching:
    """Test that training correctly matches tags with case insensitivity."""

    def test_matches_selected_tag_case_insensitive(self):
        """Verify matches_selected_tag handles case differences."""
        from core.utils import matches_selected_tag

        # Scanner normalizes to title case, files may have different cases
        selected = {"Peak", "House", "Dark"}

        # Should match regardless of case
        assert matches_selected_tag("PEAK", selected) == True
        assert matches_selected_tag("peak", selected) == True
        assert matches_selected_tag("Peak", selected) == True
        assert matches_selected_tag("house", selected) == True
        assert matches_selected_tag("HOUSE", selected) == True

        # Should not match unrelated
        assert matches_selected_tag("Techno", selected) == False
        assert matches_selected_tag("", selected) == False

    def test_matches_selected_tag_fuzzy(self):
        """Verify fuzzy matching for similar tags."""
        from core.utils import matches_selected_tag

        selected = {"Hi Hats", "Head Knodding"}

        # Fuzzy matches
        assert matches_selected_tag("Hi-Hats", selected) == True
        assert matches_selected_tag("hi hats", selected) == True

    def test_training_finds_samples_with_mixed_case_tags(self):
        """Integration test: training should find samples even with case mismatches."""
        from core.utils import matches_selected_tag

        # Simulate what happens during training
        # Scanner returns title-cased tags
        selected_tags = {
            'genre': ['House', 'Techno'],
            'timing': ['Peak', 'Build'],
            'mood': ['Dark', 'Uplifting'],
            'descriptive': ['Funky', 'Driving'],
        }

        # Simulated file tags with various cases (as read from actual files)
        test_files = [
            {'genre': 'HOUSE', 'timing': 'PEAK', 'mood': 'DARK', 'descriptive': ['FUNKY']},
            {'genre': 'house', 'timing': 'build', 'mood': 'uplifting', 'descriptive': ['driving']},
            {'genre': 'House', 'timing': 'Peak', 'mood': 'Dark', 'descriptive': ['Funky']},
            {'genre': 'Techno', 'timing': '', 'mood': '', 'descriptive': []},  # Only genre
            {'genre': '', 'timing': 'Build', 'mood': '', 'descriptive': []},   # Only timing
            {'genre': '', 'timing': '', 'mood': 'Uplifting', 'descriptive': []},  # Only mood
            {'genre': '', 'timing': '', 'mood': '', 'descriptive': ['Driving']},  # Only descriptive
        ]

        # All should match with case-insensitive logic
        for tags in test_files:
            has_valid_tag = False

            genre = tags.get('genre', '').strip()
            if matches_selected_tag(genre, set(selected_tags['genre'])):
                has_valid_tag = True

            timing = tags.get('timing', '').strip()
            if matches_selected_tag(timing, set(selected_tags['timing'])):
                has_valid_tag = True

            mood = tags.get('mood', '').strip()
            if matches_selected_tag(mood, set(selected_tags['mood'])):
                has_valid_tag = True

            descriptive = tags.get('descriptive', [])
            if isinstance(descriptive, list):
                descriptive = ', '.join(descriptive)
            descriptive_tags = [c.strip() for c in descriptive.split(',') if c.strip()]
            if any(matches_selected_tag(t, set(selected_tags['descriptive'])) for t in descriptive_tags):
                has_valid_tag = True

            assert has_valid_tag, f"Should match: {tags}"

    def test_empty_selected_tags_never_match(self):
        """Verify empty selection sets don't match anything."""
        from core.utils import matches_selected_tag

        assert matches_selected_tag("House", set()) == False
        assert matches_selected_tag("", set()) == False
