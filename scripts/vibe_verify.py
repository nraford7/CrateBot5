#!/usr/bin/env python3
"""
CrateBot Vibe Generator v2 — Chunk 5 verification harness.

Checks the three success criteria from the spec
(docs/superpowers/specs/2026-06-13-vibe-generator-v2-design.md) over a
directory of MP3 files that were just tagged with the AI Descriptions
toggle on.

Frames read:
- TCOM (vibe short)
- TIT3 (vibe description / prose)
- MVNM (movement / DJ-use mix hint)

Run:
    python3 scripts/vibe_verify.py /path/to/tagged/mp3s [--limit N]

Exit code 0 if all three criteria pass, 1 otherwise.
"""

from __future__ import annotations

import argparse
import os
import re
import sys
from collections import Counter, defaultdict
from pathlib import Path

try:
    from mutagen.id3 import ID3, ID3NoHeaderError
    from mutagen.mp3 import MP3  # noqa: F401  (kept for parity with sibling scripts)
except ImportError:  # pragma: no cover
    sys.stderr.write("mutagen is required. pip install mutagen\n")
    sys.exit(2)


# Phrases that indicate chain-of-thought leaked into the user-facing field.
COT_PATTERNS = [
    re.compile(r"^\s*LOOKING AT", re.IGNORECASE),
    re.compile(r"^\s*ANALYZING", re.IGNORECASE),
    re.compile(r"^\s*PROCESS\s*:", re.IGNORECASE),
    re.compile(r"^\s*STEP\s*\d", re.IGNORECASE),
    re.compile(r"^\s*Let me ", re.IGNORECASE),
    re.compile(r"^\s*Here\s*'s the analysis", re.IGNORECASE),
    re.compile(r"^\s*```", re.IGNORECASE),
    re.compile(r"^\s*\{", re.IGNORECASE),  # raw JSON leaked into TCOM
    re.compile(r"^\s*VIBE\s*:", re.IGNORECASE),  # legacy CrateBot4 marker
    re.compile(r"^\s*REASONING", re.IGNORECASE),
]

SHORT_RE = re.compile(r"^[A-Z]+(?: [A-Z]+){3,4}$")
ARTICLES = {"A", "AN", "THE"}
DJ_CUES = {
    "drop", "slot", "bridge", "open", "cut", "follow", "save", "pair", "hold",
    "stack", "after", "before", "between", "from", "into", "when", "build",
    "lift", "shift", "release", "reset", "transition", "segue", "opener",
    "closer", "warmup", "energy", "toughness", "drums", "break", "breakdown",
}
LONG_DJ_WORDS = {
    "dj", "mix", "drop", "play", "set", "slot", "opener", "closer",
    "warmup", "transition", "segue", "blend", "cue", "follow",
}
STOPWORDS = {
    "the", "a", "an", "and", "or", "of", "to", "in", "on", "at", "by",
    "for", "with", "from", "into", "after", "before", "between", "when",
    "then", "than", "that", "this", "these", "those", "is", "are", "was",
    "were", "be", "been", "being", "it", "its", "as", "but", "not", "no",
    "so", "if", "you", "your", "their", "there", "here", "over", "under",
    "through", "track", "field", "music", "record",
}


def read_frame(tag: ID3, frame_id: str) -> str | None:
    if tag is None:
        return None
    frame = tag.get(frame_id)
    if frame is None:
        return None
    # mutagen text frames carry a list of strings; join non-empty entries.
    text = " ".join(str(t) for t in getattr(frame, "text", [str(frame)]) if t)
    text = text.strip()
    return text if text else None


def ngrams(words: list[str], n: int = 4):
    return [" ".join(words[i : i + n]).lower() for i in range(0, len(words) - n + 1)]


def words(text: str) -> list[str]:
    return re.findall(r"[A-Za-z0-9']+", text.lower())


def significant(text: str) -> set[str]:
    return {w for w in words(text) if len(w) >= 3 and w not in STOPWORDS}


