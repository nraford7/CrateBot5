# Vibe Description Redesign Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace formulaic adjective-stacking vibe descriptions with distinctive hook-focused short tags and synesthetic mnemonic anchors for long descriptions.

**Architecture:** Modify the prompt templates in `vibe_generator.py` to shift from template-slot filling to identifying what makes each track unique. Short vibe uses [ENERGY] [DISTINCTIVE THING] [MOMENT] structure. Long description becomes a 2-3 word mnemonic anchor combining a synesthetic modifier with a concrete archetype/object.

**Tech Stack:** Python, Claude API (existing infrastructure)

---

## Task 1: Update Short Vibe SYSTEM_PROMPT

**Files:**
- Modify: `CrateBot5/python/src/core/vibe_generator.py:688-767`

**Step 1: Replace SYSTEM_PROMPT content**

Replace the existing `SYSTEM_PROMPT` class variable (lines 688-767) with this new prompt:

```python
    SYSTEM_PROMPT = """You are a DJ identifying what makes each track MEMORABLE and DISTINCTIVE. Your job is to create a scannable tag that captures the track's essence in a specific structure.

## THE STRUCTURE: [ENERGY] [DISTINCTIVE THING] [MOMENT]

1. **ENERGY** (1-2 words) - The mood/feel of the track
   → dark, heavy, joyful, grindy, smooth, raw, warm, cold, dreamy, nasty, fierce, lush

2. **DISTINCTIVE THING** (2-4 words) - What makes THIS track stand out
   → The unusual element, the hook, what you'd remember it by
   → Ask: "What would make me pick THIS track over similar ones?"
   → Be specific: "PITCHED VOCAL CHOP" not "VOCALS", "GRINDING SAW BASS" not "BASS"
   → If an instrument is unusual for the genre (flute in techno, steel drums in house), highlight it

3. **MOMENT** (1 word) - What kind of track / when to play it
   → PEAK, BUILDER, OPENER, JOURNEY, SLAMMER, STOMPER, CRUISER, GROOVER, FLOATER

## FINDING THE DISTINCTIVE THING

Look for what's UNUSUAL, not what's typical:
- A walking bassline in house is expected. A walking bassline in techno is notable.
- Standard kick-hat patterns are boring. Unusual percussion or broken rhythms stand out.
- If PANNs detected something unexpected for the genre, that's probably the hook.

The distinctive thing should answer: "What would I tell a friend to listen for?"

## EXAMPLES

DARK GRINDING SAW BASS PEAK
HEAVY ARABIC FLUTE LOOP BUILDER
JOYFUL STEEL DRUMS GROOVE OPENER
SMOOTH WALKING JAZZ BASS CRUISER
GRINDY PITCHED VOCAL CHOP SLAMMER
DREAMY UNDERWATER SYNTH PAD JOURNEY
NASTY DISTORTED KICK STOMPER
RAW TRIBAL CHANTING BUILD
WEIRD DETUNED PIANO STABS HYPNOTIC
FILTHY ACID 303 LINE PEAK
WARM RHODES CHORDS SUNRISE FLOATER
FIERCE AFRO PERCUSSION BREAKDOWN PEAK

## CRITICAL RULES

1. **4-8 WORDS** - Flexible, but structure matters more than count
2. **NO COMMAS** - Space-separated words only
3. **ALL CAPS** - Always
4. **STRUCTURE OVER TEMPLATE** - [ENERGY] [DISTINCTIVE THING] [MOMENT] - not random adjective stacking
5. **DISTINCTIVE BEATS GENERIC** - "WEIRD PITCHED VOCAL" beats "DOPE FUNKY GROOVE"
6. **OUTLIERS ARE HOOKS** - Unusual instruments/sounds for the genre = the memorable thing
""" + (TAG_LEXICON_PROMPT if HAS_LEXICON else "")
```

**Step 2: Verify the change compiles**

Run: `cd /Users/noahraford/Projects/claude_projects/11_CrateBot/CrateBot5/python && python -c "from src.core.vibe_generator import VibeGenerator; print('OK')"`
Expected: `OK`

**Step 3: Commit**

