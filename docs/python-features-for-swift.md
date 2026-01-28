# Python Features for Future Swift Implementation

**Date:** 2026-01-28
**Purpose:** Document Python-only features worth implementing in Swift before deprecating Python codebase

---

## Priority Ranking

| Rank | Feature | Value | Complexity | Recommendation |
|------|---------|-------|------------|----------------|
| 1 | Lexicon System | HIGH | Medium | Implement |
| 2 | Override Database | HIGH | Low | Implement |
| 3 | Review Manager | HIGH | Medium | Implement |
| 4 | Audio Hash | MEDIUM | Low | Implement (needed for overrides) |
| 5 | Refinement Sessions | MEDIUM | Medium | Consider later |
| 6 | Tag Lexicon Definitions | MEDIUM | Low | Port as constants |
| 7 | Lyrics-First Hook Detection | LOW | High | Skip (API-based approach works) |

---

## Tier 1: High Value, Should Implement

### 1. Lexicon System (Vocabulary Customization)

**What it does in plain language:**
Lets you customize the words used for tags without retraining your model. If you prefer "Climax" instead of "Peak", or want tags written to different ID3 fields, you configure this once and it applies everywhere.

**Why DJs need this:**
- Match your existing tagging vocabulary from years of manual work
- Configure where tags are written for compatibility with your DJ software (Traktor writes to different fields than Rekordbox)
- Change terminology without losing your trained model
- Keep consistent vocabulary as your preferences evolve

**How it works:**
- JSON file stores mappings: canonical tag -> user's preferred word
- Per-category ID3 frame configuration (Genre->TCON, Timing->TALB, Mood->TIT1, Descriptive->COMM)
- Bidirectional: transforms tags when writing, reverse-transforms when reading for training
- Automatic migration from older format versions

**Key capabilities:**
```
User wants "Climax" instead of "Peak":
  lexicon.set_mapping("timing", "Peak", "Climax")

User wants mood tags in Comments instead of Album:
  lexicon.set_id3_frame("mood", "COMM")

Reading tags for training:
  "Climax" -> reverse mapped to "Peak" -> model trains on canonical form

Writing tags after prediction:
  Model predicts "Peak" -> lexicon transforms to "Climax" -> written to file
```

**Files:** `lexicon.py` (180 lines)

---

### 2. Override Database (Per-Track Corrections)

**What it does in plain language:**
When the AI gets a track wrong, you manually correct it once and that correction sticks forever - even if you retrain the model, move the file, or rename it. The correction is tied to the audio content itself, not the filename.

