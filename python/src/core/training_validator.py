"""
Training Validator for CrateBot

Pre-flight checks to ensure all required components are ready before training.
This prevents silent failures where training proceeds with degraded features.
"""

import logging
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, List, Optional, Tuple

logger = logging.getLogger(__name__)


@dataclass
class ValidationResult:
    """Result of a single validation check."""
    name: str
    passed: bool
    required: bool
    message: str
    fix_command: Optional[str] = None


@dataclass
class TrainingValidation:
    """Complete training validation results."""
    checks: List[ValidationResult] = field(default_factory=list)

    @property
    def all_passed(self) -> bool:
        """True if all required checks passed."""
        return all(c.passed for c in self.checks if c.required)

    @property
    def required_failures(self) -> List[ValidationResult]:
        """List of required checks that failed."""
        return [c for c in self.checks if c.required and not c.passed]

    @property
    def warnings(self) -> List[ValidationResult]:
        """List of optional checks that failed (warnings)."""
        return [c for c in self.checks if not c.required and not c.passed]

    def add(self, result: ValidationResult):
        """Add a validation result."""
        self.checks.append(result)

    def raise_if_failed(self):
        """Raise an exception if any required checks failed."""
        failures = self.required_failures
        if failures:
            msg_parts = ["Training cannot proceed - required components missing:"]
            for f in failures:
                msg_parts.append(f"  - {f.name}: {f.message}")
                if f.fix_command:
                    msg_parts.append(f"    Fix: {f.fix_command}")
            raise TrainingValidationError("\n".join(msg_parts))


class TrainingValidationError(Exception):
    """Raised when training validation fails."""
    pass


def validate_training_requirements(
    require_panns: bool = True,
    require_clap: bool = True,
    require_jamendo: bool = False,
    require_essentia: bool = False,
    verbose: bool = True
) -> TrainingValidation:
    """
    Validate that all required components are ready for training.

    Args:
        require_panns: Whether PANNs model is required (default True)
        require_clap: Whether CLAP model is required (default True)
        require_jamendo: Whether Jamendo classifiers are required (default False)
        require_essentia: Whether Essentia is required (default False)
        verbose: Print validation progress

    Returns:
        TrainingValidation with all check results

    Raises:
        TrainingValidationError if any required check fails
    """
    validation = TrainingValidation()

    if verbose:
        print("=" * 60)
        print("Pre-Training Validation")
        print("=" * 60)

    # Check 1: PyTorch
    if verbose:
        print("\n[1/6] PyTorch...")
    try:
        import torch
        validation.add(ValidationResult(
            name="PyTorch",
            passed=True,
            required=True,
            message=f"v{torch.__version__}"
        ))
        if verbose:
            print(f"  ✓ PyTorch {torch.__version__}")
    except ImportError:
        validation.add(ValidationResult(
            name="PyTorch",
            passed=False,
            required=True,
            message="Not installed",
            fix_command="pip install torch"
        ))
        if verbose:
            print("  ✗ PyTorch NOT INSTALLED")

    # Check 2: PANNs
    if verbose:
        print("\n[2/6] PANNs (sound detection)...")
    panns_result = _check_panns()
    panns_result.required = require_panns
    validation.add(panns_result)
    if verbose:
        status = "✓" if panns_result.passed else ("⚠" if not require_panns else "✗")
        print(f"  {status} {panns_result.message}")

    # Check 3: CLAP
    if verbose:
        print("\n[3/6] CLAP (semantic embeddings)...")
    clap_result = _check_clap()
    clap_result.required = require_clap
    validation.add(clap_result)
    if verbose:
        status = "✓" if clap_result.passed else ("⚠" if not require_clap else "✗")
        print(f"  {status} {clap_result.message}")

    # Check 4: Jamendo
    if verbose:
        print("\n[4/6] Jamendo (mood classifiers)...")
    jamendo_result = _check_jamendo()
    jamendo_result.required = require_jamendo
    validation.add(jamendo_result)
    if verbose:
        status = "✓" if jamendo_result.passed else ("⚠" if not require_jamendo else "✗")
        print(f"  {status} {jamendo_result.message}")

    # Check 5: Essentia
    if verbose:
        print("\n[5/6] Essentia (advanced audio)...")
    essentia_result = _check_essentia()
    essentia_result.required = require_essentia
    validation.add(essentia_result)
    if verbose:
        status = "✓" if essentia_result.passed else ("⚠" if not require_essentia else "✗")
        print(f"  {status} {essentia_result.message}")

    # Check 6: Hardware config
    if verbose:
        print("\n[6/6] Hardware configuration...")
    hardware_result = _check_hardware()
    validation.add(hardware_result)
    if verbose:
        status = "✓" if hardware_result.passed else "⚠"
        print(f"  {status} {hardware_result.message}")

    # Summary
    if verbose:
        print("\n" + "=" * 60)
        if validation.all_passed:
            print("✓ All required components ready - training can proceed")
        else:
            print("✗ VALIDATION FAILED - training blocked")
            for f in validation.required_failures:
                print(f"\n  Missing: {f.name}")
                print(f"  Issue: {f.message}")
                if f.fix_command:
                    print(f"  Fix: {f.fix_command}")

        if validation.warnings:
            print("\n  Warnings (optional components):")
            for w in validation.warnings:
                print(f"    - {w.name}: {w.message}")

        print("=" * 60)

    return validation