```bash
git add src/core/vibe_generator.py
git commit -m "refactor: update short vibe prompt to [ENERGY][DISTINCTIVE][MOMENT] structure

Replaces formulaic adjective-stacking with hook-focused structure.
Emphasizes finding what makes each track unique vs generic descriptors.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

## Task 2: Update Short Vibe USER_PROMPT_TEMPLATE

**Files:**
- Modify: `CrateBot5/python/src/core/vibe_generator.py:769-790`

**Step 1: Replace USER_PROMPT_TEMPLATE content**

Replace the existing `USER_PROMPT_TEMPLATE` (lines 769-790) with:

```python
    USER_PROMPT_TEMPLATE = """Identify what makes this track DISTINCTIVE and create a vibe tag:

{context}

## OUTLIER DETECTION
Look at the detected sounds above. What's UNUSUAL for this genre?
- Unexpected instruments? (flute in techno, accordion in house)
- Unusual rhythm patterns? (broken beats in 4/4 genre)
- Distinctive vocal treatment? (pitched, chopped, chanted)

## YOUR TASK
Find the ONE THING that makes this track memorable, then build the tag:

1. ENERGY (1-2 words): What's the mood/feel?
2. DISTINCTIVE THING (2-4 words): What would you tell a friend to listen for?
3. MOMENT (1 word): When would you play this? (PEAK/BUILDER/OPENER/JOURNEY/SLAMMER/etc)

ALSO: If there's a vocal transcription above, identify the most memorable hook phrase (3-6 words).

Respond in this EXACT format:
VIBE: [ENERGY] [DISTINCTIVE THING] [MOMENT]
HOOK: [the catchy hook phrase, or NONE if no clear hook]

Example:
VIBE: DARK GRINDING SAW BASS PEAK
HOOK: killers in the jungle"""
```

**Step 2: Verify the change compiles**

Run: `cd /Users/noahraford/Projects/claude_projects/11_CrateBot/CrateBot5/python && python -c "from src.core.vibe_generator import VibeGenerator; print('OK')"`
Expected: `OK`

**Step 3: Commit**

```bash
git add src/core/vibe_generator.py
git commit -m "refactor: update user prompt to guide outlier detection

Adds explicit outlier detection step to help Claude find distinctive elements.
Restructures the task around finding the memorable hook.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

## Task 3: Update Long Description DESCRIPTION_SYSTEM_PROMPT

**Files:**
- Modify: `CrateBot5/python/src/core/vibe_generator.py:792-821`

**Step 1: Replace DESCRIPTION_SYSTEM_PROMPT content**

Replace the existing `DESCRIPTION_SYSTEM_PROMPT` (lines 792-821) with:

```python
    DESCRIPTION_SYSTEM_PROMPT = """You create MNEMONIC ANCHORS for music tracks - short, vivid phrases that work like album art in text form.

## YOUR MISSION

Create a 2-3 word phrase that FEELS like the track without DESCRIBING it. This phrase becomes a mental bookmark - like how a record sleeve's color or weird artwork becomes synonymous with the music.

## THE FORMULA: [SYNESTHETIC MODIFIER] + [CONCRETE ANCHOR]

**Synesthetic Modifier** - Translate the track's sonic qualities into other senses:
- Temperature: warm, cold, frozen, burning, humid
- Texture: velvet, chrome, dusty, rusty, silky, gritty
- Material: golden, marble, wooden, copper, glass
- Light: glowing, shadowed, neon, dim, phosphorescent
- Wetness: sweating, dripping, parched, misty, soaked

**Concrete Anchor** - Something you can picture:
- Archetypes: wizard, priest, grandmother, astronaut, butcher, shaman
- Animals: panther, owl, serpent, moth, whale
- Places/Objects: cathedral, basement, satellite, jungle, volcano

## EXAMPLES

warm wizard - mellow, mysterious, wise energy
chrome shaman - cold, metallic, spiritual
dusty panther - gritty, prowling, predatory
velvet butcher - smooth but heavy, dangerous elegance
sweating marble - tense, monumental, under pressure
golden grandmother - bright, nostalgic, nurturing
rusty cathedral - decayed grandeur, cavernous
frozen serpent - cold, sinuous, hypnotic
humid jungle - thick, alive, overwhelming
neon priest - artificial light, ritualistic

## CRITICAL RULES

1. **2-3 WORDS ONLY** - No more
2. **LOWERCASE** - Always
3. **NO DESCRIPTION** - Don't describe the music, create an association
4. **CONCRETE ANCHOR** - Must be something you can visualize
5. **SYNESTHETIC MODIFIER** - Translate sound to other senses
6. **UNIQUE** - Each track gets its own distinct anchor
"""
```

**Step 2: Verify the change compiles**

Run: `cd /Users/noahraford/Projects/claude_projects/11_CrateBot/CrateBot5/python && python -c "from src.core.vibe_generator import VibeGenerator; print('OK')"`
Expected: `OK`

**Step 3: Commit**

```bash
git add src/core/vibe_generator.py
git commit -m "refactor: replace poetic imagery with mnemonic anchor system

New approach creates album-art-like memory hooks using synesthetic
modifiers + concrete archetypes. 2-3 words that FEEL like the track
rather than describing it.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

## Task 4: Update DESCRIPTION_USER_PROMPT_TEMPLATE

**Files:**
- Modify: `CrateBot5/python/src/core/vibe_generator.py:823-833`

**Step 1: Replace DESCRIPTION_USER_PROMPT_TEMPLATE content**

Replace the existing `DESCRIPTION_USER_PROMPT_TEMPLATE` (lines 823-833) with:

```python
    DESCRIPTION_USER_PROMPT_TEMPLATE = """Create a mnemonic anchor for this track.

VIBE TAG: {vibe}
{track_context}
{context}

The vibe tag above captures WHAT makes the track distinctive.
Now translate that into a 2-3 word phrase that FEELS like the track.

Use: [synesthetic modifier] + [concrete anchor]
- Modifier from senses: warm, cold, dusty, chrome, velvet, sweating, golden, rusty, frozen, humid
- Anchor you can picture: wizard, panther, cathedral, grandmother, shaman, satellite, serpent

This becomes the track's mental bookmark - like album art in text form.

Respond with ONLY the 2-3 word anchor. Lowercase. No quotes."""
```

**Step 2: Verify the change compiles**

Run: `cd /Users/noahraford/Projects/claude_projects/11_CrateBot/CrateBot5/python && python -c "from src.core.vibe_generator import VibeGenerator; print('OK')"`
Expected: `OK`

**Step 3: Commit**

```bash
git add src/core/vibe_generator.py
git commit -m "refactor: update description user prompt for mnemonic anchors

