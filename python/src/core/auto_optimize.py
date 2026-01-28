"""
Automatic Hardware Optimization for CrateBot

Detects hardware capabilities and automatically configures optimal settings:
- PyTorch thread count
- Number of parallel workers
- Device selection (MPS/CUDA/CPU)
- Memory settings
- Batch sizes

Usage:
    # At the start of any training or analysis script:
    from src.core.auto_optimize import optimize_for_hardware
    optimize_for_hardware()

    # Or with custom settings:
    optimize_for_hardware(verbose=True, apply_env=True)
"""

import logging
import multiprocessing
import os
import subprocess
import sys
from dataclasses import dataclass, field
from typing import Any, Dict, List, Optional, Tuple

logger = logging.getLogger(__name__)


@dataclass
class HardwareProfile:
    """Detected hardware profile."""
    # CPU
    cpu_count_logical: int = 0
    cpu_count_physical: int = 0
    cpu_brand: str = ""

    # Memory
    ram_total_gb: float = 0.0
    ram_available_gb: float = 0.0

    # GPU
    has_cuda: bool = False
    cuda_device_count: int = 0
    cuda_devices: List[Dict[str, Any]] = field(default_factory=list)
    has_mps: bool = False
    mps_recommended: bool = False

    # Computed recommendations
    recommended_workers: int = 0
    recommended_torch_threads: int = 0
    recommended_batch_size: int = 32
    recommended_device: str = "cpu"

    def __str__(self) -> str:
        parts = [
            f"CPU: {self.cpu_count_logical} cores ({self.cpu_brand})",
            f"RAM: {self.ram_total_gb:.0f}GB",
        ]
        if self.has_cuda:
            parts.append(f"GPU: CUDA ({self.cuda_device_count} device(s))")
        elif self.has_mps:
            parts.append("GPU: Apple MPS")
        else:
            parts.append("GPU: None")
        return " | ".join(parts)


def detect_hardware() -> HardwareProfile:
    """
    Detect hardware capabilities.

    Returns:
        HardwareProfile with detected hardware info and recommendations
    """
    profile = HardwareProfile()

    # CPU detection
    profile.cpu_count_logical = multiprocessing.cpu_count()

    # Try to get physical cores (macOS)
    try:
        result = subprocess.run(
            ['sysctl', '-n', 'hw.physicalcpu'],
            capture_output=True, text=True, timeout=5
        )
        if result.returncode == 0:
            profile.cpu_count_physical = int(result.stdout.strip())
    except Exception:
        profile.cpu_count_physical = profile.cpu_count_logical

    # CPU brand (macOS)
    try:
        result = subprocess.run(
            ['sysctl', '-n', 'machdep.cpu.brand_string'],
            capture_output=True, text=True, timeout=5
        )
        if result.returncode == 0:
            profile.cpu_brand = result.stdout.strip()
    except Exception:
        pass

    # RAM detection (macOS)
    try:
        result = subprocess.run(
            ['sysctl', '-n', 'hw.memsize'],
            capture_output=True, text=True, timeout=5
        )
        if result.returncode == 0:
            profile.ram_total_gb = int(result.stdout.strip()) / (1024**3)
    except Exception:
        pass

    # PyTorch GPU detection
    try:
        import torch

        # CUDA
        profile.has_cuda = torch.cuda.is_available()
        if profile.has_cuda:
            profile.cuda_device_count = torch.cuda.device_count()
            for i in range(profile.cuda_device_count):
                props = torch.cuda.get_device_properties(i)
                profile.cuda_devices.append({
                    'name': props.name,
                    'memory_gb': props.total_memory / (1024**3),
                    'compute_capability': f"{props.major}.{props.minor}",
                })

        # MPS (Apple Silicon)
        if hasattr(torch.backends, 'mps'):
            profile.has_mps = torch.backends.mps.is_available()
            profile.mps_recommended = profile.has_mps and torch.backends.mps.is_built()
    except ImportError:
        pass

    # Compute recommendations
    profile.recommended_workers = _compute_optimal_workers(profile)
    profile.recommended_torch_threads = _compute_optimal_threads(profile)
    profile.recommended_batch_size = _compute_optimal_batch_size(profile)
    profile.recommended_device = _compute_optimal_device(profile)

    return profile


