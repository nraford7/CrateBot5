# Lexicon & Taxonomy Redesign Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Transform CrateBot from "train your own model" to "customize your vocabulary" by shipping a pre-trained model with lexicon mapping and per-track overrides.

**Architecture:** Four-phase approach: (1) Restructure taxonomy to separate Genre/Timing/Mood/Descriptive, (2) Add lexicon mapping layer for user vocabulary customization, (3) Add override system for per-track corrections by audio hash, (4) Bundle pre-trained model.

**Tech Stack:** Python 3.11+, scikit-learn/LightGBM, Mutagen (ID3), SQLite (overrides), JSON (lexicon)

---

## Phase 1: Taxonomy Restructure

### Task 1.1: Add New Taxonomy Constants

**Files:**
- Modify: `python/src/core/constants.py:1-50`
- Test: `python/tests/test_constants.py` (create)

**Step 1: Write the failing test**

```python
# python/tests/test_constants.py
"""Tests for taxonomy constants."""
import pytest
from src.core.constants import (
    CANONICAL_GENRES,
    CANONICAL_TIMING,
    CANONICAL_MOODS,
    TAXONOMY_ID3_MAPPING,
)


def test_canonical_genres_has_9_values():
    assert len(CANONICAL_GENRES) == 9
    assert "House" in CANONICAL_GENRES
    assert "Techno" in CANONICAL_GENRES
    assert "Jungle/DnB" in CANONICAL_GENRES


def test_canonical_timing_has_5_values():
    assert len(CANONICAL_TIMING) == 5
    assert "Start" in CANONICAL_TIMING
    assert "Build" in CANONICAL_TIMING
    assert "Peak" in CANONICAL_TIMING
    assert "Sustain" in CANONICAL_TIMING
    assert "Release" in CANONICAL_TIMING


def test_canonical_moods_has_6_values():
    assert len(CANONICAL_MOODS) == 6
    assert "Happy" in CANONICAL_MOODS
    assert "Dark" in CANONICAL_MOODS
    assert "Groovy" in CANONICAL_MOODS


def test_taxonomy_id3_mapping():
    assert TAXONOMY_ID3_MAPPING["genre"] == "TCON"
    assert TAXONOMY_ID3_MAPPING["timing"] == "TALB"
    assert TAXONOMY_ID3_MAPPING["mood"] == "TIT1"
    assert TAXONOMY_ID3_MAPPING["descriptive"] == "COMM"
```

**Step 2: Run test to verify it fails**

Run: `cd python && pytest tests/test_constants.py -v`
Expected: FAIL with ImportError (constants not defined)

**Step 3: Write minimal implementation**

Add to `python/src/core/constants.py` after existing constants:

```python
# === New Taxonomy (v2) ===

CANONICAL_GENRES = [
    "House",
    "Techno",
    "Jungle/DnB",
    "Rap",
    "DiscoFunk",
    "Breakbeat",
    "Ambient",
    "Dubstep",
    "Trance",
]

CANONICAL_TIMING = [
    "Start",
    "Build",
    "Peak",
    "Sustain",
    "Release",
]

CANONICAL_MOODS = [
    "Happy",
    "Dark",
    "Emotional",
    "Aggressive",
    "Dreamy",
    "Groovy",
]

TAXONOMY_ID3_MAPPING = {
    "genre": "TCON",
    "timing": "TALB",
    "mood": "TIT1",
    "descriptive": "COMM",
}
```

**Step 4: Run test to verify it passes**

Run: `cd python && pytest tests/test_constants.py -v`
Expected: PASS

**Step 5: Commit**

```bash
git add python/src/core/constants.py python/tests/test_constants.py
git commit -m "$(cat <<'EOF'
feat: add canonical taxonomy constants for v2 redesign

Adds CANONICAL_GENRES (9), CANONICAL_TIMING (5), CANONICAL_MOODS (6),
and TAXONOMY_ID3_MAPPING for the new lexicon/taxonomy system.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 1.2: Update TagPredictor for 4-Classifier Architecture

**Files:**
- Modify: `python/src/models/tag_predictor.py:1-100`
- Test: `python/tests/test_tag_predictor.py`

**Step 1: Write the failing test**

Add to `python/tests/test_tag_predictor.py`:

```python
def test_predict_returns_new_taxonomy_structure(mock_feature_vector):
    """Predictions should return genre, timing, mood, and descriptive keys."""
    predictor = TagPredictor()
    # Create minimal training data for new taxonomy
    training_data = {
        "features": [mock_feature_vector for _ in range(20)],
        "genre": ["House"] * 10 + ["Techno"] * 10,
        "timing": ["Peak"] * 10 + ["Build"] * 10,
        "mood": ["Happy"] * 10 + ["Dark"] * 10,
        "descriptive": [["Driving", "Melodic"]] * 20,
    }
    selected_tags = {
        "genre": ["House", "Techno"],
        "timing": ["Peak", "Build"],
        "mood": ["Happy", "Dark"],
        "descriptive": ["Driving", "Melodic", "Punchy"],
    }
    predictor.train(training_data, selected_tags)

    result = predictor.predict_tags(mock_feature_vector)

    assert "genre" in result
    assert "timing" in result
    assert "mood" in result
    assert "descriptive" in result
    assert result["genre"]["value"] in ["House", "Techno"]
    assert result["timing"]["value"] in ["Peak", "Build"]
    assert result["mood"]["value"] in ["Happy", "Dark"]
    assert isinstance(result["descriptive"]["tags"], list)