Guides Claude to create synesthetic modifier + concrete anchor combinations.
Uses the vibe tag as input to inform the translation.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

## Task 5: Update Validation (if needed)

**Files:**
- Modify: `CrateBot5/python/src/core/vibe_generator.py` (search for validation logic)

**Step 1: Find and review validation code**

Search for where vibe responses are validated (word count checks, caps enforcement, etc.)

Run: `cd /Users/noahraford/Projects/claude_projects/11_CrateBot/CrateBot5/python && grep -n "5-8\|word.*count\|validate\|len.*split" src/core/vibe_generator.py | head -20`

**Step 2: Update validation if rigid 5-8 word count exists**

If there's validation enforcing exactly 5-8 words, update to allow 4-8 words for short vibe.
If there's validation on description length, update to allow 2-4 words.

**Step 3: Verify and commit if changes made**

Run: `cd /Users/noahraford/Projects/claude_projects/11_CrateBot/CrateBot5/python && python -c "from src.core.vibe_generator import VibeGenerator; print('OK')"`

```bash
git add src/core/vibe_generator.py
git commit -m "fix: relax validation for new vibe format

Short vibe now allows 4-8 words (was 5-8).
Description now allows 2-4 words for mnemonic anchors.

Co-Authored-By: Claude Opus 4.5 <noreply@anthropic.com>"
```

---

## Task 6: Test with Real Audio File

**Files:**
- No files modified - integration test

**Step 1: Find a test audio file**

Run: `find /Users/noahraford/Projects/claude_projects/11_CrateBot -name "*.mp3" -o -name "*.wav" | head -5`

**Step 2: Run vibe generation on test file**

This depends on how the CLI works. Check for a test command or script.

Run: `cd /Users/noahraford/Projects/claude_projects/11_CrateBot/CrateBot5/python && python -c "
from src.core.vibe_generator import VibeGenerator, VibeContext

# Create minimal test context
ctx = VibeContext(
    tempo=125.0,
    energy=0.7,
    danceability=0.8,
    mood_happy=0.3,
    mood_sad=0.1,
    mood_aggressive=0.4,
    mood_relaxed=0.2,
    voice_instrumental=0.1,
    arousal=6.0,
    valence=5.0,
    genre='Techno',
    detected_instruments=['Synthesizer', 'Drum machine'],
    detected_drums=['Hi-hat', 'Kick drum'],
    detected_mood=['Dark', 'Energetic']
)

gen = VibeGenerator()
if gen.is_available:
    result = gen.generate_vibe(ctx)
    print('VIBE:', result.get('vibe', 'N/A'))
    print('HOOK:', result.get('hook', 'N/A'))
else:
    print('API not available - check ANTHROPIC_API_KEY')
"
`

**Step 3: Verify output matches new format**

Expected: Vibe should follow [ENERGY] [DISTINCTIVE THING] [MOMENT] structure, not old adjective-stacking.

**Step 4: Test description generation**

Run a similar test for the description/mnemonic anchor if there's a separate method.

---

## Task 7: Final Review and Cleanup

**Step 1: Review all changes**

Run: `cd /Users/noahraford/Projects/claude_projects/11_CrateBot/CrateBot5 && git diff HEAD~4 --stat`

**Step 2: Run any existing tests**

Run: `cd /Users/noahraford/Projects/claude_projects/11_CrateBot/CrateBot5/python && pytest tests/ -v -k vibe 2>/dev/null || echo "No vibe tests found or pytest not available"`

**Step 3: Confirm prompts read clearly**

Re-read the prompts in context to ensure they flow well and are unambiguous.

---

## Summary of Changes

| Component | Before | After |
|-----------|--------|-------|
| Short Vibe Structure | 5-slot template: [OPENER][TEXTURE][GENRE][ANCHOR][TRAILING] | 3-part: [ENERGY][DISTINCTIVE THING][MOMENT] |
| Short Vibe Focus | Adjective stacking, variety enforcement | Finding what's unique/memorable |
| Long Description | 10-20 word poetic imagery | 2-3 word mnemonic anchor |
| Long Description Style | Scene-setting, places, moments | Synesthetic modifier + concrete archetype |
| Validation | Rigid 5-8 words | Flexible 4-8 words |
