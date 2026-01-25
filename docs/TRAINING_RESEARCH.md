# Training Accuracy Research

Research findings on techniques, models, and libraries for improving CrateBot's audio tagging accuracy.

---

## Pre-trained Audio Embedding Models

### Tier 1: Most Promising for CrateBot

| Model | Embedding Dim | Trained On | Strengths | CoreML Feasibility |
|-------|--------------|------------|-----------|-------------------|
| **LAION CLAP** | 512 | 630K audio-text pairs + music | Zero-shot classification, text-audio similarity | Medium - HuggingFace Transformers support |
| **MERT** | 768 (13 layers) | 20K hrs music | Music-specific, SOTA on MIR tasks | Medium - 95M params, transformer |
| **BEATs** | 768 | AudioSet | General audio, iterative self-supervised | Medium - Microsoft research model |
| **PANN** | 2048 | AudioSet 2M clips | General audio understanding | Done - Python code exists |

### Tier 2: Worth Considering

| Model | Notes |
|-------|-------|
| **musicnn** | Musically-motivated CNN, 90.77 ROC-AUC on MagnaTagATune |
| **OpenL3** | Good for small datasets with SVM classifier |
| **Audio Spectrogram Transformer (AST)** | Convolution-free, purely attention-based |

---

## Model Details

### LAION CLAP

CLAP (Contrastive Language-Audio Pretraining) is to audio what CLIP is to image. It learns the similarity between audio and text through contrastive learning, mapping both modalities into a joint multimodal space.

**Key Features:**
- Trained on LAION-Audio-630K (633,526 text/audio pairs)
- Zero-shot classification without training
- Multiple variants: `larger_clap_music` (71% GTZAN), `larger_clap_music_and_speech`

**Usage for Embeddings:**
```python
from transformers import ClapModel, ClapProcessor

model = ClapModel.from_pretrained("laion/larger_clap_music")
processor = ClapProcessor.from_pretrained("laion/larger_clap_music")

inputs = processor(audios=audio_array, return_tensors="pt")
audio_embed = model.get_audio_features(**inputs)  # 512-dim
```

**Zero-Shot Classification:**
```python
from transformers import pipeline

classifier = pipeline(
    task="zero-shot-audio-classification",
    model="laion/larger_clap_music"
)
output = classifier(audio, candidate_labels=["funky", "mellow", "energetic"])
```

**Links:**
- GitHub: https://github.com/LAION-AI/CLAP
- HuggingFace: https://huggingface.co/laion/larger_clap_music

---

### MERT (Acoustic Music Understanding Model)

MERT is a self-supervised transformer model specifically trained for music understanding. Uses masked language modeling with acoustic and musical teachers.

**Key Features:**
- 95M parameters, 12 transformer layers
- Trained on 20K hours of music
- 768-dim embeddings at 75 Hz (features per second)
- 13 layers of hidden states (different layers perform differently on different tasks)
- Requires 24kHz audio input

**Usage for Embeddings:**
```python
from transformers import Wav2Vec2FeatureExtractor, AutoModel
import torch

model = AutoModel.from_pretrained("m-a-p/MERT-v1-95M", trust_remote_code=True)
processor = Wav2Vec2FeatureExtractor.from_pretrained("m-a-p/MERT-v1-95M", trust_remote_code=True)

inputs = processor(audio_24khz, sampling_rate=24000, return_tensors="pt")
with torch.no_grad():
    outputs = model(**inputs, output_hidden_states=True)

# All 13 layers: [13, Time, 768]
all_layers = torch.stack(outputs.hidden_states).squeeze()

# Aggregate across time for classification
time_reduced = all_layers.mean(-2)  # [13, 768]

# Use weighted average or specific layer
final_embedding = time_reduced.mean(0)  # [768]
```

**Links:**
- HuggingFace: https://huggingface.co/m-a-p/MERT-v1-95M
- Paper: https://arxiv.org/abs/2306.00107

---

### BEATs (Audio Pre-Training with Acoustic Tokenizers)

BEATs is an iterative audio pre-training framework from Microsoft that learns bidirectional encoder representations using acoustic tokenizers.