**Why DJs need this:**
- That one remix that always gets tagged wrong? Fix it once, forget it
- Corrections survive model retraining (your fixes aren't lost when you improve the model)
- Files can be reorganized without losing corrections
- Quick fixes without waiting for retraining

**How it works:**
- SQLite database stores: audio_hash -> corrected tags
- Audio hash computed from first 30 seconds of audio content (SHA256)
- Before writing any tags, check if override exists
- Overrides applied before lexicon transformation

**Key capabilities:**
```
User corrects a track:
  1. Compute audio hash (content-based fingerprint)
  2. Store: hash -> {genre: "Techno", timing: "Peak", ...}

Next time track is tagged (even after moving/renaming):
  1. Compute audio hash
  2. Find override in database
  3. Use override instead of model prediction
```

**Files:** `overrides.py` (60 lines), `audio_hash.py` (25 lines)

---

### 3. Review Manager (Confidence-Based Queue)

**What it does in plain language:**
When the AI isn't confident about its prediction, it doesn't write potentially wrong tags. Instead, it queues the track for your review. You look at uncertain predictions when you have time, confirm or correct them, and those decisions improve future accuracy.

**Why DJs need this:**
- No more silently wrong tags on difficult tracks
- Only review tracks that actually need attention (not your whole library)
- Corrections feed back into model improvement
- Confidence thresholds are configurable per category

**How it works:**
- Each prediction has a confidence score (0-1)
- Thresholds: Genre 60%, Timing 60%, Mood 60%, Descriptive 40%
- Below threshold -> queued for review instead of written
- Review actions: Confirm (prediction was right), Correct (provide right answer), Skip (decide later)
- Confirmed/corrected items can be exported for retraining

**Key capabilities:**
```
Model predicts with low confidence:
  Genre: "House" (0.72) -> above 0.6, write it
  Timing: "Build" (0.45) -> below 0.6, queue for review

Review queue shows:
  "track.mp3" - Timing uncertain (45% confidence)
  Predicted: Build
  [Confirm] [Correct: ___] [Skip]

After review session:
  Export corrections for retraining
  Clear processed items from queue
```

**Files:** `review_manager.py` (180 lines)

---

### 4. Audio Hash (Content-Based Identification)

**What it does in plain language:**
Creates a unique fingerprint for each track based on its actual audio, not its filename. The same track always produces the same fingerprint, even if renamed or moved.

**Why DJs need this:**
- Required for override system to work across file moves
- Could enable duplicate detection
- Same track in different locations gets consistent handling

**How it works:**
- Load first 30 seconds of audio at 22050 Hz mono
- Compute SHA256 hash of audio samples
- Returns 64-character hex string

**Files:** `audio_hash.py` (25 lines)

---

## Tier 2: Medium Value, Consider Later

### 5. Refinement Sessions (Interactive Improvement)

**What it does in plain language:**
Guides you through reviewing a diverse sample of your music to improve model accuracy. Instead of randomly picking tracks, it intelligently selects ones that cover different genres, moods, and styles to maximize the value of your review time.

**Why DJs need this:**
- Efficient use of limited review time
- Diverse sampling covers model blind spots
- Pause/resume for long sessions
- Progress tracking

**How it works:**
- DiverseSampler groups tracks by (genre, album) combinations
- Within each group, prioritizes different comment tags
- Round-robin selection ensures coverage
- Session persists to JSON for pause/resume

**Files:** `refinement_manager.py` (200 lines)

---

### 6. Tag Lexicon Definitions (DJ Vocabulary)

**What it does in plain language:**
A dictionary of 130+ DJ tags with detailed definitions. This vocabulary is fed to Claude during vibe generation to ensure it uses terms consistently with their intended meanings.

**Why DJs need this:**
- Consistent terminology in generated vibes
- AI understands nuances (TECHY vs TECHNO, DRIVING vs CHUGGING)
- Comprehensive coverage of dance music terminology

**Categories:**
- Texture & Motion (27 terms): HATS, DRIVING, BOUNCY, PUNCHY, BROKEN...
- Mood & Quality (34 terms): DOPE, EPIC, MELODIC, FUNKY, DREAMY...
- Genre & Region (26 terms): AFRO, DISCO, ELECTRO, LATIN, TROPICAL...
- Sound Elements (22 terms): BEATS, SINGING, CONGAS, GUITAR, PADS...
- DJ Function (19 terms): PEAK, BUILD, JOURNEY, RELEASE, SLAMMER...

**Files:** `tag_lexicon.py` (350 lines of definitions)

---

## Tier 3: Low Value, Skip

### 7. Lyrics-First Hook Detection

**What it does:**
Fetches lyrics from online APIs and finds hooks there before falling back to Whisper transcription. Reduces transcription errors.

**Why skip:**
- Swift already has API-based hook detection
- Lyrics APIs are unreliable and rate-limited
- Whisper transcription quality has improved
- Adds complexity for marginal benefit

---

## Implementation Notes

### Data Migration
When implementing in Swift, consider:
- Lexicon: Read existing `~/.cratebot/lexicon.json` for migration
- Overrides: Read existing `~/.cratebot/overrides.db` SQLite database
- Review Queue: Read existing `data/review_queue.json`

### Swift Equivalents Needed

| Python | Swift Equivalent Needed |
|--------|------------------------|
| `lexicon.json` | `LexiconConfiguration` struct with Codable |
| `overrides.db` | SQLite via GRDB or similar |
| `review_queue.json` | `ReviewQueue` struct with Codable |
| `audio_hash` | AudioKit or AVFoundation + CryptoKit |

### UI Considerations

**Lexicon:**
- Settings panel with vocabulary mappings
- ID3 field picker per category
- Import/export for sharing configs

**Overrides:**
- Right-click track -> "Override tags..."
- Badge on tracks with overrides
- Override management view (list, edit, delete)

**Review Queue:**
- Badge showing queue count
- Dedicated review interface
- Batch confirm/correct actions
- Export to training button

---

## Dependency Graph

```
Override System
    └── Audio Hash (required)

Review Manager
    └── Confidence Thresholds (from TrainingConfiguration)

Lexicon System
    └── Standalone (no dependencies)

Refinement Sessions
    ├── Review Manager patterns
    └── Feature Cache (for analysis)
```

---

## Summary

**Implement now (before destroying Python):**
1. Document exact JSON/SQLite schemas for data migration
2. Port Audio Hash algorithm (simple)
3. Design Swift APIs for Lexicon, Override, Review

**Implement in Swift (future work):**
1. Lexicon system with Settings UI
2. Override database with SQLite
3. Review queue with dedicated UI
4. Refinement sessions (stretch goal)

**Safe to destroy:**
- All Python code after documenting schemas
- Lyrics verification (not needed)
- Python CLI (replaced by Swift UI)
- Python-specific utilities (logging, config, paths)
