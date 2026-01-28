"""
Apple Neural Engine (ANE) Support for CrateBot

Provides utilities for converting PyTorch models to CoreML format
for acceleration on Apple Silicon's Neural Engine.

Requirements:
    pip install coremltools>=8.0

ANE Constraints:
- Tensor dimensions should be multiples of 32 for optimal ANE performance
- Models must be statically traced (no dynamic control flow)
- Supported operations vary by iOS/macOS version

Expected Performance Gains:
- 30-50% speedup for supported operations
- Lower power consumption
- Reduced memory pressure (unified memory architecture)

References:
- https://apple.github.io/coremltools/docs-guides/source/convert-pytorch.html
- https://machinelearning.apple.com/research/neural-engine-transformers
- https://github.com/apple/ml-ane-transformers
"""

import logging
import os
from pathlib import Path
from typing import Any, Dict, Optional, Tuple

logger = logging.getLogger(__name__)

# Check for coremltools
try:
    import coremltools as ct
    from coremltools.models.neural_network import quantization_utils
    HAS_COREML = True
    COREML_VERSION = ct.__version__
except ImportError:
    HAS_COREML = False
    COREML_VERSION = None

# Check for torch
try:
    import torch
    HAS_TORCH = True
except ImportError:
    HAS_TORCH = False

# Check for numpy
try:
    import numpy as np
    HAS_NUMPY = True
except ImportError:
    HAS_NUMPY = False


def is_ane_available() -> bool:
    """Check if ANE conversion tools are available."""
    return HAS_COREML and HAS_TORCH


def get_ane_status() -> Dict[str, Any]:
    """Get detailed ANE support status."""
    status = {
        'available': is_ane_available(),
        'coremltools_installed': HAS_COREML,
        'coremltools_version': COREML_VERSION,
        'torch_installed': HAS_TORCH,
    }

    if HAS_COREML:
        status['compute_units'] = ['CPU_ONLY', 'CPU_AND_GPU', 'CPU_AND_NE', 'ALL']
        status['recommended_version'] = '8.3.0'

    return status


class ANEModelConverter:
    """
    Convert PyTorch models to CoreML for Apple Neural Engine acceleration.

    Example usage:
        converter = ANEModelConverter()

        # Convert a model
        success = converter.convert_model(
            model=my_pytorch_model,
            sample_input=torch.randn(1, 3, 224, 224),
            output_path='my_model.mlpackage',
            compute_units='CPU_AND_NE'
        )

        # Load and use the converted model
        if success:
            predictions = converter.run_inference('my_model.mlpackage', input_data)
    """

    # Supported compute unit configurations
    COMPUTE_UNITS = {
        'CPU_ONLY': 'ct.ComputeUnit.CPU_ONLY',
        'CPU_AND_GPU': 'ct.ComputeUnit.CPU_AND_GPU',
        'CPU_AND_NE': 'ct.ComputeUnit.CPU_AND_NE',  # CPU + Neural Engine
        'ALL': 'ct.ComputeUnit.ALL',  # Let CoreML decide
    }

    def __init__(self, models_dir: Optional[str] = None):
        """
        Initialize the ANE converter.

        Args:
            models_dir: Directory to store converted models.
                        Default: ~/.cratebot/coreml_models/
        """
        if not HAS_COREML:
            logger.warning(
                "coremltools not installed. Install with: pip install coremltools>=8.0"
            )

        if models_dir:
            self.models_dir = Path(models_dir)
        else:
            self.models_dir = Path.home() / '.cratebot' / 'coreml_models'

        self.models_dir.mkdir(parents=True, exist_ok=True)

    def convert_model(
        self,
        model: 'torch.nn.Module',
        sample_input: 'torch.Tensor',
        output_path: str,
        compute_units: str = 'ALL',
        minimum_deployment_target: Optional[str] = None,
        quantize: bool = False,
    ) -> bool:
        """
        Convert a PyTorch model to CoreML format.

        Args:
            model: PyTorch model to convert
            sample_input: Example input tensor for tracing
            output_path: Output path (relative to models_dir or absolute)
            compute_units: Target compute units ('CPU_ONLY', 'CPU_AND_GPU',
                          'CPU_AND_NE', 'ALL')
            minimum_deployment_target: e.g., 'iOS15', 'macOS12'
            quantize: Whether to quantize to 16-bit weights

        Returns:
            True if conversion successful, False otherwise
        """
        if not HAS_COREML:
            logger.error("coremltools not installed")
            return False

        if not HAS_TORCH:
            logger.error("PyTorch not installed")
            return False

        # Resolve output path
        if not os.path.isabs(output_path):
            output_path = str(self.models_dir / output_path)

        try:
            # Put model in eval mode
            model.eval()

            # Trace the model
            logger.info("Tracing PyTorch model...")
            traced_model = torch.jit.trace(model, sample_input)

            # Convert to CoreML
            logger.info("Converting to CoreML format...")

            # Build conversion arguments
            convert_kwargs = {
                'inputs': [ct.TensorType(shape=sample_input.shape)],
            }

            # Set compute units
            if compute_units in self.COMPUTE_UNITS:
                convert_kwargs['compute_units'] = getattr(
                    ct.ComputeUnit, compute_units
                )

            # Set deployment target if specified
            if minimum_deployment_target:
                convert_kwargs['minimum_deployment_target'] = getattr(
                    ct.target, minimum_deployment_target
                )

            # Convert
            mlmodel = ct.convert(traced_model, **convert_kwargs)

            # Optional quantization
            if quantize:
                logger.info("Quantizing model to 16-bit...")
                mlmodel = quantization_utils.quantize_weights(
                    mlmodel, nbits=16
                )

            # Save
            logger.info(f"Saving to {output_path}...")
            mlmodel.save(output_path)

            logger.info("Conversion complete!")
            return True

        except Exception as e:
            logger.error(f"Conversion failed: {e}")
            return False

    def load_model(self, model_path: str) -> Optional[Any]:
        """
        Load a converted CoreML model.

        Args:
            model_path: Path to .mlpackage or .mlmodel file

        Returns:
            CoreML model or None if loading fails
        """
        if not HAS_COREML:
            logger.error("coremltools not installed")
            return None

        # Resolve path
        if not os.path.isabs(model_path):
            model_path = str(self.models_dir / model_path)

        try:
            return ct.models.MLModel(model_path)
        except Exception as e:
            logger.error(f"Failed to load model: {e}")
            return None

    def run_inference(
        self,
        model_path: str,
        input_data: 'np.ndarray',
        input_name: str = 'input'
    ) -> Optional['np.ndarray']:
        """
        Run inference using a CoreML model.

        Args:
            model_path: Path to CoreML model
            input_data: Input numpy array
            input_name: Name of input tensor in model

        Returns:
            Output numpy array or None if inference fails
        """
        model = self.load_model(model_path)
        if model is None:
            return None

        try:
            predictions = model.predict({input_name: input_data})
            # Return first output
            output_name = list(predictions.keys())[0]
            return predictions[output_name]
        except Exception as e:
            logger.error(f"Inference failed: {e}")
            return None

    def benchmark_model(
        self,
        model_path: str,
        sample_input: 'np.ndarray',
        num_runs: int = 100,
        warmup_runs: int = 10,
    ) -> Dict[str, float]:
        """
        Benchmark a CoreML model's inference speed.

        Args:
            model_path: Path to CoreML model
            sample_input: Sample input for benchmarking
            num_runs: Number of inference runs
            warmup_runs: Number of warmup runs before timing

        Returns:
            Dict with timing statistics
        """
        import time

        model = self.load_model(model_path)
        if model is None:
            return {'error': 'Failed to load model'}

        input_name = list(model.input_description.keys())[0]

        # Warmup
        for _ in range(warmup_runs):
            model.predict({input_name: sample_input})

        # Timed runs
        times = []
        for _ in range(num_runs):
            start = time.perf_counter()
            model.predict({input_name: sample_input})
            times.append(time.perf_counter() - start)

        times = np.array(times) * 1000  # Convert to ms

        return {
            'mean_ms': float(np.mean(times)),
            'std_ms': float(np.std(times)),
            'min_ms': float(np.min(times)),
            'max_ms': float(np.max(times)),
            'median_ms': float(np.median(times)),
            'num_runs': num_runs,
        }


