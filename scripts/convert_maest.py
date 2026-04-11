#!/usr/bin/env python3
"""
Convert MAEST (Music Audio Efficient Spectrogram Transformer) ONNX model to CoreML.

Downloads the discogs-maest-10s-pw-129e model from Hugging Face and converts
to CoreML .mlpackage format for use in CrateBot.

MAEST produces 768-dimensional embeddings from audio spectrograms.

Requirements:
    pip install onnx coremltools huggingface_hub

Usage:
    python scripts/convert_maest.py

Output:
    Models/MAEST.mlpackage
"""

import os
import sys

def main():
    try:
        import onnx
        import coremltools as ct
        from huggingface_hub import hf_hub_download
    except ImportError as e:
        print(f"Missing dependency: {e}")
        print("Install with: pip install onnx coremltools huggingface_hub")
        sys.exit(1)

    # MAEST model on Hugging Face
    # discogs-maest-10s-pw-129e: 10-second patchwise model trained for 129 epochs
    repo_id = "mtg-upf/discogs-maest-10s-pw-129e"
    onnx_filename = "model.onnx"

    output_dir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "Models")
    os.makedirs(output_dir, exist_ok=True)
    output_path = os.path.join(output_dir, "MAEST.mlpackage")

    # Download ONNX model from Hugging Face
    print(f"Downloading MAEST ONNX model from {repo_id}...")
    try:
        onnx_path = hf_hub_download(
            repo_id=repo_id,
            filename=onnx_filename,
        )
        print(f"Downloaded to: {onnx_path}")
    except Exception as e:
        print(f"Download failed: {e}")
        print()
        print("The model may not have a pre-exported ONNX file.")
        print("Alternative approaches:")
        print("  1. Export from PyTorch: load the model with transformers/timm and export with torch.onnx.export()")
        print("  2. Check the repo for available files: huggingface-cli repo info mtg-upf/discogs-maest-10s-pw-129e")
        print("  3. Try a different filename (e.g., 'discogs-maest-10s-pw-129e.onnx')")
        print()
        print("To export from PyTorch manually:")
        print("  pip install torch timm")
        print("  import torch")
        print("  model = torch.hub.load('palonso/MAEST', 'maest_10s_pw_129e')")
        print("  dummy = torch.randn(1, 1, 96, 625)  # [batch, channels, mel_bands, time_frames]")
        print("  torch.onnx.export(model, dummy, 'maest.onnx', input_names=['input'], output_names=['embedding'])")
        sys.exit(1)

    # Load and verify ONNX model
    print("Loading ONNX model...")
    onnx_model = onnx.load(onnx_path)
    onnx.checker.check_model(onnx_model)

    # Print model input/output info for debugging
    print("\nModel inputs:")
    for inp in onnx_model.graph.input:
        shape = [d.dim_value for d in inp.type.tensor_type.shape.dim]
        print(f"  {inp.name}: {shape}")

    print("\nModel outputs:")
    for out in onnx_model.graph.output:
        shape = [d.dim_value for d in out.type.tensor_type.shape.dim]
        print(f"  {out.name}: {shape}")

    # Convert ONNX to CoreML
    # NOTE: The exact input shape depends on the model variant.
    # discogs-maest-10s uses 10 seconds of audio as mel spectrogram.
    # Typical shape: [1, 1, 96, 625] (batch, channels, mel_bands, time_frames)
    # Adjust ct.TensorType shape if conversion fails with shape mismatch.
    print("\nConverting to CoreML...")
    try:
        mlmodel = ct.converters.convert(
            onnx_path,
            compute_precision=ct.precision.FLOAT32,
            minimum_deployment_target=ct.target.macOS14,
        )
    except Exception as e:
        print(f"Conversion failed: {e}")
        print()
        print("If this is a shape issue, try specifying input shape explicitly:")
        print("  ct.converters.convert(onnx_path, inputs=[ct.TensorType(shape=(1, 1, 96, 625))])")
        print()
        print("Check the printed input/output shapes above and adjust accordingly.")
        sys.exit(1)

    # Print CoreML model spec for input/output names
    spec = mlmodel.get_spec()
    print("\nCoreML model inputs:")
    for inp in spec.description.input:
        print(f"  {inp.name}: {inp.type}")
    print("\nCoreML model outputs:")
    for out in spec.description.output:
        print(f"  {out.name}: {out.type}")

    # Save
    mlmodel.save(output_path)
    print(f"\nSaved CoreML model to: {output_path}")
    print()
    print("Next steps:")
    print("  1. Note the input/output names printed above")
    print("  2. Update MAESTExtractor.swift with the correct input/output names")
    print("  3. Add MAEST.mlpackage to the Xcode project resources")
    print("  4. Compile to .mlmodelc for faster loading (Xcode does this automatically)")


if __name__ == "__main__":
    main()
