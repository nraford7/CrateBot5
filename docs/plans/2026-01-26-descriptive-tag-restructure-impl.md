# Descriptive Tag Restructure Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Restructure the "Descriptive" category into organized sub-categories with proper multi-class classifier support for BassType and VocalType tag groups.

**Architecture:** Create `DescriptiveTagMapping` to categorize tags, update `TagGroupRegistry` with expanded groups, flow sub-categories through training metadata, and structure `UserTagPredictions` output by sub-category.

**Tech Stack:** Swift, CoreML, ID3TagEditor, XCTest

---

## Task 1: Update TagGroupRegistry Default Groups

**Files:**
- Modify: `CrateBotCore/Sources/CrateBotCore/ML/TagGroupRegistry.swift`
- Test: `CrateBotCore/Tests/CrateBotCoreTests/ML/TagGroupRegistryTests.swift`

**Step 1: Write the failing test**

Add test to `TagGroupRegistryTests.swift`:

```swift
func testDefaultGroupsIncludeExpandedBassType() {
    let registry = TagGroupRegistry.defaultGroups

    // BassType should have 4 tags
    XCTAssertNotNil(registry.groupName(for: "Punchy"))
    XCTAssertNotNil(registry.groupName(for: "Walking"))
    XCTAssertNotNil(registry.groupName(for: "BoomingBass"))
    XCTAssertNotNil(registry.groupName(for: "GrindyBass"))

    // All should be in same group
    XCTAssertEqual(registry.groupName(for: "Punchy"), registry.groupName(for: "BoomingBass"))
}

func testDefaultGroupsIncludeVocalType() {
    let registry = TagGroupRegistry.defaultGroups

    // VocalType should exist with all 5 tags
    XCTAssertNotNil(registry.groupName(for: "Singing"))
    XCTAssertNotNil(registry.groupName(for: "Chanting"))
    XCTAssertNotNil(registry.groupName(for: "Spoken Word"))
    XCTAssertNotNil(registry.groupName(for: "Rap"))
    XCTAssertNotNil(registry.groupName(for: "Instrumental"))

    // All should be in same group
    XCTAssertEqual(registry.groupName(for: "Singing"), registry.groupName(for: "Instrumental"))
}

func testOldVibeGroupRemoved() {
    let registry = TagGroupRegistry.defaultGroups

    // Old Vibe group (Dark, Dope) should NOT exist as a multi-class group
    // These become binary vibes instead
    let darkGroup = registry.groupName(for: "Dark")
    let dopeGroup = registry.groupName(for: "Dope")

    // They should either be nil (not in any group) or not in a "Vibe" group
    if let darkGroup = darkGroup {
        XCTAssertNotEqual(darkGroup, "Vibe")
    }
    if let dopeGroup = dopeGroup {
        XCTAssertNotEqual(dopeGroup, "Vibe")
    }
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter TagGroupRegistryTests.testDefaultGroupsIncludeExpandedBassType`
Expected: FAIL - BoomingBass and GrindyBass not found

**Step 3: Update defaultGroups in TagGroupRegistry.swift**

Find the `defaultGroups` static property and update:

```swift
public static let defaultGroups = TagGroupRegistry(groups: [
    "BassType": ["Punchy", "Walking", "BoomingBass", "GrindyBass"],
    "VocalType": ["Singing", "Chanting", "Spoken Word", "Rap", "Instrumental"],
    "Energy": ["Low", "Medium", "High", "Peak"],
    "Cultural": ["Asian", "Latin", "African", "MiddleEastern", "European"]
])
```

Note: Remove the old "Vibe" group (Dark, Dope, Chill, Uplifting, Melancholic) - these become binary descriptive tags.

**Step 4: Run tests to verify they pass**

Run: `swift test --filter TagGroupRegistryTests`
Expected: All tests PASS

**Step 5: Commit**

```bash
git add CrateBotCore/Sources/CrateBotCore/ML/TagGroupRegistry.swift CrateBotCore/Tests/CrateBotCoreTests/ML/TagGroupRegistryTests.swift
git commit -m "feat: expand TagGroupRegistry with BassType and VocalType groups

- Add BoomingBass and GrindyBass to BassType group
- Add new VocalType group: Singing, Chanting, Spoken Word, Rap, Instrumental
- Remove old Vibe group (Dark, Dope become binary descriptive tags)"
```

---

## Task 2: Create DescriptiveTagMapping

