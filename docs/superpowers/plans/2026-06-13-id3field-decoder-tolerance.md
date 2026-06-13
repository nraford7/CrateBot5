# ID3Field Legacy-Format Decoder Tolerance Implementation Plan

> **For Claude:** REQUIRED: Execute via Agency. Chunk-boundary two-stage review. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Make `TagMappingConfiguration` survive legacy persisted JSON where `ID3Field` values were saved with frame-ID parenthetical suffixes (`"Album Artist (TPE2)"`). Today the decode silently falls back to defaults, causing training to read the wrong ID3 frames — eval showed Noah's hundreds of Timing tags (in TPE2) were invisible because the code read TALB instead.

**Why:** Verified saved JSON in UserDefaults contains `{"timingField":"Album Artist (TPE2)","moodField":"Album (TALB)",...}`. Current `ID3Field` rawValues are `"Album Artist"`, `"Album"`. `JSONDecoder` rawValue match fails → `try?` swallows the error → `TagMappingConfiguration.default` (TALB for timing, TIT1 for mood) is used. Training picked the wrong frames; Stage 2 macro F1 collapsed to 2.7%.

**Tech Stack:** Swift / SwiftPM / XCTest. Baseline: 459 tests, 0 failures.

---

## Chunk 1: tolerant ID3Field decode + persistence fix

### Task 1.1: Custom decoder + save-back on load + tests

**Files:**
- Modify: `CrateBot/Views/TrainView.swift` (~L14-118 — `ID3Field` enum; ~L121-167 — `TagMappingConfiguration`)
- Test: `CrateBotTests/` if it exists; otherwise add a new test target file. The test must run as part of `xcodebuild test` for the app scheme — verify with the assigned agent before assuming a target exists. If no test target exists, add a lightweight one or write Swift Testing-style assertions inside a small `#if DEBUG` debug helper that the agent verifies by direct invocation.
- (Optional) Mirror unit-test in `CrateBotCore/Tests/` if a parallel `ID3Field` type exists there — verify first; do NOT duplicate behavior.

- [ ] **Step 1: Failing tests**

```swift
// TagMappingConfigurationTests
func testID3FieldDecodesLegacyFrameIDSuffix() throws {
    // Old persisted format: rawValue with parenthetical frame ID
    let json = #"{"timingField":"Album Artist (TPE2)","genreField":"Genre (TCON)","moodField":"Album (TALB)","descriptiveField":"Comments (COMM)"}"#
    let config = try JSONDecoder().decode(TagMappingConfiguration.self, from: Data(json.utf8))
    XCTAssertEqual(config.timingField, .albumArtist)
    XCTAssertEqual(config.genreField, .genre)
    XCTAssertEqual(config.moodField, .album)
    XCTAssertEqual(config.descriptiveField, .comments)
}

func testID3FieldDecodesCurrentRawValueFormat() throws {
    // Current format: bare rawValue
    let json = #"{"timingField":"Album Artist","genreField":"Genre","moodField":"Album","descriptiveField":"Comments"}"#
    let config = try JSONDecoder().decode(TagMappingConfiguration.self, from: Data(json.utf8))
    XCTAssertEqual(config.timingField, .albumArtist)
}

func testID3FieldDecodeRejectsUnknownString() {
    let json = #""TotallyBogus""#
    XCTAssertThrowsError(try JSONDecoder().decode(ID3Field.self, from: Data(json.utf8)))
}

func testTagMappingLoadSavesBackAfterLegacyDecode() throws {
    // Round-trip: legacy format decoded → encoded → current bare-rawValue format
    let json = #"{"timingField":"Album Artist (TPE2)","genreField":"Genre","moodField":"Grouping","descriptiveField":"Comments"}"#
    let config = try JSONDecoder().decode(TagMappingConfiguration.self, from: Data(json.utf8))
    let reencoded = try JSONEncoder().encode(config)
    let string = String(decoding: reencoded, as: UTF8.self)
    XCTAssertTrue(string.contains("\"timingField\":\"Album Artist\""))
    XCTAssertFalse(string.contains("(TPE2)"))
}
```

- [ ] **Step 2: Run, verify FAIL.**

- [ ] **Step 3: Implement tolerant decode** on `ID3Field`:

```swift
extension ID3Field {
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(String.self)
        // Strip a legacy frame-ID parenthetical suffix: "Album Artist (TPE2)" -> "Album Artist"
        let stripped = raw.replacingOccurrences(
            of: #"\s*\([A-Z0-9:]+\)\s*$"#,
            with: "",
            options: .regularExpression
        ).trimmingCharacters(in: .whitespaces)
        if let field = ID3Field(rawValue: stripped) {
            self = field; return
        }
        // Defensive: try matching against displayName (rawValue), trimmed differently
        if let field = ID3Field.allCases.first(where: { $0.rawValue.caseInsensitiveCompare(stripped) == .orderedSame }) {
            self = field; return
        }
        throw DecodingError.dataCorruptedError(in: try decoder.singleValueContainer(),
            debugDescription: "Unrecognized ID3Field value: \(raw)")
    }
}
```

Default `Encodable` synthesis still writes the bare `rawValue` — exactly what we want for the round-trip.

- [ ] **Step 4: Save-back on load.** Modify `TagMappingConfiguration.load()` so that after a successful decode, if the on-disk JSON didn't match the current encoded form, it re-saves immediately. Cheap, idempotent:

```swift
static func load() -> TagMappingConfiguration {
    guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
          let config = try? JSONDecoder().decode(TagMappingConfiguration.self, from: data) else {
        return .default
    }
    // Migrate legacy persisted forms by re-saving in the current bare-rawValue format
    if let current = try? JSONEncoder().encode(config), current != data {
        UserDefaults.standard.set(current, forKey: userDefaultsKey)
    }
    return config
}
```

- [ ] **Step 5: Run, PASS, full suite green** (`swift test` for CrateBotCore + `xcodebuild -scheme CrateBot build` and `test` if there's a test target). If the app has no test target, document this in the commit message and run the assertion-style helper directly from the agent to prove correctness.

- [ ] **Step 6: Commit** — `fix: tolerate legacy frame-ID-suffix format when decoding TagMappingConfiguration` + Co-Authored-By: Claude Opus 4.7 <noreply@anthropic.com>.

### Acceptance criteria

- All four new tests pass.
- The persisted `{"timingField":"Album Artist (TPE2)", ...}` JSON now decodes to `.albumArtist`, `.album` (mood), `.genre`, `.comments` — matching Noah's stated intent.
- After `load()`, the persisted blob is rewritten in current format so future launches don't need the tolerance path.
- App target builds; full Swift Package suite still 459/0.
- No changes to `CrateBotCore` — the bug is in the app-side ID3Field, not the Core's `ID3FieldType`.

**CHUNK 1 REVIEW GATE** (two-stage: requesting-code-review + independent no-context subagent).

---

## Out of band (orchestrator, not Agency)

After commit lands:
1. Migrate the live UserDefaults blob in `~/Library/Containers/com.cratebot.CrateBot/Data/Library/Preferences/com.cratebot.CrateBot.plist` so the user's NEXT app launch reads the right mapping immediately (don't wait for the save-back path on first launch). One `plutil`/`defaults` write.
2. Tell the user to launch CrateBot and Start Training. Cache is hot — training only, no re-extraction. ~1 hour.
3. After training, re-run `python3 scripts/accuracy_eval.py --stage-aware --optimize --boost`. Expect Mood and Stage 2 numbers to jump.
