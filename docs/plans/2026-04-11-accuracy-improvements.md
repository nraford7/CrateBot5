# Accuracy Improvements Implementation Plan

> **For Claude:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Raise tagging accuracy through per-tag optimal thresholds, zero-shot CLAP matching for rare tags, and MAEST embedding integration.

**Architecture:** Three independent features that each improve accuracy differently. Per-tag thresholds optimize the decision boundary per classifier. Zero-shot CLAP eliminates training requirements for new tags. MAEST adds transformer-based embeddings complementary to EffNet's CNN embeddings.

**Tech Stack:** Swift, CoreML, Python (coremltools, transformers), LAION-CLAP

---

## Feature 1: Per-Tag Optimal Thresholds

The global threshold (0.85) is a compromise — some tags peak at 0.70, others at 0.95. Per-tag thresholds let each classifier use its own optimal decision boundary.

### File Map

| File | Action | What |
|------|--------|------|
| `scripts/accuracy_eval.py` | Modify | Add per-tag threshold sweep, output JSON |
| `CrateBotCore/Sources/CrateBotCore/ML/ModelMetadata.swift` | Modify | Add `tagThresholds: [String: Float]?` |
| `CrateBotCore/Sources/CrateBotCore/ML/TaggingEngine.swift` | Modify | Use per-tag thresholds during inference |
| `CrateBotCore/Tests/CrateBotCoreTests/ML/ModelMetadataTests.swift` | Modify | Test tagThresholds encode/decode |

---

### Task 1: Add per-tag threshold sweep to accuracy_eval.py

**Files:**
- Modify: `scripts/accuracy_eval.py`

- [ ] **Step 1: Add `--optimize-thresholds` mode to the script**

Add a new function after `main()` that sweeps thresholds per tag and outputs JSON:

```python
def optimize_thresholds(raw_probs, sampled, classifiers, output_path=None):
    """Find optimal threshold per tag by maximizing F1."""
    thresholds_to_try = [t/100 for t in range(50, 100)]
    optimal = {}

    for tag in classifiers:
        best_f1, best_thresh = 0, 0.85
        for threshold in thresholds_to_try:
            tp = fp = fn = tn = 0
            for i, track in enumerate(sampled):
                if tag not in raw_probs[i]: continue
                predicted = raw_probs[i][tag] > threshold
                actual = tag in set(track['tags'])
                if predicted and actual: tp += 1
                elif predicted and not actual: fp += 1
                elif not predicted and actual: fn += 1
                else: tn += 1

            prec = tp/(tp+fp) if (tp+fp) > 0 else 0
            rec = tp/(tp+fn) if (tp+fn) > 0 else 0
            f1 = 2*prec*rec/(prec+rec) if (prec+rec) > 0 else 0

            if f1 > best_f1:
                best_f1 = f1
                best_thresh = threshold

        optimal[tag] = round(best_thresh, 2)
        print(f"  {tag:25s} -> {best_thresh:.2f} (F1={best_f1*100:.1f}%)")

    if output_path:
        with open(output_path, 'w') as f:
            json.dump(optimal, f, indent=2)
        print(f"\nSaved to {output_path}")

    return optimal
```

Add CLI flag handling at the bottom of `main()`:

```python
if '--optimize' in sys.argv:
    output = model_dir / "tag_thresholds.json"
    optimize_thresholds(raw_probs, sampled, classifiers, output)
```

- [ ] **Step 2: Run the optimizer**

Run: `python3 scripts/accuracy_eval.py --optimize`
Expected: Per-tag thresholds saved to `~/Library/Application Support/CrateBot/Models/CB5_v3/tag_thresholds.json`

- [ ] **Step 3: Commit**

```bash
git add scripts/accuracy_eval.py
git commit -m "feat: add per-tag threshold optimization to accuracy_eval.py"
```

---

### Task 2: Add tagThresholds to ModelMetadata

**Files:**
- Modify: `CrateBotCore/Sources/CrateBotCore/ML/ModelMetadata.swift`
- Modify: `CrateBotCore/Tests/CrateBotCoreTests/ML/ModelMetadataTests.swift`