**Files:**
- Create: `CrateBotCore/Sources/CrateBotCore/ML/DescriptiveTagMapping.swift`
- Test: `CrateBotCore/Tests/CrateBotCoreTests/ML/DescriptiveTagMappingTests.swift`

**Step 1: Write the failing test**

Create `DescriptiveTagMappingTests.swift`:

```swift
import XCTest
@testable import CrateBotCore

final class DescriptiveTagMappingTests: XCTestCase {

    func testSubCategoryForBassTypeTags() {
        XCTAssertEqual(DescriptiveTagMapping.subCategory(for: "Punchy"), .bassType)
        XCTAssertEqual(DescriptiveTagMapping.subCategory(for: "Walking"), .bassType)
        XCTAssertEqual(DescriptiveTagMapping.subCategory(for: "BoomingBass"), .bassType)
        XCTAssertEqual(DescriptiveTagMapping.subCategory(for: "GrindyBass"), .bassType)
    }

    func testSubCategoryForRhythmTags() {
        XCTAssertEqual(DescriptiveTagMapping.subCategory(for: "Broken"), .rhythm)
        XCTAssertEqual(DescriptiveTagMapping.subCategory(for: "Swung"), .rhythm)
        XCTAssertEqual(DescriptiveTagMapping.subCategory(for: "Driving"), .rhythm)
        XCTAssertEqual(DescriptiveTagMapping.subCategory(for: "Loopy"), .rhythm)
    }

    func testSubCategoryForStyleTags() {
        XCTAssertEqual(DescriptiveTagMapping.subCategory(for: "Afro"), .style)
        XCTAssertEqual(DescriptiveTagMapping.subCategory(for: "Electro"), .style)
        XCTAssertEqual(DescriptiveTagMapping.subCategory(for: "Poppy"), .style)
        XCTAssertEqual(DescriptiveTagMapping.subCategory(for: "Disco"), .style)
        XCTAssertEqual(DescriptiveTagMapping.subCategory(for: "Classic"), .style)
    }

    func testSubCategoryForVibeTags() {
        XCTAssertEqual(DescriptiveTagMapping.subCategory(for: "Fun"), .vibes)
        XCTAssertEqual(DescriptiveTagMapping.subCategory(for: "Funky"), .vibes)
        XCTAssertEqual(DescriptiveTagMapping.subCategory(for: "Bouncy"), .vibes)
        XCTAssertEqual(DescriptiveTagMapping.subCategory(for: "Dreamy"), .vibes)
        XCTAssertEqual(DescriptiveTagMapping.subCategory(for: "Dark"), .vibes)
        XCTAssertEqual(DescriptiveTagMapping.subCategory(for: "Dope"), .vibes)
    }

    func testSubCategoryForInstrumentTags() {
        XCTAssertEqual(DescriptiveTagMapping.subCategory(for: "Piano"), .instruments)
        XCTAssertEqual(DescriptiveTagMapping.subCategory(for: "Organ"), .instruments)
        XCTAssertEqual(DescriptiveTagMapping.subCategory(for: "Guitar"), .instruments)
        XCTAssertEqual(DescriptiveTagMapping.subCategory(for: "Horns"), .instruments)
        XCTAssertEqual(DescriptiveTagMapping.subCategory(for: "Congas"), .instruments)
    }

    func testSubCategoryForVocalTypeTags() {
        XCTAssertEqual(DescriptiveTagMapping.subCategory(for: "Singing"), .vocalType)
        XCTAssertEqual(DescriptiveTagMapping.subCategory(for: "Chanting"), .vocalType)
        XCTAssertEqual(DescriptiveTagMapping.subCategory(for: "Spoken Word"), .vocalType)
        XCTAssertEqual(DescriptiveTagMapping.subCategory(for: "Rap"), .vocalType)
        XCTAssertEqual(DescriptiveTagMapping.subCategory(for: "Instrumental"), .vocalType)
    }

    func testUnknownTagReturnsNil() {
        XCTAssertNil(DescriptiveTagMapping.subCategory(for: "UnknownTag"))
        XCTAssertNil(DescriptiveTagMapping.subCategory(for: "RandomStuff"))
    }

    func testTagsForSubCategory() {
        let rhythmTags = DescriptiveTagMapping.tags(for: .rhythm)
        XCTAssertTrue(rhythmTags.contains("Broken"))
        XCTAssertTrue(rhythmTags.contains("Swung"))
        XCTAssertTrue(rhythmTags.contains("Driving"))
        XCTAssertTrue(rhythmTags.contains("Loopy"))
        XCTAssertEqual(rhythmTags.count, 4)
    }

    func testOrderedSubCategories() {
        let ordered = DescriptiveSubCategory.allCases
        XCTAssertEqual(ordered[0], .bassType)
        XCTAssertEqual(ordered[1], .rhythm)
        XCTAssertEqual(ordered[2], .style)
        XCTAssertEqual(ordered[3], .vibes)
        XCTAssertEqual(ordered[4], .instruments)
        XCTAssertEqual(ordered[5], .vocalType)
    }
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter DescriptiveTagMappingTests`
Expected: FAIL - Module/type not found

