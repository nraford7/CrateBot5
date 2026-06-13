#!/usr/bin/env python3
"""
CrateBot Accuracy Evaluation
Loads trained models + checkpoint data, runs inference at multiple thresholds.

Modes:
  (default)      Legacy single-stage sweep on a 200-track sample (raw probs).
  --stage-aware  Two-stage evaluation on a stratified 20% per-tag holdout:
                 Stage 1 (perception: Genre/Mood/Descriptive) uses CALIBRATED
                 pre-boost confidences; Stage 2 (judgment: Timing) feeds those
                 confidences + multi-class group probabilities + BPM + duration
                 into the <tag>_judgment models, mirroring the Swift contract
                 (JudgmentFeatures.swift / ProductionStage1Predictor.swift /
                 ConfidenceCalibrator.swift). Reports Stage 1, Stage 2, and
                 combined macro F1 vs the 33.0% baseline.
  --boost        Co-occurrence boosting (stage-aware: perception tags only,
                 AFTER the judgment inputs are snapshotted — Stage 2 always
                 sees pre-boost values).
  --optimize     Per-tag threshold tuning on final pipeline scores
                 (post-calibration; post-judgment for Timing tags), written to
                 tag_thresholds.json in the existing nested format.
"""

import json, math, os, sys, random
import coremltools as ct
from pathlib import Path

SAMPLE_SIZE = 200
SEED = 42
HOLDOUT_FRACTION = 0.20
BASELINE_MACRO_F1 = 33.0  # CB5_v5 + boost + optimized thresholds (percent)
THRESHOLDS = [0.50, 0.55, 0.60, 0.65, 0.70, 0.75, 0.80, 0.85, 0.90, 0.92, 0.94, 0.96, 0.98, 0.99, 0.995]

# Calibrated scores live in [smoothing/2, 1 - smoothing/2] = [0.05, 0.95]
# (ConfidenceCalibrator label-smoothing adjustment), so the stage-aware
# uniform sweep covers that full range instead of starting at 0.50.
STAGE_THRESHOLDS = [round(0.05 + 0.05 * i, 2) for i in range(19)]  # 0.05 .. 0.95

# Mirrors ConfidenceCalibrator.smoothingFactor (ConfidenceCalibrator.swift:10)
# and ProductionStage1Predictor.load's explicit smoothingFactor: 0.1.
CALIBRATION_SMOOTHING = 0.1

# Mirrors JudgmentFeatureVector.missingValueSentinel (JudgmentFeatures.swift:18)
MISSING_VALUE_SENTINEL = -1.0

# Mirrors TagStageRegistry.defaultMapping (TagStageRegistry.swift:26-31):
# Timing -> judgment; Genre/Mood/Descriptive/unknown -> perception.
JUDGMENT_CATEGORIES = {"timing"}


# ---------------------------------------------------------------------------
# Stage 2 contract helpers (pure functions — unit-testable without models)
# ---------------------------------------------------------------------------

def calibrate_confidence(raw, temperature, smoothing=CALIBRATION_SMOOTHING):
    """Mirror of ConfidenceCalibrator.calibrate (ConfidenceCalibrator.swift:21-31).

    Linear temperature scaling around 0.5 (NOT sigmoid), clamped to [0, 1],
    then the label-smoothing adjustment. Stage 2 judgment models were trained
    on exactly this transform of the raw 'positive' probability — feeding
    them anything else produces garbage.
    """
    centered = raw - 0.5
    scaled = centered / temperature
    calibrated = min(max(scaled + 0.5, 0.0), 1.0)
    return calibrated * (1.0 - smoothing) + smoothing / 2.0


def stratified_holdout(tracks, fraction=HOLDOUT_FRACTION, seed=SEED):
    """Per-tag stratified split: aims for `fraction` of each tag's positive
    examples in the holdout. Greedy assignment from rarest tag up so scarce
    tags keep their quota; deterministic under the fixed seed. Returns
    (train, holdout) — the SAME holdout evaluates both stages.
    """
    random.seed(seed)

    tag_to_indices = {}
    for i, track in enumerate(tracks):
        for tag in track['tags']:
            tag_to_indices.setdefault(tag, []).append(i)

    assignment = {}  # track index -> 'holdout' | 'train'
    for tag in sorted(tag_to_indices, key=lambda t: (len(tag_to_indices[t]), t)):
        idxs = tag_to_indices[tag]
        target = max(1, round(len(idxs) * fraction))
        already = sum(1 for i in idxs if assignment.get(i) == 'holdout')
        unassigned = [i for i in idxs if i not in assignment]
        random.shuffle(unassigned)
        need = target - already
        for i in unassigned:
            if need > 0:
                assignment[i] = 'holdout'
                need -= 1
            else:
                assignment[i] = 'train'

    leftover = [i for i in range(len(tracks)) if i not in assignment]
    random.shuffle(leftover)
    cut = round(len(leftover) * fraction)
    for j, i in enumerate(leftover):
        assignment[i] = 'holdout' if j < cut else 'train'

    train = [tracks[i] for i in range(len(tracks)) if assignment[i] == 'train']
    holdout = [tracks[i] for i in range(len(tracks)) if assignment[i] == 'holdout']
    return train, holdout


