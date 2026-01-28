"""
Hardware Configuration for CrateBot Training

Allows configuration of:
- Number of worker processes for parallel feature extraction
- PyTorch thread count
- Device selection (auto/cpu/mps/cuda)
- Batch sizes
- Memory limits

Configuration priority (highest to lowest):
1. Function arguments
2. Environment variables
3. Config file (~/.cratebot/hardware.json)
4. Auto-detected defaults
"""

import json
import logging
import multiprocessing
import os
from pathlib import Path
from typing import Any, Dict, Optional

logger = logging.getLogger(__name__)

# Environment variable names
ENV_NUM_WORKERS = 'CRATEBOT_NUM_WORKERS'
ENV_TORCH_THREADS = 'CRATEBOT_TORCH_THREADS'  # Also respects TORCH_NUM_THREADS
ENV_DEVICE = 'CRATEBOT_DEVICE'
ENV_BATCH_SIZE = 'CRATEBOT_BATCH_SIZE'
ENV_MAX_MEMORY_GB = 'CRATEBOT_MAX_MEMORY_GB'
ENV_USE_MPS = 'CRATEBOT_USE_MPS'  # Explicit MPS toggle (0/1)

# Config file location
CONFIG_FILE = Path.home() / '.cratebot' / 'hardware.json'


class HardwareConfig:
    """
    Centralized hardware configuration for CrateBot.

    Usage:
        config = HardwareConfig()
        print(f"Workers: {config.num_workers}")
        print(f"Device: {config.device}")

        # Or override defaults
        config = HardwareConfig(num_workers=8, device='mps')

        # Apply to PyTorch
        config.apply_torch_settings()
    """

    def __init__(
        self,
        num_workers: Optional[int] = None,
        torch_threads: Optional[int] = None,
        device: Optional[str] = None,
        batch_size: Optional[int] = None,
        max_memory_gb: Optional[float] = None,
        use_mps: Optional[bool] = None,
    ):
        """
        Initialize hardware configuration.

        Args:
            num_workers: Number of parallel workers for feature extraction
            torch_threads: Number of PyTorch CPU threads
            device: Device for model inference ('auto', 'cpu', 'mps', 'cuda')
            batch_size: Default batch size for training
            max_memory_gb: Maximum memory to use (for dataset caching)
            use_mps: Explicitly enable/disable MPS (Apple Silicon GPU)
        """
        # Load from config file first
        file_config = self._load_config_file()

        # Apply in priority order: args > env > file > defaults
        self._num_workers = self._resolve_int(
            num_workers,
            ENV_NUM_WORKERS,
            file_config.get('num_workers'),
            self._default_num_workers()
        )

        self._torch_threads = self._resolve_int(
            torch_threads,
            ENV_TORCH_THREADS,
            file_config.get('torch_threads'),
            self._default_torch_threads(),
            alt_env='TORCH_NUM_THREADS'
        )

        self._device = self._resolve_str(
            device,
            ENV_DEVICE,
            file_config.get('device'),
            'auto'
        )

        self._batch_size = self._resolve_int(
            batch_size,
            ENV_BATCH_SIZE,
            file_config.get('batch_size'),
            32
        )

        self._max_memory_gb = self._resolve_float(
            max_memory_gb,
            ENV_MAX_MEMORY_GB,
            file_config.get('max_memory_gb'),
            None  # None means unlimited
        )

        self._use_mps = self._resolve_bool(
            use_mps,
            ENV_USE_MPS,
            file_config.get('use_mps'),
            True  # Default to using MPS if available
        )

    @staticmethod
    def _load_config_file() -> Dict[str, Any]:
        """Load configuration from file if it exists."""
        if CONFIG_FILE.exists():
            try:
                with open(CONFIG_FILE, 'r') as f:
                    return json.load(f)
            except Exception as e:
                logger.warning(f"Failed to load hardware config: {e}")
        return {}

    @staticmethod
    def _resolve_int(
        arg: Optional[int],
        env_var: str,
        file_val: Optional[int],
        default: int,
        alt_env: Optional[str] = None
    ) -> int:
        """Resolve integer config value with priority."""
        if arg is not None:
            return arg
        env_val = os.environ.get(env_var)
        if env_val:
            try:
                return int(env_val)
            except ValueError:
                pass
        if alt_env:
            env_val = os.environ.get(alt_env)
            if env_val:
                try:
                    return int(env_val)
                except ValueError:
                    pass
        if file_val is not None:
            return file_val
        return default

    @staticmethod
    def _resolve_float(
        arg: Optional[float],
        env_var: str,
        file_val: Optional[float],
        default: Optional[float]
    ) -> Optional[float]:
        """Resolve float config value with priority."""
        if arg is not None:
            return arg
        env_val = os.environ.get(env_var)
        if env_val:
            try:
                return float(env_val)
            except ValueError:
                pass
        if file_val is not None:
            return file_val
        return default

    @staticmethod
    def _resolve_str(
        arg: Optional[str],
        env_var: str,
        file_val: Optional[str],
        default: str
    ) -> str:
        """Resolve string config value with priority."""
        if arg is not None:
            return arg
        env_val = os.environ.get(env_var)
        if env_val:
            return env_val
        if file_val is not None:
            return file_val
        return default

    @staticmethod
    def _resolve_bool(
        arg: Optional[bool],
        env_var: str,
        file_val: Optional[bool],
        default: bool
    ) -> bool:
        """Resolve boolean config value with priority."""
        if arg is not None:
            return arg
        env_val = os.environ.get(env_var)
        if env_val:
            return env_val.lower() in ('1', 'true', 'yes', 'on')
        if file_val is not None:
            return file_val
        return default

    @staticmethod
    def _default_num_workers() -> int:
        """Calculate default number of workers."""
        cpu_count = multiprocessing.cpu_count()
        # Leave 2 cores for OS and main process on machines with many cores
        if cpu_count >= 8:
            return cpu_count - 2
        elif cpu_count >= 4:
            return cpu_count - 1
        else:
            return max(1, cpu_count)

    @staticmethod
    def _default_torch_threads() -> int:
        """Calculate default PyTorch thread count."""
        return multiprocessing.cpu_count()

    @property
    def num_workers(self) -> int:
        """Number of parallel workers for feature extraction."""
        return self._num_workers

    @property
    def torch_threads(self) -> int:
        """Number of PyTorch CPU threads."""
        return self._torch_threads

    @property
    def device(self) -> str:
        """
        Get the device to use for model inference.

        Returns resolved device string: 'cpu', 'mps', or 'cuda'
        """
        if self._device == 'auto':
            return self._auto_detect_device()
        return self._device

    @property
    def batch_size(self) -> int:
        """Default batch size for training."""
        return self._batch_size

    @property
    def max_memory_gb(self) -> Optional[float]:
        """Maximum memory to use in GB (None = unlimited)."""
        return self._max_memory_gb

    @property
    def use_mps(self) -> bool:
        """Whether to use MPS (Apple Silicon GPU) when available."""
        return self._use_mps

    def _auto_detect_device(self) -> str:
        """Auto-detect best available device."""
        try:
            import torch
            if torch.cuda.is_available():
                return 'cuda'
            if self._use_mps and hasattr(torch.backends, 'mps') and torch.backends.mps.is_available():
                return 'mps'
        except ImportError:
            pass
        return 'cpu'

    def apply_torch_settings(self) -> None:
        """Apply configuration to PyTorch."""
        try:
            import torch
            torch.set_num_threads(self._torch_threads)
            logger.info(f"Set PyTorch threads to {self._torch_threads}")
        except ImportError:
            logger.warning("PyTorch not available, cannot apply torch settings")

    def save_to_file(self) -> None:
        """Save current configuration to file."""
        CONFIG_FILE.parent.mkdir(parents=True, exist_ok=True)
        config = {
            'num_workers': self._num_workers,
            'torch_threads': self._torch_threads,
            'device': self._device,
            'batch_size': self._batch_size,
            'max_memory_gb': self._max_memory_gb,
            'use_mps': self._use_mps,
        }
        with open(CONFIG_FILE, 'w') as f:
            json.dump(config, f, indent=2)
        logger.info(f"Saved hardware config to {CONFIG_FILE}")

    def to_dict(self) -> Dict[str, Any]:
        """Export configuration as dictionary."""
        return {
            'num_workers': self.num_workers,
            'torch_threads': self.torch_threads,
            'device': self.device,
            'batch_size': self.batch_size,
            'max_memory_gb': self.max_memory_gb,
            'use_mps': self.use_mps,
        }

    def __repr__(self) -> str:
        return (
            f"HardwareConfig(num_workers={self.num_workers}, "
            f"torch_threads={self.torch_threads}, "
            f"device='{self.device}', "
            f"batch_size={self.batch_size}, "
            f"max_memory_gb={self.max_memory_gb})"
        )