def sliding_window_repeats(descriptions: list[str], window: int = 30, n: int = 4, max_repeats: int = 2):
    """Return list of (start_idx, ngram, count) tuples where an n-gram appears
    more than max_repeats times in any contiguous window of `window` items.
    """
    tokenized = [re.findall(r"[A-Za-z']+", d.lower()) for d in descriptions]
    grams = [ngrams(tok, n) for tok in tokenized]
    offenders: list[tuple[int, str, int]] = []
    for start in range(0, max(1, len(grams) - window + 1)):
        window_grams = grams[start : start + window]
        counts = Counter(g for batch in window_grams for g in batch)
        for gram, c in counts.items():
            if c > max_repeats and len(gram.split()) == n:
                offenders.append((start, gram, c))
    return offenders


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("directory", help="Directory of MP3 files to scan")
    parser.add_argument("--limit", type=int, default=None, help="Only scan the first N files (sorted)")
    parser.add_argument("--verbose", action="store_true", help="Print per-track frames")
    args = parser.parse_args()

    root = Path(args.directory).expanduser().resolve()
    if not root.is_dir():
        sys.stderr.write(f"not a directory: {root}\n")
        return 2

    mp3s = sorted(p for p in root.rglob("*.mp3"))
    if args.limit:
        mp3s = mp3s[: args.limit]
    if not mp3s:
        sys.stderr.write(f"no .mp3 files under {root}\n")
        return 2

    print(f"Scanning {len(mp3s)} files under {root}")
    print("=" * 72)

    cot_violations: list[tuple[Path, str]] = []
    descriptions: list[str] = []
    description_paths: list[Path] = []
    mix_hints: list[tuple[Path, str]] = []
    no_short: list[Path] = []
    no_long: list[Path] = []
    no_mix: list[Path] = []
    bad_short: list[tuple[Path, str]] = []
    long_with_dj_words: list[tuple[Path, str, str]] = []
    mix_with_cue: list[tuple[Path, str]] = []
    mix_without_cue: list[tuple[Path, str]] = []
    mix_repeats_description: list[tuple[Path, str, str]] = []
    total_with_short = 0

    for path in mp3s:
        try:
            tag = ID3(path)
        except ID3NoHeaderError:
            tag = None
        except Exception as exc:  # pragma: no cover
            print(f"  ! {path.name}: {exc}")
            continue

        short = read_frame(tag, "TCOM")
        long_desc = read_frame(tag, "TIT3")
        mix = read_frame(tag, "MVNM")

        if args.verbose:
            print(f"{path.name}")
            print(f"  TCOM: {short!r}")
            print(f"  TIT3: {long_desc!r}")
            print(f"  MVNM: {mix!r}")

        if short:
            total_with_short += 1
            short_words = short.split()
            if (
                not SHORT_RE.fullmatch(short)
                or any(w in ARTICLES for w in short_words)
                or any(len(w) > 12 for w in short_words)
            ):
                bad_short.append((path, short))
            for pat in COT_PATTERNS:
                if pat.search(short):
                    cot_violations.append((path, short))
                    break
        else:
            no_short.append(path)

        if long_desc:
            descriptions.append(long_desc)
            description_paths.append(path)
            long_tokens = set(words(long_desc))
            for token in sorted(long_tokens & LONG_DJ_WORDS):
                long_with_dj_words.append((path, long_desc, token))
                break
        else:
            no_long.append(path)

        if mix:
            mix_hints.append((path, mix))
            mix_tokens = set(words(mix))
            if (mix_tokens & DJ_CUES) or re.search(r"\b\d{1,2}(:\d{2})?\s*(am|pm)\b", mix.lower()):
                mix_with_cue.append((path, mix))
            else:
                mix_without_cue.append((path, mix))
            if short and long_desc:
                completed = significant(short) | significant(long_desc)
                overlap = significant(mix) & completed
                if overlap:
                    mix_repeats_description.append((path, mix, ", ".join(sorted(overlap)[:5])))
        else:
            no_mix.append(path)

    print()
    print("=" * 72)
    print("FRAME COVERAGE")
    print("=" * 72)
    print(f"TCOM written: {total_with_short}/{len(mp3s)}  (missing: {len(no_short)})")
    print(f"TIT3 written: {len(descriptions)}/{len(mp3s)}  (missing: {len(no_long)})")
    print(f"MVNM written: {len(mix_hints)}/{len(mp3s)}  (missing: {len(no_mix)})")

    print()
    print("=" * 72)
    print("CRITERION 1 — No chain-of-thought leakage in TCOM")
    print("=" * 72)
    if cot_violations:
        print(f"FAIL ({len(cot_violations)} tracks):")
        for path, text in cot_violations[:10]:
            print(f"  {path.name}: {text!r}")
        if len(cot_violations) > 10:
            print(f"  ... and {len(cot_violations) - 10} more")
    else:
        print("PASS")

    print()
    print("=" * 72)
    print("CRITERION 1B — TCOM is 4-5 all-caps words")
    print("=" * 72)
    if bad_short:
        print(f"FAIL ({len(bad_short)} tracks):")
        for path, text in bad_short[:10]:
            print(f"  {path.name}: {text!r}")
    else:
        print("PASS")

    print()
    print("=" * 72)
    print("CRITERION 2 — No 4-gram repeats > 2× in any 30-track window of TIT3")
    print("=" * 72)
    offenders = sliding_window_repeats(descriptions) if len(descriptions) >= 4 else []
    if offenders:
        # Collapse to unique grams with peak counts.
        peak = defaultdict(int)
        for _, gram, c in offenders:
            peak[gram] = max(peak[gram], c)
        print(f"FAIL ({len(peak)} unique 4-grams over the cap):")
        for gram, c in sorted(peak.items(), key=lambda kv: -kv[1])[:10]:
            print(f"  {c}× — {gram!r}")
    else:
        print("PASS")

    print()
    print("=" * 72)
    print("CRITERION 2B — TIT3 avoids DJ-use wording")
    print("=" * 72)
    if long_with_dj_words:
        print(f"FAIL ({len(long_with_dj_words)} tracks):")
        for path, text, token in long_with_dj_words[:10]:
            print(f"  {path.name}: {token!r} in {text!r}")
    else:
        print("PASS")

    print()
    print("=" * 72)
    print("CRITERION 3 — MVNM reads like DJ movement guidance")
    print("=" * 72)
    print(f"MVNM present with DJ-use cue:    {len(mix_with_cue)}")
    print(f"MVNM present without DJ-use cue: {len(mix_without_cue)}")
    if mix_without_cue:
        print("Sample of MVNM without DJ-use cue:")
        for path, text in mix_without_cue[:5]:
            print(f"  {path.name}: {text!r}")
    if mix_repeats_description:
        print(f"MVNM repeats completed description words ({len(mix_repeats_description)} tracks):")
        for path, text, overlap in mix_repeats_description[:5]:
            print(f"  {path.name}: {overlap} in {text!r}")

    print()
    print("=" * 72)
    print("SUMMARY")
    print("=" * 72)
    crit1_pass = not cot_violations
    crit1b_pass = not bad_short
    crit2_pass = not offenders
    crit2b_pass = not long_with_dj_words
    crit3_pass = not mix_without_cue and not mix_repeats_description
    print(f"Criterion 1 (no CoT preambles):  {'PASS' if crit1_pass else 'FAIL'}")
    print(f"Criterion 1B (short format):     {'PASS' if crit1b_pass else 'FAIL'}")
    print(f"Criterion 2 (diverse phrasing):  {'PASS' if crit2_pass else 'FAIL'}")
    print(f"Criterion 2B (long separation):  {'PASS' if crit2b_pass else 'FAIL'}")
    print(f"Criterion 3 (movement field):    {'PASS' if crit3_pass else 'FAIL'}")
    return 0 if (crit1_pass and crit1b_pass and crit2_pass and crit2b_pass and crit3_pass) else 1


if __name__ == "__main__":
    sys.exit(main())