**Step 3: Create DescriptiveTagMapping.swift**

```swift
import Foundation

/// Sub-categories for organizing descriptive tags
public enum DescriptiveSubCategory: String, CaseIterable, Codable, Sendable {
    case bassType = "BassType"
    case rhythm = "Rhythm"
    case style = "Style"
    case vibes = "Vibes"
    case instruments = "Instruments"
    case vocalType = "VocalType"
}

/// Maps descriptive tags to their sub-categories for structured output
public struct DescriptiveTagMapping: Sendable {

    /// All tag-to-subcategory mappings
    public static let mapping: [String: DescriptiveSubCategory] = [
        // BassType (multi-class)
        "Punchy": .bassType,
        "Walking": .bassType,
        "BoomingBass": .bassType,
        "GrindyBass": .bassType,

        // Rhythm (binary)
        "Broken": .rhythm,
        "Swung": .rhythm,
        "Driving": .rhythm,
        "Loopy": .rhythm,

        // Style (binary)
        "Afro": .style,
        "Electro": .style,
        "Poppy": .style,
        "Disco": .style,
        "Classic": .style,

        // Vibes (binary)
        "Fun": .vibes,
        "Funky": .vibes,
        "Bouncy": .vibes,
        "Dreamy": .vibes,
        "Emotional": .vibes,
        "Epic": .vibes,
        "Happy": .vibes,
        "Joyful": .vibes,
        "Jazzy": .vibes,
        "Melodic": .vibes,
        "Soulful": .vibes,
        "Musical": .vibes,
        "Techy": .vibes,
        "Tropical": .vibes,
        "Dubby": .vibes,
        "Glitchy": .vibes,
        "Floating": .vibes,
        "Spacey": .vibes,
        "Aggressive": .vibes,
        "Grindy": .vibes,
        "Dark": .vibes,
        "Dope": .vibes,
        "Chill": .vibes,
        "Uplifting": .vibes,
        "Melancholic": .vibes,
        "Head Nodding": .vibes,

        // Instruments (binary)
        "Piano": .instruments,
        "Organ": .instruments,
        "Guitar": .instruments,
        "Horns": .instruments,
        "Congas": .instruments,
        "Hi Hats": .instruments,
        "Pads": .instruments,
        "Sweeps": .instruments,
        "Arpeggiated": .instruments,
        "Beats": .instruments,

        // VocalType (multi-class)
        "Singing": .vocalType,
        "Chanting": .vocalType,
        "Spoken Word": .vocalType,
        "Rap": .vocalType,
        "Instrumental": .vocalType,
    ]

    /// Reverse mapping: sub-category to tags
    private static let reverseMapping: [DescriptiveSubCategory: [String]] = {
        var result: [DescriptiveSubCategory: [String]] = [:]
        for (tag, category) in mapping {
            result[category, default: []].append(tag)
        }
        return result
    }()

    /// Get the sub-category for a tag, or nil if unknown
    public static func subCategory(for tag: String) -> DescriptiveSubCategory? {
        return mapping[tag]
    }

    /// Get all tags for a given sub-category
    public static func tags(for subCategory: DescriptiveSubCategory) -> [String] {
        return reverseMapping[subCategory] ?? []
    }

    /// Organize an array of tags by sub-category
    public static func organize(_ tags: [String]) -> [DescriptiveSubCategory: [String]] {
        var result: [DescriptiveSubCategory: [String]] = [:]
        for tag in tags {
            if let category = subCategory(for: tag) {
                result[category, default: []].append(tag)
            }
        }
        return result
    }

    /// Flatten organized tags back to array in sub-category order
    public static func flatten(_ organized: [DescriptiveSubCategory: [String]]) -> [String] {
        var result: [String] = []
        for category in DescriptiveSubCategory.allCases {
            if let tags = organized[category] {
                result.append(contentsOf: tags)
            }
        }
        return result
    }
}
```

