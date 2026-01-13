# Fix Training Tag Matching Bugs

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Fix three bugs in backend API server training code that cause "0 valid samples" error due to tag matching failures.

**Architecture:** Refactor `api_server.py` training code to use the existing `matches_selected_tag()` utility function from `utils.py`, matching the pattern already working in `auto_tagger._collect_training_data()`.

**Tech Stack:** Python, FastAPI, pytest

---

## Bug Summary

| Bug | Location | Issue |
|-----|----------|-------|
| 1 | `api_server.py:574,578` | Case-sensitive `in` comparison fails when scanner normalizes to title case |
| 2 | `api_server.py:571-582` | Missing comments check - files with only comment tags skipped |
| 3 | `api_server.py:567` | Missing `lexicon` parameter in `read_tags()` call |

---

### Task 1: Add Import for matches_selected_tag

**Files:**
- Modify: `backend/api_server.py:63-65`

**Step 1: Add the import**

In `backend/api_server.py`, add import for `matches_selected_tag` from utils:

```python
# After line 65 (from core.audio_hash import compute_audio_hash)
from core.utils import matches_selected_tag
```

**Step 2: Verify import works**

Run: `cd /Users/noahraford/CrateBot3 && python -c "from backend.api_server import app; print('Import OK')"`

Expected: `Import OK`

**Step 3: Commit**

```bash
git add backend/api_server.py
git commit -m "fix(training): import matches_selected_tag utility"
```

---

### Task 2: Fix Tag Matching Logic in Training

**Files:**
- Modify: `backend/api_server.py:566-582`

**Step 1: Update the tag matching code**

Replace lines 566-582 in the training function with case-insensitive matching that includes comments:

```python
                try:
                    tags = tagger.tag_manager.read_tags(str(mp3_path), lexicon=tagger.lexicon)
                    if not tags:
                        continue

                    # Check if file has selected tags (case-insensitive fuzzy matching)
                    has_valid_tag = False

                    # Check genre
                    genre = tags.get('genre', '').strip()
                    selected_genre_set = set(selected_tags.get('genre', []))
                    if matches_selected_tag(genre, selected_genre_set):
                        has_valid_tag = True

                    # Check album/timing
                    album = tags.get('album', '').strip()
                    selected_album_set = set(selected_tags.get('album', []))
                    if matches_selected_tag(album, selected_album_set):
                        has_valid_tag = True

                    # Check comments (multi-value field)
                    comments = tags.get('comments', '')
                    if isinstance(comments, list):
                        comments = ' '.join(comments)
                    comment_tags = [c.strip() for c in comments.split(',') if c.strip()]
                    selected_comments_set = set(selected_tags.get('comments', []))
                    if any(matches_selected_tag(t, selected_comments_set) for t in comment_tags):
                        has_valid_tag = True

                    if not has_valid_tag:
                        continue
```

**Step 2: Verify syntax**

Run: `cd /Users/noahraford/CrateBot3 && python -c "from backend.api_server import app; print('Syntax OK')"`

Expected: `Syntax OK`

**Step 3: Commit**

```bash
git add backend/api_server.py
git commit -m "fix(training): use case-insensitive tag matching with comments support

- Use matches_selected_tag() for fuzzy case-insensitive matching
- Add missing comments field check
- Pass lexicon to read_tags() for custom ID3 frame support

Fixes: Training failing with '0 valid samples' when tag cases don't match"
```

---

### Task 3: Write Integration Test

**Files:**
- Create: `backend/tests/test_training_tag_matching.py`

**Step 1: Write the test**

```python
"""Tests for training tag matching logic."""
import pytest
from unittest.mock import MagicMock, patch
from pathlib import Path


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
            'album': ['Peak', 'Build'],
            'comments': ['Funky', 'Driving'],
        }

        # Simulated file tags with various cases (as read from actual files)
        test_files = [
            {'genre': 'HOUSE', 'album': 'PEAK', 'comments': ['FUNKY']},
            {'genre': 'house', 'album': 'build', 'comments': ['driving']},
            {'genre': 'House', 'album': 'Peak', 'comments': ['Funky']},
            {'genre': 'Techno', 'album': '', 'comments': []},  # Only genre
            {'genre': '', 'album': 'Build', 'comments': []},   # Only album
            {'genre': '', 'album': '', 'comments': ['Driving']},  # Only comments
        ]

        # All should match with case-insensitive logic
        for tags in test_files:
            has_valid_tag = False

            genre = tags.get('genre', '').strip()
            if matches_selected_tag(genre, set(selected_tags['genre'])):
                has_valid_tag = True

            album = tags.get('album', '').strip()
            if matches_selected_tag(album, set(selected_tags['album'])):
                has_valid_tag = True

            comments = tags.get('comments', [])
            if isinstance(comments, list):
                comments = ', '.join(comments)
            comment_tags = [c.strip() for c in comments.split(',') if c.strip()]
            if any(matches_selected_tag(t, set(selected_tags['comments'])) for t in comment_tags):
                has_valid_tag = True

            assert has_valid_tag, f"Should match: {tags}"
```

**Step 2: Run test to verify it passes**

Run: `cd /Users/noahraford/CrateBot3 && python -m pytest backend/tests/test_training_tag_matching.py -v`

Expected: All 3 tests PASS

**Step 3: Commit**

```bash
git add backend/tests/test_training_tag_matching.py
git commit -m "test(training): add tag matching integration tests

- Test case-insensitive matching
- Test fuzzy matching for similar tags
- Test mixed-case scenarios in training flow"
```

---

### Task 4: Manual Verification

**Step 1: Start the backend server**

Run: `cd /Users/noahraford/CrateBot3 && python -m backend.api_server`

**Step 2: Test with actual training**

Use the frontend or curl to start a training job and verify samples are collected.

**Step 3: Verify the fix**

Expected: Training should now find valid samples even when file tags have different cases than the scanner-normalized values.

---

## Summary

| Task | Description | Status |
|------|-------------|--------|
| 1 | Add import for matches_selected_tag | |
| 2 | Fix tag matching logic | |
| 3 | Write integration tests | |
| 4 | Manual verification | |