**Key Features:**
- Iteratively optimizes acoustic tokenizer and audio SSL model
- Uses discrete label prediction (not reconstruction loss)
- Captures high-level audio semantics

**Links:**
- GitHub: https://github.com/microsoft/unilm/tree/master/beats
- Paper: https://arxiv.org/abs/2212.09058

---

### musicnn

Pre-trained musically-motivated CNNs for music audio tagging. Attention-based version achieved SOTA results.

**Performance:**
- MagnaTagATune: 90.77 ROC-AUC / 38.61 PR-AUC
- Million Song Dataset: 88.81 ROC-AUC / 31.51 PR-AUC

**Links:**
- GitHub: https://github.com/jordipons/musicnn
- Paper: https://arxiv.org/abs/1909.06654

---

## Data Augmentation Techniques

Data augmentation can significantly improve accuracy without needing more training data. Research shows combining multiple techniques achieves best results.

### Waveform Domain Augmentations

| Technique | Description | Typical Range |
|-----------|-------------|---------------|
| **Time Stretching** | Change speed without pitch | 0.9x - 1.1x |
| **Pitch Shifting** | Change pitch without speed | ±2 semitones |
| **Noise Injection** | Add background noise | SNR 10-30 dB |
| **Time Shifting** | Random offset/crop | ±0.5 seconds |
| **Gain Variation** | Random volume change | ±6 dB |

### Spectrogram Domain Augmentations

#### SpecAugment

Originally proposed for speech recognition, now widely used for audio classification. Masks random frequency bands and time steps.

```python
def spec_augment(spectrogram, num_freq_masks=2, num_time_masks=2,
                 freq_mask_width=10, time_mask_width=20):
    augmented = spectrogram.copy()
    num_freq_bins, num_time_steps = spectrogram.shape

    # Frequency masking
    for _ in range(num_freq_masks):
        f_width = random.randint(0, freq_mask_width)
        f_start = random.randint(0, num_freq_bins - f_width)
        augmented[f_start:f_start + f_width, :] = 0

    # Time masking
    for _ in range(num_time_masks):
        t_width = random.randint(0, time_mask_width)
        t_start = random.randint(0, num_time_steps - t_width)
        augmented[:, t_start:t_start + t_width] = 0

    return augmented
```

#### Mixup

Generates new samples by linearly interpolating between pairs of existing samples and their labels.

```python
def mixup(sample1, sample2, label1, label2, alpha=0.4):
    lambda_ = np.random.beta(alpha, alpha)
    mixed_sample = lambda_ * sample1 + (1 - lambda_) * sample2
    mixed_label = {label1: lambda_, label2: 1 - lambda_}  # Soft labels
    return mixed_sample, mixed_label
```

#### SpecMix

Combines SpecAugment with Mixup - cuts out masked region from source and replaces with patch from target spectrogram.

### Recommended Combination

Research shows **Mixup + SpecAugment** achieves best performance for audio classification.

---

## Training Techniques

### For Small Datasets

#### Multi-Level Transfer Learning

Uses audio features at multiple granular levels to enhance performance of small models. Improved accuracy by up to 6.45% on ESC-50 dataset.

#### Contrastive Learning Loss

DenseNet-Contrastive achieved highest F1 score (0.88) in clinical audio studies by combining cross-entropy with supervised contrastive loss.

```python
# Supervised contrastive loss alongside cross-entropy
total_loss = cross_entropy_loss + 0.5 * contrastive_loss
```

#### Curriculum Learning

For low-resource settings (2-10% of data), start with simpler tasks before harder ones:
1. Train on text-only or synthetic data first
2. Gradually introduce real audio data
3. Fine-tune on full task

#### Knowledge Distillation

Train smaller student network using pre-trained embeddings as teacher:

```python
# Student learns to match teacher embeddings
distillation_loss = mse_loss(student_features, teacher_embeddings.detach())
total_loss = classification_loss + alpha * distillation_loss
```

### Ensemble Methods

#### Model Aggregation

