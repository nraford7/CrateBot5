# Training Bug Fixes - Session Notes

**Date:** 2026-01-10
**Status:** Fixed, awaiting user verification

---

## Issues Reported

1. **Training fails with "Only 0 valid samples. Need at least 50."**
   - Training races through files without collecting any valid samples
   - No features were extracted

2. **"Scan & Select Tags" button does nothing**
   - Clicking the button had no visible effect
   - Errors were caught silently with no user feedback

3. **LexiconEditor has limited ID3 tag options**
   - Only showed 5 ID3 frames
   - User requested comprehensive list with human-readable names

---

## Root Cause Analysis

### Bug 1: Case-Sensitive Tag Matching (Primary Issue)

**Location:** `backend/api_server.py:571-582`

**Problem:** The backend training code used case-sensitive `in` comparison:
```python
if genre in selected_tags.get('genre', []):  # Case-sensitive!
```

But `TagScanner.scan_directory()` normalizes tags to title case via `merge_similar_tags()` → `find_canonical_tag()` → `tag.title()`.

**Example failure:**
1. File has `TALB="PEAK"`
2. Scanner returns `"Peak"` (title-cased)
3. User selects `"Peak"`
4. Training reads `"PEAK"` from file
5. `"PEAK" in ["Peak"]` → **False**
6. Zero valid samples

**Fix:** Use `matches_selected_tag()` function for case-insensitive fuzzy matching.

### Bug 2: Missing Comments Check

**Location:** `backend/api_server.py:571-582`

**Problem:** Only checked `genre` and `album`, not `comments`.

**Fix:** Added comments field validation with comma-split handling.

### Bug 3: Missing Lexicon Parameter

**Location:** `backend/api_server.py:567`

**Problem:** `read_tags()` called without lexicon parameter.

**Fix:** Pass `lexicon=tagger.lexicon` to `read_tags()`.

### Bug 4: Silent Scan Errors

**Location:** `desktop/src/components/TrainTab.tsx:100-102`

**Problem:** Errors caught silently with no user feedback.

**Fix:** Show toast notification on scan failure.

### Bug 5: Missing PyInstaller Hidden Import

**Location:** `cratebot_server.spec`

**Problem:** `core.utils` module (containing `matches_selected_tag`) was not included in the bundled server binary.

**Fix:** Added `'core.utils'` and `'src.core.utils'` to hidden imports.

---

## Commits

| Commit | Description |
|--------|-------------|
| `9bdb5a74` | fix(training): use case-insensitive tag matching with comments support |
| `b39d1a2e` | fix(ui): display scan errors and add comprehensive ID3 tag list |
| `78407cd6` | fix(build): add core.utils to PyInstaller hidden imports |

---

## Files Modified

### Backend
- `backend/api_server.py` - Fixed tag matching logic, added debug logging
- `backend/tests/test_training_tag_matching.py` - Added integration tests (NEW)

### Frontend
- `desktop/src/components/TrainTab.tsx` - Added toast on scan error
- `desktop/src/components/settings/LexiconEditor.tsx` - Added 40+ ID3 frames

### Build
- `cratebot_server.spec` - Added core.utils to hidden imports

### Documentation
- `docs/plans/2026-01-09-fix-training-tag-matching.md` - Implementation plan

---

## Verification

### Tested Successfully
- Tag matching logic: **90% match rate** on 100 sample files
- Scan endpoint: Returns all 2122 files with correct tag data
- Unit tests: All 4 new tests pass, 103 existing tests pass

### Awaiting User Verification
- Full training workflow in bundled app
- Toast notifications appearing on errors
- LexiconEditor showing all ID3 frames

---

## Technical Details

### Tag Matching Logic

The `matches_selected_tag()` function in `core/utils.py`:
1. Normalizes both values to lowercase
2. Checks for exact normalized match
3. Falls back to fuzzy matching (similarity >= 0.85)

```python
def matches_selected_tag(value: str, selected_tags: Set[str], threshold: float = 0.85) -> bool:
    if not value:
        return False
    normalized = normalize_tag(value)
    for selected in selected_tags:
        if normalize_tag(selected) == normalized:
            return True
        if similarity(value, selected) >= threshold:
            return True
    return False
```

### ID3 Frames Added to LexiconEditor

| Group | Count | Examples |
|-------|-------|----------|
| Primary | 6 | TCON, TALB, TIT1, TIT2, TIT3, COMM |
| Classification | 8 | TCAT, GRP1, MVNM, MVIN, TKEY, TBPM, TLAN, TMOO |
| Artist | 6 | TPE1, TPE2, TPE3, TPE4, TCOM, TEXT |
| Sorting | 5 | TSOT, TSOA, TSOP, TSO2, TSOC |
| Publishing | 6 | TPUB, TCOP, TENC, TOWN, WCOP, WPUB |
| Date | 4 | TDRC, TDRL, TYER, TDAT |
| Track | 3 | TRCK, TPOS, TLEN |
| Custom | 6 | TXXX:CRATEBOT_*, TXXX:ENERGY, TXXX:RATING |

---

## Next Steps

1. User to verify training works in rebuilt app
2. If successful, consider adding copyable toast messages (user request)
3. Remove debug logging from api_server.py after verification