- [ ] **Step 1: Add field to ModelMetadata**

In `ModelMetadata.swift`, add after the `calibratorTemperature` field:

```swift
/// Per-tag classification thresholds (tag name -> threshold)
/// When present, overrides the global classificationThreshold for specific tags
public let tagThresholds: [String: Float]?
```

Add to `init()` with default `nil`. Add to `CodingKeys`. Add `decodeIfPresent` in the custom decoder.

- [ ] **Step 2: Add test for encode/decode**

In `ModelMetadataTests.swift`, add:

```swift
func testTagThresholdsEncodeDecode() throws {
    let metadata = ModelMetadata(
        name: "Test", version: "1.0", pipelineVersion: "1.0",
        trainedAt: Date(), trainingFileCount: 100,
        categories: ["Genre"], tags: ["Genre": ["House"]],
        tagThresholds: ["House": 0.82, "Techno": 0.91]
    )

    let data = try JSONEncoder().encode(metadata)
    let decoded = try JSONDecoder().decode(ModelMetadata.self, from: data)
    XCTAssertEqual(decoded.tagThresholds?["House"], 0.82, accuracy: 0.001)
    XCTAssertEqual(decoded.tagThresholds?["Techno"], 0.91, accuracy: 0.001)
}

func testTagThresholdsBackwardCompatibility() throws {
    // Old metadata without tagThresholds should decode with nil
    let json = """
    {"name":"Test","version":"1.0","pipelineVersion":"1.0",
     "trainedAt":"2026-01-01T00:00:00Z","trainingFileCount":100,
     "categories":["Genre"],"tags":{"Genre":["House"]},
     "featureDimension":1680}
    """.data(using: .utf8)!

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let decoded = try decoder.decode(ModelMetadata.self, from: json)
    XCTAssertNil(decoded.tagThresholds)
}
```

- [ ] **Step 3: Run tests**

Run: `cd CrateBotCore && swift test --filter ModelMetadataTests`

- [ ] **Step 4: Commit**

```bash
git add CrateBotCore/Sources/CrateBotCore/ML/ModelMetadata.swift CrateBotCore/Tests/CrateBotCoreTests/ML/ModelMetadataTests.swift
git commit -m "feat: add per-tag thresholds to ModelMetadata"
```

---

### Task 3: Apply per-tag thresholds in TaggingEngine

**Files:**
- Modify: `CrateBotCore/Sources/CrateBotCore/ML/TaggingEngine.swift`

- [ ] **Step 1: Add tagThresholds property and loader**

After line 164 (`classificationThreshold`), add:

```swift
/// Per-tag thresholds loaded from model metadata (overrides global threshold)
private var tagThresholds: [String: Float]?
```

In the `loadModel` method, after loading metadata (around line 219), add:

```swift
// Load per-tag thresholds if available
self.tagThresholds = metadata?.tagThresholds

// Also try loading from separate file (generated by accuracy_eval.py)
if self.tagThresholds == nil {
    let thresholdsURL = modelDirectory.appendingPathComponent("tag_thresholds.json")
    if let data = try? Data(contentsOf: thresholdsURL),
       let thresholds = try? JSONDecoder().decode([String: Float].self, from: data) {
        self.tagThresholds = thresholds
        logger.info("Loaded per-tag thresholds for \(thresholds.count) tags")
    }
}
```

- [ ] **Step 2: Use per-tag thresholds in inference**

At line 416, change:
```swift
if confidence >= classificationThreshold {
```
to:
```swift
let effectiveThreshold = tagThresholds?[classifier.tagName] ?? classificationThreshold
if confidence >= effectiveThreshold {
```

At line 445 (multi-class), change:
```swift
if prediction.confidence >= classificationThreshold {
```
to:
```swift
let effectiveGroupThreshold = tagThresholds?[prediction.predictedClass] ?? classificationThreshold
if prediction.confidence >= effectiveGroupThreshold {
```

- [ ] **Step 3: Run tests**

Run: `cd CrateBotCore && swift test --filter TaggingEngineTests`

- [ ] **Step 4: Commit**

