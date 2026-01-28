# Lyrics-First Hook Detection

## Overview

Hook detection now prioritizes lyrics lookup over audio transcription for significantly improved accuracy.

## How It Works

### Detection Strategy

1. **Extract metadata** - Read artist/title from ID3 tags
2. **Fetch lyrics** - Query LRCLIB and Lyrics.ovh APIs
3. **Analyze lyrics** - Find repeated phrases (chorus/hook)
4. **Optional: Verify in audio** - Confirm hook appears in transcription
5. **Fallback** - Use Whisper transcription if no lyrics found

### Why Lyrics-First?

- **Lyrics are ground truth** - No hallucination risk
- **Chorus detection** - Can identify song structure
- **High accuracy** - For known tracks with available lyrics
- **Fast** - API lookup faster than full audio transcription

### Fallback Behavior

When lyrics are unavailable:
- Falls back to Whisper transcription
- Uses existing n-gram analysis
- Confidence is discounted (0.8x) to reflect uncertainty

## API

### HookDetector (Swift)

```swift
import CrateBotCore

let detector = HookDetector()

// Check if hook detection is available
let available = await detector.isAvailable()

// Detect hook with lyrics-first approach
let result = try await detector.detectHook(
    in: fileURL,
    artist: "Artist Name",
    title: "Song Title"
)

print(result.hook ?? "No hook")     // "feel the groove tonight"
print(result.confidence)            // 0.0-1.0
print(result.occurrences)           // How many times it repeats
print(result.lyricsVerified ?? false) // Whether lyrics were used
```

The `HookDetector` automatically:
- Fetches lyrics from LRCLIB and Lyrics.ovh
- Analyzes for repeated phrases (chorus/hook detection)
- Falls back to Whisper transcription if no lyrics available
- Returns confidence scores based on detection source

## Lyrics Sources

Queries in order:
1. **LRCLIB** - Free, synced lyrics (most reliable)
2. **Lyrics.ovh** - Free, no authentication

Both APIs are free and require no API keys.

## Confidence Scoring

| Source | Base Confidence | Notes |
|--------|-----------------|-------|
| Lyrics (4+ repetitions) | 0.90 | High confidence |
| Lyrics (2-3 repetitions) | 0.80-0.85 | Good confidence |
| Lyrics (chorus marker) | 0.85 | Explicit structure |
| Transcription | 0.48-0.64 | Discounted (0.8x) |
| No detection | 0.0 | No hook found |

## Limitations

- Requires accurate ID3 metadata for lyrics lookup
- Limited to tracks with available lyrics
- Some electronic/instrumental tracks have no lyrics
- Lyrics APIs may be unavailable (rate limits, downtime)
