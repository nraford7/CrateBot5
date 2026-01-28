# Lexicon & Taxonomy Redesign - Implementation Complete

**Date:** 2026-01-09
**Commits:** d42fd2c5..1b75993a (14 commits)
**Status:** Complete

## Summary

Transformed CrateBot from a "train your own model" tool to a "customize your vocabulary" tool by implementing:

1. **New Taxonomy Structure** - 4 classifiers instead of 3
2. **Lexicon System** - User vocabulary customization
3. **Override System** - Per-track corrections via audio hash
4. **Bundled Model Support** - Pre-trained model fallback

## Changes by Phase

### Phase 1: Taxonomy Restructure

| File | Change |
|------|--------|
| `python/src/core/constants.py` | Added CANONICAL_GENRES (9), CANONICAL_TIMING (5), CANONICAL_MOODS (6), TAXONOMY_ID3_MAPPING |
| `python/src/models/tag_predictor.py` | Updated to 4-classifier architecture (genre, timing, mood, descriptive) |
| `python/src/core/tag_manager.py` | Updated write_tags/read_tags for new taxonomy (timing→TALB, mood→TIT1, descriptive→COMM) |

### Phase 2: Lexicon System

| File | Change |
|------|--------|
| `python/src/core/lexicon.py` | New - JSON-backed vocabulary customization (~/.cratebot/lexicon.json) |
| `python/src/core/auto_tagger.py` | Integrated Lexicon into tagging pipeline |

### Phase 3: Override System

| File | Change |
|------|--------|
| `python/src/core/audio_hash.py` | New - SHA256 hash of audio content (first 30 seconds) |
| `python/src/core/overrides.py` | New - SQLite-backed per-track corrections (~/.cratebot/overrides.db) |
| `python/src/core/auto_tagger.py` | Integrated Override system (checked before lexicon mapping) |

### Phase 4: Pre-trained Model Support

| File | Change |
|------|--------|
| `python/scripts/bundle_model.py` | New - Packaging script for model distribution |
| `python/src/core/config.py` | Added get_model_path() with bundled model fallback |

### Phase 5: Lexicon ID3 Frame Configuration

| File | Change |
|------|--------|
| `python/src/core/lexicon.py` | Restructured to nested format with `id3_frame` + `mappings` per category; added `get_id3_frame()`, `set_id3_frame()`, `_migrate_if_needed()` |
| `python/src/core/tag_manager.py` | Added `_write_to_frame()`, `_read_from_frame()`, `_get_frame()` helpers; `read_tags()` and `write_tags()` now accept `lexicon` parameter |
| `python/src/core/auto_tagger.py` | All `read_tags()`/`write_tags()` calls now pass `self.lexicon` |
| `python/tests/test_lexicon.py` | Added `TestLexiconID3Mapping` class (5 new tests) |

## Bug Fixes (Post-Implementation)

### Fix 1: TIT1 Field Collision (ff3cba1c)
- **Issue:** Both `work` and `mood` wrote to TIT1, causing silent overwrites
- **Fix:** Skip `work`→TIT1 when `mood` is present; mood takes precedence per new taxonomy

### Fix 2: scipy Compatibility (875808bf)
- **Issue:** `scipy.signal.hann` removed in scipy 1.13+, breaking CLAP initialization
- **Fix:** Added compatibility shim: `scipy.signal.hann = scipy.signal.windows.hann`

### Fix 3: Test Dimension Mismatch (875808bf)
- **Issue:** Tests expected 97 dimensions but analyzer now produces 184
- **Fix:** Use dynamic `AudioAnalyzer.FEATURE_VECTOR_SIZE` instead of hardcoded value

### Fix 4: CLAP Model Architecture (1b75993a)
- **Issue:** Code used `HTSAT-base` (1024 dim) but checkpoint `630k-audioset-best.pt` uses `HTSAT-tiny` (768 dim)
- **Fix:** Changed to `amodel='HTSAT-tiny'` in CLAP_Module initialization

## Test Results

```
103 passed, 3 skipped, 0 failed
```

