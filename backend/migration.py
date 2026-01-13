"""
CrateBot Migration Utility
Migrates user data from the tkinter version to the Electron version.

Migration includes:
- Config file (~/.cratebot/config.json)
- Trained models (~/.cratebot/models/*.pkl)
- Cache files (~/.cratebot/cache/*)
- Refinement sessions (~/.cratebot/data/refinement_session.json)
"""
import os
import sys
import json
import shutil
import logging
from pathlib import Path
from datetime import datetime
from typing import Dict, Any, Optional, List

from core.paths import get_cratebot_dir

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Data directory
CRATEBOT_DIR = get_cratebot_dir()
BACKUP_DIR = CRATEBOT_DIR / "backups"


class MigrationResult:
    """Result of a migration operation."""

    def __init__(self):
        self.success = True
        self.migrated_items: List[str] = []
        self.warnings: List[str] = []
        self.errors: List[str] = []
        self.backup_path: Optional[Path] = None

    def to_dict(self) -> Dict[str, Any]:
        return {
            "success": self.success,
            "migrated_items": self.migrated_items,
            "warnings": self.warnings,
            "errors": self.errors,
            "backup_path": str(self.backup_path) if self.backup_path else None,
        }


def detect_legacy_data() -> Dict[str, Any]:
    """Detect what legacy data exists that may need migration."""
    result = {
        "has_legacy_data": False,
        "items": [],
    }

    if not CRATEBOT_DIR.exists():
        return result

    # Check for config file
    config_path = CRATEBOT_DIR / "config.json"
    if config_path.exists():
        result["items"].append({
            "type": "config",
            "path": str(config_path),
            "size_bytes": config_path.stat().st_size,
        })
        result["has_legacy_data"] = True

    # Check for models
    models_dir = CRATEBOT_DIR / "models"
    if models_dir.exists():
        for model_path in models_dir.glob("*.pkl"):
            result["items"].append({
                "type": "model",
                "path": str(model_path),
                "name": model_path.stem,
                "size_bytes": model_path.stat().st_size,
            })
            result["has_legacy_data"] = True

    # Check for cache
    cache_dir = CRATEBOT_DIR / "cache"
    if cache_dir.exists():
        cache_size = sum(f.stat().st_size for f in cache_dir.rglob("*") if f.is_file())
        cache_files = list(cache_dir.rglob("*"))
        if cache_files:
            result["items"].append({
                "type": "cache",
                "path": str(cache_dir),
                "file_count": len([f for f in cache_files if f.is_file()]),
                "size_bytes": cache_size,
            })
            result["has_legacy_data"] = True

    # Check for refinement sessions
    data_dir = CRATEBOT_DIR / "data"
    if data_dir.exists():
        session_path = data_dir / "refinement_session.json"
        if session_path.exists():
            result["items"].append({
                "type": "refinement_session",
                "path": str(session_path),
                "size_bytes": session_path.stat().st_size,
            })
            result["has_legacy_data"] = True

    # Check for training checkpoints
    checkpoint_dir = CRATEBOT_DIR / "checkpoints"
    if checkpoint_dir.exists():
        checkpoints = list(checkpoint_dir.glob("checkpoint_*.json"))
        if checkpoints:
            result["items"].append({
                "type": "checkpoints",
                "path": str(checkpoint_dir),
                "file_count": len(checkpoints),
            })
            result["has_legacy_data"] = True

    return result


def create_backup() -> Optional[Path]:
    """Create a backup of the current .cratebot directory."""
    if not CRATEBOT_DIR.exists():
        return None

    # Create backup directory
    BACKUP_DIR.mkdir(parents=True, exist_ok=True)

    # Create timestamped backup
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    backup_path = BACKUP_DIR / f"backup_{timestamp}"

    try:
        # Copy everything except the backups directory itself
        items_to_backup = [
            item for item in CRATEBOT_DIR.iterdir()
            if item.name != "backups"
        ]

        if not items_to_backup:
            return None

        backup_path.mkdir(parents=True, exist_ok=True)

        for item in items_to_backup:
            dest = backup_path / item.name
            if item.is_dir():
                shutil.copytree(item, dest)
            else:
                shutil.copy2(item, dest)

        logger.info(f"Created backup at: {backup_path}")
        return backup_path

    except Exception as e:
        logger.error(f"Failed to create backup: {e}")
        return None


def migrate_config() -> bool:
    """Migrate config file to new format if needed."""
    config_path = CRATEBOT_DIR / "config.json"

    if not config_path.exists():
        return True  # Nothing to migrate

    try:
        with open(config_path, 'r') as f:
            config = json.load(f)

        # Check if already migrated (has version field)
        if config.get("_version") == "3.0":
            logger.info("Config already migrated to v3.0")
            return True

        # Migrate config format
        new_config = {
            "_version": "3.0",
            "_migrated_at": datetime.now().isoformat(),
        }

        # Map old keys to new keys
        key_mapping = {
            "anthropic_api_key": "anthropic_api_key",
            "default_model": "default_model_path",
            "whisper_model": "whisper_model_size",
            "enable_panns": "panns_enabled",
            "enable_essentia": "essentia_enabled",
        }

        for old_key, new_key in key_mapping.items():
            if old_key in config:
                new_config[new_key] = config[old_key]

        # Preserve any unknown keys
        for key, value in config.items():
            if key not in key_mapping and not key.startswith("_"):
                new_config[key] = value

        # Write migrated config
        with open(config_path, 'w') as f:
            json.dump(new_config, f, indent=2)

        logger.info("Migrated config to v3.0 format")
        return True

    except Exception as e:
        logger.error(f"Failed to migrate config: {e}")
        return False