```

**Step 2: Run test to verify it fails**

Run: `cd python && pytest tests/test_tag_predictor.py::test_predict_returns_new_taxonomy_structure -v`
Expected: FAIL (current predictor uses album, not timing/mood)

**Step 3: Write minimal implementation**

Update `python/src/models/tag_predictor.py` - change the training method signature and add mood classifier:

```python
# In train() method, add mood training alongside genre and timing (was album)
def train(self, training_data: dict, selected_tags: dict) -> dict:
    """Train classifiers for genre, timing, mood, and descriptive tags."""
    features = np.array(training_data["features"])

    # Normalize features
    self.scaler = StandardScaler()
    features_scaled = self.scaler.fit_transform(features)

    metrics = {}

    # Train Genre classifier (single-class)
    if "genre" in training_data and "genre" in selected_tags:
        metrics["genre"] = self._train_single_class(
            features_scaled, training_data["genre"],
            selected_tags["genre"], "genre"
        )

    # Train Timing classifier (single-class) - was "album"
    if "timing" in training_data and "timing" in selected_tags:
        metrics["timing"] = self._train_single_class(
            features_scaled, training_data["timing"],
            selected_tags["timing"], "timing"
        )

    # Train Mood classifier (single-class) - NEW
    if "mood" in training_data and "mood" in selected_tags:
        metrics["mood"] = self._train_single_class(
            features_scaled, training_data["mood"],
            selected_tags["mood"], "mood"
        )

    # Train Descriptive classifier (multi-label) - was "comments"
    if "descriptive" in training_data and "descriptive" in selected_tags:
        metrics["descriptive"] = self._train_multi_label(
            features_scaled, training_data["descriptive"],
            selected_tags["descriptive"], "descriptive"
        )

    return metrics
```

Update `predict_tags()` to return new structure:

```python
def predict_tags(self, features: np.ndarray) -> dict:
    """Predict tags for audio features."""
    if self.scaler is None:
        raise ValueError("Model not trained")

    features_scaled = self.scaler.transform(features.reshape(1, -1))
    result = {}

    # Predict genre
    if "genre" in self.models:
        genre_pred, genre_conf = self._predict_single_class(features_scaled, "genre")
        result["genre"] = {"value": genre_pred, "confidence": genre_conf}

    # Predict timing
    if "timing" in self.models:
        timing_pred, timing_conf = self._predict_single_class(features_scaled, "timing")
        result["timing"] = {"value": timing_pred, "confidence": timing_conf}

    # Predict mood
    if "mood" in self.models:
        mood_pred, mood_conf = self._predict_single_class(features_scaled, "mood")
        result["mood"] = {"value": mood_pred, "confidence": mood_conf}

    # Predict descriptive tags
    if "descriptive" in self.models:
        desc_tags = self._predict_multi_label(features_scaled, "descriptive")
        result["descriptive"] = {"tags": desc_tags}

    return result
```

**Step 4: Run test to verify it passes**

Run: `cd python && pytest tests/test_tag_predictor.py::test_predict_returns_new_taxonomy_structure -v`
Expected: PASS

**Step 5: Commit**

```bash
git add python/src/models/tag_predictor.py python/tests/test_tag_predictor.py
git commit -m "$(cat <<'EOF'
feat: update TagPredictor for 4-classifier taxonomy

Changes from 3 classifiers (genre, album, comments) to 4 classifiers
(genre, timing, mood, descriptive) for the new taxonomy system.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 1.3: Update TagManager ID3 Field Mapping

**Files:**
- Modify: `python/src/core/tag_manager.py:110-200`
- Test: `python/tests/test_tag_manager.py`

**Step 1: Write the failing test**

Add to `python/tests/test_tag_manager.py`:

```python
def test_write_new_taxonomy_fields(temp_audio_file):
    """Write genre/timing/mood/descriptive to correct ID3 fields."""
    manager = TagManager()
    tags = {
        "genre": "House",
        "timing": "Peak",
        "mood": "Happy",
        "descriptive": ["Driving", "Melodic", "Punchy"],
    }

    manager.write_tags(temp_audio_file, tags)

    # Verify with raw Mutagen read
    from mutagen.mp3 import MP3
    audio = MP3(temp_audio_file)

    assert str(audio.tags.get("TCON")) == "House"  # Genre
    assert str(audio.tags.get("TALB")) == "Peak"   # Timing
    assert str(audio.tags.get("TIT1")) == "Happy"  # Mood
    assert "Driving" in str(audio.tags.get("COMM::eng"))  # Descriptive
```

**Step 2: Run test to verify it fails**

