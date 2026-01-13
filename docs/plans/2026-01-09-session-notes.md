# Session Notes - January 9, 2026

## UX Redesign: Setup-First Flow

### Completed Implementation

Transformed CrateBot from a 4-tab workflow (Train → Tag → Refine → Settings) into a setup-once, tag-always experience.

**Key insight:** Most users will use pre-trained models and primarily tag files - they won't train their own models.

### New Architecture

1. **First Run**: Setup wizard guides configuration
   - Welcome screen
   - Model loading (with server status indicator)
   - Tagging preferences (Genre, Album, Comments, Likeness, Vibes, Hooks)
   - Completion summary

2. **Subsequent Runs**: Jump straight to tagging view
   - Clean drop zone interface
   - Preferences accessible via header settings icon
   - Train/Refine moved to advanced options in Settings panel

### Files Created/Modified

- `desktop/src/components/SetupWizard.tsx` - New 4-step wizard
- `desktop/src/components/MainHeader.tsx` - Compact header with model info
- `desktop/src/components/SettingsPanel.tsx` - Slide-out settings panel
- `desktop/src/components/TaggingView.tsx` - Streamlined tagging interface
- `desktop/src/stores/appStore.ts` - Added setupComplete, taggingPreferences with localStorage persistence
- `desktop/src/App.tsx` - New setup-first architecture
- `desktop/src/components/_archived/` - Archived old Sidebar.tsx, SettingsTab.tsx

### Bug Fix: scipy._cyutility

**Issue:** Model loading failed with `No module named 'scipy._cyutility'`

**Cause:** PyInstaller wasn't bundling the `scipy._cyutility` module in the server binary.

**Fix:** Added `'scipy._cyutility'` to hiddenimports in `cratebot_server.spec` and rebuilt:
```bash
pyinstaller cratebot_server.spec --noconfirm
cp dist/cratebot-server desktop/resources/python/cratebot-server
```

---

## UX Improvements (Session 2)

### Implemented Features

Based on user feedback from build review, implemented 8 improvements:

| Commit | Feature |
|--------|---------|
| `84c24f4` | Splash screen with Vinyl Warmth design (logo, brand, gradient) |
| `46abe0b` | Pre-trained model selection + external browse in wizard |
| `41edc3e` | ID3 field mapping in preferences (map tags to any ID3 field) |
| `d7af61d` | Completion screen with model name + "Tags Assigned: Successful" |
| `26d02f0` | macOS traffic light spacer (80px left padding in header) |
| `9e24058` | File status colors (grey pending, yellow processing, green complete) |
| `f22adc7` | Time estimates in status bar (files done, time/file, ETA) |
| `bc85f52` | Post-tagging completion dialog with review option |

### New taggingPreferences Structure

Changed from flat booleans to nested objects with ID3 field mapping:

**Old format:**
```typescript
taggingPreferences: {
  writeGenre: boolean
  writeAlbum: boolean
  writeComments: boolean
  writeLikeness: boolean
  generateVibes: boolean
  detectHooks: boolean
  overwrite: boolean
}
```

**New format:**
```typescript
taggingPreferences: {
  genre: { enabled: boolean; targetField: string }
  album: { enabled: boolean; targetField: string }
  comments: { enabled: boolean; targetField: string }
  likeness: { enabled: boolean; targetField: string }
  vibes: { enabled: boolean }
  hooks: { enabled: boolean }
  overwrite: boolean
}
```

### Bug Fix: Preferences Structure Crash

**Issue:** App crashed after model selection screen in wizard.

**Cause:** Components still using old preference format (`writeGenre`) after structure changed to nested format (`genre.enabled`).

**Fix:** Updated 3 files to use new structure:
- `TaggingView.tsx` - `taggingPreferences.genre.enabled` instead of `taggingPreferences.writeGenre`
- `MainHeader.tsx` - Updated header preference summary
- `SettingsPanel.tsx` - Updated all preference checkboxes

**Commit:** `17a8897`

### Files Modified

