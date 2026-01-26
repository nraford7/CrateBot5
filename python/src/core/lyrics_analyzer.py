"""
Lyrics Analyzer - Detect repeated phrases and chorus sections from lyrics text.

This module provides lyrics-based hook detection by analyzing text patterns,
identifying chorus sections (via markers or repetition), and extracting the
most hookable phrases from song lyrics.

Part of the Lyrics-First Hook Detection pipeline (Task 2).
"""

import re
import logging
from typing import Optional, List, Tuple
from dataclasses import dataclass
from collections import Counter

logger = logging.getLogger(__name__)


@dataclass
class ChorusResult:
    """Result from chorus detection."""
    chorus_text: Optional[str]  # The detected chorus text (None if instrumental)
    confidence: float  # Confidence score 0-1
    repetitions: int  # How many times the chorus/phrase appears
    is_instrumental: bool  # True if detected as instrumental track


class LyricsAnalyzer:
    """
    Analyze lyrics to detect repeated phrases, chorus sections, and hooks.

    This class provides text-based analysis of song lyrics to identify:
    - Repeated phrases that could be hooks
    - Marked chorus sections ([Chorus], etc.)
    - The most memorable/hookable phrase

    Usage:
        analyzer = LyricsAnalyzer()
        result = analyzer.detect_chorus(lyrics_text)
        if not result.is_instrumental:
            print(f"Chorus: {result.chorus_text}")

        hook = analyzer.extract_hook_phrase(lyrics_text)
        print(f"Hook: {hook}")
    """

    # Configuration constants
    MIN_PHRASE_WORDS = 3
    MAX_PHRASE_WORDS = 8

    # Common filler phrases to filter out (not interesting as hooks)
    FILLER_PHRASES = {
        'come on', 'lets go', "let's go", 'right now', 'one more', 'one more time',
        'you know', 'you know what', 'i know', 'do you', 'can you',
        'in the', 'on the', 'at the', 'to the', 'for the',
        'at the same time', 'the same time', 'same time',
        'in the house', 'in the club', 'in the place', 'on the floor',
        'all night', 'all night long', 'all day', 'tonight',
        'one two', 'one two three', 'three two one', 'one two three four',
        'here we go', 'here we go again', 'there you go',
        'what you', 'when you', 'if you', 'that you',
        'i want', 'i need', 'i got', 'i can', 'i will',
        'we can', 'we got', 'we are', 'you are', 'they are',
        'its the', "it's the", 'its a', "it's a", 'thats the', "that's the",
        'so good', 'so bad', 'too much', 'so much',
        'like this', 'like that', 'just like', 'the beat',
        'yeah yeah', 'yeah yeah yeah', 'oh oh', 'oh oh oh',
        'oh yeah', 'uh huh', 'mm hmm',
        'la la', 'la la la', 'na na', 'na na na',
        'come on everybody', 'everybody come on',
    }

    # Single filler words used for filtering phrases
    FILLER_WORDS = {
        'yeah', 'oh', 'ah', 'uh', 'um', 'like', 'just', 'got', 'get',
        'la', 'na', 'da', 'ba', 'hey', 'yo', 'aye', 'woo', 'ooh', 'whoa',
        'come', 'go', 'now', 'right', 'know', 'can', 'gonna',
        'the', 'a', 'an', 'and', 'or', 'but', 'in', 'on', 'at', 'to', 'for',
        'is', 'it', 'be', 'are', 'was', 'were', 'been', 'being',
        'i', 'you', 'we', 'they', 'he', 'she', 'me', 'my', 'your', 'this', 'that',
    }

    # Regex pattern for section markers like [Chorus], (Verse), etc.
    SECTION_MARKERS = re.compile(
        r'[\[\(]\s*(chorus|hook|refrain|verse|bridge|intro|outro|pre-chorus|'
        r'instrumental|interlude)\s*\d*\s*[\]\)]',
        re.IGNORECASE
    )

    # Regex for LRC timestamps like [00:15.23]
    LRC_TIMESTAMP = re.compile(r'\[\d+:\d+\.\d+\]')

    # Markers indicating instrumental track
    INSTRUMENTAL_MARKERS = [
        'instrumental', 'no lyrics', 'no vocal', 'no vocals',
        'this song has no lyrics', 'instrumental version',
        'instrumental track', 'music only'
    ]

    def __init__(self):
        """Initialize the LyricsAnalyzer."""
        pass

    def find_repeated_phrases(self, lyrics: str, min_occurrences: int = 2) -> List[Tuple[str, int]]:
        """
        Find phrases that repeat in the lyrics.

        Args:
            lyrics: Raw lyrics text
            min_occurrences: Minimum number of times a phrase must appear (default 2)

        Returns:
            List of (phrase, count) tuples, sorted by count descending.
            Only includes phrases that repeat at least min_occurrences times.
        """
        if not lyrics or not lyrics.strip():
            return []

        # Clean the lyrics
        cleaned = self._clean_lyrics(lyrics)
        if not cleaned:
            return []

        # Tokenize into words
        words = cleaned.split()
        if len(words) < self.MIN_PHRASE_WORDS:
            return []

        # Generate n-grams of various sizes
        ngram_counts = Counter()

        for n in range(self.MIN_PHRASE_WORDS, min(self.MAX_PHRASE_WORDS + 1, len(words) + 1)):
            for i in range(len(words) - n + 1):
                ngram = ' '.join(words[i:i + n])

                # Filter out filler phrases
                if self._is_filler(ngram):
                    continue

                ngram_counts[ngram] += 1

        # Filter to phrases that appear at least min_occurrences times
        repeated = [
            (phrase, count)
            for phrase, count in ngram_counts.items()
            if count >= min_occurrences
        ]

        if not repeated:
            return []

        # Sort by count descending, then by length descending (prefer longer phrases)
        repeated.sort(key=lambda x: (x[1], len(x[0].split())), reverse=True)

        # Remove phrases that are substrings of higher-ranked phrases
        filtered = []
        for phrase, count in repeated:
            # Check if this phrase is contained in any already-added phrase
            is_substring = False
            for existing_phrase, _ in filtered:
                if phrase in existing_phrase:
                    is_substring = True
                    break
            if not is_substring:
                filtered.append((phrase, count))

        return filtered

    def detect_chorus(self, lyrics: str) -> ChorusResult:
        """
        Identify the chorus section from lyrics.

        First attempts to find marked [Chorus] sections. If not found,
        falls back to repetition-based detection.

        Args:
            lyrics: Raw lyrics text

        Returns:
            ChorusResult with detected chorus information
        """
        if not lyrics or not lyrics.strip():
            return ChorusResult(
                chorus_text=None,
                confidence=0.0,
                repetitions=0,
                is_instrumental=True
            )

        # Check if instrumental
        if self._is_instrumental(lyrics):
            return ChorusResult(
                chorus_text=None,
                confidence=0.95,
                repetitions=0,
                is_instrumental=True
            )

        # Try to extract marked chorus first
        marked_chorus = self._extract_marked_chorus(lyrics)
        if marked_chorus:
            # Clean the extracted chorus
            cleaned_chorus = self._clean_lyrics(marked_chorus)
            if cleaned_chorus:
                # Count how many times the marked chorus appears in lyrics
                repetitions = self._count_chorus_repetitions(cleaned_chorus, lyrics)
                return ChorusResult(
                    chorus_text=cleaned_chorus,
                    confidence=0.9,  # High confidence for marked sections
                    repetitions=max(1, repetitions),
                    is_instrumental=False
                )

        # Fall back to repetition-based detection
        repeated_phrases = self.find_repeated_phrases(lyrics)
        if repeated_phrases:
            best_phrase, count = repeated_phrases[0]
            # Confidence based on repetition count
            confidence = min(0.8, 0.4 + (count - 2) * 0.1)
            return ChorusResult(
                chorus_text=best_phrase,
                confidence=confidence,
                repetitions=count,
                is_instrumental=False
            )

        # No chorus detected
        return ChorusResult(
            chorus_text=None,
            confidence=0.3,
            repetitions=0,
            is_instrumental=False
        )

    def extract_hook_phrase(self, lyrics: str) -> Optional[str]:
        """
        Extract the most hookable phrase from lyrics.

        Combines chorus detection with phrase quality analysis to
        find the best candidate hook phrase.

        Args:
            lyrics: Raw lyrics text

        Returns:
            The best hook phrase, or None if no suitable hook found
        """
        if not lyrics or not lyrics.strip():
            return None

        # Check if instrumental
        if self._is_instrumental(lyrics):
            return None

        # First try to get chorus
        chorus_result = self.detect_chorus(lyrics)

        if chorus_result.is_instrumental:
            return None

        if chorus_result.chorus_text:
            # If we have a chorus, try to extract the best phrase from it
            # If the chorus itself is short enough, use it
            word_count = len(chorus_result.chorus_text.split())
            if self.MIN_PHRASE_WORDS <= word_count <= self.MAX_PHRASE_WORDS:
                return chorus_result.chorus_text

            # Otherwise, find repeated phrases within the chorus
            chorus_phrases = self.find_repeated_phrases(chorus_result.chorus_text)
            if chorus_phrases:
                return chorus_phrases[0][0]

            # Fall back to the chorus text if it's reasonable length
            if word_count <= self.MAX_PHRASE_WORDS * 2:
                # Take the first few words as the hook
                words = chorus_result.chorus_text.split()
                hook_words = words[:self.MAX_PHRASE_WORDS]
                return ' '.join(hook_words)

        # No chorus - use repeated phrases from full lyrics
        repeated = self.find_repeated_phrases(lyrics)
        if repeated:
            return repeated[0][0]

        return None

    def _clean_lyrics(self, lyrics: str) -> str:
        """
        Clean and normalize lyrics text.

        - Removes LRC timestamps
        - Removes section markers
        - Normalizes whitespace
        - Converts to lowercase
        - Removes punctuation (keeping apostrophes in words)

        Args:
            lyrics: Raw lyrics text

        Returns:
            Cleaned, normalized lyrics text
        """
        if not lyrics:
            return ""

        text = lyrics

        # Remove LRC timestamps [00:15.23]
        text = self.LRC_TIMESTAMP.sub('', text)

        # Remove section markers [Chorus], [Verse], etc.
        text = self.SECTION_MARKERS.sub('', text)

        # Convert to lowercase
        text = text.lower()

        # Remove punctuation except apostrophes within words
        # Replace punctuation with spaces
        text = re.sub(r'[^\w\s\']', ' ', text)

        # Clean up apostrophes at word boundaries
        text = re.sub(r"(?<!\w)'|'(?!\w)", ' ', text)

        # Normalize whitespace
        text = ' '.join(text.split())

        return text.strip()

    def _is_filler(self, phrase: str) -> bool:
        """
        Check if a phrase is a common filler phrase.

        Args:
            phrase: Phrase to check (should be lowercase)

        Returns:
            True if the phrase is filler/boring, False otherwise
        """
        phrase_lower = phrase.lower().strip()

        # Check exact match against filler phrases
        if phrase_lower in self.FILLER_PHRASES:
            return True

        # Check if phrase is mostly filler words
        words = phrase_lower.split()
        if not words:
            return True

        non_filler_count = sum(1 for w in words if w not in self.FILLER_WORDS)

        # Reject if less than 40% meaningful words for longer phrases
        if len(words) >= 3 and non_filler_count < len(words) * 0.4:
            return True

        # Reject if no meaningful words at all
        if non_filler_count == 0:
            return True

        # Check for repetitive patterns (like "yeah yeah yeah")
        unique_words = set(words)
        if len(unique_words) == 1 and words[0] in self.FILLER_WORDS:
            return True

        return False

    def _is_instrumental(self, lyrics: str) -> bool:
        """
        Check if lyrics indicate an instrumental track.

        Args:
            lyrics: Raw lyrics text

        Returns:
            True if the track appears to be instrumental
        """
        if not lyrics or not lyrics.strip():
            return True

        lyrics_lower = lyrics.lower().strip()

        # Check for instrumental markers
        for marker in self.INSTRUMENTAL_MARKERS:
            if marker in lyrics_lower:
                return True

        # Check if lyrics is just "[Instrumental]" or similar
        cleaned = self._clean_lyrics(lyrics)
        if not cleaned or len(cleaned.split()) < 3:
            # Very short lyrics might be instrumental marker
            if any(m in lyrics_lower for m in ['instrumental', 'no lyric']):
                return True

        return False

    def _extract_marked_chorus(self, lyrics: str) -> Optional[str]:
        """
        Extract text from marked [Chorus] sections.

        Args:
            lyrics: Raw lyrics text

        Returns:
            The chorus text if found, None otherwise
        """
        # Pattern to match [Chorus] or (Chorus) section and capture until next section
        chorus_pattern = re.compile(
            r'[\[\(]\s*(?:chorus|hook|refrain)\s*\d*\s*[\]\)]\s*\n?(.*?)(?=[\[\(]|\Z)',
            re.IGNORECASE | re.DOTALL
        )

        matches = chorus_pattern.findall(lyrics)

        if not matches:
            return None

        # Get the first non-empty chorus
        for match in matches:
            chorus_text = match.strip()
            if chorus_text:
                # Remove any nested section markers
                chorus_text = self.SECTION_MARKERS.sub('', chorus_text)
                chorus_text = chorus_text.strip()
                if chorus_text:
                    return chorus_text

        return None

    def _count_chorus_repetitions(self, chorus: str, full_lyrics: str) -> int:
        """
        Count how many times the chorus content appears in full lyrics.

        Args:
            chorus: Cleaned chorus text
            full_lyrics: Full lyrics text

        Returns:
            Number of times the chorus (or substantial part) appears
        """
        if not chorus or not full_lyrics:
            return 0

        cleaned_full = self._clean_lyrics(full_lyrics)

        # Count exact occurrences
        count = cleaned_full.count(chorus)
        if count > 0:
            return count

        # Try partial matching - check if first line of chorus appears
        chorus_lines = chorus.split()
        if len(chorus_lines) >= self.MIN_PHRASE_WORDS:
            # Take first few words
            first_part = ' '.join(chorus_lines[:min(5, len(chorus_lines))])
            count = cleaned_full.count(first_part)

        return max(1, count)