Run: `cd python && pytest tests/test_tag_manager.py::test_write_new_taxonomy_fields -v`
Expected: FAIL (current implementation doesn't handle new taxonomy keys)

**Step 3: Write minimal implementation**

Update `write_tags()` in `python/src/core/tag_manager.py`:

```python
def write_tags(self, audio_path: str, tags: dict, overwrite: bool = False) -> None:
    """Write ID3 tags to audio file using new taxonomy mapping."""
    audio = MP3(audio_path)

    if audio.tags is None:
        audio.add_tags()

    if overwrite:
        audio.tags.clear()

    # Genre → TCON
    if "genre" in tags:
        audio.tags.add(TCON(encoding=3, text=tags["genre"]))

    # Timing → TALB (was Album)
    if "timing" in tags:
        audio.tags.add(TALB(encoding=3, text=tags["timing"]))

    # Mood → TIT1 (Grouping/Content Group)
    if "mood" in tags:
        audio.tags.add(TIT1(encoding=3, text=tags["mood"]))

    # Descriptive → COMM (Comments)
    if "descriptive" in tags:
        desc_text = " ".join(tags["descriptive"]) if isinstance(tags["descriptive"], list) else tags["descriptive"]
        audio.tags.add(COMM(encoding=3, lang="eng", desc="", text=desc_text))

    # Legacy support: also handle old keys
    if "album" in tags and "timing" not in tags:
        audio.tags.add(TALB(encoding=3, text=tags["album"]))
    if "comments" in tags and "descriptive" not in tags:
        comm_text = " ".join(tags["comments"]) if isinstance(tags["comments"], list) else tags["comments"]
        audio.tags.add(COMM(encoding=3, lang="eng", desc="", text=comm_text))

    audio.save(v2_version=3)
```

**Step 4: Run test to verify it passes**

Run: `cd python && pytest tests/test_tag_manager.py::test_write_new_taxonomy_fields -v`
Expected: PASS

**Step 5: Commit**

```bash
git add python/src/core/tag_manager.py python/tests/test_tag_manager.py
git commit -m "$(cat <<'EOF'
feat: update TagManager for new ID3 field mapping

Maps genre→TCON, timing→TALB, mood→TIT1, descriptive→COMM.
Maintains backwards compatibility with old album/comments keys.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 1.4: Update TagManager Read for New Taxonomy

**Files:**
- Modify: `python/src/core/tag_manager.py:50-109`
- Test: `python/tests/test_tag_manager.py`

**Step 1: Write the failing test**

```python
def test_read_new_taxonomy_fields(temp_audio_file):
    """Read tags should return new taxonomy structure."""
    manager = TagManager()
    # Write first
    tags = {
        "genre": "Techno",
        "timing": "Build",
        "mood": "Dark",
        "descriptive": ["Heavy", "Driving"],
    }
    manager.write_tags(temp_audio_file, tags)

    # Read back
    result = manager.read_tags(temp_audio_file)

    assert result["genre"] == "Techno"
    assert result["timing"] == "Build"
    assert result["mood"] == "Dark"
    assert "Heavy" in result["descriptive"]
    assert "Driving" in result["descriptive"]
```

**Step 2: Run test to verify it fails**

Run: `cd python && pytest tests/test_tag_manager.py::test_read_new_taxonomy_fields -v`
Expected: FAIL (read_tags returns old keys)

**Step 3: Write minimal implementation**

Update `read_tags()` in `python/src/core/tag_manager.py`:

```python
def read_tags(self, audio_path: str) -> dict:
    """Read ID3 tags from audio file using new taxonomy."""
    audio = MP3(audio_path)

    if audio.tags is None:
        return {}

    tags = {}

    # Genre ← TCON
    if "TCON" in audio.tags:
        tags["genre"] = str(audio.tags["TCON"])

    # Timing ← TALB
    if "TALB" in audio.tags:
        tags["timing"] = str(audio.tags["TALB"])

    # Mood ← TIT1
    if "TIT1" in audio.tags:
        tags["mood"] = str(audio.tags["TIT1"])

    # Descriptive ← COMM
    for key in audio.tags:
        if key.startswith("COMM"):
            comment_text = str(audio.tags[key])
            tags["descriptive"] = comment_text.split()
            break

    # Also read standard fields
    if "TIT2" in audio.tags:
        tags["title"] = str(audio.tags["TIT2"])
    if "TPE1" in audio.tags:
        tags["artist"] = str(audio.tags["TPE1"])

    return tags
```

**Step 4: Run test to verify it passes**

Run: `cd python && pytest tests/test_tag_manager.py::test_read_new_taxonomy_fields -v`
Expected: PASS

**Step 5: Commit**

```bash
git add python/src/core/tag_manager.py python/tests/test_tag_manager.py
git commit -m "$(cat <<'EOF'
feat: update TagManager.read_tags for new taxonomy

Returns genre, timing, mood, descriptive keys matching new ID3 mapping.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Phase 2: Lexicon System

### Task 2.1: Create Lexicon Module - Load/Save

**Files:**
- Create: `python/src/core/lexicon.py`
- Test: `python/tests/test_lexicon.py` (create)

**Step 1: Write the failing test**

```python
# python/tests/test_lexicon.py
"""Tests for lexicon vocabulary mapping."""
import json
import pytest
from pathlib import Path
from src.core.lexicon import Lexicon


@pytest.fixture
def temp_lexicon_path(tmp_path):
    return tmp_path / "lexicon.json"


def test_lexicon_loads_from_file(temp_lexicon_path):
    """Lexicon loads mappings from JSON file."""
    lexicon_data = {
        "timing": {"Peak": "Climax", "Build": "Tension"},
        "mood": {"Happy": "Euphoric"},
        "genre": {},
        "descriptive": {},
    }
    temp_lexicon_path.write_text(json.dumps(lexicon_data))

    lexicon = Lexicon(temp_lexicon_path)

    assert lexicon.get_mapping("timing", "Peak") == "Climax"
    assert lexicon.get_mapping("mood", "Happy") == "Euphoric"


def test_lexicon_returns_original_if_no_mapping(temp_lexicon_path):
    """Unmapped tags pass through unchanged."""
    lexicon_data = {"timing": {}, "mood": {}, "genre": {}, "descriptive": {}}
    temp_lexicon_path.write_text(json.dumps(lexicon_data))

    lexicon = Lexicon(temp_lexicon_path)

    assert lexicon.get_mapping("timing", "Peak") == "Peak"
    assert lexicon.get_mapping("genre", "House") == "House"


def test_lexicon_save_mapping(temp_lexicon_path):
    """Lexicon saves new mappings to file."""
    lexicon_data = {"timing": {}, "mood": {}, "genre": {}, "descriptive": {}}
    temp_lexicon_path.write_text(json.dumps(lexicon_data))

    lexicon = Lexicon(temp_lexicon_path)
    lexicon.set_mapping("timing", "Peak", "Climax")
    lexicon.save()

    # Reload and verify
    saved_data = json.loads(temp_lexicon_path.read_text())
    assert saved_data["timing"]["Peak"] == "Climax"


def test_lexicon_creates_default_if_missing(tmp_path):
    """Lexicon creates default file if path doesn't exist."""
    lexicon_path = tmp_path / "nonexistent" / "lexicon.json"

    lexicon = Lexicon(lexicon_path)

    assert lexicon_path.exists()
    assert lexicon.get_mapping("timing", "Peak") == "Peak"
```

**Step 2: Run test to verify it fails**

Run: `cd python && pytest tests/test_lexicon.py -v`
Expected: FAIL with ImportError (module doesn't exist)

**Step 3: Write minimal implementation**

```python
# python/src/core/lexicon.py
"""Lexicon system for user vocabulary customization."""
import json
from pathlib import Path
from typing import Optional


class Lexicon:
    """Maps canonical tags to user-preferred vocabulary."""

    DEFAULT_LEXICON = {
        "timing": {},
        "mood": {},
        "genre": {},
        "descriptive": {},
    }

    def __init__(self, path: Optional[Path] = None):
        """Initialize lexicon from file path."""
        if path is None:
            path = Path.home() / ".cratebot" / "lexicon.json"

        self.path = Path(path)
        self._mappings = self._load()

    def _load(self) -> dict:
        """Load lexicon from file, creating default if missing."""
        if not self.path.exists():
            self.path.parent.mkdir(parents=True, exist_ok=True)
            self.path.write_text(json.dumps(self.DEFAULT_LEXICON, indent=2))
            return self.DEFAULT_LEXICON.copy()

        with open(self.path, "r") as f:
            return json.load(f)

    def get_mapping(self, category: str, canonical_tag: str) -> str:
        """Get user vocabulary for a canonical tag. Returns original if unmapped."""
        category_mappings = self._mappings.get(category, {})
        return category_mappings.get(canonical_tag, canonical_tag)

    def set_mapping(self, category: str, canonical_tag: str, user_tag: str) -> None:
        """Set a mapping from canonical to user vocabulary."""
        if category not in self._mappings:
            self._mappings[category] = {}
        self._mappings[category][canonical_tag] = user_tag

    def remove_mapping(self, category: str, canonical_tag: str) -> None:
        """Remove a mapping, reverting to canonical."""
        if category in self._mappings and canonical_tag in self._mappings[category]:
            del self._mappings[category][canonical_tag]

    def save(self) -> None:
        """Save lexicon to file."""
        self.path.parent.mkdir(parents=True, exist_ok=True)
        with open(self.path, "w") as f:
            json.dump(self._mappings, f, indent=2)

    def apply_to_tags(self, tags: dict) -> dict:
        """Apply lexicon mappings to a tags dict."""
        result = tags.copy()

        for category in ["genre", "timing", "mood"]:
            if category in result:
                result[category] = self.get_mapping(category, result[category])

        if "descriptive" in result and isinstance(result["descriptive"], list):
            result["descriptive"] = [
                self.get_mapping("descriptive", tag)
                for tag in result["descriptive"]
            ]

        return result
```

**Step 4: Run test to verify it passes**

Run: `cd python && pytest tests/test_lexicon.py -v`
Expected: PASS

**Step 5: Commit**

```bash
git add python/src/core/lexicon.py python/tests/test_lexicon.py
git commit -m "$(cat <<'EOF'
feat: add Lexicon module for vocabulary customization

Users can map canonical tags (e.g., "Peak") to preferred vocabulary
(e.g., "Climax"). Stored in ~/.cratebot/lexicon.json.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2.2: Add apply_to_tags Test

**Files:**
- Modify: `python/tests/test_lexicon.py`

**Step 1: Write the failing test**

```python
def test_lexicon_apply_to_tags(temp_lexicon_path):
    """apply_to_tags transforms all tag categories."""
    lexicon_data = {
        "timing": {"Peak": "Climax"},
        "mood": {"Happy": "Euphoric"},
        "genre": {"House": "Deep House"},
        "descriptive": {"Driving": "Pumping"},
    }
    temp_lexicon_path.write_text(json.dumps(lexicon_data))

    lexicon = Lexicon(temp_lexicon_path)
    tags = {
        "genre": "House",
        "timing": "Peak",
        "mood": "Happy",
        "descriptive": ["Driving", "Melodic"],
    }

    result = lexicon.apply_to_tags(tags)

    assert result["genre"] == "Deep House"
    assert result["timing"] == "Climax"
    assert result["mood"] == "Euphoric"
    assert result["descriptive"] == ["Pumping", "Melodic"]
```

**Step 2: Run test to verify it passes** (already implemented in Step 3 above)

Run: `cd python && pytest tests/test_lexicon.py::test_lexicon_apply_to_tags -v`
Expected: PASS

**Step 3: Commit**

```bash
git add python/tests/test_lexicon.py
git commit -m "$(cat <<'EOF'
test: add apply_to_tags test for Lexicon

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2.3: Integrate Lexicon into AutoTagger Pipeline

**Files:**
- Modify: `python/src/core/auto_tagger.py`
- Test: `python/tests/test_auto_tagger.py`

**Step 1: Write the failing test**

```python
# Add to python/tests/test_auto_tagger.py
def test_auto_tagger_applies_lexicon(mock_predictor, temp_audio_file, temp_lexicon_path):
    """AutoTagger applies lexicon mappings before writing tags."""
    import json
    lexicon_data = {"timing": {"Peak": "Climax"}, "mood": {}, "genre": {}, "descriptive": {}}
    temp_lexicon_path.write_text(json.dumps(lexicon_data))

    # Mock predictor returns "Peak"
    mock_predictor.predict_tags.return_value = {
        "genre": {"value": "House", "confidence": 0.9},
        "timing": {"value": "Peak", "confidence": 0.85},
        "mood": {"value": "Happy", "confidence": 0.8},
        "descriptive": {"tags": ["Driving"]},
    }

    tagger = AutoTagger(predictor=mock_predictor, lexicon_path=temp_lexicon_path)
    tagger.tag_file(temp_audio_file)

    # Read back and verify lexicon was applied
    manager = TagManager()
    tags = manager.read_tags(temp_audio_file)

    assert tags["timing"] == "Climax"  # Not "Peak"
```

**Step 2: Run test to verify it fails**

Run: `cd python && pytest tests/test_auto_tagger.py::test_auto_tagger_applies_lexicon -v`
Expected: FAIL (AutoTagger doesn't accept lexicon_path)

**Step 3: Write minimal implementation**

Update `python/src/core/auto_tagger.py`:

```python
from src.core.lexicon import Lexicon

class AutoTagger:
    def __init__(self, predictor=None, lexicon_path=None):
        self.predictor = predictor
        self.lexicon = Lexicon(lexicon_path)
        self.tag_manager = TagManager()

    def tag_file(self, audio_path: str) -> dict:
        """Analyze and tag an audio file."""
        # Extract features
        features = self._extract_features(audio_path)

        # Get predictions
        predictions = self.predictor.predict_tags(features)

        # Convert to tags dict
        tags = {
            "genre": predictions["genre"]["value"],
            "timing": predictions["timing"]["value"],
            "mood": predictions["mood"]["value"],
            "descriptive": predictions["descriptive"]["tags"],
        }

        # Apply lexicon mapping
        tags = self.lexicon.apply_to_tags(tags)

        # Write to file
        self.tag_manager.write_tags(audio_path, tags)

        return tags
```

**Step 4: Run test to verify it passes**

Run: `cd python && pytest tests/test_auto_tagger.py::test_auto_tagger_applies_lexicon -v`
Expected: PASS

**Step 5: Commit**

```bash
git add python/src/core/auto_tagger.py python/tests/test_auto_tagger.py
git commit -m "$(cat <<'EOF'
feat: integrate Lexicon into AutoTagger pipeline

AutoTagger now applies lexicon mappings before writing ID3 tags.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Phase 3: Override System

### Task 3.1: Create Audio Hash Utility

**Files:**
- Create: `python/src/core/audio_hash.py`
- Test: `python/tests/test_audio_hash.py` (create)

**Step 1: Write the failing test**

```python
# python/tests/test_audio_hash.py
"""Tests for audio hashing."""
import pytest
from pathlib import Path
from src.core.audio_hash import compute_audio_hash


def test_compute_audio_hash_returns_hex_string(test_audio_file):
    """Hash should be a 64-character hex string (SHA256)."""
    hash_value = compute_audio_hash(test_audio_file)

    assert isinstance(hash_value, str)
    assert len(hash_value) == 64
    assert all(c in "0123456789abcdef" for c in hash_value)


def test_compute_audio_hash_is_deterministic(test_audio_file):
    """Same file should produce same hash."""
    hash1 = compute_audio_hash(test_audio_file)
    hash2 = compute_audio_hash(test_audio_file)

    assert hash1 == hash2


def test_compute_audio_hash_different_files_differ(test_audio_file, another_audio_file):
    """Different files should produce different hashes."""
    hash1 = compute_audio_hash(test_audio_file)
    hash2 = compute_audio_hash(another_audio_file)

    assert hash1 != hash2
```

**Step 2: Run test to verify it fails**

Run: `cd python && pytest tests/test_audio_hash.py -v`
Expected: FAIL with ImportError

**Step 3: Write minimal implementation**

```python
# python/src/core/audio_hash.py
"""Audio hashing for override system."""
import hashlib
from pathlib import Path

import librosa


def compute_audio_hash(audio_path: str, duration: float = 30.0) -> str:
    """
    Compute SHA256 hash of first N seconds of audio.

    Args:
        audio_path: Path to audio file
        duration: Seconds of audio to hash (default: 30)

    Returns:
        64-character hex string (SHA256)
    """
    # Load first N seconds of audio
    y, sr = librosa.load(audio_path, sr=22050, duration=duration, mono=True)

    # Convert to bytes for hashing
    audio_bytes = y.tobytes()

    # Compute SHA256
    return hashlib.sha256(audio_bytes).hexdigest()
```

**Step 4: Run test to verify it passes**

Run: `cd python && pytest tests/test_audio_hash.py -v`
Expected: PASS

**Step 5: Commit**

```bash
git add python/src/core/audio_hash.py python/tests/test_audio_hash.py
git commit -m "$(cat <<'EOF'
feat: add audio hashing for override system

Computes SHA256 of first 30 seconds of audio for portable file identification.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3.2: Create Overrides Module - Storage

**Files:**
- Create: `python/src/core/overrides.py`
- Test: `python/tests/test_overrides.py` (create)

**Step 1: Write the failing test**

```python
# python/tests/test_overrides.py
"""Tests for override system."""
import pytest
from pathlib import Path
from src.core.overrides import OverrideStore


@pytest.fixture
def temp_db_path(tmp_path):
    return tmp_path / "overrides.db"


def test_override_store_set_and_get(temp_db_path):
    """Store and retrieve overrides by audio hash."""
    store = OverrideStore(temp_db_path)

    store.set_override("abc123", {"timing": "Build", "mood": "Dark"})

    result = store.get_override("abc123")
    assert result["timing"] == "Build"
    assert result["mood"] == "Dark"


def test_override_store_returns_none_if_missing(temp_db_path):
    """Returns None for unknown hashes."""
    store = OverrideStore(temp_db_path)

    result = store.get_override("unknown_hash")

    assert result is None


def test_override_store_update_existing(temp_db_path):
    """Updates overwrite existing overrides."""
    store = OverrideStore(temp_db_path)
    store.set_override("abc123", {"timing": "Build"})
    store.set_override("abc123", {"timing": "Peak", "mood": "Happy"})

    result = store.get_override("abc123")

    assert result["timing"] == "Peak"
    assert result["mood"] == "Happy"


def test_override_store_delete(temp_db_path):
    """Delete removes override."""
    store = OverrideStore(temp_db_path)
    store.set_override("abc123", {"timing": "Build"})
    store.delete_override("abc123")

    result = store.get_override("abc123")

    assert result is None


def test_override_store_persists(temp_db_path):
    """Overrides persist across instances."""
    store1 = OverrideStore(temp_db_path)
    store1.set_override("abc123", {"timing": "Peak"})

    store2 = OverrideStore(temp_db_path)
    result = store2.get_override("abc123")

    assert result["timing"] == "Peak"
```

**Step 2: Run test to verify it fails**

Run: `cd python && pytest tests/test_overrides.py -v`
Expected: FAIL with ImportError

**Step 3: Write minimal implementation**

```python
# python/src/core/overrides.py
"""Override system for per-track corrections."""
import json
import sqlite3
from pathlib import Path
from typing import Optional


class OverrideStore:
    """SQLite-backed storage for per-track tag overrides."""

    def __init__(self, path: Optional[Path] = None):
        """Initialize override store."""
        if path is None:
            path = Path.home() / ".cratebot" / "overrides.db"

        self.path = Path(path)
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self._init_db()

    def _init_db(self) -> None:
        """Create database schema if needed."""
        conn = sqlite3.connect(self.path)
        conn.execute("""
            CREATE TABLE IF NOT EXISTS overrides (
                audio_hash TEXT PRIMARY KEY,
                tags_json TEXT NOT NULL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)
        conn.commit()
        conn.close()

    def get_override(self, audio_hash: str) -> Optional[dict]:
        """Get override for an audio hash, or None if not found."""
        conn = sqlite3.connect(self.path)
        cursor = conn.execute(
            "SELECT tags_json FROM overrides WHERE audio_hash = ?",
            (audio_hash,)
        )
        row = cursor.fetchone()
        conn.close()

        if row is None:
            return None
        return json.loads(row[0])

    def set_override(self, audio_hash: str, tags: dict) -> None:
        """Set or update override for an audio hash."""
        conn = sqlite3.connect(self.path)
        conn.execute("""
            INSERT INTO overrides (audio_hash, tags_json, updated_at)
            VALUES (?, ?, CURRENT_TIMESTAMP)
            ON CONFLICT(audio_hash) DO UPDATE SET
                tags_json = excluded.tags_json,
                updated_at = CURRENT_TIMESTAMP
        """, (audio_hash, json.dumps(tags)))
        conn.commit()
        conn.close()

    def delete_override(self, audio_hash: str) -> None:
        """Delete override for an audio hash."""
        conn = sqlite3.connect(self.path)
        conn.execute("DELETE FROM overrides WHERE audio_hash = ?", (audio_hash,))
        conn.commit()
        conn.close()

    def list_overrides(self) -> list[tuple[str, dict]]:
        """List all overrides as (hash, tags) tuples."""
        conn = sqlite3.connect(self.path)
        cursor = conn.execute("SELECT audio_hash, tags_json FROM overrides")
        rows = cursor.fetchall()
        conn.close()
        return [(row[0], json.loads(row[1])) for row in rows]
```

**Step 4: Run test to verify it passes**

Run: `cd python && pytest tests/test_overrides.py -v`
Expected: PASS

**Step 5: Commit**

```bash
git add python/src/core/overrides.py python/tests/test_overrides.py
git commit -m "$(cat <<'EOF'
feat: add OverrideStore for per-track corrections

SQLite-backed storage for tag overrides keyed by audio hash.
Overrides persist and survive file moves/renames.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3.3: Integrate Overrides into AutoTagger

**Files:**
- Modify: `python/src/core/auto_tagger.py`
- Test: `python/tests/test_auto_tagger.py`

**Step 1: Write the failing test**

```python
def test_auto_tagger_uses_overrides(mock_predictor, temp_audio_file, temp_db_path):
    """AutoTagger uses override if available."""
    from src.core.overrides import OverrideStore
    from src.core.audio_hash import compute_audio_hash

    # Set up override
    audio_hash = compute_audio_hash(temp_audio_file)
    store = OverrideStore(temp_db_path)
    store.set_override(audio_hash, {"timing": "Release", "mood": "Dreamy"})

    # Mock predictor returns different values
    mock_predictor.predict_tags.return_value = {
        "genre": {"value": "House", "confidence": 0.9},
        "timing": {"value": "Peak", "confidence": 0.85},
        "mood": {"value": "Happy", "confidence": 0.8},
        "descriptive": {"tags": ["Driving"]},
    }

    tagger = AutoTagger(predictor=mock_predictor, override_db_path=temp_db_path)
    tags = tagger.tag_file(temp_audio_file)

    # Override values should be used
    assert tags["timing"] == "Release"
    assert tags["mood"] == "Dreamy"
    # Non-overridden values from model
    assert tags["genre"] == "House"
```

**Step 2: Run test to verify it fails**

Run: `cd python && pytest tests/test_auto_tagger.py::test_auto_tagger_uses_overrides -v`
Expected: FAIL (AutoTagger doesn't check overrides)

**Step 3: Write minimal implementation**

Update `python/src/core/auto_tagger.py`:

```python
from src.core.lexicon import Lexicon
from src.core.overrides import OverrideStore
from src.core.audio_hash import compute_audio_hash

class AutoTagger:
    def __init__(self, predictor=None, lexicon_path=None, override_db_path=None):
        self.predictor = predictor
        self.lexicon = Lexicon(lexicon_path)
        self.override_store = OverrideStore(override_db_path)
        self.tag_manager = TagManager()

    def tag_file(self, audio_path: str) -> dict:
        """Analyze and tag an audio file."""
        # Compute audio hash
        audio_hash = compute_audio_hash(audio_path)

        # Extract features
        features = self._extract_features(audio_path)

        # Get predictions
        predictions = self.predictor.predict_tags(features)

        # Convert to tags dict
        tags = {
            "genre": predictions["genre"]["value"],
            "timing": predictions["timing"]["value"],
            "mood": predictions["mood"]["value"],
            "descriptive": predictions["descriptive"]["tags"],
        }

        # Apply overrides (in canonical vocabulary)
        overrides = self.override_store.get_override(audio_hash)
        if overrides:
            for key, value in overrides.items():
                if key in tags:
                    tags[key] = value

        # Apply lexicon mapping (after overrides)
        tags = self.lexicon.apply_to_tags(tags)

        # Write to file
        self.tag_manager.write_tags(audio_path, tags)

        return tags
```

**Step 4: Run test to verify it passes**

Run: `cd python && pytest tests/test_auto_tagger.py::test_auto_tagger_uses_overrides -v`
Expected: PASS

**Step 5: Commit**

```bash
git add python/src/core/auto_tagger.py python/tests/test_auto_tagger.py
git commit -m "$(cat <<'EOF'
feat: integrate override system into AutoTagger

AutoTagger checks for per-track overrides before applying lexicon.
Overrides stored in canonical vocabulary, mapped by lexicon before write.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Phase 4: Ship Pre-trained Model

### Task 4.1: Create Model Bundling Script

**Files:**
- Create: `python/scripts/bundle_model.py`
- Test: Manual verification

**Step 1: Write the script**

```python
#!/usr/bin/env python3
# python/scripts/bundle_model.py
"""Bundle trained model for distribution."""
import shutil
import json
from pathlib import Path
from datetime import datetime

def bundle_model(source_path: Path, bundle_dir: Path) -> None:
    """
    Bundle a trained model for distribution.

    Copies model file and metadata to bundle directory.
    """
    bundle_dir.mkdir(parents=True, exist_ok=True)

    # Copy model file
    dest_model = bundle_dir / "cratebot_v2.pkl"
    shutil.copy(source_path, dest_model)

    # Copy metadata if exists
    meta_source = source_path.with_suffix(".pkl.meta.json")
    if meta_source.exists():
        shutil.copy(meta_source, bundle_dir / "cratebot_v2.pkl.meta.json")

    # Create bundle manifest
    manifest = {
        "version": "2.0",
        "taxonomy": {
            "genre": ["House", "Techno", "Jungle/DnB", "Rap", "DiscoFunk",
                     "Breakbeat", "Ambient", "Dubstep", "Trance"],
            "timing": ["Start", "Build", "Peak", "Sustain", "Release"],
            "mood": ["Happy", "Dark", "Emotional", "Aggressive", "Dreamy", "Groovy"],
        },
        "bundled_at": datetime.utcnow().isoformat(),
    }

    manifest_path = bundle_dir / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2))

    print(f"Model bundled to {bundle_dir}")
    print(f"  - Model: {dest_model}")
    print(f"  - Manifest: {manifest_path}")


if __name__ == "__main__":
    import sys

    if len(sys.argv) < 2:
        print("Usage: python bundle_model.py <source_model.pkl> [bundle_dir]")
        sys.exit(1)

    source = Path(sys.argv[1])
    bundle_dir = Path(sys.argv[2]) if len(sys.argv) > 2 else Path("desktop/resources/models")

    bundle_model(source, bundle_dir)
```

**Step 2: Make executable**

Run: `chmod +x python/scripts/bundle_model.py`

**Step 3: Commit**

```bash
git add python/scripts/bundle_model.py
git commit -m "$(cat <<'EOF'
feat: add model bundling script for distribution

Creates versioned model bundle with manifest for desktop app.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4.2: Update Config to Use Bundled Model

**Files:**
- Modify: `python/src/core/config.py`
- Test: `python/tests/test_config.py`

**Step 1: Write the failing test**

```python
def test_config_finds_bundled_model(tmp_path):
    """Config locates bundled model if user hasn't trained."""
    # Create fake bundled model
    bundle_dir = tmp_path / "resources" / "models"
    bundle_dir.mkdir(parents=True)
    (bundle_dir / "cratebot_v2.pkl").write_text("fake model")

    config = Config(user_dir=tmp_path / ".cratebot", bundle_dir=bundle_dir)

    model_path = config.get_model_path()

    assert model_path == bundle_dir / "cratebot_v2.pkl"


def test_config_prefers_user_model(tmp_path):
    """User-trained model takes precedence over bundled."""
    # Create both bundled and user model
    bundle_dir = tmp_path / "resources" / "models"
    bundle_dir.mkdir(parents=True)
    (bundle_dir / "cratebot_v2.pkl").write_text("bundled")

    user_dir = tmp_path / ".cratebot" / "models"
    user_dir.mkdir(parents=True)
    (user_dir / "cratebot.pkl").write_text("user trained")

    config = Config(user_dir=tmp_path / ".cratebot", bundle_dir=bundle_dir)

    model_path = config.get_model_path()

    assert model_path == user_dir / "cratebot.pkl"
```

**Step 2: Run test to verify it fails**

Run: `cd python && pytest tests/test_config.py::test_config_finds_bundled_model -v`
Expected: FAIL

**Step 3: Write minimal implementation**

Update `python/src/core/config.py`:

```python
class Config:
    def __init__(self, user_dir=None, bundle_dir=None):
        self.user_dir = Path(user_dir) if user_dir else Path.home() / ".cratebot"
        self.bundle_dir = Path(bundle_dir) if bundle_dir else self._find_bundle_dir()

    def _find_bundle_dir(self) -> Path:
        """Locate bundled resources directory."""
        # Check relative to this file (for installed package)
        pkg_resources = Path(__file__).parent.parent.parent / "resources" / "models"
        if pkg_resources.exists():
            return pkg_resources

        # Check desktop app location
        desktop_resources = Path(__file__).parent.parent.parent.parent / "desktop" / "resources" / "models"
        if desktop_resources.exists():
            return desktop_resources

        return Path("/nonexistent")

    def get_model_path(self) -> Path:
        """Get path to model, preferring user-trained over bundled."""
        # Check for user-trained model first
        user_model = self.user_dir / "models" / "cratebot.pkl"
        if user_model.exists():
            return user_model

        # Fall back to bundled model
        bundled_model = self.bundle_dir / "cratebot_v2.pkl"
        if bundled_model.exists():
            return bundled_model

        # No model found
        raise FileNotFoundError("No model found. Run training or install bundled model.")
```

**Step 4: Run test to verify it passes**

Run: `cd python && pytest tests/test_config.py -v`
Expected: PASS

**Step 5: Commit**

```bash
git add python/src/core/config.py python/tests/test_config.py
git commit -m "$(cat <<'EOF'
feat: config supports bundled model fallback

Users without trained models use bundled v2 model automatically.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>
EOF
)"
```

---

## Summary

This plan implements the lexicon/taxonomy redesign in 4 phases:

| Phase | Tasks | New Files | Modified Files |
|-------|-------|-----------|----------------|
| 1. Taxonomy | 1.1-1.4 | `test_constants.py` | `constants.py`, `tag_predictor.py`, `tag_manager.py` |
| 2. Lexicon | 2.1-2.3 | `lexicon.py`, `test_lexicon.py` | `auto_tagger.py` |
| 3. Override | 3.1-3.3 | `audio_hash.py`, `overrides.py`, `test_*.py` | `auto_tagger.py` |
| 4. Bundle | 4.1-4.2 | `bundle_model.py` | `config.py` |

**After implementation:**
1. Relabel training data with new taxonomy
2. Retrain model
3. Bundle with `python scripts/bundle_model.py`
4. Test end-to-end flow

---

## Open Items (Not in Scope)

- Lexicon UI in Settings panel (frontend work)
- Override UI in RefineTab (frontend work)
- Subgenre support (future enhancement)
- "Learn from corrections" (requires retraining infrastructure)