```bash
git add CrateBotCore/Sources/CrateBotCore/ML/TaggingEngine.swift
git commit -m "feat: apply per-tag thresholds during inference

TaggingEngine now loads per-tag thresholds from model metadata or a
separate tag_thresholds.json file. Each classifier uses its optimal
threshold instead of the global default. Falls back to global threshold
for tags without a specific threshold."
```

---

## Feature 2: Zero-Shot CLAP Matching

Use pre-computed CLAP text embeddings to tag tracks without any trained classifier. The audio CLAP embedding (already extracted as part of the 2192-dim feature vector) is compared via cosine similarity to text embeddings for tag descriptions.

### File Map

| File | Action | What |
|------|--------|------|
| `scripts/generate_clap_text_embeddings.py` | Create | Pre-compute text embeddings for tag vocabulary |
| `CrateBotCore/Sources/CrateBotCore/Resources/clap_tag_embeddings.json` | Create | Bundled pre-computed text embeddings |
| `CrateBotCore/Sources/CrateBotCore/ML/ZeroShotMatcher.swift` | Create | Cosine similarity matching engine |
| `CrateBotCore/Sources/CrateBotCore/ML/TaggingEngine.swift` | Modify | Integrate zero-shot after trained classifiers |
| `CrateBotCore/Package.swift` | Modify | Bundle the JSON resource |
| `CrateBotCore/Tests/CrateBotCoreTests/ML/ZeroShotMatcherTests.swift` | Create | Test cosine similarity and matching |

---

### Task 4: Generate CLAP text embeddings

**Files:**
- Create: `scripts/generate_clap_text_embeddings.py`

- [ ] **Step 1: Create the text embedding generator**