def judgment_value_map(binary_by_stem, group_probs, bpm, duration):
    """Column-name -> value map mirroring JudgmentFeatureVector's producers
    (JudgmentFeatures.swift:33-50): `bin_<stem>` calibrated PRE-BOOST binary
    confidences (stems = model file names, the tagName ProductionStage1Predictor
    feeds the vector), `grp_<group>_<class>` multi-class probabilities, then
    `bpm` / `duration` with the -1.0 missing-value sentinel.
    """
    vm = {}
    for stem, conf in binary_by_stem.items():
        vm[f"bin_{stem}"] = conf
    for group, classes in group_probs.items():
        for cls, prob in classes.items():
            vm[f"grp_{group}_{cls}"] = prob
    vm["bpm"] = bpm if bpm is not None else MISSING_VALUE_SENTINEL
    vm["duration"] = duration if duration is not None else MISSING_VALUE_SENTINEL
    return vm


def build_judgment_input(column_names, value_map):
    """Assemble the Stage 2 model input in EXACTLY metadata judgmentColumnNames
    order (the schema ModelTrainer.trainJudgmentModels persisted). Any
    unresolvable column means schema mismatch: return (None, missing) — the
    caller skips judgment for that track, never feeds garbage.
    """
    missing = [c for c in column_names if c not in value_map]
    if missing:
        return None, missing
    return {c: float(value_map[c]) for c in column_names}, []


def find_judgment_models(model_dir):
    """Map judgment tag file-stem -> model path. Accepts .mlmodel and
    .mlmodelc, preferring .mlmodel (what ModelTrainer writes)."""
    found = {}
    for ext in ("mlmodel", "mlmodelc"):
        for f in sorted(Path(model_dir).glob(f"*_judgment.{ext}")):
            stem = f.stem[: -len("_judgment")]
            found.setdefault(stem, f)
    return found


def load_coreml_model(path):
    if path.suffix == ".mlmodelc":
        return ct.models.CompiledMLModel(str(path))
    return ct.models.MLModel(str(path))


def positive_probability(output):
    """Extract P(positive) from a CreateML classifier output dict."""
    prob_dict = output.get('labelProbability', output.get('probability', {}))
    return prob_dict.get('positive', 0.0)


def sanitize_model_file_name(name):
    """Mirror of ModelTrainer.sanitizeFileName / TaggingEngine.sanitizeModelFileName:
    invalid filename characters and spaces become underscores. Used to write
    threshold keys under the same sanitized-stem alias Swift indexes at load."""
    for ch in '/\\:*?"<>|':
        name = name.replace(ch, '_')
    return name.replace(' ', '_')


# ---------------------------------------------------------------------------
# Shared environment loading
# ---------------------------------------------------------------------------

