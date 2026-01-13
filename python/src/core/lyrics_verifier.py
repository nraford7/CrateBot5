"""
Lyrics Verifier - Verify detected hooks against lyrics databases.

Uses free lyrics APIs to check if a detected hook appears in the actual song lyrics.
This helps filter out transcription errors and hallucinations.

APIs used (in order of preference):
1. LRCLIB - Free, synced lyrics (more reliable)
2. Lyrics.ovh - Free, no auth required
3. Genius - Requires API key (optional)
"""

import os
import re
import logging
from typing import Optional, Dict, Any, List, Tuple
from dataclasses import dataclass
import json

logger = logging.getLogger(__name__)

# Try to import requests (handles SSL better), fall back to urllib
try:
    import requests
    HAS_REQUESTS = True
except ImportError:
    import urllib.request
    import urllib.parse
    import urllib.error
    import ssl
    import certifi
    HAS_REQUESTS = False


@dataclass
class LyricsResult:
    """Result from lyrics lookup."""
    lyrics: Optional[str]
    source: str
    artist: str
    title: str
    found: bool


@dataclass
class VerificationResult:
    """Result from hook verification."""
    hook: str
    verified: bool
    confidence: float  # 0-1, how confident we are the hook is real
    match_type: str  # 'exact', 'partial', 'fuzzy', 'none'
    lyrics_source: Optional[str]
    lyrics_snippet: Optional[str]  # Context around the match