# Global config instance (lazy-loaded)
_global_config: Optional[HardwareConfig] = None


def get_hardware_config() -> HardwareConfig:
    """Get the global hardware configuration instance."""
    global _global_config
    if _global_config is None:
        _global_config = HardwareConfig()
    return _global_config


def configure_hardware(
    num_workers: Optional[int] = None,
    torch_threads: Optional[int] = None,
    device: Optional[str] = None,
    batch_size: Optional[int] = None,
    max_memory_gb: Optional[float] = None,
    use_mps: Optional[bool] = None,
    apply_immediately: bool = True,
) -> HardwareConfig:
    """
    Configure hardware settings for CrateBot.

    This is the main entry point for configuring hardware settings.
    Settings are applied globally and affect all subsequent operations.

    Args:
        num_workers: Number of parallel workers (default: CPU count - 2)
        torch_threads: PyTorch thread count (default: CPU count)
        device: Model device ('auto', 'cpu', 'mps', 'cuda')
        batch_size: Training batch size
        max_memory_gb: Memory limit in GB
        use_mps: Enable Apple Silicon GPU
        apply_immediately: Apply torch settings now

    Returns:
        The configured HardwareConfig instance

    Example:
        # On a high-RAM machine with lots of cores
        configure_hardware(num_workers=14, torch_threads=16, batch_size=64)

        # To disable MPS and force CPU
        configure_hardware(device='cpu', use_mps=False)
    """
    global _global_config
    _global_config = HardwareConfig(
        num_workers=num_workers,
        torch_threads=torch_threads,
        device=device,
        batch_size=batch_size,
        max_memory_gb=max_memory_gb,
        use_mps=use_mps,
    )
    if apply_immediately:
        _global_config.apply_torch_settings()
    return _global_config


def print_hardware_config() -> None:
    """Print current hardware configuration."""
    config = get_hardware_config()
    print("CrateBot Hardware Configuration")
    print("=" * 40)
    print(f"  Workers:       {config.num_workers}")
    print(f"  Torch Threads: {config.torch_threads}")
    print(f"  Device:        {config.device}")
    print(f"  Batch Size:    {config.batch_size}")
    print(f"  Max Memory:    {config.max_memory_gb or 'unlimited'} GB")
    print(f"  Use MPS:       {config.use_mps}")
    print("=" * 40)
