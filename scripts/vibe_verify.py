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
- GRP1 (mix hint — substitute for spec's TXXX:CRATEBOT_MIXHINT)

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

# Vocabulary the mix hint should reference when Stage 2 fired confidently.
# (The script can only see what's written, not the Stage 2 confidence —
# so this is a presence check, not a strict gate.)
TIMING_VOCAB = {"peak", "build", "sustain", "release", "intro", "outro", "drop", "breakdown"}


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
    mix_with_timing: list[tuple[Path, str]] = []
    mix_without_timing: list[tuple[Path, str]] = []
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
        mix = read_frame(tag, "GRP1")

        if args.verbose:
            print(f"{path.name}")
            print(f"  TCOM: {short!r}")
            print(f"  TIT3: {long_desc!r}")
            print(f"  GRP1: {mix!r}")

        if short:
            total_with_short += 1
            for pat in COT_PATTERNS:
                if pat.search(short):
                    cot_violations.append((path, short))
                    break
        else:
            no_short.append(path)

        if long_desc:
            descriptions.append(long_desc)
            description_paths.append(path)
        else:
            no_long.append(path)

        if mix:
            mix_hints.append((path, mix))
            mix_lower = mix.lower()
            if any(v in mix_lower for v in TIMING_VOCAB):
                mix_with_timing.append((path, mix))
            else:
                mix_without_timing.append((path, mix))
        else:
            no_mix.append(path)

    print()
    print("=" * 72)
    print("FRAME COVERAGE")
    print("=" * 72)
    print(f"TCOM written: {total_with_short}/{len(mp3s)}  (missing: {len(no_short)})")
    print(f"TIT3 written: {len(descriptions)}/{len(mp3s)}  (missing: {len(no_long)})")
    print(f"GRP1 written: {len(mix_hints)}/{len(mp3s)}  (missing: {len(no_mix)})")

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
    print("CRITERION 3 — Mix-hint references Timing vocab when present")
    print("=" * 72)
    print("(Script-side soft check — Stage 2 confidence is not retrievable from disk)")
    print(f"GRP1 present with timing vocab:    {len(mix_with_timing)}")
    print(f"GRP1 present without timing vocab: {len(mix_without_timing)}")
    if mix_without_timing:
        print("Sample of GRP1 without timing vocab (may be fine if Stage 2 didn't fire):")
        for path, text in mix_without_timing[:5]:
            print(f"  {path.name}: {text!r}")

    print()
    print("=" * 72)
    print("SUMMARY")
    print("=" * 72)
    crit1_pass = not cot_violations
    crit2_pass = not offenders
    print(f"Criterion 1 (no CoT preambles):  {'PASS' if crit1_pass else 'FAIL'}")
    print(f"Criterion 2 (diverse phrasing):  {'PASS' if crit2_pass else 'FAIL'}")
    print(f"Criterion 3 (mix-hint vocab):    INFO (manual judgement)")
    return 0 if (crit1_pass and crit2_pass) else 1


if __name__ == "__main__":
    sys.exit(main())