def _compute_optimal_workers(profile: HardwareProfile) -> int:
    """Compute optimal number of parallel workers."""
    cpu_count = profile.cpu_count_logical

    # Leave cores for OS, main process, and GPU operations
    if cpu_count >= 16:
        # High-core systems: leave 2-3 cores
        return cpu_count - 2
    elif cpu_count >= 8:
        # Medium systems: leave 1-2 cores
        return cpu_count - 1
    elif cpu_count >= 4:
        return cpu_count - 1
    else:
        return max(1, cpu_count)


def _compute_optimal_threads(profile: HardwareProfile) -> int:
    """Compute optimal PyTorch thread count."""
    # Use physical cores if available, otherwise logical
    if profile.cpu_count_physical > 0:
        return profile.cpu_count_physical
    return profile.cpu_count_logical


def _compute_optimal_batch_size(profile: HardwareProfile) -> int:
    """Compute optimal batch size based on available memory."""
    ram_gb = profile.ram_total_gb

    # Larger batches for more RAM
    if ram_gb >= 128:
        return 128
    elif ram_gb >= 64:
        return 64
    elif ram_gb >= 32:
        return 48
    elif ram_gb >= 16:
        return 32
    else:
        return 16


def _compute_optimal_device(profile: HardwareProfile) -> str:
    """Compute optimal device for model inference."""
    if profile.has_cuda:
        return 'cuda'
    elif profile.mps_recommended:
        return 'mps'
    return 'cpu'


def apply_optimizations(
    profile: HardwareProfile,
    apply_torch: bool = True,
    apply_env: bool = False,
    verbose: bool = True
) -> Dict[str, Any]:
    """
    Apply detected optimizations.

    Args:
        profile: Detected hardware profile
        apply_torch: Apply PyTorch thread settings
        apply_env: Set environment variables for subprocesses
        verbose: Print what's being configured

    Returns:
        Dict with applied settings
    """
    applied = {}

    # Apply PyTorch settings
    if apply_torch:
        try:
            import torch

            current_threads = torch.get_num_threads()
            if current_threads != profile.recommended_torch_threads:
                torch.set_num_threads(profile.recommended_torch_threads)
                applied['torch_threads'] = profile.recommended_torch_threads
                if verbose:
                    print(f"  Set PyTorch threads: {current_threads} → {profile.recommended_torch_threads}")
            else:
                if verbose:
                    print(f"  PyTorch threads: {current_threads} (optimal)")

        except ImportError:
            if verbose:
                print("  PyTorch not available, skipping thread configuration")

    # Set environment variables for subprocesses
    if apply_env:
        # PyTorch threads
        os.environ['OMP_NUM_THREADS'] = str(profile.recommended_torch_threads)
        os.environ['MKL_NUM_THREADS'] = str(profile.recommended_torch_threads)
        os.environ['TORCH_NUM_THREADS'] = str(profile.recommended_torch_threads)
        applied['env_threads'] = profile.recommended_torch_threads

        # CrateBot settings
        os.environ['CRATEBOT_NUM_WORKERS'] = str(profile.recommended_workers)
        os.environ['CRATEBOT_DEVICE'] = profile.recommended_device
        os.environ['CRATEBOT_BATCH_SIZE'] = str(profile.recommended_batch_size)
        applied['env_workers'] = profile.recommended_workers
        applied['env_device'] = profile.recommended_device

        if verbose:
            print(f"  Set environment variables for subprocesses")

    # Update hardware config if available
    try:
        from .hardware_config import configure_hardware
        configure_hardware(
            num_workers=profile.recommended_workers,
            torch_threads=profile.recommended_torch_threads,
            device=profile.recommended_device,
            batch_size=profile.recommended_batch_size,
            apply_immediately=False  # Already applied above
        )
        applied['hardware_config'] = True
        if verbose:
            print(f"  Updated HardwareConfig module")
    except ImportError:
        pass

    return applied


