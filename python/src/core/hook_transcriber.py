"""
Hook Transcriber - Local vocal transcription and hook detection using faster-whisper.

Transcribes vocals from audio tracks and identifies the most repeated/memorable
hook or phrase for DJ library organization and vibe enrichment.

Uses faster-whisper (CTranslate2 optimized Whisper) for free local transcription.
Optionally verifies detected hooks against lyrics databases (Lyrics.ovh, LRCLIB).
"""

import os
import re
from typing import Dict, Any, Optional, List, Tuple
from dataclasses import dataclass, field
from collections import Counter
import logging

logger = logging.getLogger(__name__)

# Import lyrics verifier for optional hook verification
try:
    from .lyrics_verifier import LyricsVerifier, VerificationResult
    HAS_LYRICS_VERIFIER = True
except ImportError:
    HAS_LYRICS_VERIFIER = False
    LyricsVerifier = None
    VerificationResult = None

# Import lyrics-first hook detector
try:
    from .lyrics_first_hook import LyricsFirstHookDetector
    HAS_LYRICS_FIRST = True
except ImportError:
    HAS_LYRICS_FIRST = False
    LyricsFirstHookDetector = None

# Optional faster-whisper import
try:
    from faster_whisper import WhisperModel
    HAS_WHISPER = True
except ImportError:
    HAS_WHISPER = False


@dataclass
class TranscriptionResult:
    """Result from transcribing an audio file."""
    text: str  # Full transcription
    segments: List[Dict[str, Any]]  # Timestamped segments
    words: List[Dict[str, Any]]  # Word-level timestamps
    language: str
    language_probability: float


@dataclass
class HookResult:
    """Result from hook detection."""
    hook: Optional[str]  # The detected hook phrase
    confidence: float  # How confident we are (0-1)
    occurrences: int  # How many times it appears
    all_phrases: List[Tuple[str, int]]  # All detected phrases with counts
    transcription: str  # Full transcription for reference
    # Lyrics verification fields (optional)
    lyrics_verified: Optional[bool] = None  # True if verified in lyrics, False if not found, None if no lyrics
    lyrics_source: Optional[str] = None  # Source where lyrics were found
    lyrics_match_type: Optional[str] = None  # 'exact', 'partial', 'fuzzy', 'none'