def check_ane_compatibility(model: 'torch.nn.Module') -> Dict[str, Any]:
    """
    Check if a PyTorch model is compatible with ANE conversion.

    Args:
        model: PyTorch model to check

    Returns:
        Dict with compatibility information and warnings
    """
    if not HAS_TORCH:
        return {'error': 'PyTorch not installed'}

    result = {
        'compatible': True,
        'warnings': [],
        'layer_counts': {},
    }

    # Count layer types
    for name, module in model.named_modules():
        layer_type = type(module).__name__
        result['layer_counts'][layer_type] = result['layer_counts'].get(layer_type, 0) + 1

    # Check for potentially problematic layers
    problematic_layers = [
        'LSTM', 'GRU', 'RNN',  # Recurrent layers need special handling
        'Transformer',  # May need ANE-optimized implementation
        'MultiheadAttention',  # May need custom implementation
    ]

    for layer_type in problematic_layers:
        if layer_type in result['layer_counts']:
            result['warnings'].append(
                f"{layer_type} detected - may need ANE-optimized implementation"
            )
            result['compatible'] = False

    # Check parameter shapes for ANE alignment (multiples of 32)
    misaligned_params = []
    for name, param in model.named_parameters():
        for dim_size in param.shape:
            if dim_size % 32 != 0 and dim_size > 32:
                misaligned_params.append((name, param.shape))
                break

    if misaligned_params:
        result['warnings'].append(
            f"{len(misaligned_params)} parameters have dimensions not aligned to 32 "
            "(may reduce ANE efficiency)"
        )
        result['misaligned_params'] = misaligned_params[:5]  # Show first 5

    return result


def print_ane_status():
    """Print ANE support status."""
    status = get_ane_status()
    print("Apple Neural Engine (ANE) Support")
    print("=" * 40)
    print(f"  Available:         {status['available']}")
    print(f"  coremltools:       {status['coremltools_version'] or 'NOT INSTALLED'}")
    print(f"  PyTorch:           {'Installed' if status['torch_installed'] else 'NOT INSTALLED'}")

    if not status['available']:
        print()
        print("To enable ANE support:")
        if not status['coremltools_installed']:
            print("  pip install coremltools>=8.0")
        if not status['torch_installed']:
            print("  pip install torch")

    print("=" * 40)


if __name__ == '__main__':
    print_ane_status()