```python
#!/usr/bin/env python3
"""
Pre-compute CLAP text embeddings for CrateBot's tag vocabulary.
Uses LAION-CLAP text encoder to generate 512-dim embeddings for each tag.
Output: JSON file with tag -> embedding mapping.
"""
import json, sys
import numpy as np

def main():
    try:
        import laion_clap
    except ImportError:
        print("pip install laion-clap")
        sys.exit(1)

    # Load CLAP model (text encoder only needed)
    model = laion_clap.CLAP_Module(enable_fusion=False)
    model.load_ckpt()

    # DJ tag vocabulary with natural language descriptions
    # Format: tag_name -> description for text encoding
    tag_descriptions = {
        # Genre
        "House": "house music electronic dance four on the floor",
        "Techno": "techno music electronic industrial repetitive",
        "Acapella": "acapella vocals only no instruments singing",
        # Mood
        "Happy": "happy uplifting joyful positive cheerful music",
        "Aggressive": "aggressive intense hard heavy powerful music",
        "Dark/Intense": "dark intense moody sinister brooding music",
        "Emotional": "emotional moving heartfelt soulful deep music",
        "Floating/Spacey": "ambient spacey floating ethereal dreamy atmospheric music",
        # Timing
        "Build": "building rising tension growing energy crescendo",
        "Release": "release drop peak energy climax",
        "Start": "intro opening beginning start of track",
        "Sustain": "sustained steady maintaining groove constant energy",
        # Descriptive - Rhythm
        "Broken": "broken beat irregular syncopated rhythm",
        "Driving": "driving relentless forward propulsive rhythm",
        "Loopy": "loopy repetitive hypnotic cycling pattern",
        "Swung": "swing swung shuffle groove triplet feel",
        # Descriptive - Vibes
        "Bouncy": "bouncy fun playful upbeat energetic groove",
        "Dope": "cool dope hip stylish smooth groove",
        "Dreamy": "dreamy atmospheric lush ethereal soundscape",
        "Dubby": "dub reggae delay echo spacey bass",
        "Epic": "epic cinematic grand dramatic powerful orchestral",
        "Fun": "fun playful light party celebration",
        "Funky": "funky groove funk bass guitar rhythm",
        "Glitchy": "glitch digital distorted electronic experimental",
        "Grindy": "grindy grinding dirty raw distorted bass",
        "Jazzy": "jazz jazzy saxophone piano improvisation swing",
        "Joyful": "joyful happy uplifting celebration joy",
        "Melodic": "melodic beautiful melody harmonious musical",
        "Techy": "techy technical precise minimal electronic",
        "Tropical": "tropical warm latin caribbean percussion sunny",
        # Descriptive - Style
        "Afro": "african afrobeat percussion tribal rhythmic",
        "Arabic": "arabic middle eastern oriental oud percussion",
        "Classic": "classic timeless old school traditional",
        "Disco": "disco funk dance groove four on the floor bass",
        "Electro": "electro electronic synthesizer robotic digital",
        "Poppy": "pop catchy mainstream hook melody vocal",
        "Spiritual": "spiritual meditative zen peaceful transcendent",
        # Descriptive - Instruments
        "Arpeggiated": "arpeggio synthesizer sequenced repeating notes",
        "Beats": "percussion drums beat rhythm kick snare",
        "Congas": "conga percussion hand drums latin african",
        "Guitar": "guitar acoustic electric string instrument",
        "Hi Hats": "hi hat cymbal percussion metallic rhythmic",
        "Horns": "horn brass trumpet saxophone wind instrument",
        "Organ": "organ keyboard church hammond electric",
        "Pads": "pad synthesizer ambient sustained warm texture",
        "Piano": "piano keyboard acoustic melodic chord",
        "Strings": "strings violin cello orchestra bowed",
        "Sweeps": "sweep riser effect transition filter",
        # Other
        "Dirty": "dirty raw gritty distorted rough unpolished",
        "Head Knodding": "head nodding groove mid tempo bobbing rhythm",
    }

    # Encode all descriptions
    descriptions = list(tag_descriptions.values())
    tags = list(tag_descriptions.keys())

    print(f"Encoding {len(tags)} tag descriptions...")
    text_embeddings = model.get_text_embedding(descriptions, use_tensor=False)

    # Build output dict
    output = {}
    for tag, embedding in zip(tags, text_embeddings):
        # Normalize embedding to unit vector for cosine similarity
        norm = np.linalg.norm(embedding)
        normalized = (embedding / norm).tolist() if norm > 0 else embedding.tolist()
        output[tag] = normalized

    # Save
    output_path = "CrateBotCore/Sources/CrateBotCore/Resources/clap_tag_embeddings.json"
    with open(output_path, 'w') as f:
        json.dump(output, f)

    print(f"Saved {len(output)} embeddings ({len(output[tags[0]])} dims each) to {output_path}")

if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Install laion-clap and run**

Run:
```bash
pip install laion-clap
cd /Users/noahraford/Projects/claude_projects/11_CrateBot/CrateBot5
python3 scripts/generate_clap_text_embeddings.py
```

Expected: `clap_tag_embeddings.json` created in Resources/

- [ ] **Step 3: Add resource to Package.swift**

In `CrateBotCore/Package.swift`, add to the resources array:
```swift
.copy("Resources/clap_tag_embeddings.json"),
```

- [ ] **Step 4: Commit**

```bash
git add scripts/generate_clap_text_embeddings.py CrateBotCore/Sources/CrateBotCore/Resources/clap_tag_embeddings.json CrateBotCore/Package.swift
git commit -m "feat: pre-compute CLAP text embeddings for zero-shot tag matching"
```

---

### Task 5: Create ZeroShotMatcher

**Files:**
- Create: `CrateBotCore/Sources/CrateBotCore/ML/ZeroShotMatcher.swift`
- Create: `CrateBotCore/Tests/CrateBotCoreTests/ML/ZeroShotMatcherTests.swift`

- [ ] **Step 1: Write tests**

```swift
import XCTest
@testable import CrateBotCore

final class ZeroShotMatcherTests: XCTestCase {

    func testCosineSimilarityIdentical() {
        let a: [Float] = [1, 0, 0, 0]
        let b: [Float] = [1, 0, 0, 0]
        XCTAssertEqual(ZeroShotMatcher.cosineSimilarity(a, b), 1.0, accuracy: 0.001)
    }