def load_environment():
    """Locate latest model, load metadata + embedding cache, read ID3 ground
    truth (plus BPM/duration for Stage 2), enforce the dimension guard."""
    app_support = Path.home() / "Library/Application Support/CrateBot"

    # Find latest model
    models_dir = app_support / "Models"
    model_dirs = sorted(
        [d for d in models_dir.iterdir() if d.is_dir()],
        key=lambda d: d.stat().st_mtime, reverse=True
    )
    if not model_dirs:
        print("No trained models found"); return None

    model_dir = model_dirs[0]
    model_name = model_dir.name

    # Load metadata
    with open(model_dir / f"{model_name}.json") as f:
        metadata = json.load(f)

    # Build known tag set from metadata for name resolution
    known_tags = set()
    for cat_tags in metadata.get('tags', {}).values():
        known_tags.update(cat_tags)

    def resolve_tag_name(stem):
        """Map model filename stem back to original tag name."""
        if stem in known_tags: return stem
        slash = stem.replace("_", "/")
        if slash in known_tags: return slash
        space = stem.replace("_", " ")
        if space in known_tags: return space
        return space  # fallback

    # Load embedding cache for features
    print(f"Loading embedding cache...")
    with open(app_support / "embedding_cache.json") as f:
        cache = json.load(f)

    # Read ground-truth tags directly from ID3 via mutagen.
    # Field mapping comes from the app's lexicon.json (the runtime source of
    # truth the training pipeline writes), with the prior hardcoded defaults
    # as a fallback. Reading from hardcoded TALB/TIT1 silently produced
    # garbage ground truth when the user mapped Timing to TPE2 / Mood to TALB.
    from mutagen.id3 import ID3, ID3NoHeaderError
    from mutagen.mp3 import MP3

    DEFAULT_FRAMES = {"genre": "TCON", "timing": "TALB", "mood": "TIT1", "descriptive": "COMM"}
    frames = dict(DEFAULT_FRAMES)
    lexicon_path = os.path.expanduser("~/Library/Application Support/cratebot/lexicon.json")
    try:
        with open(lexicon_path) as lf:
            lex = json.load(lf)
        for k in frames:
            v = (lex.get(k) or {}).get("id3_frame")
            if v: frames[k] = v
        print(f"  Eval ID3 mapping (from lexicon.json): {frames}")
    except Exception as e:
        print(f"  Lexicon.json not loadable ({e}); falling back to hardcoded defaults {frames}")

    def read_track_metadata(path):
        """Returns (tags, bpm, duration). BPM from TBPM (matching
        TrainingDataCollector's bpm field -> "TBPM" mapping), duration from
        the audio header — both None when unavailable (sentinel applied at
        vector-build time, mirroring JudgmentFeatureVector)."""
        try:
            audio = MP3(path, ID3=ID3)
            tags = set()
            # Genre
            f = frames["genre"]
            if f in audio.tags:
                for v in audio.tags[f].text:
                    tags.update(t.strip() for t in str(v).split(',') if t.strip())
            # Timing (single value, no comma split — values like "Build" "Peak" are atomic)
            f = frames["timing"]
            if f in audio.tags:
                for v in audio.tags[f].text:
                    if str(v).strip(): tags.add(str(v).strip())
            # Mood (single value, no comma split)
            f = frames["mood"]
            if f in audio.tags:
                for v in audio.tags[f].text:
                    if str(v).strip(): tags.add(str(v).strip())
            # Descriptive — COMM lookup by key prefix because frames are like 'COMM::eng'
            for k in audio.tags.keys():
                if k.startswith(frames["descriptive"]):
                    for v in audio.tags[k].text:
                        tags.update(t.strip() for t in str(v).split(',') if t.strip())
            # Normalize to title case (match TagNormalizer)
            normalized = set()
            for t in tags:
                parts = [p.strip() for p in t.split('/')]
                norm_parts = []
                for p in parts:
                    words = p.split()
                    norm = ' '.join(w[0].upper() + w[1:].lower() if w else w for w in words)
                    norm_parts.append(norm)
                normalized.add('/'.join(norm_parts))

            bpm = None
            try:
                if 'TBPM' in audio.tags:
                    bpm = float(str(audio.tags['TBPM'].text[0]))
            except Exception:
                bpm = None

            duration = None
            try:
                duration = float(audio.info.length)
            except Exception:
                duration = None

            return normalized, bpm, duration
        except Exception:
            return set(), None, None

    print("Reading ID3 tags from tracks...")
    tracks = []
    for path, entry in cache.items():
        if not entry.get('embeddings'):
            continue
        if not os.path.exists(path):
            continue
        track_tags, bpm, duration = read_track_metadata(path)
        if track_tags:
            tracks.append({
                'id': path, 'tags': list(track_tags), 'features': entry['embeddings'],
                'bpm': bpm, 'duration': duration,
            })

    expected_dim = metadata["featureDimension"]
    bad = [t["id"] for t in tracks if len(t["features"]) != expected_dim]
    if bad:
        sys.exit(
            f"FATAL: {len(bad)} cached vectors do not match model featureDimension "
            f"{expected_dim} (first: {bad[0]}). The embedding cache is stale — "
            f"re-extract before evaluating. Refusing to produce garbage numbers."
        )

    return {
        'model_dir': model_dir,
        'model_name': model_name,
        'metadata': metadata,
        'tracks': tracks,
        'resolve_tag_name': resolve_tag_name,
    }


def load_data_and_run_inference(env):
    """Legacy mode: sample tracks, run binary inference (raw probabilities)."""
    model_dir = env['model_dir']
    metadata = env['metadata']
    tracks = env['tracks']

    # Sample
    random.seed(SEED)
    sampled = random.sample(tracks, min(SAMPLE_SIZE, len(tracks)))

    # Load classifiers — exclude _multiclass and _judgment files, mirroring
    # TaggingEngine's loader (judgment models take JudgmentFeatureVector
    # columns, not f0..fN embedding features).
    model_files = sorted(
        f for f in model_dir.glob("*.mlmodel")
        if not f.stem.endswith("_multiclass") and not f.stem.endswith("_judgment")
    )
    classifiers = {}
    print(f"Loading {len(model_files)} classifiers...")
    for mf in model_files:
        tag_name = env['resolve_tag_name'](mf.stem)
        try:
            classifiers[tag_name] = ct.models.MLModel(str(mf))
        except Exception as e:
            print(f"  Skip {tag_name}: {e}")

    print(f"Loaded: {len(classifiers)} | Tracks: {len(tracks)} | Sample: {len(sampled)}\n")

    # Pre-compute all raw probabilities once
    print("Running inference...")
    # raw_probs[track_idx][tag_name] = float probability
    raw_probs = []
    for i, track in enumerate(sampled):
        feat_dict = {f"f{j}": float(v) for j, v in enumerate(track['features'])}
        probs = {}
        for tag_name, model in classifiers.items():
            try:
                probs[tag_name] = positive_probability(model.predict(feat_dict))
            except:
                pass
        raw_probs.append(probs)
        if (i + 1) % 50 == 0:
            print(f"  {i+1}/{len(sampled)}...")

    return {
        'raw_probs': raw_probs,
        'sampled': sampled,
        'classifiers': classifiers,
        'metadata': metadata,
        'model_dir': model_dir,
    }


