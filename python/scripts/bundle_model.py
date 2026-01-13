#!/usr/bin/env python3
# python/scripts/bundle_model.py
"""Bundle trained model for distribution."""
import shutil
import json
from pathlib import Path
from datetime import datetime, timezone


def bundle_model(source_path: Path, bundle_dir: Path) -> None:
    """
    Bundle a trained model for distribution.

    Copies model file and metadata to bundle directory.
    """
    bundle_dir.mkdir(parents=True, exist_ok=True)

    # Copy model file
    dest_model = bundle_dir / "cratebot_v2.pkl"
    shutil.copy(source_path, dest_model)

    # Copy metadata if exists
    meta_source = source_path.with_suffix(".pkl.meta.json")
    if meta_source.exists():
        shutil.copy(meta_source, bundle_dir / "cratebot_v2.pkl.meta.json")

    # Create bundle manifest
    manifest = {
        "version": "2.0",
        "taxonomy": {
            "genre": ["House", "Techno", "Jungle/DnB", "Rap", "DiscoFunk",
                     "Breakbeat", "Ambient", "Dubstep", "Trance"],
            "timing": ["Start", "Build", "Peak", "Sustain", "Release"],
            "mood": ["Happy", "Dark", "Emotional", "Aggressive", "Dreamy", "Groovy"],
        },
        "bundled_at": datetime.now(timezone.utc).isoformat(),
    }

    manifest_path = bundle_dir / "manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2))

    print(f"Model bundled to {bundle_dir}")
    print(f"  - Model: {dest_model}")
    print(f"  - Manifest: {manifest_path}")


if __name__ == "__main__":
    import sys

    if len(sys.argv) < 2:
        print("Usage: python bundle_model.py <source_model.pkl> [bundle_dir]")
        sys.exit(1)

    source = Path(sys.argv[1])
    bundle_dir = Path(sys.argv[2]) if len(sys.argv) > 2 else Path("desktop/resources/models")

    bundle_model(source, bundle_dir)