class LyricsVerifier:
    """
    Verify detected hooks against lyrics databases.

    Usage:
        verifier = LyricsVerifier()
        result = verifier.verify_hook("let me see you work", artist="Artist", title="Song")
        if result.verified:
            print(f"Hook verified! Found in lyrics via {result.lyrics_source}")
    """

    # API endpoints
    LYRICS_OVH_URL = "https://api.lyrics.ovh/v1/{artist}/{title}"
    LRCLIB_URL = "https://lrclib.net/api/get?artist_name={artist}&track_name={title}"

    def __init__(self, genius_api_key: Optional[str] = None):
        """
        Initialize the lyrics verifier.

        Args:
            genius_api_key: Optional Genius API key for better coverage
        """
        self.genius_api_key = genius_api_key or os.environ.get('GENIUS_API_KEY')
        self._cache: Dict[str, LyricsResult] = {}

    def get_lyrics(self, artist: str, title: str) -> LyricsResult:
        """
        Fetch lyrics from available APIs.

        Args:
            artist: Artist name
            title: Song title

        Returns:
            LyricsResult with lyrics if found
        """
        # Check cache first
        cache_key = f"{artist.lower()}:{title.lower()}"
        if cache_key in self._cache:
            return self._cache[cache_key]

        # Clean up artist/title
        artist_clean = self._clean_for_api(artist)
        title_clean = self._clean_for_api(title)

        # Try LRCLIB first (more reliable), then lyrics.ovh
        result = self._try_lrclib(artist_clean, title_clean)
        if result.found:
            self._cache[cache_key] = result
            return result

        result = self._try_lyrics_ovh(artist_clean, title_clean)
        if result.found:
            self._cache[cache_key] = result
            return result

        # Return empty result
        result = LyricsResult(
            lyrics=None,
            source="none",
            artist=artist,
            title=title,
            found=False
        )
        self._cache[cache_key] = result
        return result

    def verify_hook(
        self,
        hook: str,
        artist: str,
        title: str,
        fuzzy_threshold: float = 0.8
    ) -> VerificationResult:
        """
        Verify if a detected hook appears in the song's lyrics.

        Args:
            hook: The detected hook phrase
            artist: Artist name
            title: Song title
            fuzzy_threshold: Minimum similarity for fuzzy matching (0-1)

        Returns:
            VerificationResult with verification status
        """
        # Get lyrics
        lyrics_result = self.get_lyrics(artist, title)

        if not lyrics_result.found or not lyrics_result.lyrics:
            return VerificationResult(
                hook=hook,
                verified=False,
                confidence=0.5,  # Uncertain - couldn't verify
                match_type='none',
                lyrics_source=None,
                lyrics_snippet=None
            )

        lyrics_lower = lyrics_result.lyrics.lower()
        hook_lower = hook.lower()

        # Try exact match
        if hook_lower in lyrics_lower:
            snippet = self._extract_snippet(lyrics_result.lyrics, hook)
            return VerificationResult(
                hook=hook,
                verified=True,
                confidence=1.0,
                match_type='exact',
                lyrics_source=lyrics_result.source,
                lyrics_snippet=snippet
            )

        # Try partial match (hook words appear in sequence)
        partial_match, match_ratio = self._partial_match(hook_lower, lyrics_lower)
        if partial_match and match_ratio >= 0.7:
            return VerificationResult(
                hook=hook,
                verified=True,
                confidence=match_ratio,
                match_type='partial',
                lyrics_source=lyrics_result.source,
                lyrics_snippet=None
            )

        # Try fuzzy match (for transcription errors)
        fuzzy_match, similarity = self._fuzzy_match(hook_lower, lyrics_lower, fuzzy_threshold)
        if fuzzy_match:
            return VerificationResult(
                hook=hook,
                verified=True,
                confidence=similarity,
                match_type='fuzzy',
                lyrics_source=lyrics_result.source,
                lyrics_snippet=fuzzy_match
            )

        # No match found
        return VerificationResult(
            hook=hook,
            verified=False,
            confidence=0.3,  # Low confidence - hook not in lyrics
            match_type='none',
            lyrics_source=lyrics_result.source,
            lyrics_snippet=None
        )

    def _clean_for_api(self, text: str) -> str:
        """Clean artist/title for API queries."""
        # Remove featuring artists, remix info, etc.
        text = re.sub(r'\s*\(.*?\)\s*', ' ', text)
        text = re.sub(r'\s*\[.*?\]\s*', ' ', text)
        text = re.sub(r'\s*feat\.?\s*.*', '', text, flags=re.IGNORECASE)
        text = re.sub(r'\s*ft\.?\s*.*', '', text, flags=re.IGNORECASE)
        text = re.sub(r'\s*-\s*remix.*', '', text, flags=re.IGNORECASE)
        text = re.sub(r'\s*-\s*edit.*', '', text, flags=re.IGNORECASE)
        return text.strip()

    def _try_lyrics_ovh(self, artist: str, title: str) -> LyricsResult:
        """Try to fetch lyrics from Lyrics.ovh API."""
        try:
            if HAS_REQUESTS:
                url = self.LYRICS_OVH_URL.format(
                    artist=requests.utils.quote(artist),
                    title=requests.utils.quote(title)
                )
                response = requests.get(url, headers={'User-Agent': 'CrateBot/1.0'}, timeout=8)
                response.raise_for_status()
                data = response.json()
            else:
                import urllib.parse
                import urllib.request
                url = self.LYRICS_OVH_URL.format(
                    artist=urllib.parse.quote(artist),
                    title=urllib.parse.quote(title)
                )
                request = urllib.request.Request(url, headers={'User-Agent': 'CrateBot/1.0'})
                with urllib.request.urlopen(request, timeout=8) as resp:
                    data = json.loads(resp.read().decode('utf-8'))

            if 'lyrics' in data and data['lyrics']:
                return LyricsResult(
                    lyrics=data['lyrics'],
                    source='lyrics.ovh',
                    artist=artist,
                    title=title,
                    found=True
                )
        except Exception as e:
            logger.debug(f"Lyrics.ovh error for {artist} - {title}: {e}")

        return LyricsResult(lyrics=None, source='lyrics.ovh', artist=artist, title=title, found=False)

    def _try_lrclib(self, artist: str, title: str) -> LyricsResult:
        """Try to fetch lyrics from LRCLIB API."""
        try:
            if HAS_REQUESTS:
                url = self.LRCLIB_URL.format(
                    artist=requests.utils.quote(artist),
                    title=requests.utils.quote(title)
                )
                response = requests.get(url, headers={'User-Agent': 'CrateBot/1.0'}, timeout=10)
                response.raise_for_status()
                data = response.json()
            else:
                import urllib.parse
                import urllib.request
                url = self.LRCLIB_URL.format(
                    artist=urllib.parse.quote(artist),
                    title=urllib.parse.quote(title)
                )
                request = urllib.request.Request(url, headers={'User-Agent': 'CrateBot/1.0'})
                with urllib.request.urlopen(request, timeout=10) as resp:
                    data = json.loads(resp.read().decode('utf-8'))

            # LRCLIB returns plainLyrics or syncedLyrics
            lyrics = data.get('plainLyrics') or data.get('syncedLyrics')
            if lyrics:
                # Clean synced lyrics (remove timestamps)
                if data.get('syncedLyrics') and not data.get('plainLyrics'):
                    lyrics = re.sub(r'\[\d+:\d+\.\d+\]', '', lyrics)

                return LyricsResult(
                    lyrics=lyrics,
                    source='lrclib',
                    artist=artist,
                    title=title,
                    found=True
                )
        except Exception as e:
            logger.debug(f"LRCLIB error for {artist} - {title}: {e}")

        return LyricsResult(lyrics=None, source='lrclib', artist=artist, title=title, found=False)

    def _extract_snippet(self, lyrics: str, hook: str, context_chars: int = 50) -> str:
        """Extract a snippet of lyrics around the hook match."""
        lyrics_lower = lyrics.lower()
        hook_lower = hook.lower()

        pos = lyrics_lower.find(hook_lower)
        if pos == -1:
            return ""

        start = max(0, pos - context_chars)
        end = min(len(lyrics), pos + len(hook) + context_chars)

        snippet = lyrics[start:end]
        if start > 0:
            snippet = "..." + snippet
        if end < len(lyrics):
            snippet = snippet + "..."

        return snippet.replace('\n', ' ').strip()

    def _partial_match(self, hook: str, lyrics: str) -> Tuple[bool, float]:
        """
        Check if hook words appear in sequence in lyrics.

        Returns (matched, ratio) where ratio is the fraction of words matched.
        """
        hook_words = hook.split()
        lyrics_words = lyrics.split()

        if len(hook_words) < 2:
            return False, 0.0

        # Sliding window to find best match
        best_ratio = 0.0

        for i in range(len(lyrics_words) - len(hook_words) + 1):
            window = lyrics_words[i:i + len(hook_words)]
            matches = sum(1 for h, l in zip(hook_words, window) if h == l)
            ratio = matches / len(hook_words)
            best_ratio = max(best_ratio, ratio)

        return best_ratio >= 0.7, best_ratio

    def _fuzzy_match(
        self,
        hook: str,
        lyrics: str,
        threshold: float
    ) -> Tuple[Optional[str], float]:
        """
        Fuzzy match hook against lyrics using simple similarity.

        Returns (matched_text, similarity) or (None, 0) if no match.
        """
        hook_words = hook.split()
        hook_len = len(hook_words)

        if hook_len < 3:
            return None, 0.0

        lyrics_words = lyrics.split()
        best_match = None
        best_similarity = 0.0

        for i in range(len(lyrics_words) - hook_len + 1):
            window = lyrics_words[i:i + hook_len]
            window_text = ' '.join(window)

            # Calculate character-level similarity
            similarity = self._string_similarity(hook, window_text)

            if similarity > best_similarity and similarity >= threshold:
                best_similarity = similarity
                best_match = window_text

        return best_match, best_similarity

    def _string_similarity(self, s1: str, s2: str) -> float:
        """Calculate simple string similarity (0-1)."""
        if not s1 or not s2:
            return 0.0

        # Use longest common subsequence ratio
        m, n = len(s1), len(s2)

        # Simple approach: count matching characters in order
        matches = 0
        j = 0
        for char in s1:
            while j < n:
                if s2[j] == char:
                    matches += 1
                    j += 1
                    break
                j += 1

        return (2.0 * matches) / (m + n)


def is_lyrics_verification_available() -> bool:
    """Check if lyrics verification is available (always True - uses free APIs)."""
    return True


def get_lyrics_verification_status() -> str:
    """Get status of lyrics verification."""
    return "Available (Lyrics.ovh + LRCLIB)"