**Step 4: Run tests to verify they pass**

Run: `swift test --filter DescriptiveTagMappingTests`
Expected: All tests PASS

**Step 5: Commit**

```bash
git add CrateBotCore/Sources/CrateBotCore/ML/DescriptiveTagMapping.swift CrateBotCore/Tests/CrateBotCoreTests/ML/DescriptiveTagMappingTests.swift
git commit -m "feat: add DescriptiveTagMapping for sub-category organization

- Create DescriptiveSubCategory enum with ordered cases
- Map all descriptive tags to their sub-categories
- Add helper methods: subCategory(for:), tags(for:), organize(), flatten()"
```

---

## Task 3: Add Sub-Category Support to ModelMetadata

**Files:**
- Modify: `CrateBotCore/Sources/CrateBotCore/ML/ModelMetadata.swift`
- Test: `CrateBotCore/Tests/CrateBotCoreTests/ML/ModelMetadataTests.swift` (create if needed)

**Step 1: Write the failing test**

Create or add to `ModelMetadataTests.swift`:

```swift
import XCTest
@testable import CrateBotCore

final class ModelMetadataTests: XCTestCase {

    func testDescriptiveSubCategoriesEncodeDecode() throws {
        let subCategories: [String: [String]] = [
            "BassType": ["Punchy", "Walking"],
            "Rhythm": ["Broken", "Driving"],
            "Vibes": ["Funky", "Dark"]
        ]

        let metadata = ModelMetadata(
            name: "TestModel",
            version: "1.0",
            pipelineVersion: "1.0",
            trainedAt: Date(),
            trainingFileCount: 100,
            categories: ["Descriptive"],
            tags: ["Descriptive": ["Punchy", "Walking", "Broken", "Driving", "Funky", "Dark"]],
            tagGroups: [],
            accuracy: 0.9,
            featureDimension: 1280,
            calibratorTemperature: nil,
            descriptiveSubCategories: subCategories
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(metadata)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(ModelMetadata.self, from: data)

        XCTAssertEqual(decoded.descriptiveSubCategories?["BassType"], ["Punchy", "Walking"])
        XCTAssertEqual(decoded.descriptiveSubCategories?["Rhythm"], ["Broken", "Driving"])
        XCTAssertEqual(decoded.descriptiveSubCategories?["Vibes"], ["Funky", "Dark"])
    }

    func testBackwardsCompatibilityWithoutSubCategories() throws {
        // JSON without descriptiveSubCategories field (old format)
        let oldJson = """
        {
            "name": "OldModel",
            "version": "1.0",
            "pipelineVersion": "1.0",
            "trainedAt": 0,
            "trainingFileCount": 50,
            "categories": ["Descriptive"],
            "tags": {"Descriptive": ["Funky"]},
            "tagGroups": [],
            "featureDimension": 1280
        }
        """

        let decoder = JSONDecoder()
        let metadata = try decoder.decode(ModelMetadata.self, from: oldJson.data(using: .utf8)!)

        // Should decode without error, descriptiveSubCategories should be nil
        XCTAssertNil(metadata.descriptiveSubCategories)
        XCTAssertEqual(metadata.name, "OldModel")
    }
}
```

**Step 2: Run test to verify it fails**

Run: `swift test --filter ModelMetadataTests`
Expected: FAIL - descriptiveSubCategories doesn't exist

**Step 3: Add descriptiveSubCategories to ModelMetadata**

In `ModelMetadata.swift`, add the new property:

```swift
public struct ModelMetadata: Codable, Sendable {
    public let name: String
    public let version: String
    public let pipelineVersion: String
    public let trainedAt: Date
    public let trainingFileCount: Int
    public let categories: [String]
    public let tags: [String: [String]]
    public let tagGroups: [TagGroupMetadata]
    public let accuracy: Double?
    public let featureDimension: Int
    public let calibratorTemperature: Float?

    /// Descriptive tags organized by sub-category (optional for backwards compat)
    public let descriptiveSubCategories: [String: [String]]?

    // Update init to include new parameter with default nil
    public init(
        name: String,
        version: String,
        pipelineVersion: String,
        trainedAt: Date,
        trainingFileCount: Int,
        categories: [String],
        tags: [String: [String]],
        tagGroups: [TagGroupMetadata],
        accuracy: Double?,
        featureDimension: Int,
        calibratorTemperature: Float?,
        descriptiveSubCategories: [String: [String]]? = nil
    ) {
        self.name = name
        self.version = version
        self.pipelineVersion = pipelineVersion
        self.trainedAt = trainedAt
        self.trainingFileCount = trainingFileCount
        self.categories = categories
        self.tags = tags
        self.tagGroups = tagGroups
        self.accuracy = accuracy
        self.featureDimension = featureDimension
        self.calibratorTemperature = calibratorTemperature
        self.descriptiveSubCategories = descriptiveSubCategories
    }
}
```

Also update the custom `init(from decoder:)` if it exists to handle the new optional field:

```swift
public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    // ... existing decoding ...
    self.descriptiveSubCategories = try container.decodeIfPresent([String: [String]].self, forKey: .descriptiveSubCategories)
}
```

**Step 4: Run tests to verify they pass**

Run: `swift test --filter ModelMetadataTests`
Expected: All tests PASS

**Step 5: Commit**

```bash
git add CrateBotCore/Sources/CrateBotCore/ML/ModelMetadata.swift CrateBotCore/Tests/CrateBotCoreTests/ML/ModelMetadataTests.swift
git commit -m "feat: add descriptiveSubCategories to ModelMetadata

- Add optional [String: [String]] field for sub-category organization
- Maintains backwards compatibility with old model metadata"
```

---

## Task 4: Update TrainingCoordinator to Save Sub-Categories

**Files:**
- Modify: `CrateBotCore/Sources/CrateBotCore/ML/TrainingCoordinator.swift`
- Test: `CrateBotCore/Tests/CrateBotCoreTests/ML/TrainingCoordinatorTests.swift`

**Step 1: Write the failing test**

Add test to verify sub-categories are saved in metadata:

```swift
func testMetadataIncludesDescriptiveSubCategories() async throws {
    // This test verifies that when training completes, the saved metadata
    // includes descriptiveSubCategories for any descriptive tags trained

    let coordinator = TrainingCoordinator()

    // Create mock training that includes descriptive tags
    // (Adjust based on existing test patterns in the file)

    // After training, load the metadata and verify:
    // - descriptiveSubCategories is not nil
    // - Tags are properly organized by sub-category
}
```

Note: Adapt this test based on existing TrainingCoordinator test patterns.

**Step 2: Update TrainingCoordinator metadata creation**

Find where `ModelMetadata` is created (likely in a `saveMetadata` or `createMetadata` function) and add sub-category organization:

```swift
// When building metadata, organize descriptive tags by sub-category
let descriptiveTags = tags["Descriptive"] ?? []
let organizedDescriptive = DescriptiveTagMapping.organize(descriptiveTags)
let subCategoriesDict: [String: [String]] = Dictionary(
    uniqueKeysWithValues: organizedDescriptive.map { ($0.key.rawValue, $0.value) }
)

let metadata = ModelMetadata(
    // ... existing parameters ...
    descriptiveSubCategories: subCategoriesDict.isEmpty ? nil : subCategoriesDict
)
```

**Step 3: Run tests**

Run: `swift test --filter TrainingCoordinator`
Expected: PASS

**Step 4: Commit**

```bash
git add CrateBotCore/Sources/CrateBotCore/ML/TrainingCoordinator.swift CrateBotCore/Tests/CrateBotCoreTests/ML/TrainingCoordinatorTests.swift
git commit -m "feat: save descriptive sub-categories in training metadata

- Organize trained descriptive tags by sub-category using DescriptiveTagMapping
- Store in ModelMetadata.descriptiveSubCategories"
```

---

## Task 5: Update UserTagPredictions Structure

**Files:**
- Modify: `CrateBotCore/Sources/CrateBotCore/ML/TaggingEngine.swift`
- Test: `CrateBotCore/Tests/CrateBotCoreTests/ML/TaggingEngineTests.swift`

**Step 1: Write the failing test**