### New Test Files
- `python/tests/test_constants.py` - 4 tests
- `python/tests/test_lexicon.py` - 21 tests (5 new for ID3 mapping)
- `python/tests/test_audio_hash.py` - 5 tests
- `python/tests/test_overrides.py` - 9 tests
- `python/tests/test_config.py` - 6 tests

### Feature Vector Composition (184 dimensions)
| Component | Dimensions |
|-----------|------------|
| Librosa (base) | 57 |
| Essentia | 8 |
| PANNs | 32 |
| CLAP | 32 |
| Jamendo | 55 |
| **Total** | **184** |

## ID3 Tag Mapping (New Taxonomy)

| Field | Default ID3 Frame | Values |
|-------|-------------------|--------|
| genre | TCON | House, Techno, Jungle/DnB, Rap, DiscoFunk, Breakbeat, Ambient, Dubstep, Trance |
| timing | TALB | Start, Build, Peak, Sustain, Release |
| mood | TIT1 | Happy, Dark, Emotional, Aggressive, Dreamy, Groovy |
| descriptive | COMM | Multi-label (comma-separated) |

## ID3 Frame Configuration

Users can customize which ID3 frames each taxonomy field writes to via the Lexicon. This enables compatibility with different DJ software (Traktor, Rekordbox, Serato) that may read different fields.

### Lexicon File Structure (~/.cratebot/lexicon.json)

```json
{
  "genre": {
    "id3_frame": "TCON",
    "mappings": {"House": "Deep House"}
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

### Customizing Frames via API

```python
from core.lexicon import Lexicon

lexicon = Lexicon()

# Change timing to use custom TXXX frame (preserves Album field)
lexicon.set_id3_frame("timing", "TXXX:CRATEBOT_TIMING")

# Change mood to custom frame (preserves Content Group/Work field)
lexicon.set_id3_frame("mood", "TXXX:CRATEBOT_MOOD")

