# Lyrics-First Hook Detection Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Dramatically improve hook transcription accuracy by fetching lyrics first (when available) and using them to guide/constrain hook detection, with Whisper transcription as fallback.

**Architecture:** Create a `LyricsFirstHookDetector` that prioritizes lyrics lookup over transcription. When lyrics are found, analyze them for repeated phrases (chorus detection), then optionally verify against audio. When lyrics unavailable, fall back to existing Whisper-based detection. Integrate with API layer to pass artist/title metadata.

**Tech Stack:** Python, faster-whisper, requests, mutagen (ID3), pytest

---

## Overview

### Current Problem
- Whisper hallucinates on processed vocals (reverb, autotune, beat-synced mixing)
- No song structure awareness (can't distinguish verse from chorus)
- Lyrics verification exists but artist/title not passed to hook detection

### Solution
1. **Phase 1:** Wire up artist/title from ID3 to hook detection (quick win)
2. **Phase 2:** Add lyrics-first detection with chorus analysis
3. **Phase 3:** Add tests and robustness

---

## Task 1: Pass Artist/Title to Hook Detection in API Layer

**Files:**
- Modify: `python/src/core/auto_tagger.py`
- Modify: `backend/api_server.py`

**Step 1: Read the current auto_tagger.py to find where hook detection is called**

```bash
cd /Users/noahraford/Projects/claude_projects/11_CrateBot/CrateBot5
grep -n "detect_hook\|hook_transcriber" python/src/core/auto_tagger.py
```

**Step 2: Update auto_tagger.py to pass artist/title**

Find where `detect_hook()` is called and update to pass metadata:

```python
# Before (somewhere around line 450-550):
hook_result = self.hook_transcriber.detect_hook(file_path)

# After:
# First extract artist/title from existing tags dict
artist = tags.get('artist', '')
title = tags.get('title', '')

hook_result = self.hook_transcriber.detect_hook(
    file_path,
    artist=artist,
    title=title,
    verify_lyrics=True
)
```

**Step 3: Update api_server.py batch tagging to pass metadata**

Find the batch tagging endpoint and ensure tags are read before hook detection:

```python
# In POST /api/v1/tag/batch handler:
# Ensure we read tags BEFORE calling hook detection
tags = tag_manager.read_tags(file_path)
artist = tags.get('artist', '')
title = tags.get('title', '')

hook_result = hook_transcriber.detect_hook(
    file_path,
    artist=artist,
    title=title,
    verify_lyrics=True
)
```

**Step 4: Test manually**

```bash
cd /Users/noahraford/Projects/claude_projects/11_CrateBot/CrateBot5
source python/venv/bin/activate
python -c "
from src.core.hook_transcriber import CachedHookTranscriber
from src.core.tag_manager import TagManager

# Test with a real file that has artist/title tags
transcriber = CachedHookTranscriber()
tm = TagManager()

# Replace with actual test file
test_file = '/path/to/test.mp3'
tags = tm.read_tags(test_file)
print(f'Artist: {tags.get(\"artist\")}')
print(f'Title: {tags.get(\"title\")}')

result = transcriber.detect_hook(
    test_file,
    artist=tags.get('artist', ''),
    title=tags.get('title', ''),
    verify_lyrics=True
)
print(f'Hook: {result.hook}')
print(f'Lyrics verified: {result.lyrics_verified}')
print(f'Source: {result.lyrics_source}')
"
```

**Step 5: Commit**

```bash
git add python/src/core/auto_tagger.py backend/api_server.py
git commit -m "feat: pass artist/title to hook detection for lyrics verification

- Extract artist/title from ID3 tags before hook detection
- Enable lyrics verification in auto_tagger and API batch endpoints
- This enables existing LyricsVerifier to validate detected hooks"
```

---

## Task 2: Create LyricsAnalyzer for Chorus Detection

**Files:**
- Create: `python/src/core/lyrics_analyzer.py`
- Create: `python/tests/test_lyrics_analyzer.py`

**Step 1: Write failing test**

Create `python/tests/test_lyrics_analyzer.py`:

```python
"""Tests for LyricsAnalyzer - chorus and hook phrase detection from lyrics."""

import pytest
from src.core.lyrics_analyzer import LyricsAnalyzer, ChorusResult


class TestLyricsAnalyzer:
    """Test lyrics analysis for hook detection."""

    @pytest.fixture
    def analyzer(self):
        return LyricsAnalyzer()

    def test_find_repeated_lines_simple(self, analyzer):
        """Should find lines that repeat in lyrics."""
        lyrics = """
        Verse one here
        Let me see you work
        Some other line
        Let me see you work
        Another verse
        Let me see you work
        """
        result = analyzer.find_repeated_phrases(lyrics)

        assert len(result) > 0
        # Most repeated phrase should be "let me see you work"
        top_phrase, count = result[0]
        assert "let me see you work" in top_phrase.lower()
        assert count >= 3

    def test_find_repeated_lines_with_variations(self, analyzer):
        """Should handle slight variations in repeated lines."""
        lyrics = """
        Work your body
        Work your body now
        Work your body
        Something else
        Work your body tonight
        """
        result = analyzer.find_repeated_phrases(lyrics)

        # Should identify "work your body" as the core hook
        assert len(result) > 0
        top_phrase, count = result[0]
        assert "work" in top_phrase.lower() and "body" in top_phrase.lower()

    def test_detect_chorus_structure(self, analyzer):
        """Should identify chorus sections in lyrics."""
        lyrics = """
        [Verse 1]
        Walking down the street
        Feeling so alive

        [Chorus]
        Dance all night
        Dance all night long
        We're gonna dance all night

        [Verse 2]
        Another verse here
        With different words

        [Chorus]
        Dance all night
        Dance all night long
        We're gonna dance all night
        """
        result = analyzer.detect_chorus(lyrics)

        assert result is not None
        assert result.chorus_text is not None
        assert "dance all night" in result.chorus_text.lower()
        assert result.confidence > 0.7

    def test_detect_chorus_without_markers(self, analyzer):
        """Should detect chorus even without [Chorus] markers."""
        lyrics = """
        First verse content
        Some unique lines here

        Shake your body
        Shake it all around
        Shake your body

        Second verse content
        More unique stuff

        Shake your body
        Shake it all around
        Shake your body
        """
        result = analyzer.detect_chorus(lyrics)

        assert result is not None
        assert "shake" in result.chorus_text.lower()

    def test_extract_hook_phrase(self, analyzer):
        """Should extract the most hookable phrase from chorus."""
        lyrics = """
        [Chorus]
        We're gonna rock tonight
        Feel the beat drop
        Rock tonight yeah
        Feel the beat drop
        """
        hook = analyzer.extract_hook_phrase(lyrics)

        assert hook is not None
        # "Feel the beat drop" repeats most in chorus
        assert "beat" in hook.lower() or "rock" in hook.lower()

    def test_empty_lyrics(self, analyzer):
        """Should handle empty or None lyrics gracefully."""
        assert analyzer.find_repeated_phrases("") == []
        assert analyzer.find_repeated_phrases(None) == []
        assert analyzer.detect_chorus("") is None
        assert analyzer.extract_hook_phrase("") is None

    def test_instrumental_lyrics(self, analyzer):
        """Should handle lyrics that indicate instrumental."""
        lyrics = "[Instrumental]"
        result = analyzer.detect_chorus(lyrics)
        assert result is None or result.is_instrumental

    def test_filters_common_phrases(self, analyzer):
        """Should not return common filler phrases as hooks."""
        lyrics = """
        Come on come on
        Let's go let's go
        Come on come on

        Real hook line here
        Real hook line here

        Come on come on
        """
        result = analyzer.find_repeated_phrases(lyrics)

        # "come on" and "let's go" should be filtered
        top_phrases = [p.lower() for p, _ in result[:3]]
        assert not any("come on" in p for p in top_phrases)
        assert any("real hook" in p for p in top_phrases)
```

**Step 2: Run test to verify it fails**

```bash
cd /Users/noahraford/Projects/claude_projects/11_CrateBot/CrateBot5/python
source venv/bin/activate
pytest tests/test_lyrics_analyzer.py -v
```

Expected: FAIL - `ModuleNotFoundError: No module named 'src.core.lyrics_analyzer'`

**Step 3: Implement LyricsAnalyzer**

Create `python/src/core/lyrics_analyzer.py`:

```python
"""
Lyrics Analyzer - Extract hooks and detect chorus sections from song lyrics.

Analyzes lyrics text to find:
- Repeated phrases (likely hooks)
- Chorus sections (structural analysis)
- The most "hookable" phrase for display
"""

import re
from typing import List, Tuple, Optional
from dataclasses import dataclass
from collections import Counter
import logging

logger = logging.getLogger(__name__)


@dataclass
class ChorusResult:
    """Result from chorus detection."""
    chorus_text: str          # The chorus section text
    confidence: float         # 0-1 confidence this is the chorus
    repetitions: int          # How many times it appears
    is_instrumental: bool     # True if lyrics indicate instrumental


class LyricsAnalyzer:
    """
    Analyze lyrics to find hooks and chorus sections.

    Usage:
        analyzer = LyricsAnalyzer()
        hook = analyzer.extract_hook_phrase(lyrics_text)
        print(hook)  # "let me see you work"
    """

    # Common filler phrases to filter out (not interesting hooks)
    FILLER_PHRASES = {
        'come on', 'lets go', "let's go", 'right now', 'one more time',
        'you know', 'i know', 'do you', 'can you', 'here we go',
        'oh yeah', 'yeah yeah', 'na na na', 'la la la',
        'one two', 'one two three', 'uh huh', 'mm hmm',
        'all night', 'all night long', 'tonight',
        'in the house', 'in the club', 'on the floor',
    }

    # Section markers in lyrics
    SECTION_MARKERS = re.compile(
        r'\[(chorus|verse|bridge|intro|outro|hook|pre-chorus|refrain)\s*\d*\]',
        re.IGNORECASE
    )

    # Minimum phrase length (words) to consider as hook
    MIN_PHRASE_WORDS = 3
    MAX_PHRASE_WORDS = 8

    def find_repeated_phrases(
        self,
        lyrics: Optional[str],
        min_occurrences: int = 2
    ) -> List[Tuple[str, int]]:
        """
        Find phrases that repeat in the lyrics.

        Args:
            lyrics: Full lyrics text
            min_occurrences: Minimum times a phrase must appear

        Returns:
            List of (phrase, count) tuples, sorted by count descending
        """
        if not lyrics:
            return []

        # Clean and normalize lyrics
        cleaned = self._clean_lyrics(lyrics)
        lines = [l.strip() for l in cleaned.split('\n') if l.strip()]

        # Count line occurrences (exact matches)
        line_counts = Counter(lines)

        # Also extract n-grams from lines for partial matches
        all_ngrams = []
        for line in lines:
            words = line.split()
            for n in range(self.MIN_PHRASE_WORDS, min(len(words) + 1, self.MAX_PHRASE_WORDS + 1)):
                for i in range(len(words) - n + 1):
                    ngram = ' '.join(words[i:i+n])
                    all_ngrams.append(ngram)

        ngram_counts = Counter(all_ngrams)

        # Combine line and n-gram counts, preferring longer matches
        combined = {}

        # Add full lines first
        for line, count in line_counts.items():
            if count >= min_occurrences and len(line.split()) >= self.MIN_PHRASE_WORDS:
                if not self._is_filler(line):
                    combined[line] = count

        # Add n-grams that aren't substrings of already-added lines
        for ngram, count in ngram_counts.items():
            if count >= min_occurrences and not self._is_filler(ngram):
                # Check if this is a substring of an existing phrase
                is_substring = any(ngram in existing for existing in combined.keys())
                if not is_substring:
                    combined[ngram] = count

        # Sort by count, then by length (prefer longer phrases)
        result = sorted(
            combined.items(),
            key=lambda x: (x[1], len(x[0])),
            reverse=True
        )

        return result

    def detect_chorus(self, lyrics: Optional[str]) -> Optional[ChorusResult]:
        """
        Detect the chorus section in lyrics.

        Uses both structural markers ([Chorus]) and repetition analysis.

        Args:
            lyrics: Full lyrics text

        Returns:
            ChorusResult with chorus text and confidence, or None
        """
        if not lyrics:
            return None

        # Check for instrumental marker
        if self._is_instrumental(lyrics):
            return ChorusResult(
                chorus_text="",
                confidence=1.0,
                repetitions=0,
                is_instrumental=True
            )

        # Try to find marked chorus sections
        chorus_text = self._extract_marked_chorus(lyrics)
        if chorus_text:
            # Count how many times this chorus appears
            cleaned_lyrics = self._clean_lyrics(lyrics)
            cleaned_chorus = self._clean_lyrics(chorus_text)
            repetitions = cleaned_lyrics.count(cleaned_chorus)

            return ChorusResult(
                chorus_text=chorus_text.strip(),
                confidence=0.9,  # High confidence when explicitly marked
                repetitions=max(repetitions, 1),
                is_instrumental=False
            )

        # Fall back to repetition analysis
        repeated = self.find_repeated_phrases(lyrics, min_occurrences=2)
        if not repeated:
            return None

        # The most repeated substantial phrase is likely the chorus/hook
        top_phrase, count = repeated[0]

        # Build confidence based on repetition count
        confidence = min(0.5 + (count * 0.1), 0.85)

        return ChorusResult(
            chorus_text=top_phrase,
            confidence=confidence,
            repetitions=count,
            is_instrumental=False
        )

    def extract_hook_phrase(self, lyrics: Optional[str]) -> Optional[str]:
        """
        Extract the most "hookable" phrase from lyrics.

        This is the primary method for lyrics-first hook detection.

        Args:
            lyrics: Full lyrics text

        Returns:
            The hook phrase, or None if can't be determined
        """
        if not lyrics:
            return None

        # First try to find chorus
        chorus = self.detect_chorus(lyrics)
        if chorus and chorus.is_instrumental:
            return None

        # If we have a chorus, analyze it for the hook
        if chorus and chorus.chorus_text:
            # Find the most repeated line within the chorus
            chorus_repeated = self.find_repeated_phrases(
                chorus.chorus_text,
                min_occurrences=1
            )
            if chorus_repeated:
                return chorus_repeated[0][0]
            # Otherwise return first substantial line of chorus
            lines = [l.strip() for l in chorus.chorus_text.split('\n') if l.strip()]
            for line in lines:
                if len(line.split()) >= self.MIN_PHRASE_WORDS and not self._is_filler(line):
                    return line

        # Fall back to most repeated phrase in full lyrics
        repeated = self.find_repeated_phrases(lyrics)
        if repeated:
            return repeated[0][0]

        return None

    def _clean_lyrics(self, lyrics: str) -> str:
        """Clean lyrics text for analysis."""
        # Remove section markers
        cleaned = self.SECTION_MARKERS.sub('', lyrics)
        # Normalize whitespace
        cleaned = re.sub(r'\s+', ' ', cleaned)
        # Lowercase for comparison
        cleaned = cleaned.lower()
        # Remove punctuation except apostrophes
        cleaned = re.sub(r"[^\w\s']", '', cleaned)
        return cleaned.strip()

    def _is_filler(self, phrase: str) -> bool:
        """Check if phrase is a common filler."""
        normalized = phrase.lower().strip()
        return normalized in self.FILLER_PHRASES

    def _is_instrumental(self, lyrics: str) -> bool:
        """Check if lyrics indicate instrumental track."""
        lower = lyrics.lower()
        indicators = ['[instrumental]', '(instrumental)', 'instrumental']
        return any(ind in lower for ind in indicators) and len(lyrics.strip()) < 50

    def _extract_marked_chorus(self, lyrics: str) -> Optional[str]:
        """Extract text from [Chorus] sections."""
        # Find all [Chorus] sections
        pattern = r'\[chorus[^\]]*\](.*?)(?=\[|$)'
        matches = re.findall(pattern, lyrics, re.IGNORECASE | re.DOTALL)

        if not matches:
            return None

        # Return the first chorus section (they should all be similar)
        chorus = matches[0].strip()
        return chorus if chorus else None
```

**Step 4: Run tests to verify they pass**

```bash
cd /Users/noahraford/Projects/claude_projects/11_CrateBot/CrateBot5/python
pytest tests/test_lyrics_analyzer.py -v
```

Expected: All tests PASS

**Step 5: Commit**

```bash
git add python/src/core/lyrics_analyzer.py python/tests/test_lyrics_analyzer.py
git commit -m "feat: add LyricsAnalyzer for chorus and hook detection from lyrics

- Detect repeated phrases in lyrics text
- Identify chorus sections via markers or repetition
- Extract most hookable phrase for display
- Filter common filler phrases (come on, let's go, etc.)"
```

---

## Task 3: Create LyricsFirstHookDetector

**Files:**
- Create: `python/src/core/lyrics_first_hook.py`
- Create: `python/tests/test_lyrics_first_hook.py`

**Step 1: Write failing test**

Create `python/tests/test_lyrics_first_hook.py`:

```python
"""Tests for LyricsFirstHookDetector."""

import pytest
from unittest.mock import Mock, patch, MagicMock
from src.core.lyrics_first_hook import LyricsFirstHookDetector, LyricsFirstResult


class TestLyricsFirstHookDetector:
    """Test lyrics-first hook detection."""

    @pytest.fixture
    def detector(self):
        return LyricsFirstHookDetector(enable_transcription_fallback=False)

    @pytest.fixture
    def detector_with_fallback(self):
        return LyricsFirstHookDetector(enable_transcription_fallback=True)

    def test_detect_hook_with_lyrics_found(self, detector):
        """Should return hook from lyrics when available."""
        with patch.object(detector, '_get_lyrics') as mock_lyrics:
            mock_lyrics.return_value = """
            [Verse]
            Some verse text

            [Chorus]
            Feel the groove tonight
            Feel the groove tonight
            Let it move you right
            """

            result = detector.detect_hook(
                audio_path="/fake/path.mp3",
                artist="Test Artist",
                title="Test Song"
            )

            assert result.hook is not None
            assert "groove" in result.hook.lower() or "feel" in result.hook.lower()
            assert result.source == "lyrics"
            assert result.confidence > 0.7

    def test_detect_hook_no_lyrics_no_fallback(self, detector):
        """Should return None when no lyrics and fallback disabled."""
        with patch.object(detector, '_get_lyrics', return_value=None):
            result = detector.detect_hook(
                audio_path="/fake/path.mp3",
                artist="Unknown",
                title="Unknown Track"
            )

            assert result.hook is None
            assert result.source == "none"

    def test_detect_hook_uses_transcription_fallback(self, detector_with_fallback):
        """Should fall back to transcription when no lyrics."""
        with patch.object(detector_with_fallback, '_get_lyrics', return_value=None):
            with patch.object(detector_with_fallback, '_transcribe_audio') as mock_transcribe:
                mock_transcribe.return_value = Mock(
                    hook="transcribed hook phrase",
                    confidence=0.6,
                    occurrences=3,
                    transcription="full transcription..."
                )

                result = detector_with_fallback.detect_hook(
                    audio_path="/fake/path.mp3",
                    artist="Unknown",
                    title="Unknown"
                )

                assert result.hook == "transcribed hook phrase"
                assert result.source == "transcription"

    def test_detect_hook_verifies_against_audio(self, detector):
        """Should verify lyrics-detected hook appears in audio."""
        with patch.object(detector, '_get_lyrics') as mock_lyrics:
            mock_lyrics.return_value = """
            [Chorus]
            Shake your body now
            Shake your body now
            """

            with patch.object(detector, '_verify_in_audio') as mock_verify:
                mock_verify.return_value = (True, 0.85)

                result = detector.detect_hook(
                    audio_path="/fake/path.mp3",
                    artist="Test",
                    title="Test",
                    verify_audio=True
                )

                assert result.hook is not None
                assert result.audio_verified is True
                assert result.confidence >= 0.85

    def test_detect_hook_no_artist_title(self, detector):
        """Should handle missing artist/title gracefully."""
        result = detector.detect_hook(
            audio_path="/fake/path.mp3",
            artist=None,
            title=None
        )

        # Can't do lyrics lookup without metadata
        assert result.source in ("none", "transcription")

    def test_confidence_boosted_when_lyrics_verified(self, detector):
        """Confidence should be higher when hook found in lyrics."""
        with patch.object(detector, '_get_lyrics') as mock_lyrics:
            mock_lyrics.return_value = """
            Work it work it
            Work it work it
            Work it all night
            """

            result = detector.detect_hook(
                audio_path="/fake/path.mp3",
                artist="Test",
                title="Test"
            )

            # Lyrics-sourced hooks should have high confidence
            assert result.confidence >= 0.75

    def test_returns_all_candidate_hooks(self, detector):
        """Should return multiple hook candidates when available."""
        with patch.object(detector, '_get_lyrics') as mock_lyrics:
            mock_lyrics.return_value = """
            First hook line
            First hook line
            Second hook here
            Second hook here
            Second hook here
            Third possibility
            """

            result = detector.detect_hook(
                audio_path="/fake/path.mp3",
                artist="Test",
                title="Test"
            )

            assert len(result.all_candidates) >= 2
```

**Step 2: Run test to verify it fails**

```bash
pytest tests/test_lyrics_first_hook.py -v
```

Expected: FAIL - `ModuleNotFoundError`

**Step 3: Implement LyricsFirstHookDetector**

Create `python/src/core/lyrics_first_hook.py`:

```python
"""
Lyrics-First Hook Detector - Prioritize lyrics lookup over transcription.

When lyrics are available, analyze them for repeated phrases (likely hooks).
Fall back to Whisper transcription only when lyrics unavailable.
"""

import logging
from typing import Optional, List, Tuple
from dataclasses import dataclass, field

from .lyrics_verifier import LyricsVerifier, LyricsResult
from .lyrics_analyzer import LyricsAnalyzer
from .hook_transcriber import HookTranscriber, HookResult

logger = logging.getLogger(__name__)


@dataclass
class LyricsFirstResult:
    """Result from lyrics-first hook detection."""
    hook: Optional[str]                    # The detected hook phrase
    confidence: float                      # 0-1 confidence score
    source: str                            # "lyrics", "transcription", or "none"
    occurrences: int                       # Repetition count (from lyrics or audio)

    # Additional metadata
    lyrics_source: Optional[str] = None    # "lrclib", "lyrics.ovh", etc.
    audio_verified: Optional[bool] = None  # True if hook verified in audio
    all_candidates: List[Tuple[str, int]] = field(default_factory=list)
    full_transcription: Optional[str] = None

    def to_hook_result(self) -> HookResult:
        """Convert to standard HookResult for compatibility."""
        return HookResult(
            hook=self.hook,
            confidence=self.confidence,
            occurrences=self.occurrences,
            all_phrases=self.all_candidates,
            transcription=self.full_transcription or "",
            lyrics_verified=self.source == "lyrics",
            lyrics_source=self.lyrics_source,
            lyrics_match_type="exact" if self.source == "lyrics" else "none"
        )


class LyricsFirstHookDetector:
    """
    Detect hooks by prioritizing lyrics lookup over audio transcription.

    Strategy:
    1. If artist/title available, fetch lyrics from APIs
    2. If lyrics found, analyze for repeated phrases (chorus/hook)
    3. Optionally verify hook appears in audio transcription
    4. If no lyrics, fall back to pure transcription analysis

    Usage:
        detector = LyricsFirstHookDetector()
        result = detector.detect_hook(
            audio_path="/path/to/track.mp3",
            artist="Artist Name",
            title="Song Title"
        )
        print(result.hook)  # "feel the groove tonight"
        print(result.source)  # "lyrics"
    """

    def __init__(
        self,
        enable_transcription_fallback: bool = True,
        whisper_model: str = "medium",
        enable_audio_verification: bool = False
    ):
        """
        Initialize the detector.

        Args:
            enable_transcription_fallback: Use Whisper when lyrics unavailable
            whisper_model: Whisper model size for fallback
            enable_audio_verification: Verify lyrics-detected hooks in audio
        """
        self.enable_transcription_fallback = enable_transcription_fallback
        self.enable_audio_verification = enable_audio_verification

        # Lazy-load components
        self._lyrics_verifier: Optional[LyricsVerifier] = None
        self._lyrics_analyzer: Optional[LyricsAnalyzer] = None
        self._hook_transcriber: Optional[HookTranscriber] = None
        self._whisper_model = whisper_model

    @property
    def lyrics_verifier(self) -> LyricsVerifier:
        if self._lyrics_verifier is None:
            self._lyrics_verifier = LyricsVerifier()
        return self._lyrics_verifier

    @property
    def lyrics_analyzer(self) -> LyricsAnalyzer:
        if self._lyrics_analyzer is None:
            self._lyrics_analyzer = LyricsAnalyzer()
        return self._lyrics_analyzer

    @property
    def hook_transcriber(self) -> Optional[HookTranscriber]:
        if self._hook_transcriber is None and self.enable_transcription_fallback:
            try:
                self._hook_transcriber = HookTranscriber(model_size=self._whisper_model)
            except Exception as e:
                logger.warning(f"Could not initialize Whisper: {e}")
        return self._hook_transcriber

    def detect_hook(
        self,
        audio_path: str,
        artist: Optional[str] = None,
        title: Optional[str] = None,
        verify_audio: bool = False
    ) -> LyricsFirstResult:
        """
        Detect hook using lyrics-first strategy.

        Args:
            audio_path: Path to audio file
            artist: Artist name (required for lyrics lookup)
            title: Song title (required for lyrics lookup)
            verify_audio: Whether to verify hook appears in audio

        Returns:
            LyricsFirstResult with hook and metadata
        """
        # Try lyrics-based detection first
        if artist and title:
            lyrics = self._get_lyrics(artist, title)
            if lyrics:
                return self._detect_from_lyrics(
                    lyrics=lyrics,
                    audio_path=audio_path,
                    verify_audio=verify_audio or self.enable_audio_verification,
                    lyrics_source=self._last_lyrics_source
                )

        # Fall back to transcription
        if self.enable_transcription_fallback:
            return self._detect_from_transcription(audio_path, artist, title)

        # No detection possible
        return LyricsFirstResult(
            hook=None,
            confidence=0.0,
            source="none",
            occurrences=0
        )

    def _get_lyrics(self, artist: str, title: str) -> Optional[str]:
        """Fetch lyrics from available APIs."""
        try:
            result = self.lyrics_verifier.get_lyrics(artist, title)
            if result.found and result.lyrics:
                self._last_lyrics_source = result.source
                return result.lyrics
        except Exception as e:
            logger.warning(f"Lyrics lookup failed: {e}")

        self._last_lyrics_source = None
        return None

    def _detect_from_lyrics(
        self,
        lyrics: str,
        audio_path: str,
        verify_audio: bool,
        lyrics_source: Optional[str]
    ) -> LyricsFirstResult:
        """Detect hook by analyzing lyrics."""
        # Extract hook phrase from lyrics
        hook = self.lyrics_analyzer.extract_hook_phrase(lyrics)

        if not hook:
            # No clear hook in lyrics, try transcription fallback
            if self.enable_transcription_fallback:
                return self._detect_from_transcription(audio_path, None, None)
            return LyricsFirstResult(
                hook=None,
                confidence=0.3,  # Lyrics found but no hook
                source="lyrics",
                occurrences=0,
                lyrics_source=lyrics_source
            )

        # Get all candidate phrases
        all_candidates = self.lyrics_analyzer.find_repeated_phrases(lyrics)

        # Find occurrence count for the top hook
        occurrences = 1
        for phrase, count in all_candidates:
            if phrase.lower() == hook.lower():
                occurrences = count
                break

        # Calculate confidence
        confidence = self._calculate_lyrics_confidence(hook, occurrences, all_candidates)

        # Optionally verify in audio
        audio_verified = None
        if verify_audio:
            audio_verified, verify_confidence = self._verify_in_audio(audio_path, hook)
            if audio_verified:
                confidence = min(1.0, confidence + 0.1)
            else:
                confidence = max(0.3, confidence - 0.2)

        return LyricsFirstResult(
            hook=hook,
            confidence=confidence,
            source="lyrics",
            occurrences=occurrences,
            lyrics_source=lyrics_source,
            audio_verified=audio_verified,
            all_candidates=all_candidates[:5]  # Top 5 candidates
        )

    def _detect_from_transcription(
        self,
        audio_path: str,
        artist: Optional[str],
        title: Optional[str]
    ) -> LyricsFirstResult:
        """Fall back to transcription-based detection."""
        transcriber = self.hook_transcriber
        if not transcriber:
            return LyricsFirstResult(
                hook=None,
                confidence=0.0,
                source="none",
                occurrences=0
            )

        try:
            result = transcriber.detect_hook(
                audio_path,
                artist=artist or "",
                title=title or "",
                verify_lyrics=False  # Already tried lyrics
            )

            return LyricsFirstResult(
                hook=result.hook,
                confidence=result.confidence * 0.8,  # Discount transcription confidence
                source="transcription",
                occurrences=result.occurrences,
                all_candidates=result.all_phrases[:5],
                full_transcription=result.transcription
            )
        except Exception as e:
            logger.error(f"Transcription failed: {e}")
            return LyricsFirstResult(
                hook=None,
                confidence=0.0,
                source="none",
                occurrences=0
            )

    def _verify_in_audio(
        self,
        audio_path: str,
        hook: str
    ) -> Tuple[bool, float]:
        """Verify hook appears in audio transcription."""
        transcriber = self.hook_transcriber
        if not transcriber:
            return (None, 0.0)

        try:
            # Transcribe and check if hook appears
            result = transcriber.detect_hook(audio_path, verify_lyrics=False)
            transcription_lower = result.transcription.lower()
            hook_lower = hook.lower()

            # Check for exact or fuzzy match
            if hook_lower in transcription_lower:
                return (True, 0.9)

            # Check if most words appear
            hook_words = set(hook_lower.split())
            if len(hook_words) >= 3:
                matches = sum(1 for w in hook_words if w in transcription_lower)
                ratio = matches / len(hook_words)
                if ratio >= 0.7:
                    return (True, ratio)

            return (False, 0.0)
        except Exception as e:
            logger.warning(f"Audio verification failed: {e}")
            return (None, 0.0)

    def _calculate_lyrics_confidence(
        self,
        hook: str,
        occurrences: int,
        all_candidates: List[Tuple[str, int]]
    ) -> float:
        """Calculate confidence score for lyrics-detected hook."""
        # Base confidence for lyrics-sourced hooks
        confidence = 0.75

        # Boost for repetition
        if occurrences >= 4:
            confidence += 0.15
        elif occurrences >= 3:
            confidence += 0.10
        elif occurrences >= 2:
            confidence += 0.05

        # Boost if hook is clearly the top candidate
        if all_candidates and len(all_candidates) >= 2:
            top_count = all_candidates[0][1]
            second_count = all_candidates[1][1]
            if top_count > second_count * 1.5:
                confidence += 0.05

        # Cap at 0.95 (never 100% certain)
        return min(0.95, confidence)
```

**Step 4: Run tests to verify they pass**

```bash
pytest tests/test_lyrics_first_hook.py -v
```

Expected: All tests PASS

**Step 5: Commit**

```bash
git add python/src/core/lyrics_first_hook.py python/tests/test_lyrics_first_hook.py
git commit -m "feat: add LyricsFirstHookDetector for improved hook accuracy

- Prioritize lyrics lookup over Whisper transcription
- Analyze lyrics for repeated phrases (chorus/hook)
- Optional audio verification of lyrics-detected hooks
- Fall back to transcription when lyrics unavailable
- Significantly improves accuracy for known tracks"
```

---

## Task 4: Integrate LyricsFirstHookDetector into Pipeline

**Files:**
- Modify: `python/src/core/hook_transcriber.py`
- Modify: `python/src/core/auto_tagger.py`

**Step 1: Add lyrics-first mode to CachedHookTranscriber**

In `hook_transcriber.py`, update `CachedHookTranscriber` to optionally use lyrics-first detection:

```python
# Add import at top
from .lyrics_first_hook import LyricsFirstHookDetector

# Update CachedHookTranscriber.__init__ (around line 660):
def __init__(
    self,
    model_size: str = "medium",
    enable_lyrics_verification: bool = True,
    use_lyrics_first: bool = True  # NEW parameter
):
    self._transcriber = HookTranscriber(
        model_size=model_size,
        enable_lyrics_verification=enable_lyrics_verification
    )
    self._lyrics_first_detector = None
    self._use_lyrics_first = use_lyrics_first
    # ... rest of init

# Add property for lyrics-first detector:
@property
def lyrics_first_detector(self) -> Optional[LyricsFirstHookDetector]:
    if self._lyrics_first_detector is None and self._use_lyrics_first:
        self._lyrics_first_detector = LyricsFirstHookDetector(
            enable_transcription_fallback=True
        )
    return self._lyrics_first_detector

# Update detect_hook method:
def detect_hook(
    self,
    audio_path: str,
    language: str = "en",
    artist: str = "",
    title: str = "",
    verify_lyrics: bool = True,
    skip_cache: bool = False
) -> HookResult:
    # ... existing cache check ...

    # Use lyrics-first if artist/title available
    if self._use_lyrics_first and artist and title:
        detector = self.lyrics_first_detector
        if detector:
            lyrics_result = detector.detect_hook(
                audio_path=audio_path,
                artist=artist,
                title=title
            )
            # Convert to HookResult for compatibility
            result = lyrics_result.to_hook_result()
            self._cache[cache_key] = result
            return result

    # Fall back to standard transcription
    result = self._transcriber.detect_hook(...)
    # ... rest of method
```

**Step 2: Update auto_tagger.py to use lyrics-first**

Ensure the auto_tagger passes artist/title and uses the new mode:

```python
# In generate_vibe or hook detection section:
hook_transcriber = CachedHookTranscriber(use_lyrics_first=True)

# Extract metadata
tags = self.tag_manager.read_tags(file_path)
artist = tags.get('artist', '')
title = tags.get('title', '')

# Detect hook with lyrics-first
hook_result = hook_transcriber.detect_hook(
    file_path,
    artist=artist,
    title=title,
    verify_lyrics=True
)

logger.info(f"Hook detected: '{hook_result.hook}' (source: {'lyrics' if hook_result.lyrics_verified else 'transcription'})")
```

**Step 3: Test integration**

```bash
cd /Users/noahraford/Projects/claude_projects/11_CrateBot/CrateBot5
source python/venv/bin/activate
python -c "
from src.core.hook_transcriber import CachedHookTranscriber

transcriber = CachedHookTranscriber(use_lyrics_first=True)

# Test with a known song
result = transcriber.detect_hook(
    '/path/to/test.mp3',
    artist='Daft Punk',
    title='Around the World'
)
print(f'Hook: {result.hook}')
print(f'Confidence: {result.confidence}')
print(f'Source: {\"lyrics\" if result.lyrics_verified else \"transcription\"}')
"
```

**Step 4: Commit**

```bash
git add python/src/core/hook_transcriber.py python/src/core/auto_tagger.py
git commit -m "feat: integrate LyricsFirstHookDetector into tagging pipeline

- Add use_lyrics_first option to CachedHookTranscriber
- Default to lyrics-first when artist/title available
- Transparent fallback to transcription when lyrics unavailable
- Maintains backwards compatibility with existing API"
```

---

## Task 5: Add Comprehensive Test Suite

**Files:**
- Modify: `python/tests/test_lyrics_analyzer.py`
- Modify: `python/tests/test_lyrics_first_hook.py`
- Create: `python/tests/test_lyrics_verifier.py`

**Step 1: Add tests for LyricsVerifier**

Create `python/tests/test_lyrics_verifier.py`:

```python
"""Tests for LyricsVerifier."""

import pytest
from unittest.mock import patch, Mock
from src.core.lyrics_verifier import LyricsVerifier, LyricsResult, VerificationResult


class TestLyricsVerifier:
    """Test lyrics verification."""

    @pytest.fixture
    def verifier(self):
        return LyricsVerifier()

    def test_get_lyrics_caches_results(self, verifier):
        """Should cache lyrics lookups."""
        with patch.object(verifier, '_try_lrclib') as mock_lrclib:
            mock_lrclib.return_value = LyricsResult(
                lyrics="Test lyrics here",
                source="lrclib",
                artist="Test",
                title="Song",
                found=True
            )

            # First call
            result1 = verifier.get_lyrics("Test", "Song")
            # Second call should use cache
            result2 = verifier.get_lyrics("Test", "Song")

            assert mock_lrclib.call_count == 1
            assert result1.lyrics == result2.lyrics

    def test_verify_hook_exact_match(self, verifier):
        """Should detect exact hook matches."""
        with patch.object(verifier, 'get_lyrics') as mock_lyrics:
            mock_lyrics.return_value = LyricsResult(
                lyrics="Some lyrics\nFeel the groove\nMore lyrics\nFeel the groove",
                source="lrclib",
                artist="Test",
                title="Song",
                found=True
            )

            result = verifier.verify_hook("feel the groove", "Test", "Song")

            assert result.verified is True
            assert result.match_type == "exact"

    def test_verify_hook_partial_match(self, verifier):
        """Should detect partial hook matches."""
        with patch.object(verifier, 'get_lyrics') as mock_lyrics:
            mock_lyrics.return_value = LyricsResult(
                lyrics="Feel the funky groove tonight baby",
                source="lrclib",
                artist="Test",
                title="Song",
                found=True
            )

            result = verifier.verify_hook("feel the groove", "Test", "Song")

            assert result.verified is True
            assert result.match_type in ("exact", "partial")

    def test_verify_hook_no_lyrics(self, verifier):
        """Should handle missing lyrics gracefully."""
        with patch.object(verifier, 'get_lyrics') as mock_lyrics:
            mock_lyrics.return_value = LyricsResult(
                lyrics=None,
                source="none",
                artist="Test",
                title="Song",
                found=False
            )

            result = verifier.verify_hook("some hook", "Test", "Song")

            assert result.verified is False
            assert result.confidence == 0.5  # Uncertain

    def test_clean_for_api_removes_features(self, verifier):
        """Should clean artist names for API calls."""
        cleaned = verifier._clean_for_api("Artist feat. Other Artist")
        assert "feat" not in cleaned.lower()

        cleaned = verifier._clean_for_api("Song (Radio Edit)")
        assert "edit" not in cleaned.lower()
```

**Step 2: Run all tests**

```bash
cd /Users/noahraford/Projects/claude_projects/11_CrateBot/CrateBot5/python
pytest tests/test_lyrics*.py -v
```

Expected: All tests PASS

**Step 3: Commit**

```bash
git add python/tests/test_lyrics_verifier.py
git commit -m "test: add comprehensive test suite for lyrics-first hook detection

- Tests for LyricsVerifier API caching and matching
- Tests for LyricsAnalyzer chorus detection
- Tests for LyricsFirstHookDetector integration
- Mock-based tests for API isolation"
```

---

## Task 6: Update Documentation

**Files:**
- Modify: `docs/ARCHITECTURE.md` (if exists)
- Create: `docs/LYRICS-FIRST-HOOK-DETECTION.md`

**Step 1: Create documentation**

Create `docs/LYRICS-FIRST-HOOK-DETECTION.md`:

```markdown
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

### LyricsFirstHookDetector

```python
from src.core.lyrics_first_hook import LyricsFirstHookDetector

detector = LyricsFirstHookDetector(
    enable_transcription_fallback=True,  # Use Whisper when no lyrics
    enable_audio_verification=False       # Verify hook in audio
)

result = detector.detect_hook(
    audio_path="/path/to/track.mp3",
    artist="Artist Name",
    title="Song Title"
)

print(result.hook)        # "feel the groove tonight"
print(result.source)      # "lyrics" or "transcription"
print(result.confidence)  # 0.0-1.0
```

### CachedHookTranscriber

The existing `CachedHookTranscriber` now supports lyrics-first mode:

```python
from src.core.hook_transcriber import CachedHookTranscriber

transcriber = CachedHookTranscriber(use_lyrics_first=True)

result = transcriber.detect_hook(
    audio_path="/path/to/track.mp3",
    artist="Artist",
    title="Title"
)
```

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
```

**Step 2: Commit**

```bash
git add docs/LYRICS-FIRST-HOOK-DETECTION.md
git commit -m "docs: add lyrics-first hook detection documentation

- Explain detection strategy and fallback behavior
- Document API usage and confidence scoring
- List lyrics sources and limitations"
```

---

## Execution Summary

| Task | Description | Complexity |
|------|-------------|------------|
| 1 | Pass artist/title to hook detection | Low |
| 2 | Create LyricsAnalyzer | Medium |
| 3 | Create LyricsFirstHookDetector | Medium |
| 4 | Integrate into pipeline | Medium |
| 5 | Add test suite | Low |
| 6 | Documentation | Low |

**Dependencies:**
- Task 2 must complete before Task 3
- Tasks 1-3 must complete before Task 4
- Task 4 must complete before Task 5

**Expected Outcome:**
- Hook detection accuracy significantly improved for known tracks
- Transparent fallback maintains functionality for unknown tracks
- Existing API remains backwards compatible