def apply_cooccurrence_boost(raw_probs, stats, boost_weight=0.5, confident_threshold=0.8):
    """Apply post-hoc co-occurrence boosting to a list of raw probability dicts.

    Mirrors the Swift TagCooccurrenceBooster logic:
      adjusted_logit(A) = logit(A) + boost_weight * sum_B log(P(A|B) / P(A))
    where B ranges over confident tags (p >= confident_threshold), B != A.
    """
    base_rates = stats['base_rates']
    conditional = stats['conditional']
    boosted = []

    for probs in raw_probs:
        confident = [t for t, p in probs.items() if p >= confident_threshold]
        adjusted = {}
        for tag, p in probs.items():
            log_lift = 0.0
            for c in confident:
                if c == tag:
                    continue
                p_b_given_a = conditional.get(c, {}).get(tag)
                p_b = base_rates.get(tag)
                if p_b_given_a and p_b and p_b > 0:
                    lift = p_b_given_a / p_b
                    if lift > 0:
                        log_lift += math.log(lift)
            if log_lift == 0:
                adjusted[tag] = p
            else:
                eps = 1e-6
                p_clamped = max(eps, min(1 - eps, p))
                logit_p = math.log(p_clamped / (1 - p_clamped))
                adjusted_logit = logit_p + boost_weight * log_lift
                adjusted[tag] = 1 / (1 + math.exp(-adjusted_logit))
        boosted.append(adjusted)
    return boosted


def load_boost_stats():
    stats_path = Path("CrateBotCore/Sources/CrateBotCore/Resources/tag_cooccurrence.json")
    if stats_path.exists():
        with open(stats_path) as f:
            return json.load(f)
    print(f"Warning: {stats_path} not found, running without boost")
    return None


# ---------------------------------------------------------------------------
# Metric helpers
# ---------------------------------------------------------------------------

def per_tag_counts(scores, tracks, tag, threshold):
    tp = fp = fn = tn = 0
    for i, track in enumerate(tracks):
        if tag not in scores[i]:
            continue
        # >= matches Swift's decision rule (`confidence >= threshold` in
        # TaggingEngine) — a strict > here would drift the eval semantics.
        predicted = scores[i][tag] >= threshold
        actual = tag in set(track['tags'])
        if predicted and actual:        tp += 1
        elif predicted and not actual:  fp += 1
        elif not predicted and actual:  fn += 1
        else:                           tn += 1
    return tp, fp, fn, tn


def macro_f1(scores, tracks, tags, threshold):
    """Macro F1 over tags with support > 0 (same convention as the legacy sweep)."""
    f1s = []
    for tag in tags:
        tp, fp, fn, _ = per_tag_counts(scores, tracks, tag, threshold)
        if tp + fn == 0:
            continue
        prec = tp / (tp + fp) if (tp + fp) > 0 else 0
        rec = tp / (tp + fn) if (tp + fn) > 0 else 0
        f1s.append(2 * prec * rec / (prec + rec) if (prec + rec) > 0 else 0)
    return (sum(f1s) / len(f1s), len(f1s)) if f1s else (0.0, 0)


def best_uniform_f1(scores, tracks, tags, sweep=STAGE_THRESHOLDS):
    best_f1, best_thresh, supported = 0.0, sweep[0], 0
    for threshold in sweep:
        f1, n = macro_f1(scores, tracks, tags, threshold)
        if f1 > best_f1:
            best_f1, best_thresh, supported = f1, threshold, n
    return best_f1, best_thresh, supported


# ---------------------------------------------------------------------------
# Stage-aware evaluation
# ---------------------------------------------------------------------------

