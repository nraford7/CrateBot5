import os
from pathlib import Path


def get_cratebot_dir() -> Path:
    override = os.environ.get("CRATEBOT_HOME") or os.environ.get("CRATEBOT_DIR")
    if override:
        return Path(override).expanduser()
    return Path.home() / ".cratebot"
