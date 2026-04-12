#!/usr/bin/env python3
"""
Generate tag co-occurrence statistics from the current library.
Reads ID3 tags from tracks in the embedding cache, computes base rates
and conditional probabilities, saves as JSON for Swift to load.
"""
import json, os, sys
from collections import defaultdict, Counter
from pathlib import Path
from mutagen.id3 import ID3
from mutagen.mp3 import MP3

def read_tags(path):
    """Read ID3 tags using the same fields as TrainingDataCollector."""
    try:
        audio = MP3(path, ID3=ID3)
        if audio.tags is None:
            return set()
        tags = set()
        # Genre (TCON)
        if 'TCON' in audio.tags:
            for v in audio.tags['TCON'].text:
                tags.update(t.strip() for t in str(v).split(',') if t.strip())
        # Timing (TALB - album field)
        if 'TALB' in audio.tags:
            for v in audio.tags['TALB'].text:
                if str(v).strip(): tags.add(str(v).strip())
        # Mood (TIT1 - content group)
        if 'TIT1' in audio.tags:
            for v in audio.tags['TIT1'].text:
                if str(v).strip(): tags.add(str(v).strip())
        # Descriptive (COMM)
        for k in audio.tags.keys():
            if k.startswith('COMM'):
                for v in audio.tags[k].text:
                    tags.update(t.strip() for t in str(v).split(',') if t.strip())
        # Normalize to title case (match TagNormalizer)
        normalized = set()
        for t in tags:
            parts = [p.strip() for p in t.split('/')]
            nps = []
            for p in parts:
                words = p.split()
                nps.append(' '.join(w[0].upper() + w[1:].lower() if w else w for w in words))
            normalized.add('/'.join(nps))
        return normalized
    except Exception:
        return set()

def main():
    app_support = Path.home() / "Library/Application Support/CrateBot"
    cache_path = app_support / "embedding_cache.json"
    models_dir = app_support / "Models"

    # Find latest model to get known tags
    model_dirs = sorted(
        [d for d in models_dir.iterdir() if d.is_dir()],
        key=lambda d: d.stat().st_mtime, reverse=True
    )
    if not model_dirs:
        print("No trained models found"); return

    with open(model_dirs[0] / f"{model_dirs[0].name}.json") as f:
        meta = json.load(f)
    known = set()
    for tags in meta['tags'].values():
        known.update(tags)

    # Read ID3 tags from every track in the cache
    with open(cache_path) as f:
        cache = json.load(f)

    print(f"Reading ID3 tags from {len(cache)} tracks...")
    track_tags = []
    for path in cache:
        if os.path.exists(path):
            t = read_tags(path) & known
            if t:
                track_tags.append(t)

    N = len(track_tags)
    print(f"Analyzed {N} tracks with at least one known tag")

    # Compute stats
    single = Counter()
    for t in track_tags:
        for tag in t:
            single[tag] += 1

    co = defaultdict(lambda: defaultdict(int))
    for t in track_tags:
        tl = list(t)
        for i in range(len(tl)):
            for j in range(len(tl)):
                if i != j:
                    co[tl[i]][tl[j]] += 1

    # Build output
    stats = {
        'version': 1,
        'total_tracks': N,
        'base_rates': {tag: round(count / N, 4) for tag, count in single.items()},
        'conditional': {}
    }

    MIN_SUPPORT = 10
    LIFT_THRESHOLD_HIGH = 1.5
    LIFT_THRESHOLD_LOW = 0.5

    for a in single:
        if single[a] < MIN_SUPPORT:
            continue
        conditionals = {}
        p_a = single[a] / N
        for b in co[a]:
            if single[b] < MIN_SUPPORT:
                continue
            p_b_given_a = co[a][b] / single[a]
            p_b = single[b] / N
            lift = p_b_given_a / p_b if p_b > 0 else 0
            if lift >= LIFT_THRESHOLD_HIGH or lift <= LIFT_THRESHOLD_LOW:
                conditionals[b] = round(p_b_given_a, 4)
        if conditionals:
            stats['conditional'][a] = conditionals

    output_path = Path("CrateBotCore/Sources/CrateBotCore/Resources/tag_cooccurrence.json")
    with open(output_path, 'w') as f:
        json.dump(stats, f, indent=2, sort_keys=True)

    total_cond = sum(len(v) for v in stats['conditional'].values())
    print(f"Saved {len(stats['base_rates'])} base rates and {total_cond} conditional probabilities")
    print(f"Output: {output_path}")

if __name__ == "__main__":
    main()
