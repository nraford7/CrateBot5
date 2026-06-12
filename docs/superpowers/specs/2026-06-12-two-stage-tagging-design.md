# Two-Stage Tagging Architecture: Perception → Judgment

**Date:** 2026-06-12
**Status:** Validated with Noah (brainstorming session)
**Baseline to beat:** 33.0% macro F1 (CB5_v5, per-tag thresholds + co-occurrence boost)
**Success criteria:** Combined macro F1 ≥ 45% on the same holdout; relational tags measurably above their current near-zero F1; Stage 1 and Stage 2 F1 reported separately.

## Problem

The current pipeline trains 47 independent binary classifiers, each predicting a tag from audio features alone. Audit findings (2026-06-12) identified five compounding causes of mediocre tagging:

1. Inference analyzes ~2 seconds of audio per track (one EffNet patch), discarding temporal structure. Training uses three 30s segments; inference uses one arbitrary buffer — an asymmetry that degrades real-world accuracy.
2. Relational tags (Peak, Build, Start, Release, Set Starter) encode DJ judgment, not audio content. Predicting them directly from a waveform is structurally impossible.
3. Tag absence is treated as a confirmed negative. At ~4 tags/track across 47 tags, most negatives are unknowns; the models learn the user's tagging backlog as ground truth.
4. The decision stack fights itself: thresholds tuned on raw scores judge calibrated+boosted scores; default threshold 0.85 suppresses thin tags; multi-class argmax forces answers with no confidence gate.
5. Tags are predicted independently. The structure of the user's judgment — which tag combinations co-occur and why — is invisible to the model. The `TagCooccurrenceBooster` is a fixed pairwise approximation of what should be learned.

## Design decisions (settled with Noah)

| Decision | Choice |
|----------|--------|
| Mood tags | Stage 1 (intrinsic) — audible, already strong (Happy 85% F1) |
| Missing labels | Category-complete heuristic (absence = unknown unless user tagged that category on the track) |
| Stage 2 model | BoostedTrees per relational tag now; MLP as phase 2, gated on eval results |
| Windowing | 5 fixed windows at 10/30/50/70/90% of track length, embeddings mean-pooled |

## Architecture

```
STAGE 1 — PERCEPTION
  audio → 5 windows → per-window 2960-dim embedding (EffNet 1280 + Jamendo 400
                       + CLAP 512 + MAEST 768) → mean-pooled vector
        → intrinsic classifiers: genres, moods, instruments, textures
        → calibration → Stage 1 per-tag thresholds

STAGE 2 — JUDGMENT
  input: Stage 1 binary tag confidences + multi-class group probabilities
         (BassType, VocalType) + BPM + duration
  one BoostedTree per relational tag (Peak, Build, Start, Release, Set Starter, …)
  → Stage 2 per-tag thresholds → final tags
```

**Stage 2 input vector, precisely:** every Stage 1 binary confidence, every
multi-class group class probability, BPM (from ID3 TBPM via ID3Manager; sentinel
-1.0 when absent — BoostedTrees split on it natively), and track duration in
seconds (from the audio file, always available). Musical key and a scalar
"energy" are deliberately excluded: neither exists in the codebase (no TKEY
reading, no track-level energy), and energy is already expressed through Stage 1
confidences (Driving, Aggressive, mood tags). No new feature extraction is
invented for Stage 2.

Stage 2 is a learned model of the user's judgment function: 2,500 tracks of his
historical ID3 decisions, predicted from perceptible track properties. It is small
(~60 input features), trains in seconds via existing CreateML infrastructure, and
every prediction is inspectable ("Peak because Driving 0.91 + Dark 0.84 + 132 BPM").

## Components

### 1. TagStageRegistry (new, CrateBotCore/Sources/CrateBotCore/ML/)

Single config mapping every tag to a stage. Genre, Mood, and all Descriptive
sub-categories → Stage 1. Timing and set-role tags → Stage 2. One place to move a
tag if mis-sorted. Interface: `stage(for tag: String) -> TagStage`,
`tags(in stage: TagStage) -> [String]`. Consumed by data generators, trainer,
coordinator, and TaggingEngine.

### 2. Windowed extraction (modify CombinedFeatureExtractor)

- New `windowed` mode: slice buffer at 10/30/50/70/90% of track length; extract
  each window through EffNet (+Jamendo +MAEST); mean-pool the five embeddings.
  CLAP (10s input) uses three windows at 25/50/75%, also averaged.
- Output shape unchanged (one 2960-dim vector) — classifiers, cache, trainer
  untouched downstream.
- Short tracks (<~60s): overlapping windows collapse to fewer distinct ones,
  minimum one (current behavior preserved).
- **Symmetry rule:** training and inference call the identical windowing path.
  The training-only multi-segment logic in TrainingDataCollector is replaced by
  this single code path.
- **Cache versioning:** add window fields (`windowCount`, window fractions) to
  `FeatureExtractionConfig` — its existing `configHash` (SHA256 of config fields,
  FeatureExtractionConfig.swift:34) then invalidates the cache automatically; no
  separate version integer. Reconcile with `ModelMetadata.pipelineVersion` /
  `TrainingCoordinator.currentPipelineVersion()`. Stale single-window entries must
  never mix with windowed ones (this failure mode has occurred twice before — see
  docs/plans/2026-01-29-training-pipeline-fixes.md and 2026-04-11-ml-pipeline-fix.md).