    func testCosineSimilarityOrthogonal() {
        let a: [Float] = [1, 0, 0, 0]
        let b: [Float] = [0, 1, 0, 0]
        XCTAssertEqual(ZeroShotMatcher.cosineSimilarity(a, b), 0.0, accuracy: 0.001)
    }

    func testCosineSimilarityOpposite() {
        let a: [Float] = [1, 0, 0, 0]
        let b: [Float] = [-1, 0, 0, 0]
        XCTAssertEqual(ZeroShotMatcher.cosineSimilarity(a, b), -1.0, accuracy: 0.001)
    }

    func testMatchReturnsTagsAboveThreshold() {
        // Fake embeddings: tag1 is similar to audio, tag2 is not
        let tagEmbeddings: [String: [Float]] = [
            "similar": [0.9, 0.1, 0.0, 0.0],
            "different": [0.0, 0.0, 0.9, 0.1],
        ]
        let matcher = ZeroShotMatcher(tagEmbeddings: tagEmbeddings)
        let audioEmbedding: [Float] = [1.0, 0.0, 0.0, 0.0]
        let matches = matcher.match(audioEmbedding: audioEmbedding, threshold: 0.5)

        XCTAssertTrue(matches.contains { $0.tag == "similar" })
        XCTAssertFalse(matches.contains { $0.tag == "different" })
    }

