# Chunk 5 — Manual 50-track Run Procedure

The Chunk 4 code is on master. Chunk 5 is the human-in-the-loop validation
step: tag 50 tracks with the new toggle on, eyeball the outputs, run the
verification script, capture cost-per-track, push the result memory.

## Pre-flight

1. **Anthropic API key in Keychain** — open Preferences in the app, paste a
   Sonnet-4-class key, save. The Settings panel's "AI Descriptions" row
   greys out + tooltips when the key is missing; if you see it greyed,
   the key isn't loaded.
2. **Stage 1 model loaded** — any current CB5_vN model. If
   `metadata.stage1ModelVersion` is nil/empty, the cache is skipped (LLM
   runs fresh each track). The 50-track run will still work; just won't
   benefit from a second pass.
3. **Pick the 50 tracks** — sample from across the library, not a single
   bucket. A few Peak, Build, Sustain, Release. A few with empty Stage 2
   (to exercise the no-mix-hint path).
4. **Have a duplicate or copy of the directory** — the tag pass writes
   to TCOM / TIT3 / GRP1 in place; if you want a before/after compare,
   stage the originals first.

## Run

1. Launch the app:
   ```
   cd /Users/noahraford/Projects/claude_projects/11_CrateBot/CrateBot5
   xcodebuild -project CrateBot.xcodeproj -scheme CrateBot build
   open build/dd/Build/Products/Debug/CrateBot.app
   ```
2. Tagging Options → enable "AI Descriptions". Tooltip should read
   "Generates short vibe, prose description, and DJ mix-context hint
   per track via Anthropic API. ~$0.01/track at current Sonnet 4 pricing."
3. Queue your 50 tracks, hit Tag. Watch for per-track warning logs in
   Console.app under subsystem `com.cratebot` if anything fails — the
   per-track integration logs `"Vibe generation failed for X: ..."` and
   the rest of the tag pass continues.
4. When the pass ends, all three frames are written when the LLM succeeded
   and `nil` when it failed — never partial. Re-running the same tracks
   under the same Stage 1 model hits the cache and skips the LLM.

## Verify

Run the verification script against the tagged directory:

```bash
python3 scripts/vibe_verify.py /path/to/tagged/dir --limit 50
```

It reports:
- **Frame coverage** — TCOM / TIT3 / GRP1 written count.
- **Criterion 1** — any TCOM matching CoT preamble patterns (`LOOKING AT`,
  `PROCESS:`, bare `{`, etc.) is a regression. The strict-JSON parser in
  `VibeGeneratorV2` should make this impossible; this is the tripwire.
- **Criterion 2** — sliding 30-track window over all TIT3 descriptions;
  flags any 4-word phrase that appears more than twice in a single window.
- **Criterion 3** — soft check: counts GRP1 with vs without Timing
  vocabulary (Peak/Build/Sustain/Release/etc). Stage 2 confidence is not
  retrievable from disk, so the script can't strictly gate this; just
  surfaces the ratio for your eyes.

Exit code 0 means criteria 1+2 passed.

## Capture

Open Console.app or run the app from a terminal and watch the
`com.cratebot.VibeGeneratorV2` and `com.cratebot.core.VibeCache` log
streams. After the pass:

1. Count cache hits vs misses (the cache logs at debug; or just inspect
   `~/Library/Containers/com.cratebot.CrateBot/Data/Library/Application Support/CrateBot/vibe_cache.json`
   — file size and entry count).
2. From the Anthropic Console: pick out the cost for the time window of
   the run. Divide by 50 → cost per track.
3. Edit `~/.claude/projects/-Users-noahraford-Projects-claude-projects-11-CrateBot/memory/vibe_generator_v2_chunk4_2026_06_13.md`
   and append a "Chunk 5 results" section with:
   - 50/50 tracks succeeded? Y/N + failure modes.
   - Observed cost per track.
   - Criterion 1/2/3 verdicts from the script.
   - One-line eyeball summary: "descriptions feel grounded / generic /
     repetitive / on point."

## If things look bad

The previous "Stage 2 F1 = 2.7%" panic took three iterations to unwind
because the eval was lying, not the model. Apply the same posture here:

- **Generic descriptions?** Probably title/artist nil from ID3 read or
  binaryConfidences empty. Verify by adding a `print()` to
  `VibeGenerationInputs.promptPayload()` and tagging one track.
- **Mix hint missing on every track?** Either Stage 2 confidence is below
  0.5 for the sample, or `tag_cooccurrence.json` has empty
  `conditional[<TimingLabel>]`. Regenerate with
  `python3 scripts/generate_tag_cooccurrence.py` after the next training
  run.
- **CoT preamble in TCOM?** The strict-JSON parser failed. Capture the
  raw response (log already truncates at 500 chars) and check
  `VibeGeneratorV2.extractFirstJSONObject`.

## Done condition

Chunk 5 closes when:
- 50 tracks tagged with the toggle on.
- `vibe_verify.py` exits 0 (criteria 1+2 pass).
- Cost-per-track captured in the memory file.
- A line in the memory says "looks good" or names a regression to fix.
- Push memory update (memory is shared but the project_state-style
  pointer in the repo's handoff doc is what next-session will read).