Ensemble of models achieved 0.474 mAP on AudioSet vs 0.439 for single best model (8% improvement).

#### Embedding Concatenation

Combine multiple embedding sources for richer representation:
- EffNet (1280) + Genres (400) + PANN (2048) = 3728 dimensions
- Different models capture different audio aspects

---

## Implementation Priority for CrateBot

### High Priority (Low Effort, High Impact)

1. **Data Augmentation (SpecAugment + Mixup)**
   - Pure Swift implementation, no new models needed
   - Apply during training data preparation
   - Expected improvement: 5-15% accuracy

2. **Genre Activations** (already in plan)
   - Already extracted, just concatenate
   - 1280 → 1680 dimensions

### Medium Priority (Medium Effort)

3. **CLAP Embeddings**
   - 512-dim, strong music performance
   - Zero-shot capability for cold-start
   - Requires CoreML conversion

4. **MERT Embeddings**
   - 768-dim, music-specific
   - 13 layers provide rich representation
   - Likely best for music-specific tags

### Lower Priority (Higher Effort)

5. **Contrastive Learning Loss**
   - Requires training pipeline changes
   - Better feature separation

6. **Ensemble Inference**
   - Train multiple classifier types
   - Vote or average predictions

---

## CoreML Conversion Notes

### Challenges with Transformer Models

- MERT, CLAP, BEATs are PyTorch transformer models
- Dynamic shapes can cause CoreML issues
- Need fixed input shapes for reliable conversion

### Conversion Approach

```python
import coremltools as ct
import torch

# 1. Trace model with fixed input shape
example_input = torch.randn(1, 96000)  # Fixed audio length
traced = torch.jit.trace(model, example_input)

# 2. Convert with fixed shapes
mlmodel = ct.convert(
    traced,
    inputs=[ct.TensorType(name="audio", shape=(1, 96000))],
    outputs=[ct.TensorType(name="embedding")],
    minimum_deployment_target=ct.target.macOS13,
    compute_precision=ct.precision.FLOAT16
)

# 3. Handle variable-length audio by:
#    - Padding/truncating to fixed length
#    - Processing in fixed-size chunks and averaging
```

### Recommended Models for CoreML

| Model | Conversion Difficulty | Notes |
|-------|----------------------|-------|
| PANN | Easy | CNN-based, already have Python code |
| CLAP | Medium | HuggingFace integration helps |
| MERT | Medium-Hard | Transformer, may need custom ops |
| BEATs | Hard | Complex architecture |

---

## References

### Papers
- [CLAP: Learning Audio Concepts from Natural Language Supervision](https://arxiv.org/abs/2206.04769)
- [MERT: Acoustic Music Understanding Model](https://arxiv.org/abs/2306.00107)
- [BEATs: Audio Pre-Training with Acoustic Tokenizers](https://arxiv.org/abs/2212.09058)
- [musicnn: Pre-trained CNNs for Music Audio Tagging](https://arxiv.org/abs/1909.06654)
- [SpecAugment: Data Augmentation for ASR](https://arxiv.org/abs/1904.08779)
- [Mixup: Beyond Empirical Risk Minimization](https://arxiv.org/abs/1710.09412)
- [Audio Embeddings as Teachers for Music Classification](https://arxiv.org/abs/2306.17424)

### Resources
- [HuggingFace Audio Course](https://huggingface.co/learn/audio-course/en/chapter3/introduction)
- [HuggingFace Audio Classification Models](https://huggingface.co/models?pipeline_tag=audio-classification)
- [Music Classification Tutorial - Data Augmentation](https://music-classification.github.io/tutorial/part3_supervised/data-augmentation.html)
- [Top Audio Embedding Models Guide](https://zilliz.com/learn/top-10-most-used-embedding-models-for-audio-data)

### Code Repositories
- [LAION CLAP](https://github.com/LAION-AI/CLAP)
- [Microsoft BEATs](https://github.com/microsoft/unilm/tree/master/beats)
- [musicnn](https://github.com/jordipons/musicnn)
- [Apple CoreML Tools](https://github.com/apple/coremltools)