- Full re-extraction of ~2,250 tracks at ~5x cost is absorbed by the already-pending
  MAEST retrain (one overnight run covers both).

### 3. Category-complete label filtering (modify BinaryTrainingDataGenerator)

A track is a valid negative for tag T only if the user applied at least one tag in
T's **top-level category** (Genre, Timing, Mood, Descriptive — the four categories
in TrainingCoordinator) to that track, proof the category was considered. Tracks
with no tags in that category are excluded for that tag — unknown, not negative.
Granularity is deliberately top-category, not descriptive sub-category: sub-category
filtering (e.g. only instrument-tagged tracks count as instrument negatives) would
shrink trusted negatives below trainable counts for most descriptive tags. If
instrument tags evaluate poorly under the top-category rule, tightening to
sub-category granularity is a one-line change in the filter, flagged as a known lever. Applies to both
Stage 1 and Stage 2 training. The generator logs per-tag counts (positives / trusted
negatives / excluded) and reports tags too thin to train rather than silently
skipping them (fixes the silent-skip behavior in the multi-class path).

### 4. JudgmentDataGenerator (new)

Builds Stage 2 training rows: one per track — Stage 1 binary confidences +
multi-class group probabilities (computed from cached embeddings, no re-extraction)
+ BPM (sentinel -1.0 when absent) + duration; targets are the user's ID3 relational
tags, filtered by the category-complete rule.

### 5. Two-phase training (modify TrainingCoordinator, ModelTrainer, TrainingCheckpoint)

Phase A: train Stage 1 on windowed embeddings. Phase B: run Stage 1 over the
library to produce confidences, then train Stage 2 trees. Checkpoint format
records both phases; a crash mid-run resumes cleanly. **Pairing constraint:**
Stage 2 is trained on Stage 1's actual prediction distribution, so retraining
Stage 1 invalidates Stage 2 — the coordinator enforces that both are retrained
together and ModelMetadata records the Stage 1 model version Stage 2 was paired with.

**Known tradeoff — in-sample confidences:** Phase B computes Stage 1 confidences on
tracks Stage 1 trained on, which run hotter than what unseen tracks produce at
inference. The clean fix (out-of-fold predictions) means training Stage 1 k times —
unacceptable cost for v1. Accepted mitigations: Stage 2 per-tag thresholds are tuned
on the held-out 20% (where Stage 1 confidences are honest), and the eval reports
Stage 2 F1 on that same holdout, so the optimism is measured rather than hidden.
Out-of-fold generation is a named phase-2 option if Stage 2 holdout F1 lags badly
behind its training F1.

### 6. Inference rewire (modify TaggingEngine)

```
windowed extract → Stage 1 → calibrate → Stage 1 thresholds
                      ↓ confidences
                Stage 2 trees → Stage 2 thresholds → final tags
```

Cleanups folded in:
- Per-tag thresholds are tuned on **final pipeline scores** (post-calibration),
  ending the raw-vs-calibrated mismatch. Defaults until tuned: genres 0.7,
  moods 0.55, descriptive 0.55 (replacing the global 0.85).
- `TagCooccurrenceBooster` retires for relational tags (Stage 2 subsumes it);
  remains available for Stage 1 only, off by default pending eval.
- Zero-shot CLAP fires only for tags with no trained classifier.
- Multi-class groups gain a confidence gate before argmax (no forced answer when
  the probability spread is flat).

### 7. Evaluation (modify scripts/accuracy_eval.py)

- Dimension guard: assert cached vector length matches model `featureDimension`;
  refuse to run on mismatch instead of producing silent garbage.
- Two-stage aware: reports Stage 1 macro F1 (intrinsic tags), Stage 2 macro F1
  (relational tags), and combined — against a stratified per-tag 20% holdout,
  fixed seed, same baseline data as the 33.0% figure.
- `--optimize` tunes per-tag thresholds on final pipeline scores.

## Error handling

- Windowing on unreadable/short buffers degrades to current single-window behavior.
- Stage 2 missing or unpaired with current Stage 1 model: inference runs Stage 1
  only and surfaces relational tags as unavailable (no stale judgments).
- Tags below minimum trusted-data counts: reported in training summary, excluded
  from training, excluded from eval denominators.

## Testing

- Unit: window slicing boundaries (short tracks, exact-length tracks), mean-pooling
  correctness, cache-key change, category-complete filtering truth table,
  JudgmentDataGenerator row construction, Stage 1/Stage 2 pairing enforcement.
- Integration: full two-phase training on mock tracks; inference produces relational
  tags only when paired models exist; eval script rejects dimension mismatch.
- Regression: existing 375-test suite stays green.

## Out of scope (explicitly)

- MLP judgment head (phase 2, triggered only if tree-based Stage 2 plateaus below
  45% combined F1).
- Energy-guided window placement.
- Vibe/description generation grounding (separate piece of work).
- Hook detection for instrumentals (separate piece of work).

## Build chunks (for the implementation plan)

1. Windowed extraction + cache version bump + eval dimension guard.
2. Category-complete filtering + TagStageRegistry.
3. JudgmentDataGenerator + Stage 2 training + coordinator two-phase + checkpoints.
4. Inference rewire + threshold retune + full eval against the 33.0% baseline.

Each chunk independently builds, tests green, and is reviewable as one diff.