def optimize_for_hardware(
    verbose: bool = True,
    apply_env: bool = True,
    apply_torch: bool = True
) -> HardwareProfile:
    """
    Detect hardware and automatically apply optimal settings.

    This is the main entry point - call at the start of any script.

    Args:
        verbose: Print configuration summary
        apply_env: Set environment variables for subprocesses
        apply_torch: Apply PyTorch thread settings

    Returns:
        HardwareProfile with detected info

    Example:
        from src.core.auto_optimize import optimize_for_hardware

        # At script start:
        profile = optimize_for_hardware()

        # Then run training/analysis as normal
    """
    if verbose:
        print("=" * 60)
        print("Auto-Optimizing for Hardware")
        print("=" * 60)

    # Detect hardware
    if verbose:
        print("\nDetecting hardware...")
    profile = detect_hardware()

    if verbose:
        print(f"\n  {profile}")
        print(f"\n  Recommended settings:")
        print(f"    Workers:      {profile.recommended_workers}")
        print(f"    Torch threads: {profile.recommended_torch_threads}")
        print(f"    Batch size:   {profile.recommended_batch_size}")
        print(f"    Device:       {profile.recommended_device}")

    # Apply optimizations
    if verbose:
        print("\nApplying optimizations...")

    applied = apply_optimizations(
        profile,
        apply_torch=apply_torch,
        apply_env=apply_env,
        verbose=verbose
    )

    if verbose:
        print("\n" + "=" * 60)
        print("Optimization complete")
        print("=" * 60)

    return profile


def get_optimization_summary() -> str:
    """Get a one-line summary of current optimization status."""
    try:
        import torch
        threads = torch.get_num_threads()

        device = "CPU"
        if torch.cuda.is_available():
            device = f"CUDA ({torch.cuda.get_device_name(0)})"
        elif hasattr(torch.backends, 'mps') and torch.backends.mps.is_available():
            device = "MPS"

        return f"PyTorch: {threads} threads, {device}"
    except ImportError:
        return "PyTorch not available"


def print_hardware_summary():
    """Print a detailed hardware summary without applying changes."""
    profile = detect_hardware()

    print("=" * 60)
    print("Hardware Summary")
    print("=" * 60)

    print(f"\nCPU:")
    print(f"  Brand: {profile.cpu_brand or 'Unknown'}")
    print(f"  Logical cores: {profile.cpu_count_logical}")
    print(f"  Physical cores: {profile.cpu_count_physical or 'Unknown'}")

    print(f"\nMemory:")
    print(f"  Total RAM: {profile.ram_total_gb:.1f} GB")

    print(f"\nGPU:")
    if profile.has_cuda:
        for i, dev in enumerate(profile.cuda_devices):
            print(f"  CUDA {i}: {dev['name']} ({dev['memory_gb']:.1f}GB)")
    elif profile.has_mps:
        print(f"  Apple MPS: Available")
    else:
        print(f"  None detected")

    print(f"\nRecommended Settings:")
    print(f"  Workers:       {profile.recommended_workers}")
    print(f"  Torch threads: {profile.recommended_torch_threads}")
    print(f"  Batch size:    {profile.recommended_batch_size}")
    print(f"  Device:        {profile.recommended_device}")

    print(f"\nCurrent PyTorch Settings:")
    try:
        import torch
        print(f"  Threads: {torch.get_num_threads()}")
        print(f"  Interop threads: {torch.get_num_interop_threads()}")
    except ImportError:
        print(f"  PyTorch not installed")

    print("=" * 60)


# Auto-run on import if CRATEBOT_AUTO_OPTIMIZE is set
if os.environ.get('CRATEBOT_AUTO_OPTIMIZE', '').lower() in ('1', 'true', 'yes'):
    optimize_for_hardware(verbose=False)