def _check_panns() -> ValidationResult:
    """Check PANNs availability."""
    # Check package
    try:
        from panns_inference import AudioTagging
    except ImportError:
        return ValidationResult(
            name="PANNs",
            passed=False,
            required=True,
            message="Package not installed",
            fix_command="pip install panns-inference"
        )

    # Check model
    model_path = Path.home() / '.cratebot' / 'panns_models' / 'Cnn14_mAP=0.431.pth'
    if not model_path.exists():
        return ValidationResult(
            name="PANNs",
            passed=False,
            required=True,
            message="Model not downloaded",
            fix_command='python -c "from src.core.panns_analyzer import PANNsAnalyzer; PANNsAnalyzer(auto_load=False).download_model()"'
        )

    size_mb = model_path.stat().st_size / (1024 * 1024)
    return ValidationResult(
        name="PANNs",
        passed=True,
        required=True,
        message=f"Ready ({size_mb:.0f}MB model)"
    )


def _check_clap() -> ValidationResult:
    """Check CLAP availability."""
    # Check package
    try:
        import laion_clap
    except ImportError:
        return ValidationResult(
            name="CLAP",
            passed=False,
            required=True,
            message="Package not installed",
            fix_command="pip install laion-clap"
        )

    # Check model
    model_path = Path.home() / '.cratebot' / 'clap_models' / '630k-audioset-best.pt'
    if not model_path.exists():
        return ValidationResult(
            name="CLAP",
            passed=False,
            required=True,
            message="Model not downloaded",
            fix_command='python -c "from src.core.clap_analyzer import CLAPAnalyzer; CLAPAnalyzer(auto_load=False).download_model()"'
        )

    size_mb = model_path.stat().st_size / (1024 * 1024)
    return ValidationResult(
        name="CLAP",
        passed=True,
        required=True,
        message=f"Ready ({size_mb:.0f}MB model)"
    )


def _check_jamendo() -> ValidationResult:
    """Check Jamendo classifiers availability."""
    jamendo_dir = Path.home() / '.cratebot' / 'jamendo_models'

    if not jamendo_dir.exists():
        return ValidationResult(
            name="Jamendo",
            passed=False,
            required=False,
            message="Not trained yet",
            fix_command="cratebot train-jamendo"
        )

    # Check for classifier file (can be .pkl or .joblib)
    classifier_file = jamendo_dir / 'jamendo_classifiers.pkl'
    if not classifier_file.exists():
        classifier_file = jamendo_dir / 'jamendo_classifiers.joblib'

    if not classifier_file.exists():
        # Also check for individual .joblib files (older format)
        model_count = len(list(jamendo_dir.glob('*.joblib')))
        if model_count == 0:
            return ValidationResult(
                name="Jamendo",
                passed=False,
                required=False,
                message="No classifiers found",
                fix_command="cratebot train-jamendo"
            )
        return ValidationResult(
            name="Jamendo",
            passed=True,
            required=False,
            message=f"Ready ({model_count} classifiers)"
        )

    # Load metadata to get classifier count
    metadata_file = jamendo_dir / 'jamendo_metadata.json'
    if metadata_file.exists():
        try:
            import json
            with open(metadata_file) as f:
                meta = json.load(f)
            num_tags = meta.get('num_tags', 55)
            return ValidationResult(
                name="Jamendo",
                passed=True,
                required=False,
                message=f"Ready ({num_tags} classifiers)"
            )
        except Exception:
            pass

    return ValidationResult(
        name="Jamendo",
        passed=True,
        required=False,
        message="Ready"
    )


def _check_essentia() -> ValidationResult:
    """Check Essentia availability."""
    try:
        import essentia
        return ValidationResult(
            name="Essentia",
            passed=True,
            required=False,
            message="Available"
        )
    except ImportError:
        return ValidationResult(
            name="Essentia",
            passed=False,
            required=False,
            message="Not installed (optional)",
            fix_command="pip install essentia-tensorflow"
        )


def _check_hardware() -> ValidationResult:
    """Check hardware configuration."""
    try:
        import torch
        import multiprocessing

        cpu_count = multiprocessing.cpu_count()
        torch_threads = torch.get_num_threads()

        device = "CPU"
        if torch.cuda.is_available():
            device = f"CUDA ({torch.cuda.get_device_name(0)})"
        elif hasattr(torch.backends, 'mps') and torch.backends.mps.is_available():
            device = "Apple MPS"

        message = f"{cpu_count} CPUs, {torch_threads} threads, {device}"

        # Warning if threads not optimal
        passed = torch_threads >= cpu_count - 2
        if not passed:
            message += f" (suboptimal: set TORCH_NUM_THREADS={cpu_count})"

        return ValidationResult(
            name="Hardware",
            passed=passed,
            required=False,
            message=message
        )
    except Exception as e:
        return ValidationResult(
            name="Hardware",
            passed=False,
            required=False,
            message=f"Check failed: {e}"
        )


def quick_validate() -> bool:
    """
    Quick validation check - returns True if training can proceed.

    Use this for programmatic checks without verbose output.
    """
    validation = validate_training_requirements(verbose=False)
    return validation.all_passed
