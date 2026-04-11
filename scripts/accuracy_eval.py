#!/usr/bin/env python3
"""
CrateBot Accuracy Evaluation
Loads trained models + checkpoint data, runs inference at multiple thresholds.
"""

import json, os, sys, random
import coremltools as ct
from pathlib import Path

SAMPLE_SIZE = 200
SEED = 42
THRESHOLDS = [0.50, 0.55, 0.60, 0.65, 0.70, 0.75, 0.80, 0.85, 0.90, 0.92, 0.94, 0.96, 0.98, 0.99, 0.995]

def load_data_and_run_inference():
    """Load models, checkpoint, cache. Run inference. Return everything needed for evaluation."""
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

    # Load checkpoint (ground truth tags) + embedding cache (2192-dim features)
    cp_dir = app_support / "Checkpoints"
    cp_files = sorted(cp_dir.glob("*.json"), key=lambda f: f.stat().st_mtime, reverse=True)
    if not cp_files:
        print("No checkpoint found"); return None

    print(f"Loading checkpoint + cache...")
    with open(cp_files[0]) as f:
        checkpoint = json.load(f)

    tag_lookup = {t['id']: t['tags'] for t in checkpoint['processedTracks']}

    with open(app_support / "embedding_cache.json") as f:
        cache = json.load(f)

    # Join tracks with both tags and features
    tracks = []
    for path, entry in cache.items():
        if path in tag_lookup and entry.get('embeddings'):
            tracks.append({'id': path, 'tags': tag_lookup[path], 'features': entry['embeddings']})

    # Sample
    random.seed(SEED)
    sampled = random.sample(tracks, min(SAMPLE_SIZE, len(tracks)))

    # Load classifiers
    model_files = sorted(f for f in model_dir.glob("*.mlmodel") if "multiclass" not in f.name)
    classifiers = {}
    print(f"Loading {len(model_files)} classifiers...")
    for mf in model_files:
        tag_name = resolve_tag_name(mf.stem)
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
                output = model.predict(feat_dict)
                prob_dict = output.get('labelProbability', output.get('probability', {}))
                probs[tag_name] = prob_dict.get('positive', 0.0)
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
                predicted = raw_probs[i][tag_name] > threshold
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
        macro_f1 = sum(r[3] for r in with_support) / len(with_support) if with_support else 0
        avg_prec = sum(r[1] for r in with_support) / len(with_support) if with_support else 0
        avg_rec = sum(r[2] for r in with_support) / len(with_support) if with_support else 0
        overall_acc = total_correct / total_pred if total_pred > 0 else 0
        f1_above_70 = sum(1 for r in with_support if r[3] >= 0.7)
        f1_above_50 = sum(1 for r in with_support if r[3] >= 0.5)

        print(f"  {threshold:6.2f}  {overall_acc*100:7.1f}%  {macro_f1*100:6.1f}%  {avg_prec*100:6.1f}%  {avg_rec*100:6.1f}%  {f1_above_70:5d}  {f1_above_50:5d}")

        if macro_f1 > best_f1:
            best_f1 = macro_f1
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


def optimize_thresholds(data):
    """Per-tag threshold optimization. Sweeps 0.50-0.99 independently per tag, maximizes F1."""
    raw_probs = data['raw_probs']
    sampled = data['sampled']
    classifiers = data['classifiers']
    model_dir = data['model_dir']

    sweep_thresholds = [round(0.50 + i * 0.01, 2) for i in range(50)]  # 0.50 to 0.99

    print(f"\n{'='*70}")
    print(f"  PER-TAG THRESHOLD OPTIMIZATION")
    print(f"  {len(sampled)} tracks, {len(classifiers)} tags")
    print(f"  Sweeping {len(sweep_thresholds)} thresholds per tag (0.50 - 0.99)")
    print(f"{'='*70}\n")

    results = {}

    for tag_name in sorted(classifiers.keys()):
        best_f1 = 0.0
        best_thresh = 0.50
        best_prec = 0.0
        best_rec = 0.0
        support = 0

        for threshold in sweep_thresholds:
            tp = fp = fn = tn = 0

            for i, track in enumerate(sampled):
                if tag_name not in raw_probs[i]:
                    continue
                predicted = raw_probs[i][tag_name] > threshold
                actual = tag_name in set(track['tags'])

                if predicted and actual:      tp += 1
                elif predicted and not actual: fp += 1
                elif not predicted and actual: fn += 1
                else:                          tn += 1

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
        macro_f1 = sum(r['f1'] for r in with_support) / len(with_support)
        f1_above_70 = sum(1 for r in with_support if r['f1'] >= 0.7)
        f1_above_50 = sum(1 for r in with_support if r['f1'] >= 0.5)
        avg_thresh = sum(r['threshold'] for r in with_support) / len(with_support)
        print(f"\n  Optimized macro F1: {macro_f1*100:.1f}%")
        print(f"  Tags with F1 >= 70%: {f1_above_70}/{len(with_support)}")
        print(f"  Tags with F1 >= 50%: {f1_above_50}/{len(with_support)}")
        print(f"  Average optimal threshold: {avg_thresh:.2f}")

    # Save JSON — only thresholds map for direct consumption by the app
    out_path = model_dir / "tag_thresholds.json"
    output = {
        'description': 'Per-tag optimized thresholds (maximized F1 on eval set)',
        'sample_size': len(sampled),
        'tags': results,
    }
    with open(out_path, 'w') as f:
        json.dump(output, f, indent=2)
    print(f"\n  Saved: {out_path}")
    print(f"{'='*70}\n")


def main():
    data = load_data_and_run_inference()
    if data is None:
        return

    threshold_sweep(data)

    if '--optimize' in sys.argv:
        optimize_thresholds(data)


if __name__ == "__main__":
    main()