class HookTranscriber:
    """
    Transcribe vocals and detect hooks using local Whisper model.

    Usage:
        transcriber = HookTranscriber()
        result = transcriber.detect_hook("/path/to/track.mp3")
        print(result.hook)  # "let me see you work"
    """

    # Whisper model sizes: tiny, base, small, medium, large-v2, large-v3
    # medium provides better accuracy for music with processed vocals
    DEFAULT_MODEL = "medium"

    # Minimum occurrences for a phrase to be considered a hook
    MIN_OCCURRENCES = 2

    # N-gram sizes to consider for hooks (3-6 words for more complete phrases)
    NGRAM_RANGE = (3, 7)

    # Common filler words to filter out (single words)
    FILLER_WORDS = {
        'yeah', 'oh', 'ah', 'uh', 'um', 'like', 'just', 'got', 'get',
        'la', 'na', 'da', 'ba', 'hey', 'yo', 'aye', 'woo', 'ooh', 'whoa',
        'come', 'go', 'now', 'right', 'know', 'can', 'got', 'gonna',
        'the', 'a', 'an', 'and', 'or', 'but', 'in', 'on', 'at', 'to', 'for',
        'is', 'it', 'be', 'are', 'was', 'were', 'been', 'being',
        'i', 'you', 'we', 'they', 'he', 'she', 'me', 'my', 'your', 'this', 'that',
    }

    # Common filler PHRASES to filter out (these are boring, not catchy hooks)
    FILLER_PHRASES = {
        'come on', 'lets go', 'let go', 'right now', 'one more', 'one more time',
        'you know', 'you know what', 'i know', 'do you', 'can you',
        'in the', 'on the', 'at the', 'to the', 'for the',
        'at the same time', 'the same time', 'same time', 'time at the', 'time at',
        'in the house', 'in the club', 'in the place', 'on the floor',
        'all night', 'all night long', 'all day', 'tonight',
        'one two', 'one two three', 'three two one',
        'here we go', 'here we go again', 'there you go',
        'what you', 'when you', 'if you', 'that you',
        'i want', 'i need', 'i got', 'i can', 'i will',
        'we can', 'we got', 'we are', 'you are', 'they are',
        'its the', 'its a', 'thats the', 'thats a',
        'so good', 'so bad', 'too much', 'so much',
        'like this', 'like that', 'just like', 'the beat',
    }

    # Words that make a phrase more likely to be a real hook (distinctive/catchy)
    HOOK_INDICATOR_WORDS = {
        'work', 'body', 'move', 'dance', 'shake', 'bounce', 'rock', 'roll',
        'love', 'baby', 'fire', 'hot', 'burn', 'heat',
        'party', 'night', 'freak', 'funk', 'groove', 'beat', 'rhythm',
        'drop', 'bass', 'pump', 'jump', 'hands', 'up', 'down',
        'feel', 'feeling', 'free', 'fly', 'high', 'vibe',
        'never', 'forever', 'always', 'again', 'more',
        'master', 'king', 'queen', 'star', 'shine',
        'open', 'close', 'stop', 'start', 'break',
    }

    def __init__(
        self,
        model_size: str = DEFAULT_MODEL,
        device: str = "auto",
        compute_type: str = "auto",
        enable_lyrics_verification: bool = True
    ):
        """
        Initialize the hook transcriber.

        Args:
            model_size: Whisper model size (tiny, base, small, medium, large-v2, large-v3)
            device: Device to use ("auto", "cpu", "cuda")
            compute_type: Compute type ("auto", "int8", "float16", "float32")
            enable_lyrics_verification: Whether to verify hooks against lyrics databases
        """
        self.model_size = model_size
        self.device = device
        self.compute_type = compute_type
        self._model = None

        # Initialize lyrics verifier if available and enabled
        self._lyrics_verifier = None
        if enable_lyrics_verification and HAS_LYRICS_VERIFIER:
            try:
                self._lyrics_verifier = LyricsVerifier()
                logger.info("Lyrics verification enabled")
            except Exception as e:
                logger.warning(f"Could not initialize lyrics verifier: {e}")

    @property
    def is_available(self) -> bool:
        """Check if transcription is available."""
        return HAS_WHISPER

    @property
    def model(self) -> "WhisperModel":
        """Lazy-load the Whisper model."""
        if not HAS_WHISPER:
            raise RuntimeError(
                "faster-whisper not installed. Run: pip install faster-whisper"
            )

        if self._model is None:
            logger.info(f"Loading Whisper model: {self.model_size}")

            # Determine device and compute type
            device = self.device
            compute_type = self.compute_type

            if device == "auto":
                # Try CUDA first, fall back to CPU
                try:
                    import torch
                    device = "cuda" if torch.cuda.is_available() else "cpu"
                except ImportError:
                    device = "cpu"

            if compute_type == "auto":
                # Use int8 for CPU (faster), float16 for GPU
                compute_type = "int8" if device == "cpu" else "float16"

            self._model = WhisperModel(
                self.model_size,
                device=device,
                compute_type=compute_type
            )
            logger.info(f"Whisper model loaded on {device} with {compute_type}")

        return self._model

    def transcribe(
        self,
        audio_path: str,
        language: Optional[str] = "en",
        use_vad: bool = True
    ) -> TranscriptionResult:
        """
        Transcribe an audio file.

        Args:
            audio_path: Path to audio file (MP3, WAV, etc.)
            language: Language code or None for auto-detection
            use_vad: Whether to use voice activity detection (filters non-speech)

        Returns:
            TranscriptionResult with full text and word-level timestamps
        """
        if not os.path.exists(audio_path):
            raise FileNotFoundError(f"Audio file not found: {audio_path}")

        # Transcribe with word timestamps
        if use_vad:
            segments, info = self.model.transcribe(
                audio_path,
                language=language,
                word_timestamps=True,
                vad_filter=True,
                vad_parameters=dict(
                    min_silence_duration_ms=300,  # Less aggressive filtering
                    speech_pad_ms=200,  # Pad detected speech regions
                )
            )
        else:
            segments, info = self.model.transcribe(
                audio_path,
                language=language,
                word_timestamps=True,
                vad_filter=False,
            )

        # Collect results
        all_segments = []
        all_words = []
        full_text_parts = []

        for segment in segments:
            seg_dict = {
                'start': segment.start,
                'end': segment.end,
                'text': segment.text.strip(),
            }
            all_segments.append(seg_dict)
            full_text_parts.append(segment.text.strip())

            # Extract words if available
            if segment.words:
                for word in segment.words:
                    all_words.append({
                        'word': word.word.strip(),
                        'start': word.start,
                        'end': word.end,
                        'probability': word.probability
                    })

        return TranscriptionResult(
            text=' '.join(full_text_parts),
            segments=all_segments,
            words=all_words,
            language=info.language,
            language_probability=info.language_probability
        )

    def detect_hook(
        self,
        audio_path: str,
        language: Optional[str] = "en",
        artist: Optional[str] = None,
        title: Optional[str] = None,
        verify_lyrics: bool = True
    ) -> HookResult:
        """
        Transcribe audio and detect the most prominent hook/phrase.

        Uses VAD (voice activity detection) first to filter non-speech.
        If no vocals detected, falls back to transcribing without VAD.
        Optionally verifies detected hook against lyrics databases.

        Args:
            audio_path: Path to audio file
            language: Language code or None for auto-detection
            artist: Artist name for lyrics verification (optional)
            title: Song title for lyrics verification (optional)
            verify_lyrics: Whether to verify hook against lyrics (requires artist/title)

        Returns:
            HookResult with detected hook and metadata
        """
        # Handle case where Whisper isn't available
        if not self.is_available:
            return HookResult(
                hook=None,
                confidence=0.0,
                occurrences=0,
                all_phrases=[],
                transcription=""
            )

        # Try with VAD first (cleaner, filters instrumentals)
        try:
            result = self.transcribe(audio_path, language, use_vad=True)
        except Exception as e:
            logger.warning(f"Transcription failed for {audio_path}: {e}")
            return HookResult(
                hook=None,
                confidence=0.0,
                occurrences=0,
                all_phrases=[],
                transcription=""
            )

        # If VAD filtered everything, try without VAD
        if not result.text.strip():
            logger.info(f"No vocals with VAD, trying without for {audio_path}")
            try:
                result = self.transcribe(audio_path, language, use_vad=False)
            except Exception as e:
                logger.warning(f"Non-VAD transcription also failed: {e}")

        # Still no transcription = no hook
        if not result.text.strip():
            return HookResult(
                hook=None,
                confidence=0.0,
                occurrences=0,
                all_phrases=[],
                transcription=""
            )

        # Find repeated phrases
        phrases = self._find_repeated_phrases(result)

        if not phrases:
            # No repeated phrases, but we have transcription
            # Return the most common short segment as a fallback
            return HookResult(
                hook=None,
                confidence=0.0,
                occurrences=0,
                all_phrases=[],
                transcription=result.text
            )

        # Best hook is the most repeated meaningful phrase
        best_phrase, best_count = phrases[0]

        # Calculate confidence based on repetition and phrase quality
        confidence = self._calculate_confidence(best_phrase, best_count, result)

        # Initialize lyrics verification fields
        lyrics_verified = None
        lyrics_source = None
        lyrics_match_type = None

        # Verify against lyrics if we have artist/title and verifier is enabled
        if verify_lyrics and self._lyrics_verifier and artist and title:
            verification = self._verify_hook_in_lyrics(best_phrase, artist, title)
            if verification:
                lyrics_verified = verification.verified
                lyrics_source = verification.lyrics_source
                lyrics_match_type = verification.match_type

                # Adjust confidence based on verification
                if verification.verified:
                    # Boost confidence if hook was found in actual lyrics
                    confidence = min(1.0, confidence + 0.15)
                    logger.info(f"Hook '{best_phrase}' verified in lyrics ({verification.match_type})")
                elif verification.lyrics_source:
                    # Lyrics found but hook not in them - lower confidence slightly
                    confidence = max(0.1, confidence - 0.1)
                    logger.info(f"Hook '{best_phrase}' NOT found in lyrics from {verification.lyrics_source}")
                # If no lyrics found, keep confidence as-is (neutral)

        return HookResult(
            hook=best_phrase,
            confidence=confidence,
            occurrences=best_count,
            all_phrases=phrases[:5],  # Top 5 phrases
            transcription=result.text,
            lyrics_verified=lyrics_verified,
            lyrics_source=lyrics_source,
            lyrics_match_type=lyrics_match_type
        )

    def _verify_hook_in_lyrics(
        self,
        hook: str,
        artist: str,
        title: str
    ) -> Optional["VerificationResult"]:
        """
        Verify a hook phrase against lyrics databases.

        Args:
            hook: The detected hook phrase
            artist: Artist name
            title: Song title

        Returns:
            VerificationResult or None if verification failed
        """
        if not self._lyrics_verifier:
            return None

        try:
            return self._lyrics_verifier.verify_hook(hook, artist, title)
        except Exception as e:
            logger.warning(f"Lyrics verification failed for '{artist} - {title}': {e}")
            return None

    def _find_repeated_phrases(
        self,
        result: TranscriptionResult
    ) -> List[Tuple[str, int]]:
        """
        Find repeated phrases (n-grams) in the transcription.

        Returns list of (phrase, count) tuples sorted by hook quality score.
        """
        # Clean and tokenize the text
        text = result.text.lower()
        text = re.sub(r'[^\w\s]', '', text)  # Remove punctuation
        words = text.split()

        if len(words) < self.NGRAM_RANGE[0]:
            return []

        # Generate n-grams of various sizes
        ngram_counts = Counter()

        for n in range(self.NGRAM_RANGE[0], min(self.NGRAM_RANGE[1], len(words) + 1)):
            for i in range(len(words) - n + 1):
                ngram = ' '.join(words[i:i + n])

                # Filter out filler-only phrases
                if not self._is_meaningful_phrase(ngram):
                    continue

                ngram_counts[ngram] += 1

        # Filter to phrases that appear multiple times
        repeated = [
            (phrase, count)
            for phrase, count in ngram_counts.items()
            if count >= self.MIN_OCCURRENCES
        ]

        if not repeated:
            return []

        # Score each phrase by "hook quality" (not just repetition count)
        scored = []
        for phrase, count in repeated:
            score = self._calculate_hook_score(phrase, count, ngram_counts)
            scored.append((phrase, count, score))

        # Sort by hook score (desc)
        scored.sort(key=lambda x: x[2], reverse=True)

        # Remove phrases that are substrings of higher-ranked phrases
        # BUT: if a longer phrase has similar count, prefer it even if shorter is more repeated
        filtered = []
        for phrase, count, score in scored:
            dominated = False
            for existing_phrase, existing_count, _ in filtered:
                # Skip if this phrase is contained in an already-added phrase
                if phrase in existing_phrase:
                    dominated = True
                    break
                # Skip if this is a fragment of a longer phrase with similar count
                if existing_phrase in phrase:
                    # This is a longer version - don't skip it, but remove the shorter one
                    pass

            if not dominated:
                # Check if we should replace a shorter fragment with this longer one
                to_remove = []
                for i, (existing_phrase, existing_count, existing_score) in enumerate(filtered):
                    if existing_phrase in phrase and existing_count <= count + 1:
                        # Existing is a fragment of this phrase with similar count
                        # Remove the fragment, keep the longer phrase
                        to_remove.append(i)

                for i in reversed(to_remove):
                    filtered.pop(i)

                filtered.append((phrase, count, score))

        # Return without scores
        return [(phrase, count) for phrase, count, _ in filtered]

    def _calculate_hook_score(
        self,
        phrase: str,
        count: int,
        all_ngrams: Counter
    ) -> float:
        """
        Calculate a "hook quality" score for a phrase.

        Higher scores for:
        - More repetitions
        - 3-4 word phrases (ideal hook length)
        - Contains hook indicator words (work, body, dance, etc.)
        - Not a fragment of a more common longer phrase

        Lower scores for:
        - Too short (2 words) or too long (5+ words)
        - Generic/boring phrases
        - Fragments of longer phrases
        """
        words = phrase.split()
        word_count = len(words)

        # Base score from repetition count (exponential benefit)
        repetition_score = min(2.0, count * 0.5)

        # Length score: 4-5 words is ideal for complete hooks
        if word_count == 4:
            length_score = 1.6
        elif word_count == 5:
            length_score = 1.5
        elif word_count == 3:
            length_score = 1.2
        elif word_count == 6:
            length_score = 1.0
        else:
            length_score = 0.6  # Penalize very short or very long

        # Hook indicator bonus: does it contain catchy/distinctive words?
        hook_word_count = sum(1 for w in words if w in self.HOOK_INDICATOR_WORDS)
        catchiness_score = 1.0 + (hook_word_count * 0.3)

        # Fragment penalty: if a longer phrase containing this one exists with good count
        fragment_penalty = 1.0
        for longer_phrase, longer_count in all_ngrams.items():
            if phrase != longer_phrase and phrase in longer_phrase:
                if longer_count >= count - 1:
                    # This is likely a fragment of a better phrase
                    fragment_penalty = 0.5
                    break

        # Combine scores
        total_score = repetition_score * length_score * catchiness_score * fragment_penalty

        return total_score

    def _is_meaningful_phrase(self, phrase: str) -> bool:
        """Check if a phrase is meaningful (not just filler words or boring phrases)."""
        words = phrase.split()

        # Too short
        if len(words) < 2:
            return False

        # Check against filler phrases (exact match)
        if phrase in self.FILLER_PHRASES:
            return False

        # Check if phrase CONTAINS any filler phrase (catches "the same time at the")
        for filler in self.FILLER_PHRASES:
            if filler in phrase:
                # The phrase contains a boring pattern - reject it
                # unless the non-filler content is substantial
                remaining = phrase
                for f in self.FILLER_PHRASES:
                    remaining = remaining.replace(f, ' ')
                remaining_words = [w for w in remaining.split() if w and w not in self.FILLER_WORDS]
                if len(remaining_words) < 2:
                    return False

        # Check if phrase starts or ends with very common filler patterns
        boring_starts = ['the ', 'a ', 'an ', 'and ', 'or ', 'but ', 'in ', 'on ', 'at ', 'to ', 'for ', 'is ', 'it ']
        boring_ends = [' the', ' a', ' an', ' and', ' or', ' but', ' in', ' on', ' at', ' to', ' for', ' is', ' it']

        for start in boring_starts:
            if phrase.startswith(start):
                # Allow if rest is meaningful
                rest = phrase[len(start):]
                rest_words = [w for w in rest.split() if w not in self.FILLER_WORDS]
                if len(rest_words) < 2:
                    return False

        for end in boring_ends:
            if phrase.endswith(end):
                # Allow if rest is meaningful
                rest = phrase[:-len(end)]
                rest_words = [w for w in rest.split() if w not in self.FILLER_WORDS]
                if len(rest_words) < 2:
                    return False

        # Count non-filler words
        non_filler = [w for w in words if w not in self.FILLER_WORDS]

        # Must have at least 1 non-filler word
        if len(non_filler) < 1:
            return False

        # For 2-word phrases, both should ideally be meaningful
        if len(words) == 2 and len(non_filler) < 2:
            return False

        # For longer phrases, at least 40% should be non-filler
        if len(words) >= 3 and len(non_filler) < len(words) * 0.4:
            return False

        return True

    def _calculate_confidence(
        self,
        phrase: str,
        count: int,
        result: TranscriptionResult
    ) -> float:
        """
        Calculate confidence score for a detected hook.

        Based on:
        - Repetition count (more = better)
        - Phrase length (2-4 words = ideal)
        - Word probability from Whisper (if available)
        """
        # Base score from repetition (2 occurrences = 0.5, 4+ = 1.0)
        repetition_score = min(1.0, (count - 1) / 3)

        # Phrase length score (3-4 words = ideal)
        word_count = len(phrase.split())
        if word_count in (3, 4):
            length_score = 1.0
        elif word_count in (2, 5):
            length_score = 0.8
        else:
            length_score = 0.6

        # Word probability score (average of word probabilities)
        prob_score = 0.7  # Default if no word-level data
        if result.words:
            phrase_words = set(phrase.split())
            matching_probs = [
                w['probability'] for w in result.words
                if w['word'].lower().strip() in phrase_words
            ]
            if matching_probs:
                prob_score = sum(matching_probs) / len(matching_probs)

        # Weighted average
        confidence = (
            repetition_score * 0.5 +
            length_score * 0.2 +
            prob_score * 0.3
        )

        return round(confidence, 2)


