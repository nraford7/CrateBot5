"""
Tests for tag_manager.py - ID3 tag reading and writing.
"""

import pytest
import shutil
from pathlib import Path


class TestTagManager:
    """Tests for TagManager class."""

    def test_read_tags_from_file(self, test_audio_path):
        """Should read tags from an MP3 file."""
        from core.tag_manager import TagManager

        manager = TagManager()
        tags = manager.read_tags(str(test_audio_path))

        assert isinstance(tags, dict)

    def test_read_tags_file_not_found(self):
        """Should raise FileNotFoundError for non-existent file."""
        from core.tag_manager import TagManager

        manager = TagManager()

        with pytest.raises(FileNotFoundError):
            manager.read_tags("/nonexistent/path/audio.mp3")

    def test_write_and_read_genre(self, test_audio_path, temp_dir):
        """Genre written should be readable."""
        from core.tag_manager import TagManager

        # Copy test file to temp dir
        test_file = Path(temp_dir) / "test.mp3"
        shutil.copy(test_audio_path, test_file)

        manager = TagManager()

        # Write genre
        manager.write_tags(str(test_file), {'genre': 'Tech House'}, overwrite=True)

        # Read back
        tags = manager.read_tags(str(test_file))

        assert tags.get('genre') == 'Tech House'

    def test_write_and_read_album(self, test_audio_path, temp_dir):
        """Album written should be readable."""
        from core.tag_manager import TagManager

        test_file = Path(temp_dir) / "test.mp3"
        shutil.copy(test_audio_path, test_file)

        manager = TagManager()

        manager.write_tags(str(test_file), {'album': 'Peak Energy'}, overwrite=True)

        tags = manager.read_tags(str(test_file))

        assert tags.get('album') == 'Peak Energy'

    def test_write_and_read_comments(self, test_audio_path, temp_dir):
        """Comments written should be readable."""
        from core.tag_manager import TagManager

        test_file = Path(temp_dir) / "test.mp3"
        shutil.copy(test_audio_path, test_file)

        manager = TagManager()

        manager.write_tags(str(test_file), {'comments': 'Driving, Hypnotic, Minimal'}, overwrite=True)

        tags = manager.read_tags(str(test_file))

        assert 'comments' in tags
        # Comments may be returned as list
        if isinstance(tags['comments'], list):
            assert 'Driving, Hypnotic, Minimal' in tags['comments']
        else:
            assert tags['comments'] == 'Driving, Hypnotic, Minimal'

    def test_write_multiple_tags(self, test_audio_path, temp_dir):
        """Multiple tags written should all be readable."""
        from core.tag_manager import TagManager

        test_file = Path(temp_dir) / "test.mp3"
        shutil.copy(test_audio_path, test_file)

        manager = TagManager()

        tags_to_write = {
            'genre': 'Deep House',
            'album': 'Build',
            'comments': 'Melodic, Groovy'
        }
        manager.write_tags(str(test_file), tags_to_write, overwrite=True)

        tags = manager.read_tags(str(test_file))

        assert tags.get('genre') == 'Deep House'
        assert tags.get('album') == 'Build'

    def test_overwrite_false_preserves_existing(self, test_audio_path, temp_dir):
        """With overwrite=False, existing tags should be preserved."""
        from core.tag_manager import TagManager

        test_file = Path(temp_dir) / "test.mp3"
        shutil.copy(test_audio_path, test_file)

        manager = TagManager()

        # First write
        manager.write_tags(str(test_file), {'genre': 'House'}, overwrite=True)

        # Second write without overwrite
        manager.write_tags(str(test_file), {'album': 'Peak'}, overwrite=False)

        tags = manager.read_tags(str(test_file))

        # Both should exist
        assert tags.get('genre') == 'House'
        assert tags.get('album') == 'Peak'

    def test_write_composer_vibe(self, test_audio_path, temp_dir):
        """Composer (vibe) tag should be writable and readable."""
        from core.tag_manager import TagManager

        test_file = Path(temp_dir) / "test.mp3"
        shutil.copy(test_audio_path, test_file)

        manager = TagManager()

        manager.write_tags(str(test_file), {'composer': 'DOPE GRINDY TECH BUILDER'}, overwrite=True)

        tags = manager.read_tags(str(test_file))

        assert tags.get('composer') == 'DOPE GRINDY TECH BUILDER'

    def test_write_likeness_scores(self, test_audio_path, temp_dir):
        """Likeness scores should be writable and readable."""
        from core.tag_manager import TagManager

        test_file = Path(temp_dir) / "test.mp3"
        shutil.copy(test_audio_path, test_file)

        manager = TagManager()

        manager.write_likeness_scores(
            str(test_file),
            comment_likeness=0.75,
            overall_likeness=0.82
        )

        scores = manager.read_likeness_scores(str(test_file))

        assert scores['comment'] == pytest.approx(0.75, abs=0.01)
        assert scores['overall'] == pytest.approx(0.82, abs=0.01)