```swift
func testUserTagPredictionsHasStructuredDescriptive() {
    // Create predictions with organized descriptive output
    let predictions = UserTagPredictions(
        genre: "House",
        timing: "Peak",
        mood: "Uplifting",
        bassType: "Walking",
        rhythm: ["Broken", "Driving"],
        style: ["Afro"],
        vibes: ["Funky", "Dark"],
        instruments: ["Congas", "Organ"],
        vocalType: "Chanting",
        acapella: false
    )

    XCTAssertEqual(predictions.bassType, "Walking")
    XCTAssertEqual(predictions.rhythm, ["Broken", "Driving"])
    XCTAssertEqual(predictions.vocalType, "Chanting")
    XCTAssertFalse(predictions.acapella ?? true)
}

func testUserTagPredictionsDescriptiveArrayBackwardsCompat() {
    // Old-style descriptive array should still work
    let predictions = UserTagPredictions(
        genre: "House",
        timing: nil,
        mood: nil,
        descriptive: ["Funky", "Walking", "Congas"]
    )

    XCTAssertEqual(predictions.descriptive, ["Funky", "Walking", "Congas"])
}
```

**Step 2: Update UserTagPredictions structure**

In `TaggingEngine.swift`, update the struct:

```swift
public struct UserTagPredictions: Sendable {
    public let genre: String?
    public let timing: String?
    public let mood: String?

    // Structured descriptive output (new)
    public let bassType: String?          // From multi-class
    public let rhythm: [String]           // Binary predictions
    public let style: [String]            // Binary predictions
    public let vibes: [String]            // Binary predictions
    public let instruments: [String]      // Binary predictions
    public let vocalType: String?         // From multi-class
    public let acapella: Bool?            // Binary (separate classifier)

    // Legacy flat array (computed for backwards compatibility)
    public var descriptive: [String] {
        var result: [String] = []
        if let bass = bassType { result.append(bass) }
        result.append(contentsOf: rhythm)
        result.append(contentsOf: style)
        result.append(contentsOf: vibes)
        result.append(contentsOf: instruments)
        if let vocal = vocalType { result.append(vocal) }
        return result
    }

    // Convenience init with flat descriptive array (for backwards compat)
    public init(
        genre: String?,
        timing: String?,
        mood: String?,
        descriptive: [String]
    ) {
        self.genre = genre
        self.timing = timing
        self.mood = mood

        // Parse descriptive array into structured fields
        let organized = DescriptiveTagMapping.organize(descriptive)
        self.bassType = organized[.bassType]?.first
        self.rhythm = organized[.rhythm] ?? []
        self.style = organized[.style] ?? []
        self.vibes = organized[.vibes] ?? []
        self.instruments = organized[.instruments] ?? []
        self.vocalType = organized[.vocalType]?.first
        self.acapella = nil
    }

    // Full structured init
    public init(
        genre: String?,
        timing: String?,
        mood: String?,
        bassType: String?,
        rhythm: [String],
        style: [String],
        vibes: [String],
        instruments: [String],
        vocalType: String?,
        acapella: Bool?
    ) {
        self.genre = genre
        self.timing = timing
        self.mood = mood
        self.bassType = bassType
        self.rhythm = rhythm
        self.style = style
        self.vibes = vibes
        self.instruments = instruments
        self.vocalType = vocalType
        self.acapella = acapella
    }
}
```

**Step 3: Run tests**

Run: `swift test --filter TaggingEngineTests`
Expected: PASS

**Step 4: Commit**

```bash
git add CrateBotCore/Sources/CrateBotCore/ML/TaggingEngine.swift CrateBotCore/Tests/CrateBotCoreTests/ML/TaggingEngineTests.swift
git commit -m "feat: add structured descriptive fields to UserTagPredictions

- Add bassType, rhythm, style, vibes, instruments, vocalType, acapella fields
- Keep computed descriptive property for backwards compatibility
- Add convenience init that parses flat array into structured fields"
```

---

## Task 6: Update TaggingEngine Prediction Logic

**Files:**
- Modify: `CrateBotCore/Sources/CrateBotCore/ML/TaggingEngine.swift`

**Step 1: Locate prediction assembly code**

Find where `UserTagPredictions` is constructed from classifier results (likely in `analyze()` or a helper method).

**Step 2: Update to use structured output**

Update the prediction assembly to organize by sub-category:

```swift
// After running all classifiers, organize results
let allDescriptiveTags: [String] = // existing logic to collect descriptive predictions

// Get multi-class results
let bassTypeResult = multiClassClassifiers["BassType"]?.predict(features)
let vocalTypeResult = multiClassClassifiers["VocalType"]?.predict(features)

// Binary descriptive tags, excluding multi-class tags
let binaryDescriptive = allDescriptiveTags.filter { tag in
    DescriptiveTagMapping.subCategory(for: tag) != .bassType &&
    DescriptiveTagMapping.subCategory(for: tag) != .vocalType
}

// Organize binary tags by sub-category
let organized = DescriptiveTagMapping.organize(binaryDescriptive)

let predictions = UserTagPredictions(
    genre: genreResult,
    timing: timingResult,
    mood: moodResult,
    bassType: bassTypeResult,
    rhythm: organized[.rhythm] ?? [],
    style: organized[.style] ?? [],
    vibes: organized[.vibes] ?? [],
    instruments: organized[.instruments] ?? [],
    vocalType: vocalTypeResult,
    acapella: acapellaResult
)
```

**Step 3: Run tests**

Run: `swift test --filter TaggingEngine`
Expected: PASS

**Step 4: Commit**

```bash
git add CrateBotCore/Sources/CrateBotCore/ML/TaggingEngine.swift
git commit -m "feat: organize TaggingEngine predictions by sub-category

- Use DescriptiveTagMapping to structure binary predictions
- Populate bassType and vocalType from multi-class classifiers
- Organize rhythm, style, vibes, instruments into separate arrays"
```

---

## Task 7: Update ID3 Writing for Structured Output

**Files:**
- Modify: `CrateBot/Views/TaggingView.swift`

**Step 1: Locate ID3 writing code**

Find where tags are written to the Comments field (likely in a `writeTags` or similar method).

**Step 2: Update to write in sub-category order**

```swift
// Build descriptive string in sub-category order
var descriptiveParts: [String] = []

if let bass = predictions.bassType {
    descriptiveParts.append(bass)
}
if !predictions.rhythm.isEmpty {
    descriptiveParts.append(contentsOf: predictions.rhythm)
}
if !predictions.style.isEmpty {
    descriptiveParts.append(contentsOf: predictions.style)
}
if !predictions.vibes.isEmpty {
    descriptiveParts.append(contentsOf: predictions.vibes)
}
if !predictions.instruments.isEmpty {
    descriptiveParts.append(contentsOf: predictions.instruments)
}
if let vocal = predictions.vocalType {
    descriptiveParts.append(vocal)
}

let descriptiveString = descriptiveParts.joined(separator: ", ")
// Write to Comments field
```

**Step 3: Test manually**

Run the app and verify tags are written in correct order.

**Step 4: Commit**

```bash
git add CrateBot/Views/TaggingView.swift
git commit -m "feat: write descriptive tags in sub-category order to ID3

- Order: BassType, Rhythm, Style, Vibes, Instruments, VocalType
- Maintains comma-separated format in Comments field"
```

---

## Task 8: Final Integration Test

**Step 1: Build and test end-to-end**

```bash
swift build
swift test
```

**Step 2: Manual verification checklist**

- [ ] Train a new model with expanded BassType and VocalType tags
- [ ] Verify metadata JSON contains `descriptiveSubCategories`
- [ ] Run inference and verify predictions are structured
- [ ] Verify ID3 output is ordered correctly

**Step 3: Final commit**

```bash
git add -A
git commit -m "feat: complete descriptive tag restructure

Summary:
- Expand TagGroupRegistry with BassType (4 tags) and VocalType (5 tags)
- Add DescriptiveTagMapping for sub-category organization
- Update ModelMetadata with descriptiveSubCategories field
- Structure UserTagPredictions by sub-category
- Write ID3 tags in consistent sub-category order

Closes #<issue> if applicable"
```

---

## Execution Summary

| Task | Description | Est. Complexity |
|------|-------------|-----------------|
| 1 | Update TagGroupRegistry | Low |
| 2 | Create DescriptiveTagMapping | Medium |
| 3 | Add sub-categories to ModelMetadata | Low |
| 4 | Update TrainingCoordinator | Medium |
| 5 | Update UserTagPredictions structure | Medium |
| 6 | Update TaggingEngine prediction logic | Medium |
| 7 | Update ID3 writing | Low |
| 8 | Integration testing | Low |

**Dependencies:**
- Task 2 (DescriptiveTagMapping) should complete before Tasks 4, 5, 6
- Task 3 (ModelMetadata) should complete before Task 4
- Task 5 should complete before Task 6 and 7