def run_stage_aware(env, use_boost, use_optimize):
    model_dir = env['model_dir']
    metadata = env['metadata']
    tracks = env['tracks']

    # ProductionStage1Predictor.load: metadata temperature when present,
    # else the default calibrator (temperature 1.0); smoothing fixed at 0.1.
    temperature = metadata.get('calibratorTemperature') or 1.0

    # Partition tags by stage (TagStageRegistry.defaultMapping: Timing ->
    # judgment, everything else including unknown categories -> perception).
    perception_tags, judgment_tags = set(), set()
    for category, cat_tags in metadata.get('tags', {}).items():
        bucket = judgment_tags if category.lower() in JUDGMENT_CATEGORIES else perception_tags
        bucket.update(cat_tags)

    judgment_columns = metadata.get('judgmentColumnNames')
    judgment_model_paths = find_judgment_models(model_dir)
    judgment_available = bool(judgment_model_paths) and bool(judgment_columns)

    train_split, holdout = stratified_holdout(tracks)
    print(f"\nStratified holdout: {len(holdout)} eval / {len(train_split)} train "
          f"({HOLDOUT_FRACTION:.0%} per tag, seed {SEED}) — same holdout for both stages")
    print("  WARNING (contamination): this holdout is drawn from the same tracks the "
          "loaded models were TRAINED on, so absolute numbers are in-sample-optimistic. "
          f"The {BASELINE_MACRO_F1:.1f}% baseline was measured identically, so the "
          "RELATIVE comparison stands. Clean absolute numbers require a training-side "
          "holdout — a known limitation, not fixed here.")

    # --- Load Stage 1 binary classifiers (mirrors ProductionStage1Predictor.load:
    # every model file except _multiclass / _judgment suffixes) ---
    classifiers = {}    # resolved tag -> model
    stem_for_tag = {}   # resolved tag -> file stem (the bin_<stem> column key)
    for mf in sorted(model_dir.glob("*.mlmodel")):
        if mf.stem.endswith("_multiclass") or mf.stem.endswith("_judgment"):
            continue
        tag = env['resolve_tag_name'](mf.stem)
        try:
            classifiers[tag] = ct.models.MLModel(str(mf))
            stem_for_tag[tag] = mf.stem
        except Exception as e:
            print(f"  Skip {tag}: {e}")

    # --- Multi-class group models (metadata tagGroups -> <group>_multiclass) ---
    group_models = {}
    for group_info in metadata.get('tagGroups', []):
        gname = group_info['groupName']
        for ext in ('mlmodel', 'mlmodelc'):
            path = model_dir / f"{gname}_multiclass.{ext}"
            if path.exists():
                try:
                    group_models[gname] = load_coreml_model(path)
                except Exception as e:
                    print(f"  Skip group {gname}: {e}")
                break

    # --- Stage 2 judgment models ---
    judgment_models = {}
    if judgment_available:
        for stem, path in judgment_model_paths.items():
            tag = env['resolve_tag_name'](stem)
            try:
                judgment_models[tag] = load_coreml_model(path)
            except Exception as e:
                print(f"  Skip judgment {tag}: {e}")
        judgment_available = bool(judgment_models)

    print(f"Loaded: {len(classifiers)} binary | {len(group_models)} multi-class | "
          f"{len(judgment_models)} judgment | temperature {temperature}")

    # --- Inference over the holdout ---
    print("Running stage-aware inference...")
    calibrated_probs = []   # all binary tags, calibrated PRE-BOOST (Stage 2's input)
    judgment_probs = []     # judgment tag -> P(positive) from <tag>_judgment
    judgment_skipped = 0
    missing_reported = False

    for i, track in enumerate(holdout):
        feat_dict = {f"f{j}": float(v) for j, v in enumerate(track['features'])}

        raw = {}
        for tag_name, model in classifiers.items():
            try:
                raw[tag_name] = positive_probability(model.predict(feat_dict))
            except Exception:
                pass
        # Calibrate exactly as TaggingEngine pass 1 / ProductionStage1Predictor:
        # predictWithConfidence -> ConfidenceCalibrator.calibrate, pre-boost.
        cal = {t: calibrate_confidence(p, temperature) for t, p in raw.items()}
        calibrated_probs.append(cal)

        jp = {}
        if judgment_available:
            group_probs = {}
            for gname, gmodel in group_models.items():
                try:
                    output = gmodel.predict(feat_dict)
                    prob_dict = output.get('labelProbability', output.get('probability', {}))
                    group_probs[gname] = {str(k): float(v) for k, v in prob_dict.items()}
                except Exception:
                    pass
            binary_by_stem = {stem_for_tag[t]: c for t, c in cal.items() if t in stem_for_tag}
            value_map = judgment_value_map(
                binary_by_stem, group_probs, track.get('bpm'), track.get('duration'))
            jinput, missing = build_judgment_input(judgment_columns, value_map)
            if jinput is None:
                judgment_skipped += 1
                if not missing_reported:
                    print(f"  WARNING: judgment schema mismatch — missing columns "
                          f"{missing[:6]}{'...' if len(missing) > 6 else ''}; "
                          f"skipping judgment for affected tracks")
                    missing_reported = True
            else:
                for tag_name, jmodel in judgment_models.items():
                    try:
                        jp[tag_name] = positive_probability(jmodel.predict(jinput))
                    except Exception:
                        pass
        judgment_probs.append(jp)

        if (i + 1) % 50 == 0:
            print(f"  {i+1}/{len(holdout)}...")

    if judgment_skipped:
        print(f"  Judgment skipped for {judgment_skipped}/{len(holdout)} tracks (schema mismatch)")

    # --- Final pipeline scores ---
    # Perception: calibrated (+ boost if requested — booster scoped to
    # perception only, mirroring TaggingEngine's Stage 2 rewire; Stage 2
    # already consumed the pre-boost snapshot above).
    perception_scores = [
        {t: p for t, p in cal.items() if t in perception_tags}
        for cal in calibrated_probs
    ]
    if use_boost:
        stats = load_boost_stats()
        if stats:
            print("Applying co-occurrence boost (perception tags only)...")
            perception_scores = apply_cooccurrence_boost(perception_scores, stats)

    final_scores = []
    for i in range(len(holdout)):
        s = dict(perception_scores[i])
        s.update(judgment_probs[i])  # Timing tags come from Stage 2 ONLY
        final_scores.append(s)

    eval_perception = sorted(t for t in perception_tags if t in classifiers)
    eval_judgment = sorted(judgment_models.keys())

    # --- Report ---
    print(f"\n{'='*70}")
    print(f"  TWO-STAGE EVALUATION — {env['model_name']} (holdout n={len(holdout)})")
    print(f"{'='*70}")

    s1_f1, s1_thresh, s1_n = best_uniform_f1(final_scores, holdout, eval_perception)
    print(f"  Stage 1 (perception, {len(eval_perception)} tags, {s1_n} with support): "
          f"macro F1 {s1_f1*100:.1f}% @ uniform threshold {s1_thresh:.2f}")

    if not judgment_available:
        print(f"  Stage 2 (judgment): NO judgment models present "
              f"(_judgment files: {len(judgment_model_paths)}, "
              f"judgmentColumnNames: {'present' if judgment_columns else 'absent'}).")
        print(f"  Pre-retrain state — reporting Stage 1 only. "
              f"Run the two-phase retrain to produce Stage 2 models.")
        print(f"  vs baseline {BASELINE_MACRO_F1:.1f}%: Stage 1 alone is not comparable "
              f"(baseline includes Timing tags).")
        if use_optimize:
            print(f"  Skipping --optimize: writing tag_thresholds.json without "
                  f"Timing entries would clobber the full threshold set.")
        print(f"{'='*70}\n")
        return

    s2_f1, s2_thresh, s2_n = best_uniform_f1(final_scores, holdout, eval_judgment)
    all_tags = eval_perception + eval_judgment
    comb_f1, comb_thresh, comb_n = best_uniform_f1(final_scores, holdout, all_tags)

    print(f"  Stage 2 (judgment,   {len(eval_judgment)} tags, {s2_n} with support): "
          f"macro F1 {s2_f1*100:.1f}% @ uniform threshold {s2_thresh:.2f}")
    print(f"  Combined ({len(all_tags)} tags, {comb_n} with support):           "
          f"macro F1 {comb_f1*100:.1f}% @ uniform threshold {comb_thresh:.2f}")
    delta = comb_f1 * 100 - BASELINE_MACRO_F1
    print(f"\n  Combined vs {BASELINE_MACRO_F1:.1f}% baseline: {delta:+.1f} points "
          f"(success gate: >= 45.0%)")
    print(f"{'='*70}\n")

    if use_optimize:
        results = optimize_thresholds(
            final_scores, holdout, all_tags, model_dir,
            sweep_lo=0.05, sweep_hi=0.95)

        def subset_macro(tags):
            rs = [r for t, r in results.items() if t in tags and r['support'] > 0]
            return (sum(r['f1'] for r in rs) / len(rs), len(rs)) if rs else (0.0, 0)

        o1, n1 = subset_macro(set(eval_perception))
        o2, n2 = subset_macro(set(eval_judgment))
        oc, nc = subset_macro(set(all_tags))
        print(f"  OPTIMIZED (per-tag thresholds on final pipeline scores):")
        print(f"    Stage 1 macro F1: {o1*100:.1f}% ({n1} tags)")
        print(f"    Stage 2 macro F1: {o2*100:.1f}% ({n2} tags)")
        print(f"    Combined macro F1: {oc*100:.1f}% ({nc} tags) — "
              f"vs {BASELINE_MACRO_F1:.1f}% baseline: {oc*100 - BASELINE_MACRO_F1:+.1f} points")
        print()


