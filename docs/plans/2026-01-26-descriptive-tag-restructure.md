# Descriptive Tag Restructure Plan

## Overview

Restructure the "Descriptive" category into organized sub-categories with proper multi-class classifier support for mutually exclusive tag groups.

## Current State

- All descriptive tags lumped under "General" or "Descriptive"
- Only 2 multi-class groups: BassType (Punchy, Walking), Vibe (Dark, Dope)
- No distinction between instruments, vibes, rhythm, etc.
- Tags written as flat list to Comments (COMM) field

## Target Structure

### Descriptive Sub-Categories (in order)

| # | Category | Type | Tags |
|---|----------|------|------|
| 1 | **BassType** | Multi-class | Punchy, Walking, BoomingBass, GrindyBass |
| 2 | **Rhythm** | Binary | Broken, Swung, Driving, Loopy |
| 3 | **Style** | Binary | Afro, Electro, Poppy, Disco, Classic |
| 4 | **Vibes** | Binary | Fun, Funky, Bouncy, Dreamy, Emotional, Epic, Happy, Joyful, Jazzy, Melodic, Soulful/Musical, Techy, Tropical, Dubby, Glitchy, Floating/Spacey, Aggressive, Grindy, Head Knodding |
| 5 | **Instruments** | Binary | Piano, Organ, Guitar, Horns, Congas, Hi Hats, Pads, Sweeps, Arpeggiated, Beats |
| 6 | **VocalType** | Multi-class | Singing, Chanting, Spoken Word, Rap, Instrumental |

**Note:** Acapella remains a separate binary classifier (it indicates "no instruments" not a vocal style).

## Implementation Tasks

### 1. Update TagGroupRegistry
**File:** `CrateBotCore/Sources/CrateBotCore/ML/TagGroupRegistry.swift`

- Expand `BassType` group to include: Punchy, Walking, BoomingBass, GrindyBass
- Add new `VocalType` group: Singing, Chanting, Spoken Word, Rap, Instrumental
- Remove old `Vibe` group (Dark, Dope) - these become binary vibes

```swift
static let defaultGroups = TagGroupRegistry(groups: [
    TagGroup(name: "BassType", tags: ["Punchy", "Walking", "BoomingBass", "GrindyBass"]),
    TagGroup(name: "VocalType", tags: ["Singing", "Chanting", "Spoken Word", "Rap", "Instrumental"])
])
```

### 2. Add Descriptive Sub-Category Mapping
**File:** `CrateBotCore/Sources/CrateBotCore/ML/DescriptiveTagMapping.swift` (new)

Create a mapping that categorizes descriptive tags into sub-categories:

```swift
public enum DescriptiveSubCategory: String, CaseIterable, Codable {
    case bassType = "BassType"
    case rhythm = "Rhythm"
    case style = "Style"
    case vibes = "Vibes"
    case instruments = "Instruments"
    case vocalType = "VocalType"
}

public struct DescriptiveTagMapping {
    public static let mapping: [String: DescriptiveSubCategory] = [
        // BassType (handled by multi-class)
        "Punchy": .bassType,
        "Walking": .bassType,
        "BoomingBass": .bassType,
        "GrindyBass": .bassType,

        // Rhythm
        "Broken": .rhythm,
        "Swung": .rhythm,
        "Driving": .rhythm,
        "Loopy": .rhythm,

        // Style
        "Afro": .style,
        "Electro": .style,
        "Poppy": .style,
        "Disco": .style,
        "Classic": .style,

        // Vibes
        "Fun": .vibes,
        "Funky": .vibes,
        // ... etc

        // Instruments
        "Piano": .instruments,
        "Organ": .instruments,
        // ... etc

        // VocalType (handled by multi-class)
        "Singing": .vocalType,
        "Chanting": .vocalType,
        "Spoken Word": .vocalType,
        "Rap": .vocalType,
        "Instrumental": .vocalType,
    ]
}
```

### 3. Update Model Metadata Structure
**File:** `CrateBotCore/Sources/CrateBotCore/ML/ModelMetadata.swift`

Add sub-category support to metadata:

```swift
public struct ModelMetadata: Codable, Sendable {
    // Existing fields...

    /// Descriptive tags organized by sub-category
    public let descriptiveSubCategories: [String: [String]]?  // Optional for backwards compat
}
```

### 4. Update TrainingCoordinator
**File:** `CrateBotCore/Sources/CrateBotCore/ML/TrainingCoordinator.swift`

- When saving metadata, organize descriptive tags by sub-category
- Ensure multi-class groups are properly detected and trained

### 5. Update TrainingOptions / TrainView
**Files:**
- `CrateBotCore/Sources/CrateBotCore/ML/TrainingCoordinator.swift`
- `CrateBot/Views/TrainView.swift`

- Add UI for selecting tags within sub-categories (optional, can keep flat selection)
- Pass sub-category info through to training

### 6. Update TaggingEngine Prediction Output
**File:** `CrateBotCore/Sources/CrateBotCore/ML/TaggingEngine.swift`

Organize predictions by sub-category:

```swift
public struct UserTagPredictions: Sendable {
    public let genre: String?
    public let timing: String?
    public let mood: String?

    // Structured descriptive output
    public let bassType: String?      // From multi-class
    public let rhythm: [String]       // Binary predictions
    public let style: [String]        // Binary predictions
    public let vibes: [String]        // Binary predictions
    public let instruments: [String]  // Binary predictions
    public let vocalType: String?     // From multi-class
    public let acapella: Bool?        // Binary
}
```

### 7. Update ID3 Writing
**File:** `CrateBot/Views/TaggingView.swift`

Write structured descriptive tags to Comments:

```
BassType: Walking | Rhythm: Broken, Driving | Style: Afro | Vibes: Funky, Happy | Instruments: Congas, Organ | VocalType: Chanting
```

Or simpler flat format with ordering:
```
Walking, Broken, Driving, Afro, Funky, Happy, Congas, Organ, Chanting
```

## Migration Notes

- Existing models will continue to work (backwards compatible)
- New training runs will use the updated structure
- No changes needed to MP3 files or existing tags

## Testing

1. Train a new model with the updated TagGroupRegistry
2. Verify BassType multi-class includes all 4 bass tags
3. Verify VocalType multi-class trains correctly
4. Verify predictions are organized by sub-category
5. Verify ID3 writing outputs in correct order

## Future Considerations

- UI could show sub-categories in Fallback Mappings editor
- Could add sub-category filtering in tag selection during training
- Could write sub-categories to separate ID3 fields if needed
