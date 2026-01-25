#!/usr/bin/env python3
"""
Convert LAION CLAP model to CoreML for CrateBot.
Outputs audio encoder only (512-dim embeddings).

Usage:
    pip install transformers coremltools torch
    python convert_clap_to_coreml.py
"""

import torch
import coremltools as ct
from transformers import ClapModel, ClapProcessor
import numpy as np

def main():
    print("Loading CLAP model...")
    model = ClapModel.from_pretrained("laion/larger_clap_music")
    processor = ClapProcessor.from_pretrained("laion/larger_clap_music")
    model.eval()

    # We only need the audio encoder
    audio_model = model.audio_model
    audio_projection = model.audio_projection

    class CLAPAudioEncoder(torch.nn.Module):
        def __init__(self, audio_model, audio_projection):
            super().__init__()
            self.audio_model = audio_model
            self.audio_projection = audio_projection

        def forward(self, input_features):
            # input_features: [batch, mel_bins, time_frames]
            outputs = self.audio_model(input_features=input_features)
            pooled = outputs.pooler_output  # [batch, hidden_size]
            embeddings = self.audio_projection(pooled)  # [batch, 512]
            return embeddings

    encoder = CLAPAudioEncoder(audio_model, audio_projection)
    encoder.eval()

    # CLAP expects mel spectrogram input
    # Fixed shape for CoreML: [1, 64, 1001] (64 mel bins, ~10 seconds at default hop)
    example_input = torch.randn(1, 64, 1001)

    print("Tracing model...")
    traced = torch.jit.trace(encoder, example_input)

    print("Converting to CoreML...")
    mlmodel = ct.convert(
        traced,
        inputs=[
            ct.TensorType(name="mel_spectrogram", shape=(1, 64, 1001))
        ],
        outputs=[
            ct.TensorType(name="embedding")
        ],
        minimum_deployment_target=ct.target.macOS13,
        compute_precision=ct.precision.FLOAT16
    )

    # Add metadata
    mlmodel.author = "CrateBot (converted from LAION CLAP)"
    mlmodel.short_description = "CLAP audio encoder for music embeddings (512-dim)"
    mlmodel.version = "1.0"

    output_path = "CLAPAudioEncoder.mlpackage"
    mlmodel.save(output_path)
    print(f"Saved to {output_path}")

    # Verify
    print("Verifying...")
    import coremltools as ct
    loaded = ct.models.MLModel(output_path)
    test_input = {"mel_spectrogram": np.random.randn(1, 64, 1001).astype(np.float32)}
    output = loaded.predict(test_input)
    print(f"Output shape: {output['embedding'].shape}")  # Should be (1, 512)
    print("Done!")

if __name__ == "__main__":
    main()