# ---------------------------------------------------------------------------
# Legacy sweep + optimizer
# ---------------------------------------------------------------------------

def threshold_sweep(data):
    """Run the standard threshold sweep across all tags uniformly."""
    raw_probs = data['raw_probs']
    sampled = data['sampled']
    classifiers = data['classifiers']
    metadata = data['metadata']

    print(f"\n{'='*70}")
    print(f"  CRATEBOT CB5_v3 — THRESHOLD SWEEP")
    print(f"  {len(sampled)} tracks, {len(classifiers)} tags, {metadata['featureDimension']}-dim")
    print(f"{'='*70}\n")

    # Summary table header
    print(f"  {'Thresh':>6s}  {'Accuracy':>8s}  {'MacroF1':>7s}  {'AvgPrec':>7s}  {'AvgRec':>7s}  {'F1>70%':>6s}  {'F1>50%':>6s}")
    print(f"  {'-'*62}")

    best_f1 = 0
    best_thresh = 0.5
    best_detail = None

    for threshold in THRESHOLDS:
        tag_tp, tag_fp, tag_fn, tag_tn = {}, {}, {}, {}
        for tag in classifiers:
            tag_tp[tag] = tag_fp[tag] = tag_fn[tag] = tag_tn[tag] = 0

        total_correct = 0
        total_pred = 0

        for i, track in enumerate(sampled):
            ground_truth = set(track['tags'])
            for tag_name in classifiers:
                if tag_name not in raw_probs[i]: continue
                # >= matches Swift's `confidence >= threshold` decision rule.
                predicted = raw_probs[i][tag_name] >= threshold
                actual = tag_name in ground_truth

                if predicted and actual:      tag_tp[tag_name] += 1; total_correct += 1
                elif predicted and not actual: tag_fp[tag_name] += 1
                elif not predicted and actual: tag_fn[tag_name] += 1
                else:                          tag_tn[tag_name] += 1; total_correct += 1
                total_pred += 1

        # Compute per-tag metrics
        tag_results = []
        for tag in classifiers:
            tp, fp, fn, tn = tag_tp[tag], tag_fp[tag], tag_fn[tag], tag_tn[tag]
            support = tp + fn
            prec = tp / (tp + fp) if (tp + fp) > 0 else 0
            rec = tp / (tp + fn) if (tp + fn) > 0 else 0
            f1 = 2*prec*rec/(prec+rec) if (prec+rec) > 0 else 0
            acc = (tp + tn) / (tp + tn + fp + fn) if (tp + tn + fp + fn) > 0 else 0
            tag_results.append((tag, prec, rec, f1, acc, support))

        with_support = [r for r in tag_results if r[5] > 0]
        macro_f1_val = sum(r[3] for r in with_support) / len(with_support) if with_support else 0
        avg_prec = sum(r[1] for r in with_support) / len(with_support) if with_support else 0
        avg_rec = sum(r[2] for r in with_support) / len(with_support) if with_support else 0
        overall_acc = total_correct / total_pred if total_pred > 0 else 0
        f1_above_70 = sum(1 for r in with_support if r[3] >= 0.7)
        f1_above_50 = sum(1 for r in with_support if r[3] >= 0.5)

        print(f"  {threshold:6.2f}  {overall_acc*100:7.1f}%  {macro_f1_val*100:6.1f}%  {avg_prec*100:6.1f}%  {avg_rec*100:6.1f}%  {f1_above_70:5d}  {f1_above_50:5d}")

        if macro_f1_val > best_f1:
            best_f1 = macro_f1_val
            best_thresh = threshold
            best_detail = sorted(tag_results, key=lambda r: r[5], reverse=True)

    print(f"  {'-'*62}")
    print(f"  Best macro F1: {best_f1*100:.1f}% at threshold {best_thresh:.2f}")

    # Print detailed results at best threshold
    print(f"\n{'='*70}")
    print(f"  DETAILED RESULTS @ threshold={best_thresh:.2f}")
    print(f"{'='*70}")
    print(f"\n  {'Tag':<25s} {'Prec':>6s} {'Recall':>6s} {'F1':>6s} {'Acc':>6s} {'Pos':>5s}")
    print(f"  {'-'*60}")

    for tag, prec, rec, f1, acc, support in best_detail:
        marker = ""
        if support > 0:
            if f1 >= 0.7: marker = " +++"
            elif f1 >= 0.5: marker = " +"
            elif f1 < 0.3 and support >= 5: marker = " !!!"
        print(f"  {tag[:25]:<25s} {prec*100:5.1f}% {rec*100:5.1f}% {f1*100:5.1f}% {acc*100:5.1f}% {support:4d}{marker}")

    print(f"  {'-'*60}")
    print(f"{'='*70}\n")