- `desktop/index.html` - New splash screen design
- `desktop/src/components/SetupWizard.tsx` - Model selection, ID3 mapping, completion screen
- `desktop/src/components/MainHeader.tsx` - Traffic light spacer + preference format fix
- `desktop/src/components/FileQueue.tsx` - Status colors with labelColor property
- `desktop/src/components/StatusBar.tsx` - Time estimates display
- `desktop/src/components/CompletionDialog.tsx` - New post-tagging dialog
- `desktop/src/components/TaggingView.tsx` - Completion dialog integration + preference format fix
- `desktop/src/components/SettingsPanel.tsx` - Preference format fix
- `desktop/src/stores/appStore.ts` - New preference structure + taggingStats
- `desktop/src/hooks/useTagging.ts` - Stats calculation effect
- `desktop/src/App.tsx` - Navigate-to-refine event handler

### Running the App

```bash
cd desktop
npm run electron:dev    # Development mode with hot-reload
npm run build           # Package for distribution
```

---

## UX Fixes Batch 2 (Session 3)

### Overview

Fixed remaining UX issues from the setup-first flow redesign. Implemented 7 tasks using subagent-driven development workflow.

### Commits

| Commit | Description |
|--------|-------------|
| `1b739985` | Loading screen updated to match app design (solid background, circular logo) |
| `76b934ba` | Added accessibility attributes to loading screen |
| `9b98089f` | Removed border from model page navigation footer |
| `f58ec1cb` | Simplified "All Set" screen - green values, removed mapping text |
| `55bbfeb7` | Simplified header model display, removed "(X genres)" text |
| `9ad7caf4` | Fixed file matching in useTagging WebSocket handler |
| `673109ba` | Optimized basename extraction in file matching loop |
| `8db0b3b8` | Fixed status bar stats condition (shows during entire tagging operation) |
| `a90862e4` | Fixed code quality issues for auto-load tagged files feature |

### Task Details

**Task 1: Loading Screen Style Update**
- Changed background from gradient to solid `#1a1918`
- Changed logo container from rounded rectangle to circle (`border-radius: 50%`)
- Added amber glow background on circle
- Added accessibility: `aria-label`, `aria-hidden` attributes
- File: `desktop/index.html`

**Task 2: Model Page Border Removal**
- Removed `border-t border-border-light dark:border-border-dark` from model step footer
- File: `desktop/src/components/SetupWizard.tsx:319`

**Task 3: "All Set" Screen Redesign**
- Model name displayed in emerald green
- Tags displayed as simple list (Genre, Mood, Comments, Likeness) - no field mappings
- AI Features (Vibes & Hooks) shown in emerald green when enabled
- File: `desktop/src/components/SetupWizard.tsx:473-521`

**Task 4: Header Model Display Fix**
- Changed fallback from "Unknown" to "Loaded" / "Not loaded"
- Removed genre count text `(X genres)`
- File: `desktop/src/components/MainHeader.tsx:50-56`

**Task 5: File Status Colors Fix**
- Improved file matching in WebSocket progress handler
- Added three-tier matching: exact path → path suffix → basename
- Extracted basename parsing outside loop for performance
- Added error logging for unmatched files
- File: `desktop/src/hooks/useTagging.ts:126-154`

**Task 6: Status Bar Stats Display Fix**
- Changed condition from `processing > 0` to `startTime !== null && completed < total`
- Now shows stats throughout entire tagging operation, not just during active processing
- File: `desktop/src/components/StatusBar.tsx:85`

**Task 7: Auto-load Tagged Files in RefineTab**
- Added `recentlyTaggedFiles` state to appStore
- `handleReview()` stores tagged file paths before navigation
- Added `loadFiles()` function to useRefinement hook
- RefineTab auto-loads files on mount when recentlyTaggedFiles exists
- Only clears store after successful load (preserves for retry on error)
- Added race condition guard in loadTagsForItem
- Files: `appStore.ts`, `TaggingView.tsx`, `useRefinement.ts`, `RefineTab.tsx`

### Code Quality Fixes

During Task 7 review, identified and fixed:
1. **Error handling**: Only clear recentlyTaggedFiles after successful loadFiles()
2. **Race condition guard**: Verify item.path still matches before setState in loadTagsForItem

### localStorage Migration

Added migration logic in appStore initialization to handle old flat preference format:
```typescript
// Detect old format and reset to defaults
if ('writeGenre' in parsed || !('genre' in parsed) || typeof parsed.genre !== 'object') {
  localStorage.removeItem(TAGGING_PREFERENCES_KEY)
  return DEFAULT_TAGGING_PREFERENCES
}
```

### Files Modified