def migrate_models() -> bool:
    """Ensure models are in the correct location."""
    models_dir = CRATEBOT_DIR / "models"

    if not models_dir.exists():
        models_dir.mkdir(parents=True, exist_ok=True)
        return True

    # Models are already in the right place, no migration needed
    # Just verify they're valid
    for model_path in models_dir.glob("*.pkl"):
        try:
            # Quick validation - just check file is readable
            with open(model_path, 'rb') as f:
                # Read first few bytes to verify it's a pickle file
                header = f.read(2)
                if header != b'\x80\x04' and header != b'\x80\x05':
                    logger.warning(f"Model may be corrupted or old format: {model_path}")
        except Exception as e:
            logger.warning(f"Could not validate model {model_path}: {e}")

    return True


def run_migration(create_backup_first: bool = True) -> MigrationResult:
    """
    Run the full migration process.

    Args:
        create_backup_first: Whether to create a backup before migrating

    Returns:
        MigrationResult with details of what was migrated
    """
    result = MigrationResult()

    logger.info("Starting CrateBot migration...")

    # Detect legacy data
    legacy = detect_legacy_data()
    if not legacy["has_legacy_data"]:
        logger.info("No legacy data found, nothing to migrate")
        result.migrated_items.append("No legacy data found")
        return result

    logger.info(f"Found {len(legacy['items'])} items to check")

    # Create backup
    if create_backup_first:
        backup_path = create_backup()
        if backup_path:
            result.backup_path = backup_path
            result.migrated_items.append(f"Created backup: {backup_path}")
        else:
            result.warnings.append("Could not create backup (directory may be empty)")

    # Migrate config
    if migrate_config():
        result.migrated_items.append("Migrated config.json")
    else:
        result.errors.append("Failed to migrate config.json")
        result.success = False

    # Migrate models
    if migrate_models():
        result.migrated_items.append("Verified models directory")
    else:
        result.errors.append("Failed to verify models")
        result.success = False

    # Ensure required directories exist
    required_dirs = [
        CRATEBOT_DIR / "models",
        CRATEBOT_DIR / "cache",
        CRATEBOT_DIR / "data",
        CRATEBOT_DIR / "checkpoints",
    ]

    for dir_path in required_dirs:
        dir_path.mkdir(parents=True, exist_ok=True)

    result.migrated_items.append("Ensured required directories exist")

    if result.success:
        logger.info("Migration completed successfully")
    else:
        logger.error("Migration completed with errors")

    return result


def restore_backup(backup_path: str) -> bool:
    """
    Restore from a backup.

    Args:
        backup_path: Path to the backup directory

    Returns:
        True if successful
    """
    backup = Path(backup_path)
    if not backup.exists():
        logger.error(f"Backup not found: {backup_path}")
        return False

    try:
        # Remove current data (except backups)
        for item in CRATEBOT_DIR.iterdir():
            if item.name != "backups":
                if item.is_dir():
                    shutil.rmtree(item)
                else:
                    item.unlink()

        # Restore from backup
        for item in backup.iterdir():
            dest = CRATEBOT_DIR / item.name
            if item.is_dir():
                shutil.copytree(item, dest)
            else:
                shutil.copy2(item, dest)

        logger.info(f"Restored from backup: {backup_path}")
        return True

    except Exception as e:
        logger.error(f"Failed to restore backup: {e}")
        return False


def list_backups() -> List[Dict[str, Any]]:
    """List available backups."""
    if not BACKUP_DIR.exists():
        return []

    backups = []
    for backup_dir in BACKUP_DIR.iterdir():
        if backup_dir.is_dir() and backup_dir.name.startswith("backup_"):
            try:
                timestamp_str = backup_dir.name.replace("backup_", "")
                timestamp = datetime.strptime(timestamp_str, "%Y%m%d_%H%M%S")

                # Calculate size
                size = sum(f.stat().st_size for f in backup_dir.rglob("*") if f.is_file())

                backups.append({
                    "path": str(backup_dir),
                    "name": backup_dir.name,
                    "timestamp": timestamp.isoformat(),
                    "size_bytes": size,
                })
            except ValueError:
                continue

    return sorted(backups, key=lambda x: x["timestamp"], reverse=True)


# CLI interface
if __name__ == "__main__":
    import argparse

    parser = argparse.ArgumentParser(description="CrateBot Migration Utility")
    parser.add_argument("command", choices=["detect", "migrate", "backup", "restore", "list-backups"],
                        help="Command to run")
    parser.add_argument("--backup-path", help="Path to backup (for restore command)")
    parser.add_argument("--no-backup", action="store_true", help="Skip creating backup before migration")

    args = parser.parse_args()

    if args.command == "detect":
        result = detect_legacy_data()
        print(json.dumps(result, indent=2))

    elif args.command == "migrate":
        result = run_migration(create_backup_first=not args.no_backup)
        print(json.dumps(result.to_dict(), indent=2))

    elif args.command == "backup":
        backup_path = create_backup()
        if backup_path:
            print(f"Backup created: {backup_path}")
        else:
            print("No data to backup or backup failed")
            sys.exit(1)

    elif args.command == "restore":
        if not args.backup_path:
            print("Error: --backup-path required for restore command")
            sys.exit(1)
        if restore_backup(args.backup_path):
            print("Restore successful")
        else:
            print("Restore failed")
            sys.exit(1)

    elif args.command == "list-backups":
        backups = list_backups()
        print(json.dumps(backups, indent=2))