def optimize_thresholds(scores, tracks, tag_names, model_dir, sweep_lo=0.50, sweep_hi=0.99):
    """Per-tag threshold optimization on the given scores (legacy: raw probs;
    stage-aware: FINAL pipeline scores — post-calibration, post-judgment for
    Timing tags). Sweeps independently per tag, maximizes F1, writes
    tag_thresholds.json in the existing nested format."""
    n_steps = int(round((sweep_hi - sweep_lo) / 0.01)) + 1
    sweep_thresholds = [round(sweep_lo + i * 0.01, 2) for i in range(n_steps)]

    print(f"\n{'='*70}")
    print(f"  PER-TAG THRESHOLD OPTIMIZATION")
    print(f"  {len(tracks)} tracks, {len(tag_names)} tags")
    print(f"  Sweeping {len(sweep_thresholds)} thresholds per tag ({sweep_lo:.2f} - {sweep_hi:.2f})")
    print(f"{'='*70}\n")

    results = {}

    for tag_name in sorted(tag_names):
        best_f1 = 0.0
        best_thresh = sweep_lo
        best_prec = 0.0
        best_rec = 0.0
        support = 0

        for threshold in sweep_thresholds:
            tp, fp, fn, tn = per_tag_counts(scores, tracks, tag_name, threshold)

            prec = tp / (tp + fp) if (tp + fp) > 0 else 0
            rec = tp / (tp + fn) if (tp + fn) > 0 else 0
            f1 = 2 * prec * rec / (prec + rec) if (prec + rec) > 0 else 0
            tag_support = tp + fn

            if f1 > best_f1:
                best_f1 = f1
                best_thresh = threshold
                best_prec = prec
                best_rec = rec
                support = tag_support

        results[tag_name] = {
            'threshold': best_thresh,
            'f1': round(best_f1, 4),
            'precision': round(best_prec, 4),
            'recall': round(best_rec, 4),
            'support': support,
        }

    # Print results table
    print(f"  {'Tag':<25s} {'Thresh':>6s} {'Prec':>6s} {'Recall':>6s} {'F1':>6s} {'Pos':>5s}")
    print(f"  {'-'*60}")

    sorted_results = sorted(results.items(), key=lambda r: r[1]['support'], reverse=True)
    for tag, r in sorted_results:
        marker = ""
        if r['support'] > 0:
            if r['f1'] >= 0.7: marker = " +++"
            elif r['f1'] >= 0.5: marker = " +"
            elif r['f1'] < 0.3 and r['support'] >= 5: marker = " !!!"
        print(f"  {tag[:25]:<25s} {r['threshold']:6.2f} {r['precision']*100:5.1f}% {r['recall']*100:5.1f}% {r['f1']*100:5.1f}% {r['support']:4d}{marker}")

    print(f"  {'-'*60}")

    # Summary stats
    with_support = [r for _, r in sorted_results if r['support'] > 0]
    if with_support:
        macro = sum(r['f1'] for r in with_support) / len(with_support)
        f1_above_70 = sum(1 for r in with_support if r['f1'] >= 0.7)
        f1_above_50 = sum(1 for r in with_support if r['f1'] >= 0.5)
        avg_thresh = sum(r['threshold'] for r in with_support) / len(with_support)
        print(f"\n  Optimized macro F1: {macro*100:.1f}%")
        print(f"  Tags with F1 >= 70%: {f1_above_70}/{len(with_support)}")
        print(f"  Tags with F1 >= 50%: {f1_above_50}/{len(with_support)}")
        print(f"  Average optimal threshold: {avg_thresh:.2f}")

    # Save JSON — only thresholds map for direct consumption by the app.
    # Each tag is written under BOTH its resolved name and its sanitized
    # model-file stem (first-wins, never overwriting an explicit key), so the
    # lookup resolves regardless of which form Swift queries with. Swift also
    # dual-keys at load (TaggingEngine.addingSanitizedStemAliases) — this is
    # the matching producer-side alignment.
    tags_out = dict(results)
    for tag in sorted(results):
        alias = sanitize_model_file_name(tag)
        if alias != tag and alias not in tags_out:
            tags_out[alias] = results[tag]

    out_path = model_dir / "tag_thresholds.json"
    output = {
        'description': 'Per-tag optimized thresholds (maximized F1 on eval set)',
        'sample_size': len(tracks),
        'tags': tags_out,
    }
    with open(out_path, 'w') as f:
        json.dump(output, f, indent=2)
    print(f"\n  Saved: {out_path}")
    print(f"{'='*70}\n")

    return results


def main():
    env = load_environment()
    if env is None:
        return

    if '--stage-aware' in sys.argv:
        run_stage_aware(env, use_boost='--boost' in sys.argv,
                        use_optimize='--optimize' in sys.argv)
        return

    data = load_data_and_run_inference(env)

    if '--boost' in sys.argv:
        stats = load_boost_stats()
        if stats:
            print(f"\nApplying co-occurrence boost...")
            data['raw_probs'] = apply_cooccurrence_boost(data['raw_probs'], stats)
            print(f"Boosted {len(data['raw_probs'])} probability dicts\n")

    threshold_sweep(data)

    if '--optimize' in sys.argv:
        optimize_thresholds(
            data['raw_probs'], data['sampled'],
            list(data['classifiers'].keys()), data['model_dir'])


if __name__ == "__main__":
    main()