    func testMatchExcludesTrainedTags() {
        let tagEmbeddings: [String: [Float]] = [
            "trained": [1.0, 0.0, 0.0, 0.0],
            "untrained": [0.9, 0.1, 0.0, 0.0],
        ]
        let matcher = ZeroShotMatcher(tagEmbeddings: tagEmbeddings)
        let audioEmbedding: [Float] = [1.0, 0.0, 0.0, 0.0]
        let matches = matcher.match(
            audioEmbedding: audioEmbedding,
            threshold: 0.5,
            excludingTags: Set(["trained"])
        )

        XCTAssertFalse(matches.contains { $0.tag == "trained" })
        XCTAssertTrue(matches.contains { $0.tag == "untrained" })
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd CrateBotCore && swift test --filter ZeroShotMatcherTests`

- [ ] **Step 3: Implement ZeroShotMatcher**

Create `CrateBotCore/Sources/CrateBotCore/ML/ZeroShotMatcher.swift`:

```swift
import Foundation
import Accelerate

/// Zero-shot tag matching using pre-computed CLAP text embeddings.
/// Compares audio CLAP embeddings to text embeddings via cosine similarity.
public struct ZeroShotMatcher: Sendable {

    public struct Match: Sendable {
        public let tag: String
        public let similarity: Float
    }

    private let tagEmbeddings: [String: [Float]]

    /// Initialize with pre-computed tag text embeddings
    public init(tagEmbeddings: [String: [Float]]) {
        self.tagEmbeddings = tagEmbeddings
    }

    /// Load from bundled JSON resource
    public static func loadFromBundle() -> ZeroShotMatcher? {
        guard let url = Bundle.module.url(forResource: "clap_tag_embeddings", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let embeddings = try? JSONDecoder().decode([String: [Float]].self, from: data) else {
            return nil
        }
        return ZeroShotMatcher(tagEmbeddings: embeddings)
    }

    /// Find tags matching the audio embedding above a similarity threshold
    public func match(
        audioEmbedding: [Float],
        threshold: Float = 0.3,
        maxResults: Int = 5,
        excludingTags: Set<String> = []
    ) -> [Match] {
        var results: [Match] = []

        for (tag, textEmbedding) in tagEmbeddings {
            guard !excludingTags.contains(tag) else { continue }
            guard textEmbedding.count == audioEmbedding.count else { continue }

            let similarity = Self.cosineSimilarity(audioEmbedding, textEmbedding)
            if similarity >= threshold {
                results.append(Match(tag: tag, similarity: similarity))
            }
        }

        return results
            .sorted { $0.similarity > $1.similarity }
            .prefix(maxResults)
            .map { $0 }
    }

    /// Cosine similarity between two vectors using Accelerate
    public static func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }

        var dotProduct: Float = 0
        var normA: Float = 0
        var normB: Float = 0

        vDSP_dotpr(a, 1, b, 1, &dotProduct, vDSP_Length(a.count))
        vDSP_dotpr(a, 1, a, 1, &normA, vDSP_Length(a.count))
        vDSP_dotpr(b, 1, b, 1, &normB, vDSP_Length(b.count))

        let denom = sqrt(normA) * sqrt(normB)
        return denom > 0 ? dotProduct / denom : 0
    }
}
```

- [ ] **Step 4: Run tests**

Run: `cd CrateBotCore && swift test --filter ZeroShotMatcherTests`

- [ ] **Step 5: Commit**

```bash
git add CrateBotCore/Sources/CrateBotCore/ML/ZeroShotMatcher.swift CrateBotCore/Tests/CrateBotCoreTests/ML/ZeroShotMatcherTests.swift
git commit -m "feat: add ZeroShotMatcher for CLAP-based tag matching"
```

---

### Task 6: Integrate zero-shot into TaggingEngine

**Files:**
- Modify: `CrateBotCore/Sources/CrateBotCore/ML/TaggingEngine.swift`

- [ ] **Step 1: Add ZeroShotMatcher to TaggingEngine**

After the `confidenceCalibrator` property, add:

```swift
/// Zero-shot matcher for CLAP-based tag predictions (no training needed)
private let zeroShotMatcher: ZeroShotMatcher?
```

In `init()`, add:

```swift
self.zeroShotMatcher = ZeroShotMatcher.loadFromBundle()
```

- [ ] **Step 2: Add zero-shot predictions after trained classifiers**

In the `analyze` method, after the multi-class classifier loop (around line 445) and before the fallback mappings section, add:

```swift
// Zero-shot CLAP predictions for tags without trained classifiers
if let matcher = zeroShotMatcher, extendedFeatures.count >= 2192 {
    let clapEmbedding = Array(extendedFeatures[1680..<2192])
    let zeroShotMatches = matcher.match(
        audioEmbedding: clapEmbedding,
        threshold: 0.3,
        maxResults: 3,
        excludingTags: trainedTagNames
    )
    for match in zeroShotMatches {
        predictedTags.append(match.tag)
    }
}
```

- [ ] **Step 3: Add zero-shot tags to UserTagPredictions**

In `UserTagPredictions`, add a field to distinguish zero-shot from trained:

```swift
public let zeroShotTags: [String]
```

Update the constructor call to include zero-shot tags.

- [ ] **Step 4: Run tests**

Run: `cd CrateBotCore && swift test --filter TaggingEngineTests`

- [ ] **Step 5: Commit**

```bash
git add CrateBotCore/Sources/CrateBotCore/ML/TaggingEngine.swift
git commit -m "feat: integrate zero-shot CLAP matching into tagging pipeline

Tags without trained classifiers are now matched via cosine similarity
between CLAP audio embeddings and pre-computed text embeddings. Zero-shot
predictions are applied after trained classifiers and before fallback
mappings, with a 0.3 similarity threshold and max 3 results."
```

---

## Feature 3: MAEST Embedding Integration

Add MAEST transformer embeddings (768-dim) as a complementary feature source alongside EffNet (CNN, 1280-dim). MAEST captures different musical properties than EffNet.

**Note:** This feature requires downloading and converting the MAEST ONNX model (~350MB) to CoreML. The conversion may need adjustments based on the model's actual input/output specification.

### File Map

| File | Action | What |
|------|--------|------|
| `scripts/convert_maest.py` | Create | Download + convert MAEST ONNX to CoreML |
| `CrateBotCore/Sources/CrateBotCore/Resources/MAEST.mlpackage` | Create | Converted CoreML model |
| `CrateBotCore/Sources/CrateBotCore/Audio/MAESTExtractor.swift` | Create | MAEST embedding extractor |
| `CrateBotCore/Sources/CrateBotCore/Audio/CombinedFeatureExtractor.swift` | Modify | Add MAEST config option |
| `CrateBotCore/Package.swift` | Modify | Bundle MAEST model |

---

### Task 7: Download and convert MAEST model

**Files:**
- Create: `scripts/convert_maest.py`

- [ ] **Step 1: Create conversion script**

```python
#!/usr/bin/env python3
"""Download MAEST ONNX model and convert to CoreML."""
import subprocess, sys, os

def main():
    model_name = "discogs-maest-10s-pw-129e"
    onnx_path = f"/tmp/{model_name}.onnx"
    output_dir = "CrateBotCore/Sources/CrateBotCore/Resources"
    output_path = f"{output_dir}/MAEST.mlpackage"

