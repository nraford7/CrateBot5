"""
Comprehensive Training Pipeline Diagnostic for CrateBot

Checks all components required for training:
- Python dependencies
- ML models (PANNs, CLAP, Essentia, Jamendo)
- Hardware configuration
- File system paths
- Feature extraction pipeline
"""

import importlib
import logging
import os
import subprocess
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

logger = logging.getLogger(__name__)


class TrainingDiagnostic:
    """Complete diagnostic for CrateBot training pipeline."""

    def __init__(self, verbose: bool = True):
        self.verbose = verbose
        self.results = {}
        self.errors = []
        self.warnings = []
        self.missing_packages = []
        self.missing_models = []

    def log(self, msg: str, level: str = 'info'):
        """Print message if verbose."""
        if self.verbose:
            prefix = {'info': '  ', 'ok': '  ✓', 'warn': '  ⚠', 'error': '  ✗'}
            print(f"{prefix.get(level, '  ')} {msg}")

    def run_all(self) -> Dict[str, Any]:
        """Run all diagnostics."""
        if self.verbose:
            print("=" * 60)
            print("CrateBot Training Pipeline Diagnostic")
            print("=" * 60)

        self._check_python_version()
        self._check_core_dependencies()
        self._check_ml_dependencies()
        self._check_optional_dependencies()
        self._check_models()
        self._check_hardware()
        self._check_paths()
        self._check_feature_extraction()
        self._print_summary()

        return self.results

    def _check_python_version(self):
        """Check Python version."""
        if self.verbose:
            print("\n[1/8] Python Version...")

        version = sys.version_info
        self.results['python'] = {
            'version': f"{version.major}.{version.minor}.{version.micro}",
            'ok': version >= (3, 9)
        }

        if version >= (3, 9):
            self.log(f"Python {version.major}.{version.minor}.{version.micro}", 'ok')
        else:
            self.log(f"Python {version.major}.{version.minor} - need 3.9+", 'error')
            self.errors.append("Python 3.9+ required")

    def _check_core_dependencies(self):
        """Check core required packages."""
        if self.verbose:
            print("\n[2/8] Core Dependencies...")

        core_packages = [
            ('numpy', 'numpy', '1.20.0'),
            ('scipy', 'scipy', '1.7.0'),
            ('librosa', 'librosa', '0.9.0'),
            ('scikit-learn', 'sklearn', '1.0.0'),
            ('torch', 'torch', '2.0.0'),
            ('tqdm', 'tqdm', '4.60.0'),
            ('joblib', 'joblib', '1.0.0'),
        ]

        self.results['core_deps'] = {}

        for pkg_name, import_name, min_version in core_packages:
            try:
                mod = importlib.import_module(import_name)
                version = getattr(mod, '__version__', 'unknown')
                self.results['core_deps'][pkg_name] = {'installed': True, 'version': version}
                self.log(f"{pkg_name}: {version}", 'ok')
            except ImportError:
                self.results['core_deps'][pkg_name] = {'installed': False}
                self.log(f"{pkg_name}: NOT INSTALLED", 'error')
                self.errors.append(f"Missing core package: {pkg_name}")
                self.missing_packages.append(pkg_name)

    def _check_ml_dependencies(self):
        """Check ML-specific packages."""
        if self.verbose:
            print("\n[3/8] ML Dependencies...")

        ml_packages = [
            ('panns-inference', 'panns_inference', 'PANNs sound detection'),
            ('laion-clap', 'laion_clap', 'CLAP semantic embeddings'),
            ('faster-whisper', 'faster_whisper', 'Audio transcription'),
        ]

        self.results['ml_deps'] = {}

        for pkg_name, import_name, description in ml_packages:
            try:
                mod = importlib.import_module(import_name)
                version = getattr(mod, '__version__', 'installed')
                self.results['ml_deps'][pkg_name] = {'installed': True, 'version': version}
                self.log(f"{pkg_name}: {version} ({description})", 'ok')
            except ImportError:
                self.results['ml_deps'][pkg_name] = {'installed': False, 'description': description}
                self.log(f"{pkg_name}: NOT INSTALLED ({description})", 'warn')
                self.warnings.append(f"Optional ML package missing: {pkg_name}")

    def _check_optional_dependencies(self):
        """Check optional packages."""
        if self.verbose:
            print("\n[4/8] Optional Dependencies...")

        optional_packages = [
            ('essentia-tensorflow', 'essentia', 'Advanced audio analysis'),
            ('coremltools', 'coremltools', 'Apple Neural Engine support'),
            ('pandas', 'pandas', 'Data manipulation'),
            ('matplotlib', 'matplotlib', 'Plotting'),
        ]

        self.results['optional_deps'] = {}

        for pkg_name, import_name, description in optional_packages:
            try:
                mod = importlib.import_module(import_name)
                version = getattr(mod, '__version__', 'installed')
                self.results['optional_deps'][pkg_name] = {'installed': True, 'version': version}
                self.log(f"{pkg_name}: {version}", 'ok')
            except ImportError:
                self.results['optional_deps'][pkg_name] = {'installed': False}
                self.log(f"{pkg_name}: not installed ({description})", 'info')

    def _check_models(self):
        """Check ML model availability."""
        if self.verbose:
            print("\n[5/8] ML Models...")

        self.results['models'] = {}
        cratebot_dir = Path.home() / '.cratebot'

        # PANNs model
        panns_path = cratebot_dir / 'panns_models' / 'Cnn14_mAP=0.431.pth'
        if panns_path.exists():
            size_mb = panns_path.stat().st_size / (1024 * 1024)
            self.results['models']['panns'] = {'available': True, 'size_mb': size_mb}
            self.log(f"PANNs CNN14: {size_mb:.0f}MB", 'ok')
        else:
            self.results['models']['panns'] = {'available': False}
            self.log("PANNs CNN14: NOT DOWNLOADED", 'warn')
            self.missing_models.append(('PANNs', 'python -c "from src.core.panns_analyzer import PANNsAnalyzer; PANNsAnalyzer().download_model()"'))

        # CLAP model
        clap_path = cratebot_dir / 'clap_models' / '630k-audioset-best.pt'
        if clap_path.exists():
            size_mb = clap_path.stat().st_size / (1024 * 1024)
            self.results['models']['clap'] = {'available': True, 'size_mb': size_mb}
            self.log(f"CLAP 630k-audioset: {size_mb:.0f}MB", 'ok')
        else:
            self.results['models']['clap'] = {'available': False}
            self.log("CLAP 630k-audioset: NOT DOWNLOADED", 'warn')
            self.missing_models.append(('CLAP', 'python -c "from src.core.clap_analyzer import CLAPAnalyzer; CLAPAnalyzer().download_model()"'))

        # Jamendo models
        jamendo_dir = cratebot_dir / 'jamendo_models'
        if jamendo_dir.exists():
            model_count = len(list(jamendo_dir.glob('*.joblib')))
            if model_count > 0:
                self.results['models']['jamendo'] = {'available': True, 'count': model_count}
                self.log(f"Jamendo classifiers: {model_count} models", 'ok')
            else:
                self.results['models']['jamendo'] = {'available': False, 'count': 0}
                self.log("Jamendo classifiers: NOT TRAINED", 'warn')
                self.warnings.append("Jamendo models not trained - run Jamendo trainer first")
        else:
            self.results['models']['jamendo'] = {'available': False}
            self.log("Jamendo classifiers: NOT TRAINED", 'warn')

        # Essentia models (if essentia is installed)
        try:
            import essentia
            self.results['models']['essentia'] = {'available': True}
            self.log("Essentia: built-in models available", 'ok')
        except ImportError:
            self.results['models']['essentia'] = {'available': False}
            self.log("Essentia: not installed", 'info')

    def _check_hardware(self):
        """Check hardware configuration."""
        if self.verbose:
            print("\n[6/8] Hardware Configuration...")

        self.results['hardware'] = {}

        # CPU
        import multiprocessing
        cpu_count = multiprocessing.cpu_count()
        self.results['hardware']['cpu_count'] = cpu_count
        self.log(f"CPU cores: {cpu_count}", 'ok')

        # RAM
        try:
            result = subprocess.run(['sysctl', '-n', 'hw.memsize'], capture_output=True, text=True)
            if result.returncode == 0:
                ram_gb = int(result.stdout.strip()) / (1024**3)
                self.results['hardware']['ram_gb'] = ram_gb
                self.log(f"RAM: {ram_gb:.0f} GB", 'ok')
        except Exception:
            pass

        # PyTorch/GPU
        try:
            import torch
            self.results['hardware']['torch_threads'] = torch.get_num_threads()
            self.log(f"PyTorch threads: {torch.get_num_threads()}", 'ok')

            if torch.cuda.is_available():
                self.results['hardware']['gpu'] = 'cuda'
                self.log(f"GPU: CUDA ({torch.cuda.get_device_name(0)})", 'ok')
            elif hasattr(torch.backends, 'mps') and torch.backends.mps.is_available():
                self.results['hardware']['gpu'] = 'mps'
                self.log("GPU: Apple MPS (Metal)", 'ok')
            else:
                self.results['hardware']['gpu'] = 'cpu'
                self.log("GPU: None (CPU only)", 'warn')
        except ImportError:
            self.results['hardware']['gpu'] = 'unknown'

        # Check hardware config module
        try:
            from .hardware_config import get_hardware_config
            config = get_hardware_config()
            self.log(f"HardwareConfig: workers={config.num_workers}, device={config.device}", 'ok')
        except Exception as e:
            self.log(f"HardwareConfig: error loading ({e})", 'warn')

    def _check_paths(self):
        """Check required paths and directories."""
        if self.verbose:
            print("\n[7/8] Paths & Directories...")

        self.results['paths'] = {}
        cratebot_dir = Path.home() / '.cratebot'

        # CrateBot directory
        if cratebot_dir.exists():
            self.results['paths']['cratebot_dir'] = str(cratebot_dir)
            self.log(f"CrateBot dir: {cratebot_dir}", 'ok')
        else:
            cratebot_dir.mkdir(parents=True, exist_ok=True)
            self.results['paths']['cratebot_dir'] = str(cratebot_dir)
            self.log(f"CrateBot dir: created {cratebot_dir}", 'ok')

        # Feature cache
        cache_path = cratebot_dir / 'feature_cache.db'
        if cache_path.exists():
            size_mb = cache_path.stat().st_size / (1024 * 1024)
            self.results['paths']['feature_cache'] = {'exists': True, 'size_mb': size_mb}
            self.log(f"Feature cache: {size_mb:.1f}MB", 'ok')
        else:
            self.results['paths']['feature_cache'] = {'exists': False}
            self.log("Feature cache: not created yet", 'info')

        # Check for training data directories
        # This is just informational - user needs to provide their own data
        self.log("Training data: user-provided (not checked)", 'info')

    def _check_feature_extraction(self):
        """Test feature extraction pipeline."""
        if self.verbose:
            print("\n[8/8] Feature Extraction Pipeline...")

        self.results['pipeline'] = {}

        # Test imports
        components = [
            ('FastAudioAnalyzer', '.fast_analyzer', 'FastAudioAnalyzer'),
            ('ParallelFeatureExtractor', '.fast_analyzer', 'ParallelFeatureExtractor'),
            ('FeatureCache', '.feature_cache', 'FeatureCache'),
            ('PANNsAnalyzer', '.panns_analyzer', 'PANNsAnalyzer'),
            ('CLAPAnalyzer', '.clap_analyzer', 'CLAPAnalyzer'),
            ('EssentiaAnalyzer', '.essentia_analyzer', 'EssentiaAnalyzer'),
            ('JamendoClassifier', '.jamendo_classifier', 'JamendoClassifier'),
        ]

        for name, module, class_name in components:
            try:
                mod = importlib.import_module(module, package='src.core')
                cls = getattr(mod, class_name)
                self.results['pipeline'][name] = {'available': True}
                self.log(f"{name}: available", 'ok')
            except Exception as e:
                self.results['pipeline'][name] = {'available': False, 'error': str(e)}
                self.log(f"{name}: error - {e}", 'warn')

        # Test actual feature extraction (quick test)
        try:
            from .fast_analyzer import FastAudioAnalyzer
            analyzer = FastAudioAnalyzer(lazy_load=True)
            expected_size = analyzer.FEATURE_VECTOR_SIZE
            self.results['pipeline']['feature_vector_size'] = expected_size
            self.log(f"Feature vector size: {expected_size} dimensions", 'ok')
        except Exception as e:
            self.log(f"Feature vector test failed: {e}", 'warn')

    def _print_summary(self):
        """Print diagnostic summary."""
        if self.verbose:
            print("\n" + "=" * 60)
            print("DIAGNOSTIC SUMMARY")
            print("=" * 60)

            # Status counts
            error_count = len(self.errors)
            warning_count = len(self.warnings)
            missing_pkg_count = len(self.missing_packages)
            missing_model_count = len(self.missing_models)

            if error_count == 0 and missing_pkg_count == 0:
                print("\n✓ Training pipeline is READY")
            else:
                print(f"\n✗ {error_count} errors, {warning_count} warnings")

            # Missing packages
            if self.missing_packages:
                print(f"\nMissing packages ({len(self.missing_packages)}):")
                print(f"  pip install {' '.join(self.missing_packages)}")

            # Missing models
            if self.missing_models:
                print(f"\nMissing models ({len(self.missing_models)}):")
                for model_name, download_cmd in self.missing_models:
                    print(f"  {model_name}: {download_cmd}")

            # Warnings
            if self.warnings:
                print(f"\nWarnings ({len(self.warnings)}):")
                for warn in self.warnings[:5]:
                    print(f"  - {warn}")
                if len(self.warnings) > 5:
                    print(f"  ... and {len(self.warnings) - 5} more")

            # Errors
            if self.errors:
                print(f"\nErrors ({len(self.errors)}):")
                for err in self.errors:
                    print(f"  - {err}")

            print("\n" + "=" * 60)


def run_training_diagnostic(verbose: bool = True) -> Dict[str, Any]:
    """Run complete training pipeline diagnostic."""
    diag = TrainingDiagnostic(verbose=verbose)
    return diag.run_all()


if __name__ == '__main__':
    run_training_diagnostic()