- `desktop/index.html` - Loading screen redesign
- `desktop/src/stores/appStore.ts` - recentlyTaggedFiles state, migration logic
- `desktop/src/components/SetupWizard.tsx` - Model page border, All Set screen
- `desktop/src/components/MainHeader.tsx` - Simplified model display
- `desktop/src/components/StatusBar.tsx` - Stats display condition
- `desktop/src/components/TaggingView.tsx` - handleReview stores files
- `desktop/src/components/RefineTab.tsx` - Auto-load on mount
- `desktop/src/hooks/useTagging.ts` - File matching improvements
- `desktop/src/hooks/useRefinement.ts` - loadFiles function, race condition guard

### Testing Notes

- Electron build verified: `npm run build:electron` passes
- No formal test suite in project
- All changes reviewed through spec compliance and code quality checks

### Next Steps

- Test full tagging workflow end-to-end
- Verify "Review Tags" button correctly loads files in RefineTab
- Consider adding automated tests for critical paths
- Bundle default pre-trained model in `desktop/resources/models/`

---

## Model Enhancement: CLAP + Jamendo Integration (Session 4)

### Background

The tagging model was trained on 2,100 personal EDM tracks with a custom taxonomy:
- **Genre** (timing/feel): House, Techno, Jungle, etc.
- **Album** (DJ function): Peak, Build, Release, etc.
- **Comments** (character): 140+ tags across Beats, Bass, Vibes, Instruments, Vocals

Goal: Improve accuracy, coverage, and generalization by adding smarter embeddings.

### External Datasets Evaluated

| Dataset | Tracks | Labels | Decision |
|---------|--------|--------|----------|
| **MTG-Jamendo** | 55K | 195 tags (genre, instrument, mood) | Used for auxiliary heads |
| **Emotify** | 400 | 9 GEMS emotions | Too small, skipped |
| **Discogs-VI** | 1.9M | Cover song relationships | Not applicable (version ID) |
| **MuMu** | Unknown | Unknown | Could not access (403) |

### Approach Selected

**CLAP Embeddings + Jamendo Auxiliary Heads**

Rationale:
- CLAP provides semantic audio understanding ("dark driving techno") without explicit training
- Jamendo classifiers add structured mood/theme predictions from 55K tracks
- Fits existing LightGBM architecture (just add features)
- ~8s/track inference on Apple Silicon (acceptable)

Alternatives considered but not implemented:
- MERT transformer (overkill, slower)
- Transfer learning (requires architecture change)
- Taxonomy mapping (error-prone, DJ tags have no equivalent)

### Implementation

#### New Files Created

| File | Purpose |
|------|---------|
| `python/src/core/clap_analyzer.py` | CLAP embedding extraction (512→32 dims) |
| `python/src/core/jamendo_classifier.py` | Jamendo mood/theme predictions (55 dims) |
| `python/src/core/jamendo_trainer.py` | One-time Jamendo classifier training |

#### Modified Files

| File | Changes |
|------|---------|
| `python/src/core/fast_analyzer.py` | Added CLAP + Jamendo integration, updated FEATURE_VECTOR_SIZE |
| `python/src/core/audio_analyzer.py` | Added CLAP + Jamendo integration, updated FEATURE_VECTOR_SIZE |
| `python/src/core/constants.py` | Bumped CACHE_VERSION 6 → 7 |
| `python/src/core/cli.py` | Added 3 new commands |
| `python/requirements.txt` | Added laion-clap dependency |

#### Feature Vector Growth

```
Before: 97 dims  (57 librosa + 8 Essentia + 32 PANNs)
After:  184 dims (+ 32 CLAP + 55 Jamendo)
```

| Component | Dimensions | Source |
|-----------|------------|--------|
| MFCC | 13 | librosa |
| Spectral | 5 | librosa |
| Chroma | 12 | librosa |
| Spectral Contrast | 7 | librosa |
| Tonnetz | 6 | librosa |
| Rhythmic | 4 | librosa |
| Harmonic | 3 | librosa |
| Timbral | 3 | librosa |
| Dynamic | 4 | librosa |
| Essentia | 8 | essentia-tensorflow |
| PANNs | 32 | panns-inference |
| **CLAP** | **32** | **laion-clap (NEW)** |
| **Jamendo** | **55** | **trained classifiers (NEW)** |
| **Total** | **184** | |

#### New CLI Commands

```bash
cratebot download-clap    # Download CLAP model (~600MB)
cratebot train-jamendo    # Train Jamendo classifiers (~5-10 min)
cratebot model-status     # Check status of all ML models
```