lexicon.save()
```

### Supported Frame Types

- Standard frames: `TCON`, `TALB`, `TIT1`, `COMM`
- Custom TXXX frames: `TXXX:CUSTOM_DESC` (writes to TXXX with specified description)

## Backwards Compatibility

- TagManager reads both old (`album`, `comments`) and new (`timing`, `mood`, `descriptive`) field names
- New fields take precedence when both are present
- Model format version bumped to 2.0
- TIT1 priority: mood > work > content_group
- Old flat lexicon format (`{"timing": {"Peak": "Climax"}}`) auto-migrates to new nested format

## Commit History

| Commit | Description |
|--------|-------------|
| d42fd2c5 | feat: add canonical taxonomy constants |
| 5ed509a9 | feat: update TagPredictor to 4-classifier architecture |
| d4addcf5 | feat: update TagManager.write_tags for new taxonomy |
| 1d5a119d | feat: update TagManager.read_tags for new taxonomy |
| adf13acd | feat: add Lexicon module for vocabulary customization |
| 466c557c | feat: integrate Lexicon into AutoTagger pipeline |
| 5cbee04d | feat: add audio hash utility for override system |
| b96b464b | feat: add OverrideStore for per-track corrections |
| b05804db | feat: integrate override system into AutoTagger |
| feb5d684 | feat: add model bundling script |
| 77d7b2ee | feat: add get_model_path to Config |
| ff3cba1c | fix: prevent TIT1 collision between work and mood |
| 875808bf | fix: resolve audio analyzer test failures |
| 1b75993a | fix: use correct HTSAT-tiny architecture for CLAP |

### Phase 6: Frontend Integration

| File | Change |
|------|--------|
| `backend/api_server.py` | Added GET/PUT `/api/v1/lexicon`, GET/POST `/api/v1/override` endpoints; integrated lexicon with tag read/write |
| `desktop/src/api/client.ts` | Added `getLexicon()`, `updateLexicon()`, `saveOverride()`, `getOverride()` methods with types |
| `desktop/src/components/settings/LexiconEditor.tsx` | New - UI for vocabulary mappings and ID3 frame configuration per category |
| `desktop/src/components/SettingsPanel.tsx` | Added "Lexicon & Vocabulary" section with LexiconEditor |
| `desktop/src/hooks/useRefinement.ts` | Updated for 4-field taxonomy; added `saveAsCorrection()`, tracks `hasOverride` |
| `desktop/src/components/refine/TagEditor.tsx` | Rewritten for 4 fields: Genre, Timing, Mood, Descriptive (multi-select) |
| `desktop/src/components/RefineTab.tsx` | Updated TagEditor usage; added "Save as Correction" button |

### Phase 7: Critical Bug Fixes & UX Improvements

| File | Change |
|------|--------|
| `python/src/core/audio_player.py` | Lazy pygame import pattern to prevent SDL crashes at startup |
| `python/requirements.txt` | Removed pygame dependency (audio playback handled by Electron) |
| `cratebot_server.spec` | Added recursion limit fix for PyInstaller |
| `desktop/electron/main.ts` | Redesigned splash screen with "Vinyl Warmth" theme; increased server timeout to 30s |
| `desktop/src/components/SetupWizard.tsx` | Added "Train Custom Model" option to skip model loading |
| `desktop/src/stores/appStore.ts` | Added `pendingView` state for post-setup navigation |
| `desktop/src/App.tsx` | Consume `pendingView` to navigate to Train tab after setup |
| `desktop/index.html` | Updated loading screen with new taxonomy tagline |

### Fix 5: SDL 1.2 Crash on macOS ARM64 (308368f4)
- **Issue:** App crashed on startup with `libSDL-1.2.0.dylib` abort during `dllinit`
- **Root Cause:** Essentia (not pygame) bundles SDL 1.2 which is incompatible with ARM64 Mac
- **Fix:**
  - Removed `libSDL-1.2.0.dylib` from essentia in venv
  - Cleared PyInstaller bincache to remove cached SDL 1.2
  - Rebuilt `cratebot-server` binary without SDL 1.2
  - Removed pygame from requirements.txt (not used by server)

### Fix 6: Splash Screen Styling (862d71d4)
- **Issue:** Splash screen used old blue/slate styling, didn't match app theme
- **Fix:** Redesigned splash screen with "Vinyl Warmth" theme:
  - Background: `#1a1918` (surface-dark)
  - Amber accent: `#f59e0b`
  - DM Sans font
  - Centered vertical layout with vinyl disc icon
  - Taxonomy tagline: "GENRE • TIMING • MOOD • DESCRIPTIVE"

### Fix 7: Train Custom Model Option (1397c8e2)
- **Issue:** Users couldn't train a model without first loading one (chicken-and-egg for first-time users)
- **Fix:** Added "Train Custom Model" button in Setup Wizard that:
  - Skips model loading requirement
  - Completes setup and navigates directly to Train tab
  - Uses `pendingView` state in appStore

### Fix 8: Server Startup Timeout (862d71d4)
- **Issue:** Server takes 8-15 seconds to start (loading ML models), causing timeout
- **Fix:** Increased Electron server timeout from 10s to 30s

## Commit History (Phase 7)

| Commit | Description |
|--------|-------------|
| 1397c8e2 | fix: resolve critical startup issues (SDL lazy load, Train option) |
| c4616774 | fix: update splash screen and remove pygame dependency |
| 308368f4 | fix: remove SDL 1.2 from essentia to prevent ARM64 crash |
| 862d71d4 | fix: restyle splash screen to match Vinyl Warmth theme |

## Next Steps

### Immediate (Model & Data)
1. Relabel training data with new taxonomy (genre/timing/mood/descriptive)
2. Retrain model on new taxonomy
3. Bundle trained model with `python scripts/bundle_model.py`

### Completed
- ~~Add Lexicon UI to Settings panel~~ ✅ (Phase 6)
- ~~Add Override UI to RefineTab~~ ✅ (Phase 6)
- ~~Update user documentation for new taxonomy~~ ✅ (this document)
- ~~Document lexicon customization workflow~~ ✅ (ID3 Frame Configuration section)
- ~~Fix SDL crash on macOS ARM64~~ ✅ (Phase 7)
- ~~Update splash screen to match app theme~~ ✅ (Phase 7)
- ~~Add Train Custom Model option~~ ✅ (Phase 7)