    # Download from Hugging Face
    if not os.path.exists(onnx_path):
        print("Downloading MAEST model...")
        url = f"https://huggingface.co/mtg-upf/discogs-maest-10s-pw-129e/resolve/main/{model_name}.onnx"
        subprocess.run(["curl", "-L", "-o", onnx_path, url], check=True)

    # Convert to CoreML
    print("Converting ONNX -> CoreML...")
    import coremltools as ct

    # Load and inspect
    model = ct.converters.onnx.load(onnx_path)

    # Convert with appropriate settings
    mlmodel = ct.convert(
        onnx_path,
        minimum_deployment_target=ct.target.macOS14,
        compute_precision=ct.precision.FLOAT32,
    )

    # Inspect
    spec = mlmodel.get_spec()
    print("\nInputs:")
    for inp in spec.description.input:
        print(f"  {inp.name}: {inp.type}")
    print("\nOutputs:")
    for out in spec.description.output:
        print(f"  {out.name}: {out.type}")

    mlmodel.save(output_path)
    print(f"\nSaved to {output_path}")

if __name__ == "__main__":
    main()
```

- [ ] **Step 2: Run the conversion**

Run: `python3 scripts/convert_maest.py`

Note: If the conversion fails, inspect the ONNX model with `python3 -c "import onnx; m = onnx.load('/tmp/discogs-maest-10s-pw-129e.onnx'); print(m.graph.input); print(m.graph.output)"` and adjust the conversion script accordingly.

- [ ] **Step 3: Verify the converted model**

```python
import coremltools as ct
model = ct.models.MLModel("CrateBotCore/Sources/CrateBotCore/Resources/MAEST.mlpackage")
spec = model.get_spec()
# Note the exact input name, shape, and output name/dimension
```

Record the input name, shape, output name, and output dimension for MAESTExtractor.

- [ ] **Step 4: Commit**

```bash
git add scripts/convert_maest.py
# DO NOT commit the .mlpackage yet (too large for git, handle separately)
git commit -m "feat: add MAEST ONNX-to-CoreML conversion script"
```

---

### Task 8: Create MAESTExtractor

**Files:**
- Create: `CrateBotCore/Sources/CrateBotCore/Audio/MAESTExtractor.swift`
- Modify: `CrateBotCore/Sources/CrateBotCore/Audio/CombinedFeatureExtractor.swift`
- Modify: `CrateBotCore/Package.swift`

- [ ] **Step 1: Create MAESTExtractor**

Mirror the EffNetExtractor pattern. The exact input/output names come from Task 7 Step 3.

```swift
import AVFoundation
import CoreML

/// Extracts 768-dimensional embeddings using MAEST transformer model.
/// Complements EffNet (CNN) with transformer-based musical understanding.
public actor MAESTExtractor {

    public static let embeddingDimension = 768
    public static let targetSampleRate: Double = 16000

    private let model: MLModel
    private let melGenerator: MelSpectrogramGenerator

    // TODO: Update these from Task 7 Step 3 output
    private static let inputName = "input"
    private static let outputName = "output"

    public init() throws {
        let config = MLModelConfiguration()
        config.computeUnits = .cpuAndNeuralEngine

        if let url = Bundle.module.url(forResource: "MAEST", withExtension: "mlmodelc") {
            self.model = try MLModel(contentsOf: url, configuration: config)
        } else if let url = Bundle.module.url(forResource: "MAEST", withExtension: "mlpackage") {
            let compiledURL = try MLModel.compileModel(at: url)
            self.model = try MLModel(contentsOf: compiledURL, configuration: config)
        } else {
            throw MAESTError.modelNotFound
        }

        self.melGenerator = MelSpectrogramGenerator()
    }

    public func extract(from buffer: AVAudioPCMBuffer) async throws -> [Float] {
        // Generate mel spectrogram (same as EffNet)
        let melSpec = try melGenerator.generate(from: buffer)
        let flatMelSpec = melGenerator.flatten(melSpec)

        // Create input — shape depends on model spec (from Task 7)
        // TODO: Adjust shape based on actual model input spec
        let inputArray = try MLMultiArray(shape: [1, 128, 96], dataType: .float32)
        for (i, value) in flatMelSpec.prefix(128 * 96).enumerated() {
            inputArray[i] = NSNumber(value: value)
        }

        let provider = try MLDictionaryFeatureProvider(dictionary: [
            Self.inputName: MLFeatureValue(multiArray: inputArray)
        ])

        let output = try model.prediction(from: provider)

        guard let outputArray = output.featureValue(for: Self.outputName)?.multiArrayValue else {
            throw MAESTError.invalidOutput
        }

        var embeddings = [Float](repeating: 0, count: Self.embeddingDimension)
        for i in 0..<Self.embeddingDimension {
            embeddings[i] = outputArray[i].floatValue
        }

        return embeddings
    }

    public enum MAESTError: Error {
        case modelNotFound
        case invalidOutput
    }
}
```

- [ ] **Step 2: Add MAEST to CombinedFeatureExtractor**

In the FeatureConfig enum, add:
```swift
case effnetGenresCLAPMAEST = "effnetGenresCLAPMAEST"  // 2960 dims (1280+400+512+768)
```

Add `dimension` case:
```swift
case .effnetGenresCLAPMAEST: return 2960
```

Add MAEST extractor property and init:
```swift
private let maestExtractor: MAESTExtractor?
```

Add extraction case in `extract()`:
```swift
case .effnetGenresCLAPMAEST:
    let (embeddings, genres) = try await effnetExtractor.extractWithGenres(from: buffer)
    var result = embeddings + genres
    if let clap = clapExtractor {
        let clapEmb = try await clap.extract(from: extractFloatSamples(from: buffer), sampleRate: Double(buffer.format.sampleRate))
        result += clapEmb
    }
    if let maest = maestExtractor {
        let maestEmb = try await maest.extract(from: buffer)
        result += maestEmb
    }
    return result
```

- [ ] **Step 3: Add to Package.swift resources**

```swift
.copy("Resources/MAEST.mlpackage"),
```

- [ ] **Step 4: Run tests**

Run: `cd CrateBotCore && swift test`

- [ ] **Step 5: Commit**

```bash
git add CrateBotCore/Sources/CrateBotCore/Audio/MAESTExtractor.swift CrateBotCore/Sources/CrateBotCore/Audio/CombinedFeatureExtractor.swift CrateBotCore/Package.swift
git commit -m "feat: add MAEST transformer embeddings (768-dim)

MAEST provides transformer-based musical understanding complementary
to EffNet's CNN embeddings. Combined feature vector grows from 2192
to 2960 dims (1280 EffNet + 400 genres + 512 CLAP + 768 MAEST).
Graceful fallback if MAEST model is not available."
```

---

## Verification

### Task 9: Full test suite + accuracy re-evaluation

- [ ] **Step 1: Run full test suite**

Run: `cd CrateBotCore && swift test`

- [ ] **Step 2: Build Xcode project**

Run: `xcodebuild -project CrateBot.xcodeproj -scheme CrateBot build 2>&1 | tail -5`

- [ ] **Step 3: Run accuracy evaluation with per-tag thresholds**

Run: `python3 scripts/accuracy_eval.py --optimize`

Compare macro F1 with and without per-tag thresholds.

---

## Implementation Notes

- **Feature 1 (per-tag thresholds)** and **Feature 2 (zero-shot CLAP)** are fully independent and can be parallelized.
- **Feature 3 (MAEST)** depends on model conversion success. If ONNX conversion fails, it should be deferred without blocking the other features.
- After MAEST is added, all models need retraining on the expanded 2960-dim feature vector.
- The MAEST .mlpackage is too large for git. Add to .gitignore and distribute via LFS or direct download.
