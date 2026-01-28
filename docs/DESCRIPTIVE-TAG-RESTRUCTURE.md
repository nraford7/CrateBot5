# Descriptive Tag Restructure

**Date:** 2026-01-26

## Overview

Restructured the "Descriptive" category from a flat list of tags into organized sub-categories with proper multi-class classifier support for BassType and VocalType tag groups.

## Changes

### Sub-Category Structure

Descriptive tags are now organized into 6 sub-categories (in output order):

| # | Sub-Category | Type | Tags |
|---|--------------|------|------|
| 1 | **BassType** | Multi-class | Punchy, Walking, BoomingBass, GrindyBass |
| 2 | **Rhythm** | Binary | Broken, Swung, Driving, Loopy |
| 3 | **Style** | Binary | Afro, Electro, Poppy, Disco, Classic |
| 4 | **Vibes** | Binary | Fun, Funky, Bouncy, Dreamy, Emotional, Epic, Happy, Joyful, Jazzy, Melodic, Soulful, Musical, Techy, Tropical, Dubby, Glitchy, Floating, Spacey, Aggressive, Grindy, Dark, Dope, Chill, Uplifting, Melancholic, Head Nodding |
| 5 | **Instruments** | Binary | Piano, Organ, Guitar, Horns, Congas, Hi Hats, Pads, Sweeps, Arpeggiated, Beats |
| 6 | **VocalType** | Multi-class | Singing, Chanting, Spoken Word, Rap, Instrumental |

**Multi-class** = mutually exclusive (only one can be predicted)
**Binary** = independent (multiple can be predicted)

### Files Changed

#### New Files
- `CrateBotCore/Sources/CrateBotCore/ML/DescriptiveTagMapping.swift` - Sub-category enum and tag mapping
- `CrateBotCore/Tests/CrateBotCoreTests/ML/DescriptiveTagMappingTests.swift` - Tests
- `CrateBotCore/Tests/CrateBotCoreTests/ML/ModelMetadataTests.swift` - Tests

#### Modified Files
- `CrateBotCore/Sources/CrateBotCore/ML/TagGroupRegistry.swift` - Updated default groups
- `CrateBotCore/Sources/CrateBotCore/ML/ModelMetadata.swift` - Added `descriptiveSubCategories` field
- `CrateBotCore/Sources/CrateBotCore/ML/TrainingCoordinator.swift` - Save sub-categories in metadata
- `CrateBotCore/Sources/CrateBotCore/ML/TaggingEngine.swift` - Structured `UserTagPredictions`
- `CrateBotCore/Tests/CrateBotCoreTests/ML/TagGroupRegistryTests.swift` - New tests
- `CrateBotCore/Tests/CrateBotCoreTests/ML/TrainingCoordinatorTests.swift` - New tests
- `CrateBotCore/Tests/CrateBotCoreTests/ML/TaggingEngineTests.swift` - New tests

## API Changes

### UserTagPredictions (TaggingEngine.swift)

**Before:**
```swift
struct UserTagPredictions {
    let genre: String?
    let timing: String?
    let mood: String?
    let descriptive: [String]  // Flat array
}
```

**After:**
```swift
struct UserTagPredictions {
    let genre: String?
    let timing: String?
    let mood: String?

    // Structured descriptive output
    let bassType: String?       // Multi-class
    let rhythm: [String]        // Binary
    let style: [String]         // Binary
    let vibes: [String]         // Binary
    let instruments: [String]   // Binary
    let vocalType: String?      // Multi-class
    let acapella: Bool?         // Binary

    // Computed for backwards compatibility
    var descriptive: [String]   // Returns tags in sub-category order
}
```

### ModelMetadata

New optional field for backwards compatibility:
```swift
let descriptiveSubCategories: [String: [String]]?
```

### DescriptiveTagMapping (New)

Static utility for sub-category organization:
```swift
DescriptiveTagMapping.subCategory(for: "Funky")  // .vibes
DescriptiveTagMapping.tags(for: .rhythm)         // ["Broken", "Swung", "Driving", "Loopy"]
DescriptiveTagMapping.organize(["Funky", "Walking", "Piano"])  // Groups by sub-category
DescriptiveTagMapping.flatten(organized)         // Back to array in order
```

## Backwards Compatibility

- Existing trained models continue to work (new metadata field is optional)
- `UserTagPredictions.descriptive` computed property provides flat array access
- Legacy init `UserTagPredictions(genre:timing:mood:descriptive:)` still works
- ID3 writing unchanged (uses computed `descriptive` property)

## ID3 Output

Tags are written to the Comments field in sub-category order:
```
Walking, Broken, Driving, Afro, Funky, Happy, Congas, Organ, Chanting
```

## Testing

New tests added:
- `DescriptiveTagMappingTests` - 9 tests for sub-category mapping
- `TagGroupRegistryTests` - 3 new tests for expanded groups
- `ModelMetadataTests` - 2 tests for encode/decode and backwards compat
- `TrainingCoordinatorTests` - 2 tests for sub-category saving
- `TaggingEngineTests` - 2 tests for structured predictions

All 323 relevant tests pass.
