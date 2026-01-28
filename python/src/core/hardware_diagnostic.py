"""
Hardware Diagnostic Tool for CrateBot Training

Checks GPU/MPS utilization, CPU cores, memory, and provides
recommendations for optimal training configuration.
"""

import os
import sys
import time
import multiprocessing
import subprocess
from typing import Dict, Any, Optional

# psutil is optional
try:
    import psutil
    HAS_PSUTIL = True
except ImportError:
    HAS_PSUTIL = False

# Check PyTorch
try:
    import torch
    HAS_TORCH = True
except ImportError:
    HAS_TORCH = False

# Check numpy
try:
    import numpy as np
    HAS_NUMPY = True
except ImportError:
    HAS_NUMPY = False


def get_system_info() -> Dict[str, Any]:
    """Get system hardware information."""
    info = {
        'cpu_count_logical': os.cpu_count(),
        'cpu_count_multiprocessing': multiprocessing.cpu_count(),
    }

    if HAS_PSUTIL:
        info['cpu_count_physical'] = psutil.cpu_count(logical=False)
        info['ram_total_gb'] = psutil.virtual_memory().total / (1024**3)
        info['ram_available_gb'] = psutil.virtual_memory().available / (1024**3)
        info['ram_percent_used'] = psutil.virtual_memory().percent
    else:
        # Fallback for macOS without psutil
        info['cpu_count_physical'] = None
        try:
            # Get RAM from sysctl on macOS
            result = subprocess.run(['sysctl', '-n', 'hw.memsize'], capture_output=True, text=True)
            if result.returncode == 0:
                info['ram_total_gb'] = int(result.stdout.strip()) / (1024**3)
            else:
                info['ram_total_gb'] = None
        except Exception:
            info['ram_total_gb'] = None
        info['ram_available_gb'] = None
        info['ram_percent_used'] = None

    return info


def get_pytorch_info() -> Dict[str, Any]:
    """Get PyTorch hardware configuration."""
    if not HAS_TORCH:
        return {'available': False, 'error': 'PyTorch not installed'}

    info = {
        'available': True,
        'version': torch.__version__,
        'num_threads': torch.get_num_threads(),
        'num_interop_threads': torch.get_num_interop_threads(),
    }

    # CUDA
    info['cuda_available'] = torch.cuda.is_available()
    if info['cuda_available']:
        info['cuda_device_count'] = torch.cuda.device_count()
        info['cuda_devices'] = []
        for i in range(torch.cuda.device_count()):
            props = torch.cuda.get_device_properties(i)
            info['cuda_devices'].append({
                'name': props.name,
                'total_memory_gb': props.total_memory / (1024**3),
                'multi_processor_count': props.multi_processor_count,
            })

    # MPS (Apple Silicon)
    info['mps_available'] = hasattr(torch.backends, 'mps') and torch.backends.mps.is_available()
    if info['mps_available']:
        info['mps_built'] = torch.backends.mps.is_built()

    return info


def test_mps_performance() -> Dict[str, Any]:
    """Test MPS GPU performance with matrix operations."""
    if not HAS_TORCH:
        return {'error': 'PyTorch not installed'}

    if not (hasattr(torch.backends, 'mps') and torch.backends.mps.is_available()):
        return {'error': 'MPS not available'}

    results = {}

    # Test matrix multiplication performance
    sizes = [1000, 2000, 4000]

    for size in sizes:
        # CPU test
        a_cpu = torch.randn(size, size)
        b_cpu = torch.randn(size, size)

        torch.mps.synchronize() if hasattr(torch.mps, 'synchronize') else None
        start = time.perf_counter()
        _ = torch.mm(a_cpu, b_cpu)
        cpu_time = time.perf_counter() - start

        # MPS test
        a_mps = a_cpu.to('mps')
        b_mps = b_cpu.to('mps')

        # Warmup
        _ = torch.mm(a_mps, b_mps)
        if hasattr(torch.mps, 'synchronize'):
            torch.mps.synchronize()

        start = time.perf_counter()
        _ = torch.mm(a_mps, b_mps)
        if hasattr(torch.mps, 'synchronize'):
            torch.mps.synchronize()
        mps_time = time.perf_counter() - start

        results[f'matmul_{size}x{size}'] = {
            'cpu_time_ms': cpu_time * 1000,
            'mps_time_ms': mps_time * 1000,
            'speedup': cpu_time / mps_time if mps_time > 0 else 0,
        }

    return results


def test_model_device_placement() -> Dict[str, Any]:
    """Test if CrateBot models are actually on GPU."""
    results = {}

    # Test PANNs
    try:
        from .panns_analyzer import PANNsAnalyzer, is_panns_available
        if is_panns_available():
            analyzer = PANNsAnalyzer(auto_load=True)
            results['panns'] = {
                'available': True,
                'device': analyzer.device,
                'model_loaded': analyzer.model is not None,
            }
            if analyzer.model is not None and hasattr(analyzer.model, 'model'):
                # Check actual parameter device
                try:
                    for name, param in analyzer.model.model.named_parameters():
                        results['panns']['param_device'] = str(param.device)
                        break
                except Exception:
                    results['panns']['param_device'] = analyzer.device or 'unknown'
        else:
            results['panns'] = {'available': False, 'reason': 'not installed or model not downloaded'}
    except Exception as e:
        results['panns'] = {'available': False, 'error': str(e)}

    # Test CLAP
    try:
        from .clap_analyzer import CLAPAnalyzer, is_clap_available
        if is_clap_available():
            analyzer = CLAPAnalyzer(auto_load=True)
            results['clap'] = {
                'available': True,
                'device': analyzer.device,
                'model_loaded': analyzer.model is not None,
            }
            if analyzer.model is not None:
                # Check actual parameter device
                for name, param in analyzer.model.named_parameters():
                    results['clap']['param_device'] = str(param.device)
                    break
        else:
            results['clap'] = {'available': False, 'reason': 'not installed or model not downloaded'}
    except Exception as e:
        results['clap'] = {'available': False, 'error': str(e)}

    return results


