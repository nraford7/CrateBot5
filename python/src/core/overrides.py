"""Override system for per-track corrections."""
import json
import sqlite3
from pathlib import Path
from typing import Optional

from .paths import get_cratebot_dir

class OverrideStore:
    """SQLite-backed storage for per-track tag overrides."""

    def __init__(self, path: Optional[Path] = None):
        """Initialize override store."""
        if path is None:
            path = get_cratebot_dir() / "overrides.db"

        self.path = Path(path)
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self._init_db()

    def _init_db(self) -> None:
        """Create database schema if needed."""
        conn = sqlite3.connect(self.path)
        conn.execute("""
            CREATE TABLE IF NOT EXISTS overrides (
                audio_hash TEXT PRIMARY KEY,
                tags_json TEXT NOT NULL,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        """)
        conn.commit()
        conn.close()

    def get_override(self, audio_hash: str) -> Optional[dict]:
        """Get override for an audio hash, or None if not found."""
        conn = sqlite3.connect(self.path)
        cursor = conn.execute(
            "SELECT tags_json FROM overrides WHERE audio_hash = ?",
            (audio_hash,)
        )
        row = cursor.fetchone()
        conn.close()

        if row is None:
            return None
        return json.loads(row[0])

    def set_override(self, audio_hash: str, tags: dict) -> None:
        """Set or update override for an audio hash."""
        conn = sqlite3.connect(self.path)
        conn.execute("""
            INSERT INTO overrides (audio_hash, tags_json, updated_at)
            VALUES (?, ?, CURRENT_TIMESTAMP)
            ON CONFLICT(audio_hash) DO UPDATE SET
                tags_json = excluded.tags_json,
                updated_at = CURRENT_TIMESTAMP
        """, (audio_hash, json.dumps(tags)))
        conn.commit()
        conn.close()

    def delete_override(self, audio_hash: str) -> None:
        """Delete override for an audio hash."""
        conn = sqlite3.connect(self.path)
        conn.execute("DELETE FROM overrides WHERE audio_hash = ?", (audio_hash,))
        conn.commit()
        conn.close()

    def list_overrides(self) -> list[tuple[str, dict]]:
        """List all overrides as (hash, tags) tuples."""
        conn = sqlite3.connect(self.path)
        cursor = conn.execute("SELECT audio_hash, tags_json FROM overrides")
        rows = cursor.fetchall()
        conn.close()
        return [(row[0], json.loads(row[1])) for row in rows]
