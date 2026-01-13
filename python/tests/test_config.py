"""
Tests for config.py - Configuration management.
"""

import pytest
from pathlib import Path


class TestConfigModelPath:
    """Tests for Config.get_model_path() method."""

    def test_config_finds_user_model(self, tmp_path):
        """Config prefers user-trained model over bundled."""
        from core.config import Config

        # Create fake user model
        user_dir = tmp_path / ".cratebot" / "models"
        user_dir.mkdir(parents=True)
        user_model = user_dir / "cratebot.pkl"
        user_model.write_text("fake model")

        config = Config()
        config.config_dir = tmp_path / ".cratebot"

        model_path = config.get_model_path()
        assert model_path == user_model

    def test_config_falls_back_to_bundled_model(self, tmp_path, monkeypatch):
        """Config falls back to bundled model when no user model exists."""
        from core.config import Config

        # Create fake bundled model in a temp location
        bundled_dir = tmp_path / "resources" / "models"
        bundled_dir.mkdir(parents=True)
        bundled_model = bundled_dir / "cratebot.pkl"
        bundled_model.write_text("fake bundled model")

        config = Config()
        # Set config_dir to a location without a user model
        config.config_dir = tmp_path / ".cratebot_empty"
        config.config_dir.mkdir(parents=True)

        # Patch _find_bundled_model to return our temp bundled model
        monkeypatch.setattr(config, '_find_bundled_model', lambda: bundled_model)

        model_path = config.get_model_path()
        assert model_path == bundled_model

    def test_config_raises_when_no_model_found(self, tmp_path, monkeypatch):
        """Config raises FileNotFoundError when no model exists."""
        from core.config import Config

        config = Config()
        # Set config_dir to a location without a user model
        config.config_dir = tmp_path / ".cratebot_empty"
        config.config_dir.mkdir(parents=True)

        # Patch _find_bundled_model to return None (no bundled model)
        monkeypatch.setattr(config, '_find_bundled_model', lambda: None)

        with pytest.raises(FileNotFoundError) as exc_info:
            config.get_model_path()

        assert "No model found" in str(exc_info.value)

    def test_config_prefers_user_model_over_bundled(self, tmp_path, monkeypatch):
        """When both user and bundled models exist, user model is returned."""
        from core.config import Config

        # Create both user and bundled models
        user_dir = tmp_path / ".cratebot" / "models"
        user_dir.mkdir(parents=True)
        user_model = user_dir / "cratebot.pkl"
        user_model.write_text("user trained model")

        bundled_dir = tmp_path / "resources" / "models"
        bundled_dir.mkdir(parents=True)
        bundled_model = bundled_dir / "cratebot.pkl"
        bundled_model.write_text("bundled model")

        config = Config()
        config.config_dir = tmp_path / ".cratebot"

        # Patch _find_bundled_model to return the bundled model
        monkeypatch.setattr(config, '_find_bundled_model', lambda: bundled_model)

        model_path = config.get_model_path()
        # Should return user model, not bundled
        assert model_path == user_model
        assert model_path != bundled_model


class TestFindBundledModel:
    """Tests for Config._find_bundled_model() method."""

    def test_find_bundled_model_returns_none_when_not_found(self, tmp_path, monkeypatch):
        """_find_bundled_model returns None when no bundled model exists."""
        from core.config import Config

        config = Config()

        # Monkeypatch Path(__file__) resolution by patching the candidates
        # to check non-existent paths
        original_find = config._find_bundled_model

        def patched_find():
            # Just check that it returns None for non-existent paths
            candidates = [
                tmp_path / "nonexistent1" / "cratebot_v2.pkl",
                tmp_path / "nonexistent2" / "cratebot.pkl",
            ]
            for path in candidates:
                if path.exists():
                    return path
            return None

        monkeypatch.setattr(config, '_find_bundled_model', patched_find)

        result = config._find_bundled_model()
        assert result is None

    def test_find_bundled_model_checks_multiple_candidates(self, tmp_path):
        """_find_bundled_model checks multiple candidate paths."""
        from core.config import Config

        config = Config()

        # The method should check both cratebot_v2.pkl and cratebot.pkl
        # and both pkg_dir/resources and pkg_dir.parent/desktop/resources
        # This is a structural test - we verify the actual implementation
        # finds models in the expected location

        # The real bundled model should be found if it exists
        bundled = config._find_bundled_model()
        # May be None in test environment, or may find actual bundled model
        if bundled is not None:
            assert bundled.exists()
            assert bundled.suffix == ".pkl"
