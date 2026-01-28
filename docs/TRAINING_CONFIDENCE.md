# Training Confidence & Low-Sample Tags

*Discussion captured: January 2026*

## Problem Statement

Tags with fewer training samples (25-50) may produce less reliable classifiers. Currently, we have a hard minimum of 50 samples. The question is: how can we train tags with fewer samples while maintaining reliability?

## Current State

| What | Tracked During Training | Saved With Model | Available at Inference |
|------|------------------------|------------------|----------------------|
| Per-tag validation accuracy | Yes | No | No |
| Per-tag sample count | Yes | No | No |
| Overall average accuracy | Yes | Yes | Yes |
| Fallback mappings | N/A | Separate config | Yes |

**The Gap:** Per-tag confidence info isn't persisted with the model, so at inference time we can't know which tags were trained with low confidence.

## Existing Fallback System

We have a fallback mapping system (`TagFallbackMapping`) that:
- Maps user tags to Essentia predictions (mood, genre, instrument)
- Works for tags WITHOUT trained classifiers
- Uses pre-trained models with millions of training samples

## Proposed Options

### Option A: Simple - Use Fallbacks Aggressively

- Keep minimum samples at 50
- For tags with <50 samples, use fallback mappings exclusively
- **Pros:** No code changes, leverages robust pre-trained models
- **Cons:** Limited to Essentia's vocabulary (56 moods, 400 genres, 40 instruments)

### Option B: Medium - Store Per-Tag Metadata (Recommended)

Lower minimum to 25, store confidence metadata, validate low-confidence predictions against fallbacks.

**Changes Required:**

1. **ModelMetadata.swift** - Add per-tag confidence:
```swift
public struct TagConfidence: Codable, Sendable {
    public let validationAccuracy: Double
    public let sampleCount: Int
    public let isLowConfidence: Bool  // sampleCount < 50 or accuracy < 0.7
}

public struct ModelMetadata: Codable, Sendable {
    // ... existing fields ...
    public let tagConfidences: [String: TagConfidence]?
}
```

2. **TrainingCoordinator.swift** - Save per-tag confidence when creating metadata

3. **TaggingEngine.swift** - At inference time:
   - Load tag confidences with model
   - For low-confidence tags with fallback mappings:
     - Require BOTH classifier AND fallback to agree
     - Or weight the predictions based on confidence
   - Tags without agreement get lower prediction confidence

**Visual indicator options:**
- Suffix like `Happy_?` for uncertain predictions
- Confidence score in metadata for downstream processing
- Different ID3 field for low-confidence tags

### Option C: Full - Ensemble Approach

Train all tags with >=25 samples, use weighted combination of classifier + fallback predictions.

**At inference:**
```
final_confidence = (classifier_weight * classifier_prediction) + (fallback_weight * fallback_prediction)

where:
  classifier_weight = f(validation_accuracy, sample_count)
  fallback_weight = 1 - classifier_weight (if fallback exists)
```

**Pros:** Most nuanced approach, best of both worlds
**Cons:** More complex, harder to debug/explain

## Key Insight

Essentia's pre-trained models (trained on millions of samples) may be MORE reliable than a custom classifier trained on 25 samples for similar concepts. The value of custom classifiers is capturing YOUR specific tagging style/vocabulary, not necessarily being more accurate for generic concepts.

## Recommendation

**For tags with clear Essentia equivalents** (e.g., "Happy" → Essentia mood "happy"):
- Use fallback mapping instead of training with <50 samples
- Essentia's model is likely more reliable

**For tags unique to your vocabulary** (e.g., "WalkingBass", "Stabby"):
- Option B - train anyway, but flag as low-confidence
- At inference, apply higher threshold or require user review

## Future Work

1. Implement Option B when ready
2. Consider UI indicator for low-confidence predictions
3. Potentially allow user to "confirm" low-confidence predictions to improve training data
4. Track prediction accuracy over time to identify which low-confidence classifiers are actually reliable