class TestTagCleanup:
    """Tests for tag cleanup functionality."""

    def test_cleanup_preserves_multi_word_tags(self):
        """Multi-word tags like 'Head Knodding' should be preserved."""
        from core.tag_manager import TagManager

        manager = TagManager()

        result = manager.cleanup_comment_tags("Head Knodding, Funky, Hi Hats")

        assert "Head Knodding" in result
        assert "Hi Hats" in result

    def test_cleanup_removes_duplicates(self):
        """Duplicate tags should be removed."""
        from core.tag_manager import TagManager

        manager = TagManager()

        result = manager.cleanup_comment_tags("Funky, FUNKY, funky")

        # Should have only one "Funky" (case-insensitive dedup)
        assert result.lower().count('funky') == 1


class TestNewTaxonomyFields:
    """Tests for new taxonomy field mapping (timing, mood, descriptive)."""

    def test_write_new_taxonomy_fields(self, test_audio_path, temp_dir):
        """Write genre/timing/mood/descriptive to correct ID3 fields."""
        from core.tag_manager import TagManager
        from mutagen.mp3 import MP3
        import shutil
        from pathlib import Path

        test_file = Path(temp_dir) / "test.mp3"
        shutil.copy(test_audio_path, test_file)

        manager = TagManager()
        tags = {
            "genre": "House",
            "timing": "Peak",
            "mood": "Happy",
            "descriptive": ["Driving", "Melodic", "Punchy"],
        }

        manager.write_tags(str(test_file), tags)

        # Verify with raw Mutagen read
        audio = MP3(str(test_file))
        assert str(audio.tags.get("TCON")) == "House"  # Genre
        assert str(audio.tags.get("TALB")) == "Peak"   # Timing
        assert str(audio.tags.get("TIT1")) == "Happy"  # Mood
        # Descriptive in COMM - check it contains the tags
        for frame in audio.tags.getall('COMM'):
            if "Driving" in str(frame):
                break
        else:
            assert False, "Descriptive tags not found in COMM"

    def test_write_timing_to_talb(self, test_audio_path, temp_dir):
        """Timing should be written to TALB (Album) field."""
        from core.tag_manager import TagManager
        from mutagen.mp3 import MP3
        import shutil
        from pathlib import Path

        test_file = Path(temp_dir) / "test.mp3"
        shutil.copy(test_audio_path, test_file)

        manager = TagManager()
        manager.write_tags(str(test_file), {"timing": "Build"})

        audio = MP3(str(test_file))
        assert str(audio.tags.get("TALB")) == "Build"

    def test_write_mood_to_tit1(self, test_audio_path, temp_dir):
        """Mood should be written to TIT1 (Content Group) field."""
        from core.tag_manager import TagManager
        from mutagen.mp3 import MP3
        import shutil
        from pathlib import Path

        test_file = Path(temp_dir) / "test.mp3"
        shutil.copy(test_audio_path, test_file)

        manager = TagManager()
        manager.write_tags(str(test_file), {"mood": "Dreamy"})

        audio = MP3(str(test_file))
        assert str(audio.tags.get("TIT1")) == "Dreamy"

    def test_write_descriptive_list_to_comm(self, test_audio_path, temp_dir):
        """Descriptive list should be written to COMM field."""
        from core.tag_manager import TagManager
        from mutagen.mp3 import MP3
        import shutil
        from pathlib import Path

        test_file = Path(temp_dir) / "test.mp3"
        shutil.copy(test_audio_path, test_file)

        manager = TagManager()
        manager.write_tags(str(test_file), {"descriptive": ["Funky", "Groovy", "Bouncy"]})

        audio = MP3(str(test_file))
        # Check COMM frames contain the descriptive tags
        comm_found = False
        for frame in audio.tags.getall('COMM'):
            if "Funky" in str(frame) and "Groovy" in str(frame) and "Bouncy" in str(frame):
                comm_found = True
                break
        assert comm_found, "Descriptive tags not found in COMM"

    def test_write_descriptive_string_to_comm(self, test_audio_path, temp_dir):
        """Descriptive string should be written to COMM field."""
        from core.tag_manager import TagManager
        from mutagen.mp3 import MP3
        import shutil
        from pathlib import Path

        test_file = Path(temp_dir) / "test.mp3"
        shutil.copy(test_audio_path, test_file)

        manager = TagManager()
        manager.write_tags(str(test_file), {"descriptive": "Driving, Hypnotic"})

        audio = MP3(str(test_file))
        # Check COMM frames contain the descriptive string
        comm_found = False
        for frame in audio.tags.getall('COMM'):
            if "Driving" in str(frame) and "Hypnotic" in str(frame):
                comm_found = True
                break
        assert comm_found, "Descriptive string not found in COMM"

    def test_backwards_compat_album_still_works(self, test_audio_path, temp_dir):
        """Old 'album' key should still write to TALB."""
        from core.tag_manager import TagManager
        from mutagen.mp3 import MP3
        import shutil
        from pathlib import Path

        test_file = Path(temp_dir) / "test.mp3"
        shutil.copy(test_audio_path, test_file)

        manager = TagManager()
        manager.write_tags(str(test_file), {"album": "Legacy Album"})

        audio = MP3(str(test_file))
        assert str(audio.tags.get("TALB")) == "Legacy Album"

    def test_backwards_compat_comments_still_works(self, test_audio_path, temp_dir):
        """Old 'comments' key should still write to COMM."""
        from core.tag_manager import TagManager
        from mutagen.mp3 import MP3
        import shutil
        from pathlib import Path

        test_file = Path(temp_dir) / "test.mp3"
        shutil.copy(test_audio_path, test_file)

        manager = TagManager()
        manager.write_tags(str(test_file), {"comments": "Legacy comment"}, overwrite=True)

        audio = MP3(str(test_file))
        comm_found = False
        for frame in audio.tags.getall('COMM'):
            if "Legacy comment" in str(frame):
                comm_found = True
                break
        assert comm_found, "Legacy comments not found in COMM"

    def test_timing_takes_precedence_over_album(self, test_audio_path, temp_dir):
        """When both timing and album provided, timing should be used (newer API)."""
        from core.tag_manager import TagManager
        from mutagen.mp3 import MP3
        import shutil
        from pathlib import Path

        test_file = Path(temp_dir) / "test.mp3"
        shutil.copy(test_audio_path, test_file)

        manager = TagManager()
        # Both provided - timing should take precedence
        manager.write_tags(str(test_file), {"timing": "Peak", "album": "SomeAlbum"})

        audio = MP3(str(test_file))
        # Since timing is written last (takes precedence), expect Peak
        assert str(audio.tags.get("TALB")) == "Peak"

    def test_overwrite_clears_timing_field(self, test_audio_path, temp_dir):
        """Overwrite mode should clear TALB when timing is provided."""
        from core.tag_manager import TagManager
        from mutagen.mp3 import MP3
        import shutil
        from pathlib import Path

        test_file = Path(temp_dir) / "test.mp3"
        shutil.copy(test_audio_path, test_file)

        manager = TagManager()
        # Write initial
        manager.write_tags(str(test_file), {"timing": "Start"}, overwrite=True)

        # Overwrite with new
        manager.write_tags(str(test_file), {"timing": "Peak"}, overwrite=True)

        audio = MP3(str(test_file))
        assert str(audio.tags.get("TALB")) == "Peak"

    def test_overwrite_clears_mood_field(self, test_audio_path, temp_dir):
        """Overwrite mode should clear TIT1 when mood is provided."""
        from core.tag_manager import TagManager
        from mutagen.mp3 import MP3
        import shutil
        from pathlib import Path

        test_file = Path(temp_dir) / "test.mp3"
        shutil.copy(test_audio_path, test_file)

        manager = TagManager()
        # Write initial
        manager.write_tags(str(test_file), {"mood": "Happy"}, overwrite=True)

        # Overwrite with new
        manager.write_tags(str(test_file), {"mood": "Dark"}, overwrite=True)

        audio = MP3(str(test_file))
        assert str(audio.tags.get("TIT1")) == "Dark"

    def test_overwrite_clears_descriptive_field(self, test_audio_path, temp_dir):
        """Overwrite mode should clear COMM when descriptive is provided."""
        from core.tag_manager import TagManager
        from mutagen.mp3 import MP3
        import shutil
        from pathlib import Path

        test_file = Path(temp_dir) / "test.mp3"
        shutil.copy(test_audio_path, test_file)

        manager = TagManager()
        # Write initial
        manager.write_tags(str(test_file), {"descriptive": ["First", "Tags"]}, overwrite=True)

        # Overwrite with new
        manager.write_tags(str(test_file), {"descriptive": ["New", "Tags"]}, overwrite=True)

        audio = MP3(str(test_file))
        # Should only have "New, Tags", not "First, Tags"
        comm_text = ""
        for frame in audio.tags.getall('COMM'):
            comm_text += str(frame)
        assert "New" in comm_text
        assert "First" not in comm_text

    def test_read_new_taxonomy_fields(self, test_audio_path, temp_dir):
        """Read should return new taxonomy keys (timing, mood, descriptive)."""
        from core.tag_manager import TagManager
        import shutil
        from pathlib import Path

        test_file = Path(temp_dir) / "test.mp3"
        shutil.copy(test_audio_path, test_file)

        manager = TagManager()

        # Write with new taxonomy
        manager.write_tags(str(test_file), {
            "genre": "Techno",
            "timing": "Build",
            "mood": "Dark",
            "descriptive": ["Heavy", "Driving"],
        })

        # Read back
        tags = manager.read_tags(str(test_file))

        # Should have new taxonomy keys
        assert tags["genre"] == "Techno"
        assert tags["timing"] == "Build"
        assert tags["mood"] == "Dark"
        assert "Heavy" in tags["descriptive"]
        assert "Driving" in tags["descriptive"]

        # Should also have old keys for backwards compat
        assert tags["album"] == "Build"  # Same as timing
        assert tags["work"] == "Dark"    # Same as mood
        assert "comments" in tags        # Should have comments too

    def test_read_timing_from_talb(self, test_audio_path, temp_dir):
        """Reading TALB should return both timing and album keys."""
        from core.tag_manager import TagManager
        import shutil
        from pathlib import Path

        test_file = Path(temp_dir) / "test.mp3"
        shutil.copy(test_audio_path, test_file)

        manager = TagManager()
        manager.write_tags(str(test_file), {"album": "Peak"})

        tags = manager.read_tags(str(test_file))

        # Both keys should have same value
        assert tags["album"] == "Peak"
        assert tags["timing"] == "Peak"

    def test_read_mood_from_tit1(self, test_audio_path, temp_dir):
        """Reading TIT1 should return both mood and work keys."""
        from core.tag_manager import TagManager
        import shutil
        from pathlib import Path

        test_file = Path(temp_dir) / "test.mp3"
        shutil.copy(test_audio_path, test_file)

        manager = TagManager()
        manager.write_tags(str(test_file), {"work": "Energetic"})

        tags = manager.read_tags(str(test_file))

        # Both keys should have same value
        assert tags["work"] == "Energetic"
        assert tags["mood"] == "Energetic"

    def test_read_descriptive_from_comm(self, test_audio_path, temp_dir):
        """Reading COMM should return descriptive as parsed list."""
        from core.tag_manager import TagManager
        import shutil
        from pathlib import Path

        test_file = Path(temp_dir) / "test.mp3"
        shutil.copy(test_audio_path, test_file)

        manager = TagManager()
        manager.write_tags(str(test_file), {"comments": "Funky, Groovy, Bouncy"}, overwrite=True)

        tags = manager.read_tags(str(test_file))

        # Should have descriptive as list
        assert "descriptive" in tags
        assert isinstance(tags["descriptive"], list)
        assert "Funky" in tags["descriptive"]
        assert "Groovy" in tags["descriptive"]
        assert "Bouncy" in tags["descriptive"]

        # Should also have original comments
        assert "comments" in tags
