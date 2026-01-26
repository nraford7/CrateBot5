"""
Lyrics-First Hook Detector - Coordinate lyrics fetching and analysis for hook detection.

This module provides a lyrics-first approach to hook detection:
1. First try to fetch lyrics for the track (via LyricsVerifier)
2. Analyze lyrics for repeated phrases and chorus sections (via LyricsAnalyzer)
3. Optionally fall back to Whisper transcription if no lyrics found
4. Optionally verify lyrics-detected hooks appear in the actual audio

Part of the Lyrics-First Hook Detection pipeline (Task 3).
"""

import logging
from typing import Optional, List, Tuple
from dataclasses import dataclass, field

logger = logging.getLogger(__name__)

# Import dependencies - they should all exist from earlier tasks
try:
    from .lyrics_verifier import LyricsVerifier, LyricsResult
    HAS_LYRICS_VERIFIER = True
except ImportError:
    HAS_LYRICS_VERIFIER = False
    LyricsVerifier = None
    LyricsResult = None

try:
    from .lyrics_analyzer import LyricsAnalyzer, ChorusResult
    HAS_LYRICS_ANALYZER = True
except ImportError:
    HAS_LYRICS_ANALYZER = False
    LyricsAnalyzer = None
    ChorusResult = None

try:
    from .hook_transcriber import HookTranscriber, HookResult
    HAS_HOOK_TRANSCRIBER = True
except ImportError:
    HAS_HOOK_TRANSCRIBER = False
    HookTranscriber = None
    HookResult = None


@dataclass
class LyricsFirstResult:
    """Result from lyrics-first hook detection.

    Attributes:
        hook: The detected hook phrase (None if no hook found)
        confidence: Confidence score 0-1
        source: Where the hook came from ("lyrics", "transcription", "none")
        occurrences: How many times the hook appears
        lyrics_source: API source of lyrics (e.g., "lrclib", "lyrics.ovh", None)
        audio_verified: Whether the hook was verified in audio transcription
        all_candidates: All candidate hooks as (phrase, count) tuples
        full_transcription: Full audio transcription (if transcription was used)
    """
    hook: Optional[str]
    confidence: float
    source: str  # "lyrics", "transcription", "none"
    occurrences: int
    lyrics_source: Optional[str]
    audio_verified: Optional[bool] = None
    all_candidates: List[Tuple[str, int]] = field(default_factory=list)
    full_transcription: Optional[str] = None

    def to_hook_result(self) -> "HookResult":
        """Convert to HookResult for backwards compatibility with existing pipeline.

        Returns:
            HookResult with equivalent data
        """
        if not HAS_HOOK_TRANSCRIBER:
            raise RuntimeError("HookResult not available - hook_transcriber not installed")

        return HookResult(
            hook=self.hook,
            confidence=self.confidence,
            occurrences=self.occurrences,
            all_phrases=self.all_candidates,
            transcription=self.full_transcription or "",
            lyrics_verified=self.source == "lyrics",
            lyrics_source=self.lyrics_source,
            lyrics_match_type="exact" if self.source == "lyrics" else None
        )


