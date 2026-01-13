# Lexicon ID3 Frame Mapping Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Extend Lexicon to include configurable ID3 frame mapping, so users control both vocabulary AND where tags are written.

**Architecture:** Restructure Lexicon JSON from flat mappings to nested structure with `id3_frame` and `mappings` per category. TagManager reads frame preferences from Lexicon instead of hardcoded values. Maintain backwards compatibility with existing flat-format lexicon files.

**Tech Stack:** Python, mutagen (ID3), JSON

---

## New Lexicon Structure

**Old format (still supported for backwards compat):**
```json
{
  "timing": {"Peak": "Climax"},
  "mood": {},
  "genre": {},
  "descriptive": {}
}
```

**New format:**
```json
{
  "genre": {
    "id3_frame": "TCON",
    "mappings": {}
  },
  "timing": {
    "id3_frame": "TALB",
    "mappings": {"Peak": "Climax"}
  },
  "mood": {
    "id3_frame": "TIT1",
    "mappings": {}
  },
  "descriptive": {
    "id3_frame": "COMM",
    "mappings": {}
  }
}
```

---

### Task 1: Update Lexicon DEFAULT_LEXICON and Structure

**Files:**
- Modify: `python/src/core/lexicon.py:15-20`
- Test: `python/tests/test_lexicon.py`

**Step 1: Write test for new default structure**

Add to `test_lexicon.py`:
```python
class TestLexiconID3Mapping:
    """Tests for ID3 frame mapping functionality."""

    def test_default_lexicon_has_id3_frames(self, tmp_path):
        """Default lexicon should include id3_frame for each category."""
        lexicon_path = tmp_path / "lexicon.json"
        lexicon = Lexicon(lexicon_path)

        # Check file structure
        with open(lexicon_path, 'r') as f:
            data = json.load(f)

        assert data["genre"]["id3_frame"] == "TCON"
        assert data["timing"]["id3_frame"] == "TALB"
        assert data["mood"]["id3_frame"] == "TIT1"
        assert data["descriptive"]["id3_frame"] == "COMM"
        assert data["genre"]["mappings"] == {}
```

**Step 2: Run test to verify it fails**

Run: `pytest tests/test_lexicon.py::TestLexiconID3Mapping::test_default_lexicon_has_id3_frames -v`
Expected: FAIL (KeyError or structure mismatch)

**Step 3: Update DEFAULT_LEXICON in lexicon.py**

```python
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
```

**Step 4: Run test to verify it passes**

Run: `pytest tests/test_lexicon.py::TestLexiconID3Mapping::test_default_lexicon_has_id3_frames -v`
Expected: PASS

**Step 5: Commit**

```bash
git add python/src/core/lexicon.py python/tests/test_lexicon.py
git commit -m "feat: update Lexicon default structure with id3_frame per category"
```

---

### Task 2: Add Backwards Compatibility for Old Format

**Files:**
- Modify: `python/src/core/lexicon.py:34-54` (_load method)
- Test: `python/tests/test_lexicon.py`

**Step 1: Write test for backwards compatibility**

```python
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

    # Should have migrated to new structure
    assert lexicon.get_id3_frame("timing") == "TALB"  # Default
    assert lexicon.get_mapping("timing", "Peak") == "Climax"  # Preserved
    assert lexicon.get_mapping("mood", "Happy") == "Euphoric"  # Preserved
```

**Step 2: Run test to verify it fails**

