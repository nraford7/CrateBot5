# Lexicon & Taxonomy Redesign

## Overview

Transform CrateBot from a "train your own model" tool into a "customize your vocabulary" tool. Ship a pre-trained model based on a reference DJ library, let users map canonical tags to their preferred vocabulary.

**Key insight:** Most users won't label 2,100+ tracks to train a model. Instead, ship a pre-trained model that understands DJ concepts, let users rename tags to their vocabulary.

## New Taxonomy

### Genre (single-class, 9 values)

Actual musical genre of the track.

| Genre | Notes |
|-------|-------|
| House | |
| Techno | |
| Jungle/DnB | Combined category |
| Rap | |
| DiscoFunk | |
| Breakbeat | Renamed from PartyBreaks |
| Ambient | |
| Dubstep | For other users |
| Trance | For other users |

**ID3 Field:** TCON (Genre)

**Future:** Support subgenres (House → Deep House, Tech House, etc.)

### Timing (single-class, 5 values)

Position in DJ energy arc. Orthogonal to mood - a track can be "Dark + Peak" or "Dark + Release".

| Timing | Description |
|--------|-------------|
| **Start** | Opening tracks: interesting, engaging, recognizable, approachable, intriguing, head-nodding |
| **Build** | Increasing tension, urgency, energy, momentum. Usually 2-3 before a peak |
| **Peak** | Climax moment. Resolution of momentum from build tracks |
| **Sustain** | Maintain energy at new level, or change direction stylistically at same energy |
| **Release** | Let tension/energy down, reset before starting/building again |

**ID3 Field:** TALB (Album)

### Mood (single-class, 6 values)

Emotional color of the track. Independent of energy level.

| Mood | Jamendo signals (features, not output) |
|------|----------------------------------------|
| **Happy** | uplifting, happy, energetic, epic |
| **Dark** | dark, heavy, dramatic, deep |
| **Emotional** | melancholic, sad, emotional, soft |
| **Aggressive** | powerful, heavy, energetic, fast |
| **Dreamy** | dream, meditative, soft, soundscape |
| **Groovy** | groovy, fun, party, upbeat |

**ID3 Field:** TIT1 (Grouping) or custom

### Descriptive (multi-label, 50+ values)

Sonic characteristics. Combines trained tags with Jamendo predictions.

**Categories:**
- Beats: Four on the Floor, Breakbeat, Rolling, etc.
- Bass: Wobble, Reese, Sub, 808, etc.
- Instruments: Piano, Synth, Strings, etc.
- Vibes: + DJ-relevant Jamendo tags (melodic, uplifting, energetic, etc.)

**ID3 Field:** COMM (Comments)

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                        FEATURE EXTRACTION                        │
│  Audio → librosa + Essentia + PANNs + CLAP + Jamendo → 184 dims │
└─────────────────────────────────┬───────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────┐
│                     PRE-TRAINED MODEL (ships default)            │
│  Trained on reference DJ library (2,100 tracks)                 │
│  Outputs canonical tags:                                        │
│    • Genre (9): House, Techno, Jungle/DnB, Rap, DiscoFunk,     │
│                 Breakbeat, Ambient, Dubstep, Trance             │
│    • Timing (5): Start, Build, Peak, Sustain, Release          │
│    • Mood (6): Happy, Dark, Emotional, Aggressive, Dreamy,     │
│                Groovy                                           │
│    • Descriptive (multi): Beats, Bass, Instruments, Vibes +    │
│                           Jamendo subset                        │
└─────────────────────────────────┬───────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────┐
│                      OVERRIDE CHECK                              │
│  Hash file → lookup in override DB → use override if exists     │
└─────────────────────────────────┬───────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────┐
│                      LEXICON MAPPING                             │
│  Canonical → User vocabulary                                    │
│  "Peak" → "Climax", "Happy" → "Euphoric", etc.                 │
└─────────────────────────────────┬───────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────────────────────────────────────────────────┐
│                      ID3 TAG WRITING                             │
│  Genre → TCON, Timing → TALB, Mood → TIT1, Descriptive → COMM  │
└─────────────────────────────────────────────────────────────────┘
```

## Lexicon System

Users customize vocabulary without retraining.

### Storage

```json
// ~/.cratebot/lexicon.json
{
  "timing": {
    "Peak": "Climax",
    "Build": "Tension"
  },
  "mood": {
    "Happy": "Euphoric"
  },
  "genre": {},
  "descriptive": {}
}
```

### Behavior

- Unmapped tags pass through unchanged
- Users only define overrides they care about
- Changing lexicon doesn't re-analyze - just re-maps on next tag write
- Lexicon stored per-user (`~/.cratebot/`) or per-project

## Override System

Per-track corrections for when the model gets it wrong.

### Storage

```json
// ~/.cratebot/overrides.db (SQLite) or overrides.json
{
  "abc123def456": {  // audio hash
    "timing": "Build",
    "mood": "Dark"
  }
}
```

### Hash Strategy

- Compute hash from first 30 seconds of audio (MD5 or SHA256)
- Hash computed during analysis (already loading audio)
- Portable: overrides survive file moves/renames

### Behavior

- Overrides stored in canonical vocabulary (not user vocabulary)
- Override survives lexicon changes
- Checked before lexicon mapping in the pipeline
- Future: "Learn from corrections" to improve model

## User Flow

### First Run (New User)

1. Install CrateBot
2. Model ships pre-trained, works immediately
3. Drop files → get predictions using canonical vocabulary
4. Optional: customize lexicon in Settings

### Ongoing Use

1. Drop files into tagging view
2. Model predicts tags (Genre, Timing, Mood, Descriptive)
3. Lexicon maps to user vocabulary
4. Tags written to files

### Refinement

1. Open RefineTab with tagged files
2. See predictions, override any that are wrong
3. Overrides stored by audio hash
4. Future re-imports will use override

### Vocabulary Change

1. User decides "Peak" should be called "Climax"
2. Edit lexicon: `"Peak": "Climax"`
3. Re-tag files → new vocabulary applied
4. No re-analysis needed

## Migration from Current System

### Taxonomy Changes

| Old Field | Old Purpose | New Field | New Purpose |
|-----------|-------------|-----------|-------------|
| Genre (TCON) | Timing + genres mixed | Genre (TCON) | Actual genre only |
| Album (TALB) | Mood | Timing (TALB) | DJ function |
| Comments (COMM) | Descriptive | Mood (TIT1) | Emotional color |
| - | - | Descriptive (COMM) | Sonic characteristics |

### Data Migration

1. Re-label training data with new taxonomy
2. Retrain model on new taxonomy
3. Ship new model as default

## Implementation Tasks

### Phase 1: Taxonomy Restructure

1. Update `tag_predictor.py` - new output structure
2. Update `tag_manager.py` - new ID3 field mapping
3. Update training data labels
4. Retrain model

### Phase 2: Lexicon System

1. Create `lexicon.py` - load/save/apply lexicon
2. Add lexicon UI to Settings panel
3. Integrate lexicon into tag writing pipeline

### Phase 3: Override System

1. Create `overrides.py` - hash computation, storage, lookup
2. Add override UI to RefineTab
3. Integrate overrides into tag writing pipeline

### Phase 4: Ship Pre-trained Model

1. Train final model on full taxonomy
2. Bundle model in `desktop/resources/models/`
3. Update setup wizard - no training required

## Open Questions

1. **Subgenres**: How to add later? Hierarchical (House → Deep House) or flat?
2. **Learn from corrections**: Feed overrides back to model? Requires retraining infrastructure.
3. **Multi-user**: Share lexicons/overrides between users? Export/import?
