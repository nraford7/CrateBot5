import json
import os
from pathlib import Path
from typing import Optional

from .paths import get_cratebot_dir

class Config:
    """Configuration manager for CrateBot application."""
    def __init__(self):
        self.config_dir = get_cratebot_dir()
        self.config_file = self.config_dir / "config.json"
        self._config = self._load()

    def _load(self) -> dict:
        if self.config_file.exists():
            try:
                with open(self.config_file, 'r') as f:
                    return json.load(f)
            except (json.JSONDecodeError, IOError):
                return {}
        return {}

    def _save(self) -> None:
        self.config_dir.mkdir(parents=True, exist_ok=True)
        with open(self.config_file, 'w') as f:
            json.dump(self._config, f, indent=2)

    def get_last_directory(self, key: str) -> Optional[str]:
        path = self._config.get(key)
        if path and os.path.exists(path):
            return path
        return None

    def set_last_directory(self, key: str, path: str) -> None:
        self._config[key] = os.path.abspath(path)
        self._save()

    def get_api_key(self, service: str = "anthropic") -> Optional[str]:
        """Get API key from config or environment variable."""
        # Environment variable takes precedence
        env_key = os.environ.get("ANTHROPIC_API_KEY")
        if env_key:
            return env_key
        # Fall back to stored config
        return self._config.get(f"{service}_api_key")

    def set_api_key(self, key: str, service: str = "anthropic") -> None:
        """Store API key in config file."""
        self._config[f"{service}_api_key"] = key
        self._save()

    def clear_api_key(self, service: str = "anthropic") -> None:
        """Remove API key from config."""
        if f"{service}_api_key" in self._config:
            del self._config[f"{service}_api_key"]
            self._save()

    def get_model_path(self) -> Path:
        """Get path to model, preferring user-trained over bundled.

        Returns:
            Path to the model file.

        Raises:
            FileNotFoundError: If no model is found.
        """
        # Check for user-trained model first
        user_model = self.config_dir / "models" / "cratebot.pkl"
        if user_model.exists():
            return user_model

        # Fall back to bundled model
        bundled_model = self._find_bundled_model()
        if bundled_model and bundled_model.exists():
            return bundled_model

        # No model found
        raise FileNotFoundError(
            "No model found. Run training or install bundled model."
        )

    def _find_bundled_model(self) -> Optional[Path]:
        """Locate bundled model in package resources.

        Returns:
            Path to bundled model if found, None otherwise.
        """
        # Check relative to this file (for installed package)
        pkg_dir = Path(__file__).parent.parent.parent
        candidates = [
            pkg_dir / "resources" / "models" / "cratebot_v2.pkl",
            pkg_dir / "resources" / "models" / "cratebot.pkl",
            pkg_dir.parent / "desktop" / "resources" / "models" / "cratebot_v2.pkl",
            pkg_dir.parent / "desktop" / "resources" / "models" / "cratebot.pkl",
        ]
        for path in candidates:
            if path.exists():
                return path
        return None


config = Config()