class CachedHookTranscriber:
    """
    Hook transcriber with caching to avoid re-processing files.

    Supports lyrics-first mode which attempts to detect hooks from lyrics
    before falling back to Whisper transcription.
    """

    def __init__(
        self,
        model_size: str = HookTranscriber.DEFAULT_MODEL,
        cache_dir: Optional[str] = None,
        enable_lyrics_verification: bool = True,
        use_lyrics_first: bool = True
    ):
        """
        Initialize cached hook transcriber.

        Args:
            model_size: Whisper model size
            cache_dir: Directory for cache file
            enable_lyrics_verification: Whether to verify hooks against lyrics
            use_lyrics_first: Whether to use lyrics-first mode when artist/title available
        """
        self._model_size = model_size
        self._use_lyrics_first = use_lyrics_first and HAS_LYRICS_FIRST
        self._lyrics_first_detector: Optional['LyricsFirstHookDetector'] = None

        self.transcriber = HookTranscriber(
            model_size=model_size,
            enable_lyrics_verification=enable_lyrics_verification
        )
        self._cache: Dict[str, HookResult] = {}
        self._stats = {'cache_hits': 0, 'transcriptions': 0, 'lyrics_verified': 0, 'lyrics_first_hits': 0}

    @property
    def lyrics_first_detector(self) -> Optional['LyricsFirstHookDetector']:
        """Lazy-load lyrics-first detector on first use."""
        if self._lyrics_first_detector is None and self._use_lyrics_first:
            try:
                self._lyrics_first_detector = LyricsFirstHookDetector(
                    enable_transcription_fallback=True,
                    whisper_model=self._model_size
                )
                logger.debug("LyricsFirstHookDetector initialized")
            except Exception as e:
                logger.warning(f"Could not initialize LyricsFirstHookDetector: {e}")
        return self._lyrics_first_detector

    @property
    def is_available(self) -> bool:
        """Check if transcription is available."""
        return self.transcriber.is_available

    def detect_hook(
        self,
        audio_path: str,
        skip_cache: bool = False,
        artist: Optional[str] = None,
        title: Optional[str] = None,
        verify_lyrics: bool = True
    ) -> HookResult:
        """
        Detect hook with caching.

        Uses lyrics-first mode when artist/title are available and the mode is enabled.
        Falls back to Whisper transcription if lyrics lookup fails or is disabled.

        Args:
            audio_path: Path to audio file
            skip_cache: If True, always re-transcribe
            artist: Artist name for lyrics lookup/verification
            title: Song title for lyrics lookup/verification
            verify_lyrics: Whether to verify hook against lyrics (for transcription fallback)

        Returns:
            HookResult with detected hook
        """
        # Simple in-memory cache by file path
        cache_key = os.path.abspath(audio_path)

        if not skip_cache and cache_key in self._cache:
            self._stats['cache_hits'] += 1
            return self._cache[cache_key]

        # Use lyrics-first if artist/title available and enabled
        if self._use_lyrics_first and artist and title:
            detector = self.lyrics_first_detector
            if detector:
                try:
                    lyrics_result = detector.detect_hook(
                        audio_path=audio_path,
                        artist=artist,
                        title=title
                    )
                    result = lyrics_result.to_hook_result()
                    self._stats['lyrics_first_hits'] += 1

                    if lyrics_result.source == "lyrics":
                        self._stats['lyrics_verified'] += 1

                    # Cache and return
                    self._cache[cache_key] = result
                    return result
                except Exception as e:
                    logger.warning(f"Lyrics-first detection failed for {artist} - {title}: {e}")
                    # Fall through to standard transcription

        # Fall back to standard transcription
        result = self.transcriber.detect_hook(
            audio_path,
            artist=artist,
            title=title,
            verify_lyrics=verify_lyrics
        )
        self._stats['transcriptions'] += 1

        if result.lyrics_verified:
            self._stats['lyrics_verified'] += 1

        # Cache result
        self._cache[cache_key] = result

        return result

    def get_stats(self) -> Dict[str, int]:
        """Get cache statistics."""
        return self._stats.copy()

    def clear_cache(self) -> int:
        """Clear the cache. Returns number of entries removed."""
        count = len(self._cache)
        self._cache = {}
        return count


def is_hook_transcription_available() -> bool:
    """Quick check if hook transcription is available."""
    return HAS_WHISPER


def is_lyrics_verification_available() -> bool:
    """Quick check if lyrics verification is available."""
    return HAS_LYRICS_VERIFIER


def get_hook_transcription_status() -> str:
    """Get human-readable transcription status."""
    if not HAS_WHISPER:
        return "Not installed (pip install faster-whisper)"

    status = "Available"
    if HAS_LYRICS_VERIFIER:
        status += " (+lyrics verification)"
    return status