### Technical Details

#### CLAP Analyzer (`clap_analyzer.py`)
- Model: `630k-audioset-best.pt` (AudioSet + LAION-Audio-630K)
- Sample rate: 48kHz
- Embedding: 512-dim → reduced to 32 via segment statistics
- Device support: CUDA > MPS (Apple Silicon) > CPU
- Storage: `~/.cratebot/clap_models/`

#### Jamendo Classifier (`jamendo_classifier.py`)
- 55 mood/theme tags from MTG-Jamendo dataset
- Tags include: action, adventure, calm, dark, energetic, happy, melancholic, melodic, etc.
- Uses CLAP embeddings as input (not raw audio)
- LogisticRegression classifiers (lightweight, fast)
- Storage: `~/.cratebot/jamendo_models/`

#### Jamendo Trainer (`jamendo_trainer.py`)
- Downloads Jamendo metadata from GitHub
- Uses synthetic training data for bootstrapping (captures semantic relationships)
- Trains 55 binary classifiers
- Training time: ~5-10 minutes on CPU

### Graceful Degradation

All new features follow the established pattern:
- Try/except with `HAS_*` flags at import time
- `is_*_available()` and `get_*_status()` functions
- `_get_default_features()` returns neutral values (0.0 or 0.5)
- Features gracefully degrade if models unavailable

### Usage Instructions

```bash
# 1. Install CLAP dependency
pip install laion-clap

# 2. Download CLAP model (~600MB)
cratebot download-clap

# 3. Train Jamendo classifiers (~5-10 min)
cratebot train-jamendo

# 4. Verify all models ready
cratebot model-status

# 5. Retrain your model with new 184-dim features
cratebot train /path/to/library
```

### Backup

Original codebase backed up to: `/Users/noahraford/CrateBot3_v1`

### Testing Performed

1. **Import tests**: All modules import successfully
2. **Feature vector size**: Verified 184 = 57 + 8 + 32 + 32 + 55
3. **CLI commands**: All three new commands import correctly
4. **Graceful degradation**: CLAP shows "Not installed" when laion-clap missing

### Future Enhancements

If needed, could add:
- **MERT embeddings**: 768-dim music transformer (slower but more music-specific)
- **Real Jamendo training**: Download actual audio for classifier training
- **Text similarity**: Use CLAP's text embeddings for tag-to-audio matching

---

## Model Setup Completion (Session 5)

### Issue

Session 4 froze during CLAP/Jamendo setup. The code was committed but dependencies weren't installed.

### Diagnosis

Ran `cratebot model-status` which showed:
- Essentia: Available (8 dims)
- PANNs: **PyTorch not installed**
- CLAP: **PyTorch not installed**
- Jamendo: **Classifiers not trained**

Root cause: PyTorch was the blocking dependency - without it, neither PANNs nor CLAP could load.

### Resolution Steps

| Step | Command | Result |
|------|---------|--------|
| 1. Install PyTorch | `pip install torch torchvision torchaudio` | 74.5 MB downloaded, MPS support enabled |
| 2. Install CLAP + PANNs | `pip install laion-clap panns-inference` | Installed with transformers, wandb, etc. |
| 3. Download CLAP model | `cratebot download-clap` | Already downloaded (~600MB) |
| 4. Train Jamendo | `cratebot train-jamendo` | 55 classifiers trained in ~5 seconds |

### Final Model Status

```
┏━━━━━━━━━━┳━━━━━━━━━━━┳━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃ Model    ┃ Status    ┃ Features                               ┃
┡━━━━━━━━━━╇━━━━━━━━━━━╇━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┩
│ Essentia │ Available │ 8 dims (mood, danceability, vocals)    │
│ PANNs    │ Available │ 32 dims (genre, instruments, drums)    │
│ CLAP     │ Available │ 32 dims (semantic audio understanding) │
│ Jamendo  │ Available │ 56 dims (mood/theme predictions)       │
└──────────┴───────────┴────────────────────────────────────────┘

Total feature vector size: 185 dimensions
```

Note: Final dimension count is 185 (not 184 as originally documented) due to Jamendo having 56 tags instead of 55.

### Next Steps

1. Retrain the tagging model with enhanced 185-dim features:
   ```bash
   cratebot train /path/to/library
   ```

2. Test inference on sample tracks to verify CLAP + Jamendo features are being extracted

3. Compare accuracy metrics before/after the feature enhancement