Run: `pytest tests/test_lexicon.py::TestLexiconID3Mapping::test_lexicon_migrates_old_format -v`
Expected: FAIL (get_id3_frame doesn't exist or migration not working)

**Step 3: Update _load method to detect and migrate old format**

```python
def _load(self) -> dict:
    """Load lexicon from file, migrating old format if needed."""
    if self.path.exists():
        try:
            with open(self.path, 'r') as f:
                loaded = json.load(f)
            # Detect old format (flat mappings without id3_frame)
            loaded = self._migrate_if_needed(loaded)
            # Ensure all categories exist
            for category, defaults in self.DEFAULT_LEXICON.items():
                if category not in loaded:
                    loaded[category] = dict(defaults)
            return loaded
        except (json.JSONDecodeError, IOError):
            return self._create_default()
    else:
        return self._create_default()

def _migrate_if_needed(self, data: dict) -> dict:
    """Migrate old flat format to new nested format."""
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
```

**Step 4: Run test to verify it passes**

Run: `pytest tests/test_lexicon.py::TestLexiconID3Mapping::test_lexicon_migrates_old_format -v`
Expected: PASS

**Step 5: Commit**

```bash
git add python/src/core/lexicon.py python/tests/test_lexicon.py
git commit -m "feat: add backwards compatibility for old lexicon format"
```

---

### Task 3: Add get_id3_frame and set_id3_frame Methods

**Files:**
- Modify: `python/src/core/lexicon.py`
- Test: `python/tests/test_lexicon.py`

**Step 1: Write tests**

```python
def test_get_id3_frame_returns_configured_frame(self, tmp_path):
    """get_id3_frame returns the configured ID3 frame for a category."""
    lexicon_path = tmp_path / "lexicon.json"
    lexicon = Lexicon(lexicon_path)

    assert lexicon.get_id3_frame("genre") == "TCON"
    assert lexicon.get_id3_frame("timing") == "TALB"
    assert lexicon.get_id3_frame("mood") == "TIT1"
    assert lexicon.get_id3_frame("descriptive") == "COMM"

def test_set_id3_frame_changes_frame(self, tmp_path):
    """set_id3_frame changes the ID3 frame for a category."""
    lexicon_path = tmp_path / "lexicon.json"
    lexicon = Lexicon(lexicon_path)

    # Change timing to use TXXX custom frame
    lexicon.set_id3_frame("timing", "TXXX:CRATEBOT_TIMING")
    assert lexicon.get_id3_frame("timing") == "TXXX:CRATEBOT_TIMING"

    # Save and reload
    lexicon.save()
    lexicon2 = Lexicon(lexicon_path)
    assert lexicon2.get_id3_frame("timing") == "TXXX:CRATEBOT_TIMING"

def test_get_id3_frame_unknown_category_returns_none(self, tmp_path):
    """get_id3_frame returns None for unknown category."""
    lexicon_path = tmp_path / "lexicon.json"
    lexicon = Lexicon(lexicon_path)

    assert lexicon.get_id3_frame("unknown") is None
```

**Step 2: Run tests to verify they fail**

Run: `pytest tests/test_lexicon.py::TestLexiconID3Mapping::test_get_id3_frame_returns_configured_frame -v`
Expected: FAIL (method doesn't exist)

**Step 3: Implement get_id3_frame and set_id3_frame**

```python
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
```

**Step 4: Run tests to verify they pass**

Run: `pytest tests/test_lexicon.py::TestLexiconID3Mapping -v`
Expected: All PASS

**Step 5: Commit**

```bash
git add python/src/core/lexicon.py python/tests/test_lexicon.py
git commit -m "feat: add get_id3_frame and set_id3_frame methods to Lexicon"
```

---

### Task 4: Update get_mapping and set_mapping for New Structure

**Files:**
- Modify: `python/src/core/lexicon.py:66-90`
- Test: `python/tests/test_lexicon.py`

**Step 1: Run existing mapping tests to see what breaks**

Run: `pytest tests/test_lexicon.py::TestLexiconMapping -v`
Expected: FAIL (because internal structure changed)

**Step 2: Update get_mapping to use nested structure**

```python
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
```

**Step 3: Run tests to verify they pass**

Run: `pytest tests/test_lexicon.py::TestLexiconMapping -v`
Expected: All PASS

**Step 4: Commit**

```bash
git add python/src/core/lexicon.py
git commit -m "refactor: update mapping methods for nested lexicon structure"
```

---

### Task 5: Update TagManager to Use Lexicon for ID3 Frames

**Files:**
- Modify: `python/src/core/tag_manager.py`
- Test: `python/tests/test_tag_manager.py`

**Step 1: Write test for configurable ID3 frame**

Add to `test_tag_manager.py`:
```python
class TestLexiconID3Integration:
    """Tests for TagManager using Lexicon ID3 frame configuration."""

    def test_write_timing_to_custom_frame(self, test_audio_path, tmp_path):
        """TagManager writes timing to Lexicon-configured frame."""
        from core.tag_manager import TagManager
        from core.lexicon import Lexicon

        # Configure lexicon to use custom TXXX frame for timing
        lexicon_path = tmp_path / "lexicon.json"
        lexicon = Lexicon(lexicon_path)
        lexicon.set_id3_frame("timing", "TXXX:CRATEBOT_TIMING")
        lexicon.save()

        # Write with lexicon
        manager = TagManager()
        manager.write_tags(str(test_audio_path), {"timing": "Peak"}, lexicon=lexicon)

        # Read back - timing should be in TXXX, not TALB
        tags = manager.read_tags(str(test_audio_path), lexicon=lexicon)
        assert tags.get("timing") == "Peak"

        # Verify TALB was NOT written
        from mutagen.mp3 import MP3
        audio = MP3(str(test_audio_path))
        assert "TALB" not in audio.tags or str(audio.tags["TALB"]) != "Peak"
```

**Step 2: Run test to verify it fails**

Run: `pytest tests/test_tag_manager.py::TestLexiconID3Integration::test_write_timing_to_custom_frame -v`
Expected: FAIL (TagManager doesn't accept lexicon parameter)

**Step 3: Update TagManager.write_tags to accept lexicon**

Update method signature and add frame lookup:
```python
def write_tags(self, audio_path: str, tags: Dict[str, Any],
               overwrite: bool = True, lexicon: Optional['Lexicon'] = None) -> None:
    """Write tags to audio file.

    Args:
        audio_path: Path to audio file
        tags: Dictionary of tags to write
        overwrite: If True, clear existing tags before writing
        lexicon: Optional Lexicon for ID3 frame configuration
    """
    # Helper to get frame for a category
    def get_frame(category: str, default: str) -> str:
        if lexicon:
            return lexicon.get_id3_frame(category) or default
        return default

    # ... in the timing section:
    if 'timing' in tags:
        frame = get_frame("timing", "TALB")
        self._write_to_frame(audio, frame, tags['timing'])
```

**Step 4: Implement _write_to_frame helper that handles TXXX**

```python
def _write_to_frame(self, audio, frame: str, value: str) -> None:
    """Write value to specified ID3 frame.

    Args:
        audio: Mutagen MP3 object
        frame: Frame name (e.g., 'TALB', 'TXXX:CUSTOM')
        value: Value to write
    """
    if frame.startswith("TXXX:"):
        # Custom TXXX frame
        desc = frame[5:]  # Everything after "TXXX:"
        # Remove existing TXXX with same description
        for txxx in audio.tags.getall("TXXX"):
            if txxx.desc == desc:
                audio.tags.remove(txxx)
        audio.tags.add(TXXX(encoding=3, desc=desc, text=value))
    elif frame == "TALB":
        if "TALB" in audio.tags:
            audio.tags.delall("TALB")
        audio.tags.add(TALB(encoding=3, text=value))
    elif frame == "TIT1":
        if "TIT1" in audio.tags:
            audio.tags.delall("TIT1")
        audio.tags.add(TIT1(encoding=3, text=value))
    elif frame == "TCON":
        if "TCON" in audio.tags:
            audio.tags.delall("TCON")
        audio.tags.add(TCON(encoding=3, text=value))
    elif frame == "COMM":
        audio.tags.delall("COMM")
        audio.tags.add(COMM(encoding=3, lang='eng', desc='', text=value))
    # Add more frames as needed
```

**Step 5: Run test to verify it passes**

Run: `pytest tests/test_tag_manager.py::TestLexiconID3Integration -v`
Expected: PASS

**Step 6: Commit**

```bash
git add python/src/core/tag_manager.py python/tests/test_tag_manager.py
git commit -m "feat: TagManager uses Lexicon for ID3 frame configuration"
```

---

### Task 6: Update TagManager.read_tags to Use Lexicon

**Files:**
- Modify: `python/src/core/tag_manager.py:19-100`
- Test: `python/tests/test_tag_manager.py`

**Step 1: Write test**

```python
def test_read_timing_from_custom_frame(self, test_audio_path, tmp_path):
    """TagManager reads timing from Lexicon-configured frame."""
    from core.tag_manager import TagManager
    from core.lexicon import Lexicon
    from mutagen.mp3 import MP3
    from mutagen.id3 import TXXX

    # Write directly to custom TXXX frame
    audio = MP3(str(test_audio_path))
    audio.tags.add(TXXX(encoding=3, desc="CRATEBOT_TIMING", text="Peak"))
    audio.save()

    # Configure lexicon
    lexicon_path = tmp_path / "lexicon.json"
    lexicon = Lexicon(lexicon_path)
    lexicon.set_id3_frame("timing", "TXXX:CRATEBOT_TIMING")
    lexicon.save()

    # Read with lexicon
    manager = TagManager()
    tags = manager.read_tags(str(test_audio_path), lexicon=lexicon)

    assert tags.get("timing") == "Peak"
```

**Step 2: Run test to verify it fails**

Run: `pytest tests/test_tag_manager.py::TestLexiconID3Integration::test_read_timing_from_custom_frame -v`
Expected: FAIL

**Step 3: Update read_tags to accept lexicon and read from configured frames**

```python
def read_tags(self, audio_path: str, lexicon: Optional['Lexicon'] = None) -> Dict[str, Any]:
    """Read tags from audio file.

    Args:
        audio_path: Path to audio file
        lexicon: Optional Lexicon for ID3 frame configuration
    """
    # ... existing code ...

    # Helper to get frame for a category
    def get_frame(category: str, default: str) -> str:
        if lexicon:
            return lexicon.get_id3_frame(category) or default
        return default

    # Read timing from configured frame
    timing_frame = get_frame("timing", "TALB")
    timing_value = self._read_from_frame(audio, timing_frame)
    if timing_value:
        tags["timing"] = timing_value

    # ... similar for mood, genre, descriptive ...
```

**Step 4: Implement _read_from_frame helper**

```python
def _read_from_frame(self, audio, frame: str) -> Optional[str]:
    """Read value from specified ID3 frame.

    Args:
        audio: Mutagen MP3 object
        frame: Frame name (e.g., 'TALB', 'TXXX:CUSTOM')

    Returns:
        Value from frame, or None if not found.
    """
    if frame.startswith("TXXX:"):
        desc = frame[5:]
        for txxx in audio.tags.getall("TXXX"):
            if txxx.desc == desc:
                return str(txxx.text[0]) if txxx.text else None
        return None
    elif frame in audio.tags:
        return str(audio.tags[frame])
    return None
```

**Step 5: Run tests**

Run: `pytest tests/test_tag_manager.py::TestLexiconID3Integration -v`
Expected: PASS

**Step 6: Commit**

```bash
git add python/src/core/tag_manager.py python/tests/test_tag_manager.py
git commit -m "feat: TagManager.read_tags uses Lexicon for ID3 frame configuration"
```

---

### Task 7: Update AutoTagger to Pass Lexicon to TagManager

**Files:**
- Modify: `python/src/core/auto_tagger.py`
- Test: `python/tests/test_lexicon.py` (AutoTagger integration tests)

**Step 1: Update AutoTagger.tag_file to pass lexicon to TagManager**

In `auto_tagger.py`, find where TagManager.write_tags is called and pass lexicon:

```python
# In tag_file method, after applying lexicon vocabulary:
self.tag_manager.write_tags(mp3_path, write_tags, overwrite=overwrite, lexicon=self.lexicon)
```

**Step 2: Run existing AutoTagger tests**

Run: `pytest tests/test_lexicon.py::TestAutoTaggerLexiconIntegration -v`
Expected: PASS (or SKIP if import issues)

**Step 3: Commit**

```bash
git add python/src/core/auto_tagger.py
git commit -m "feat: AutoTagger passes Lexicon to TagManager for ID3 frame config"
```

---

### Task 8: Run Full Test Suite and Fix Any Regressions

**Step 1: Run all tests**

Run: `pytest tests/ -v`
Expected: All tests pass (98+ tests)

**Step 2: Fix any failures**

If tests fail, identify the issue:
- Old tests using flat lexicon format → update fixtures
- Import issues → check circular imports
- Assertion failures → update expected values

**Step 3: Final commit**

```bash
git add -A
git commit -m "test: fix regressions from Lexicon ID3 mapping changes"
```

---

### Task 9: Update Documentation

**Files:**
- Modify: `docs/plans/2026-01-09-lexicon-taxonomy-implementation-complete.md`

**Step 1: Add section about ID3 frame configuration**

Add to documentation:

```markdown
## ID3 Frame Configuration

Users can configure which ID3 frames each taxonomy field writes to via the Lexicon.

**Default frame mapping:**
| Field | Default Frame | Description |
|-------|---------------|-------------|
| genre | TCON | Standard genre field |
| timing | TALB | Album field (DJ energy arc) |
| mood | TIT1 | Content Group / Work |
| descriptive | COMM | Comments |

**Customizing frames:**
```python
from core.lexicon import Lexicon

lexicon = Lexicon()
lexicon.set_id3_frame("timing", "TXXX:CRATEBOT_TIMING")  # Custom frame
lexicon.set_id3_frame("mood", "TXXX:CRATEBOT_MOOD")      # Custom frame
lexicon.save()
```

**Lexicon file structure (~/.cratebot/lexicon.json):**
```json
{
  "genre": {
    "id3_frame": "TCON",
    "mappings": {"House": "Deep House"}
  },
  "timing": {
    "id3_frame": "TXXX:CRATEBOT_TIMING",
    "mappings": {"Peak": "Climax"}
  }
}
```
```

**Step 2: Commit**

```bash
git add docs/
git commit -m "docs: add ID3 frame configuration documentation"
```

---

## Summary

| Task | Description | Files |
|------|-------------|-------|
| 1 | Update DEFAULT_LEXICON structure | lexicon.py |
| 2 | Add backwards compatibility migration | lexicon.py |
| 3 | Add get_id3_frame/set_id3_frame | lexicon.py |
| 4 | Update get_mapping/set_mapping | lexicon.py |
| 5 | TagManager.write_tags uses Lexicon | tag_manager.py |
| 6 | TagManager.read_tags uses Lexicon | tag_manager.py |
| 7 | AutoTagger passes Lexicon | auto_tagger.py |
| 8 | Fix test regressions | tests/ |
| 9 | Update documentation | docs/ |

**Estimated commits:** 9
**Test coverage:** All existing tests should pass, plus new tests for ID3 frame configuration