class LyricsFirstHookDetector:
    """
    Coordinate lyrics fetching and analysis for hook detection.

    This class implements a lyrics-first approach:
    1. Try to fetch lyrics using artist/title
    2. Analyze lyrics for repeated phrases and chorus sections
    3. Fall back to Whisper transcription if no lyrics available
    4. Optionally verify lyrics-detected hooks appear in the audio

    Usage:
        detector = LyricsFirstHookDetector()
        result = detector.detect_hook(
            audio_path="/path/to/track.mp3",
            artist="Artist Name",
            title="Song Title"
        )
        if result.hook:
            print(f"Hook: {result.hook} (from {result.source})")
    """

    def __init__(
        self,
        enable_transcription_fallback: bool = True,
        whisper_model: str = "medium",
        enable_audio_verification: bool = False
    ):
        """
        Initialize the LyricsFirstHookDetector.

        Args:
            enable_transcription_fallback: Whether to fall back to Whisper when no lyrics
            whisper_model: Whisper model size for transcription fallback
            enable_audio_verification: Whether to verify lyrics hooks in audio by default
        """
        self._enable_transcription_fallback = enable_transcription_fallback
        self._whisper_model = whisper_model
        self._enable_audio_verification = enable_audio_verification

        # Lazy-loaded components
        self._lyrics_verifier: Optional[LyricsVerifier] = None
        self._lyrics_analyzer: Optional[LyricsAnalyzer] = None
        self._hook_transcriber: Optional[HookTranscriber] = None

    @property
    def lyrics_verifier(self) -> Optional[LyricsVerifier]:
        """Lazy-load LyricsVerifier on first use."""
        if self._lyrics_verifier is None and HAS_LYRICS_VERIFIER:
            try:
                self._lyrics_verifier = LyricsVerifier()
                logger.debug("LyricsVerifier initialized")
            except Exception as e:
                logger.warning(f"Could not initialize LyricsVerifier: {e}")
        return self._lyrics_verifier

    @property
    def lyrics_analyzer(self) -> Optional[LyricsAnalyzer]:
        """Lazy-load LyricsAnalyzer on first use."""
        if self._lyrics_analyzer is None and HAS_LYRICS_ANALYZER:
            try:
                self._lyrics_analyzer = LyricsAnalyzer()
                logger.debug("LyricsAnalyzer initialized")
            except Exception as e:
                logger.warning(f"Could not initialize LyricsAnalyzer: {e}")
        return self._lyrics_analyzer

    @property
    def hook_transcriber(self) -> Optional[HookTranscriber]:
        """Lazy-load HookTranscriber on first use."""
        if self._hook_transcriber is None and HAS_HOOK_TRANSCRIBER:
            try:
                self._hook_transcriber = HookTranscriber(
                    model_size=self._whisper_model,
                    enable_lyrics_verification=False  # We handle verification ourselves
                )
                logger.debug(f"HookTranscriber initialized with model: {self._whisper_model}")
            except Exception as e:
                logger.warning(f"Could not initialize HookTranscriber: {e}")
        return self._hook_transcriber

    def detect_hook(
        self,
        audio_path: str,
        artist: Optional[str] = None,
        title: Optional[str] = None,
        verify_audio: bool = False
    ) -> LyricsFirstResult:
        """
        Detect the hook phrase for a track using lyrics-first approach.

        Args:
            audio_path: Path to the audio file
            artist: Artist name (optional, enables lyrics lookup)
            title: Song title (optional, enables lyrics lookup)
            verify_audio: Whether to verify lyrics hook in audio transcription

        Returns:
            LyricsFirstResult with detected hook and metadata
        """
        # Handle empty audio path
        if not audio_path:
            logger.warning("Empty audio path provided")
            return LyricsFirstResult(
                hook=None,
                confidence=0.0,
                source="none",
                occurrences=0,
                lyrics_source=None,
                audio_verified=None,
                all_candidates=[],
                full_transcription=None
            )

        # Try lyrics-first approach if we have artist and title
        if artist and title:
            try:
                lyrics_result = self._get_lyrics(artist, title)

                if lyrics_result and lyrics_result.found and lyrics_result.lyrics:
                    # Analyze lyrics for hook
                    result = self._detect_from_lyrics(
                        lyrics=lyrics_result.lyrics,
                        audio_path=audio_path,
                        verify_audio=verify_audio or self._enable_audio_verification,
                        lyrics_source=lyrics_result.source
                    )

                    if result.hook:
                        return result

                    # Lyrics found but no hook detected (instrumental or no repetition)
                    # Fall through to transcription if enabled

            except Exception as e:
                logger.warning(f"Lyrics lookup/analysis failed for {artist} - {title}: {e}")

        # Fall back to transcription if enabled
        if self._enable_transcription_fallback:
            return self._detect_from_transcription(audio_path, artist, title)

        # No hook found and no fallback
        return LyricsFirstResult(
            hook=None,
            confidence=0.0,
            source="none",
            occurrences=0,
            lyrics_source=None,
            audio_verified=None,
            all_candidates=[],
            full_transcription=None
        )

    def _get_lyrics(self, artist: str, title: str) -> Optional[LyricsResult]:
        """
        Fetch lyrics using LyricsVerifier.

        Args:
            artist: Artist name
            title: Song title

        Returns:
            LyricsResult or None if verifier unavailable
        """
        verifier = self.lyrics_verifier
        if verifier is None:
            logger.debug("LyricsVerifier not available")
            return None

        try:
            return verifier.get_lyrics(artist, title)
        except Exception as e:
            logger.warning(f"Error fetching lyrics: {e}")
            return None

    def _detect_from_lyrics(
        self,
        lyrics: str,
        audio_path: str,
        verify_audio: bool,
        lyrics_source: str
    ) -> LyricsFirstResult:
        """
        Analyze lyrics to detect hook phrase.

        Args:
            lyrics: Raw lyrics text
            audio_path: Path to audio file (for optional verification)
            verify_audio: Whether to verify hook in audio
            lyrics_source: Source of the lyrics (e.g., "lrclib")

        Returns:
            LyricsFirstResult with detected hook
        """
        analyzer = self.lyrics_analyzer
        if analyzer is None:
            logger.debug("LyricsAnalyzer not available")
            return LyricsFirstResult(
                hook=None,
                confidence=0.0,
                source="none",
                occurrences=0,
                lyrics_source=lyrics_source,
                audio_verified=None,
                all_candidates=[],
                full_transcription=None
            )

        # Detect chorus and extract hook
        chorus_result = analyzer.detect_chorus(lyrics)

        # Handle instrumental tracks
        if chorus_result.is_instrumental:
            return LyricsFirstResult(
                hook=None,
                confidence=chorus_result.confidence,
                source="lyrics",
                occurrences=0,
                lyrics_source=lyrics_source,
                audio_verified=None,
                all_candidates=[],
                full_transcription=None
            )

        # Find repeated phrases for candidates
        repeated_phrases = analyzer.find_repeated_phrases(lyrics)

        # Get the hook (either from chorus or repeated phrases)
        hook = chorus_result.chorus_text
        occurrences = chorus_result.repetitions

        if not hook and repeated_phrases:
            hook, occurrences = repeated_phrases[0]

        if not hook:
            return LyricsFirstResult(
                hook=None,
                confidence=0.3,
                source="lyrics",
                occurrences=0,
                lyrics_source=lyrics_source,
                audio_verified=None,
                all_candidates=repeated_phrases[:5],
                full_transcription=None
            )

        # Calculate confidence
        confidence = self._calculate_lyrics_confidence(hook, occurrences, repeated_phrases)

        # Optionally verify in audio
        audio_verified = None
        full_transcription = None

        if verify_audio:
            verified, transcription = self._verify_in_audio(audio_path, hook)
            audio_verified = verified
            full_transcription = transcription

            # Boost confidence if verified
            if verified:
                confidence = min(1.0, confidence + 0.15)

        return LyricsFirstResult(
            hook=hook,
            confidence=confidence,
            source="lyrics",
            occurrences=occurrences,
            lyrics_source=lyrics_source,
            audio_verified=audio_verified,
            all_candidates=repeated_phrases[:5],
            full_transcription=full_transcription
        )

    def _detect_from_transcription(
        self,
        audio_path: str,
        artist: Optional[str],
        title: Optional[str]
    ) -> LyricsFirstResult:
        """
        Detect hook using Whisper transcription fallback.

        Args:
            audio_path: Path to audio file
            artist: Artist name (for metadata)
            title: Song title (for metadata)

        Returns:
            LyricsFirstResult from transcription
        """
        transcriber = self.hook_transcriber

        if transcriber is None or not transcriber.is_available:
            logger.debug("HookTranscriber not available")
            return LyricsFirstResult(
                hook=None,
                confidence=0.0,
                source="none",
                occurrences=0,
                lyrics_source=None,
                audio_verified=None,
                all_candidates=[],
                full_transcription=None
            )

        try:
            hook_result = transcriber.detect_hook(
                audio_path=audio_path,
                artist=artist,
                title=title,
                verify_lyrics=False  # We've already tried lyrics
            )

            return LyricsFirstResult(
                hook=hook_result.hook,
                confidence=hook_result.confidence,
                source="transcription",
                occurrences=hook_result.occurrences,
                lyrics_source=None,
                audio_verified=None,  # Transcription is the audio itself
                all_candidates=hook_result.all_phrases,
                full_transcription=hook_result.transcription
            )

        except Exception as e:
            logger.warning(f"Transcription failed for {audio_path}: {e}")
            return LyricsFirstResult(
                hook=None,
                confidence=0.0,
                source="none",
                occurrences=0,
                lyrics_source=None,
                audio_verified=None,
                all_candidates=[],
                full_transcription=None
            )

    def _verify_in_audio(self, audio_path: str, hook: str) -> Tuple[bool, Optional[str]]:
        """
        Verify that a lyrics-detected hook appears in the audio transcription.

        Args:
            audio_path: Path to audio file
            hook: Hook phrase to verify

        Returns:
            Tuple of (verified: bool, transcription: Optional[str])
        """
        transcriber = self.hook_transcriber

        if transcriber is None or not transcriber.is_available:
            logger.debug("Cannot verify - HookTranscriber not available")
            return False, None

        try:
            # Get transcription
            transcription_result = transcriber.transcribe(audio_path)
            full_text = transcription_result.text.lower()

            # Check if hook appears in transcription
            hook_lower = hook.lower()
            verified = hook_lower in full_text

            if verified:
                logger.debug(f"Hook '{hook}' verified in audio transcription")
            else:
                logger.debug(f"Hook '{hook}' NOT found in audio transcription")

            return verified, transcription_result.text

        except Exception as e:
            logger.warning(f"Audio verification failed: {e}")
            return False, None

    def _calculate_lyrics_confidence(
        self,
        hook: str,
        occurrences: int,
        all_candidates: List[Tuple[str, int]]
    ) -> float:
        """
        Calculate confidence score for a lyrics-detected hook.

        Factors:
        - Repetition count (more = higher confidence)
        - Whether hook is clearly the best candidate
        - Phrase length (3-5 words ideal)

        Args:
            hook: The detected hook phrase
            occurrences: How many times it appears
            all_candidates: All candidate phrases with counts

        Returns:
            Confidence score 0-1
        """
        # Base score from repetitions
        if occurrences >= 4:
            repetition_score = 0.9
        elif occurrences >= 3:
            repetition_score = 0.75
        elif occurrences >= 2:
            repetition_score = 0.6
        else:
            repetition_score = 0.4

        # Phrase length score (3-5 words ideal)
        word_count = len(hook.split())
        if 3 <= word_count <= 5:
            length_score = 1.0
        elif word_count == 2 or word_count == 6:
            length_score = 0.8
        else:
            length_score = 0.6

        # Dominance score - is this clearly the best candidate?
        dominance_score = 1.0
        if all_candidates and len(all_candidates) > 1:
            top_count = all_candidates[0][1]
            second_count = all_candidates[1][1] if len(all_candidates) > 1 else 0

            if top_count > second_count * 1.5:
                dominance_score = 1.0  # Clearly dominant
            elif top_count > second_count:
                dominance_score = 0.85  # Somewhat dominant
            else:
                dominance_score = 0.7  # Not clearly dominant

        # Combine scores
        confidence = (repetition_score * 0.5 + length_score * 0.2 + dominance_score * 0.3)

        # Lyrics source provides baseline confidence boost
        confidence = min(1.0, confidence + 0.1)

        return round(confidence, 2)


def is_lyrics_first_detection_available() -> bool:
    """Check if lyrics-first hook detection is available."""
    return HAS_LYRICS_VERIFIER and HAS_LYRICS_ANALYZER


def get_lyrics_first_status() -> str:
    """Get human-readable status of lyrics-first detection."""
    components = []

    if HAS_LYRICS_VERIFIER:
        components.append("LyricsVerifier")
    if HAS_LYRICS_ANALYZER:
        components.append("LyricsAnalyzer")
    if HAS_HOOK_TRANSCRIBER:
        components.append("HookTranscriber (fallback)")

    if not components:
        return "Not available - missing dependencies"

    return f"Available ({', '.join(components)})"