def get_recommendations(system_info: Dict, pytorch_info: Dict) -> list:
    """Generate optimization recommendations based on hardware."""
    recommendations = []

    # CPU threads
    if HAS_TORCH:
        optimal_threads = system_info['cpu_count_physical'] or system_info['cpu_count_logical']
        current_threads = pytorch_info.get('num_threads', 0)
        if current_threads < optimal_threads:
            recommendations.append({
                'type': 'CPU_THREADS',
                'severity': 'medium',
                'current': current_threads,
                'recommended': optimal_threads,
                'action': f'Set torch.set_num_threads({optimal_threads}) or TORCH_NUM_THREADS={optimal_threads}',
            })

    # MPS usage
    if pytorch_info.get('mps_available') and not pytorch_info.get('cuda_available'):
        recommendations.append({
            'type': 'MPS_AVAILABLE',
            'severity': 'info',
            'message': 'Apple Silicon GPU (MPS) is available and should be used for inference',
        })

    # Memory
    ram_gb = system_info.get('ram_total_gb') or 0
    if ram_gb >= 64:
        recommendations.append({
            'type': 'HIGH_RAM',
            'severity': 'info',
            'message': f'High RAM detected ({ram_gb:.0f}GB). Consider larger batch sizes and caching more data in memory.',
        })

    # Multiprocessing workers
    cpu_count = system_info['cpu_count_logical']
    recommended_workers = max(1, cpu_count - 2)  # Leave 2 for OS and main process
    recommendations.append({
        'type': 'WORKERS',
        'severity': 'info',
        'recommended': recommended_workers,
        'message': f'Recommended parallel workers: {recommended_workers} (of {cpu_count} cores)',
    })

    return recommendations


def run_full_diagnostic(verbose: bool = True) -> Dict[str, Any]:
    """Run complete hardware diagnostic."""
    results = {}

    if verbose:
        print("=" * 60)
        print("CrateBot Hardware Diagnostic")
        print("=" * 60)

    # System info
    if verbose:
        print("\n[1/5] System Information...")
    results['system'] = get_system_info()
    if verbose:
        physical = results['system'].get('cpu_count_physical') or 'N/A'
        print(f"  CPU Cores: {results['system']['cpu_count_logical']} logical, {physical} physical")
        ram_total = results['system'].get('ram_total_gb')
        ram_avail = results['system'].get('ram_available_gb')
        ram_str = f"{ram_total:.1f} GB total" if ram_total else "N/A"
        if ram_avail:
            ram_str += f", {ram_avail:.1f} GB available"
        print(f"  RAM: {ram_str}")

    # PyTorch info
    if verbose:
        print("\n[2/5] PyTorch Configuration...")
    results['pytorch'] = get_pytorch_info()
    if verbose:
        if results['pytorch']['available']:
            print(f"  Version: {results['pytorch']['version']}")
            print(f"  Threads: {results['pytorch']['num_threads']}")
            print(f"  CUDA: {results['pytorch']['cuda_available']}")
            print(f"  MPS (Apple GPU): {results['pytorch']['mps_available']}")
        else:
            print(f"  ERROR: {results['pytorch'].get('error', 'Unknown error')}")

    # MPS performance test
    if verbose:
        print("\n[3/5] GPU Performance Test...")
    results['mps_performance'] = test_mps_performance()
    if verbose:
        if 'error' not in results['mps_performance']:
            for test_name, test_results in results['mps_performance'].items():
                print(f"  {test_name}: CPU={test_results['cpu_time_ms']:.1f}ms, MPS={test_results['mps_time_ms']:.1f}ms, Speedup={test_results['speedup']:.1f}x")
        else:
            print(f"  Skipped: {results['mps_performance']['error']}")

    # Model device placement
    if verbose:
        print("\n[4/5] Model Device Placement...")
    results['model_devices'] = test_model_device_placement()
    if verbose:
        for model_name, model_info in results['model_devices'].items():
            if model_info.get('available'):
                device = model_info.get('param_device', model_info.get('device', 'unknown'))
                print(f"  {model_name.upper()}: {device}")
            else:
                reason = model_info.get('error', model_info.get('reason', 'unknown'))
                print(f"  {model_name.upper()}: NOT AVAILABLE ({reason})")

    # Recommendations
    if verbose:
        print("\n[5/5] Recommendations...")
    results['recommendations'] = get_recommendations(results['system'], results['pytorch'])
    if verbose:
        for rec in results['recommendations']:
            severity = rec.get('severity', 'info').upper()
            if 'action' in rec:
                print(f"  [{severity}] {rec['type']}: {rec['action']}")
            else:
                print(f"  [{severity}] {rec.get('message', rec['type'])}")

    if verbose:
        print("\n" + "=" * 60)
        print("Diagnostic Complete")
        print("=" * 60)

    return results


if __name__ == '__main__':
    run_full_diagnostic(verbose=True)
