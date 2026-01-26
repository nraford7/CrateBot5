"""Tests for the CachedHookTranscriber integration with lyrics-first mode.

Part of Task 4: Integrating LyricsFirstHookDetector into the pipeline.
"""

import pytest
from unittest.mock import Mock, patch, MagicMock

from core.hook_transcriber import (
    CachedHookTranscriber,
    HookResult,
    HAS_LYRICS_FIRST,
)


class TestCachedHookTranscriberInit:
    """Tests for CachedHookTranscriber initialization with lyrics-first mode."""

    def test_default_use_lyrics_first_enabled(self):
        """By default, use_lyrics_first should be True (if available)."""
        transcriber = CachedHookTranscriber()
        assert transcriber._use_lyrics_first == HAS_LYRICS_FIRST

    def test_use_lyrics_first_can_be_disabled(self):
        """use_lyrics_first=False disables lyrics-first mode."""
        transcriber = CachedHookTranscriber(use_lyrics_first=False)
        assert transcriber._use_lyrics_first is False

    def test_lyrics_first_detector_lazy_loaded(self):
        """LyricsFirstHookDetector is not loaded until needed."""
        transcriber = CachedHookTranscriber()
        # Should not be loaded yet
        assert transcriber._lyrics_first_detector is None

    def test_stats_include_lyrics_first_hits(self):
        """Stats dictionary includes lyrics_first_hits counter."""
        transcriber = CachedHookTranscriber()
        stats = transcriber.get_stats()
        assert 'lyrics_first_hits' in stats
        assert stats['lyrics_first_hits'] == 0


class TestCachedHookTranscriberLyricsFirstProperty:
    """Tests for the lyrics_first_detector property."""

    @patch('core.hook_transcriber.LyricsFirstHookDetector')
    def test_lyrics_first_detector_property_creates_instance(self, MockDetector):
        """Property creates LyricsFirstHookDetector on first access."""
        mock_instance = Mock()
        MockDetector.return_value = mock_instance

        transcriber = CachedHookTranscriber(use_lyrics_first=True)

        # Access the property
        detector = transcriber.lyrics_first_detector

        # Should have created an instance
        if HAS_LYRICS_FIRST:
            assert detector is not None
        else:
            # If not available, should be None
            assert detector is None

    def test_lyrics_first_detector_none_when_disabled(self):
        """Property returns None when lyrics-first is disabled."""
        transcriber = CachedHookTranscriber(use_lyrics_first=False)
        assert transcriber.lyrics_first_detector is None


class TestCachedHookTranscriberDetectHookLyricsFirst:
    """Tests for detect_hook using lyrics-first mode."""

    @patch('core.hook_transcriber.LyricsFirstHookDetector')
    def test_detect_hook_uses_lyrics_first_with_artist_title(self, MockDetector):
        """When artist/title provided and lyrics-first enabled, use lyrics-first detection."""
        # Setup mock
        mock_detector_instance = MockDetector.return_value
        mock_lyrics_result = Mock()
        mock_lyrics_result.source = "lyrics"
        mock_lyrics_result.hook = "let me see you work"
        mock_lyrics_result.to_hook_result.return_value = HookResult(
            hook="let me see you work",
            confidence=0.85,
            occurrences=3,
            all_phrases=[("let me see you work", 3)],
            transcription="full lyrics text",
            lyrics_verified=True,
            lyrics_source="lrclib",
            lyrics_match_type="exact"
        )
        mock_detector_instance.detect_hook.return_value = mock_lyrics_result

        transcriber = CachedHookTranscriber(use_lyrics_first=True)
        # Force the detector to be our mock
        transcriber._lyrics_first_detector = mock_detector_instance
        transcriber._use_lyrics_first = True

        result = transcriber.detect_hook(
            audio_path="/path/to/track.mp3",
            artist="Test Artist",
            title="Test Song"
        )

        # Should use lyrics-first
        assert result.hook == "let me see you work"
        assert result.lyrics_verified is True

        # Stats should reflect lyrics-first usage
        stats = transcriber.get_stats()
        assert stats['lyrics_first_hits'] == 1
        assert stats['lyrics_verified'] == 1

    @patch('core.hook_transcriber.LyricsFirstHookDetector')
    def test_detect_hook_falls_back_without_artist_title(self, MockDetector):
        """Without artist/title, fall back to standard transcription."""
        mock_detector_instance = MockDetector.return_value

        transcriber = CachedHookTranscriber(use_lyrics_first=True)
        transcriber._lyrics_first_detector = mock_detector_instance
        transcriber._use_lyrics_first = True

        # Mock the underlying transcriber
        with patch.object(transcriber.transcriber, 'detect_hook') as mock_transcribe:
            mock_transcribe.return_value = HookResult(
                hook="transcribed hook",
                confidence=0.7,
                occurrences=2,
                all_phrases=[("transcribed hook", 2)],
                transcription="full transcription"
            )

            result = transcriber.detect_hook(
                audio_path="/path/to/track.mp3"
                # No artist or title
            )

            # Should use standard transcription
            mock_transcribe.assert_called_once()
            assert result.hook == "transcribed hook"

            # Lyrics-first should NOT have been called
            mock_detector_instance.detect_hook.assert_not_called()

    @patch('core.hook_transcriber.LyricsFirstHookDetector')
    def test_detect_hook_falls_back_on_lyrics_first_error(self, MockDetector):
        """If lyrics-first fails, fall back to standard transcription."""
        mock_detector_instance = MockDetector.return_value
        mock_detector_instance.detect_hook.side_effect = Exception("API Error")

        transcriber = CachedHookTranscriber(use_lyrics_first=True)
        transcriber._lyrics_first_detector = mock_detector_instance
        transcriber._use_lyrics_first = True

        # Mock the underlying transcriber for fallback
        with patch.object(transcriber.transcriber, 'detect_hook') as mock_transcribe:
            mock_transcribe.return_value = HookResult(
                hook="fallback hook",
                confidence=0.6,
                occurrences=2,
                all_phrases=[("fallback hook", 2)],
                transcription="fallback transcription"
            )

            result = transcriber.detect_hook(
                audio_path="/path/to/track.mp3",
                artist="Test Artist",
                title="Test Song"
            )

            # Should fall back to standard transcription
            mock_transcribe.assert_called_once()
            assert result.hook == "fallback hook"


class TestCachedHookTranscriberCaching:
    """Tests for caching behavior with lyrics-first mode."""

    @patch('core.hook_transcriber.LyricsFirstHookDetector')
    def test_cache_hit_skips_lyrics_first(self, MockDetector):
        """Cache hit should skip lyrics-first detection."""
        mock_detector_instance = MockDetector.return_value
        mock_lyrics_result = Mock()
        mock_lyrics_result.source = "lyrics"
        mock_lyrics_result.to_hook_result.return_value = HookResult(
            hook="cached hook",
            confidence=0.8,
            occurrences=2,
            all_phrases=[],
            transcription=""
        )
        mock_detector_instance.detect_hook.return_value = mock_lyrics_result

        transcriber = CachedHookTranscriber(use_lyrics_first=True)
        transcriber._lyrics_first_detector = mock_detector_instance
        transcriber._use_lyrics_first = True

        # First call - should use lyrics-first
        result1 = transcriber.detect_hook(
            audio_path="/tmp/test.mp3",
            artist="Artist",
            title="Title"
        )

        # Second call - should use cache
        result2 = transcriber.detect_hook(
            audio_path="/tmp/test.mp3",
            artist="Artist",
            title="Title"
        )

        # Detector should only be called once
        assert mock_detector_instance.detect_hook.call_count == 1

        # Stats should show cache hit
        stats = transcriber.get_stats()
        assert stats['cache_hits'] == 1
        assert stats['lyrics_first_hits'] == 1

    def test_skip_cache_bypasses_cache(self):
        """skip_cache=True should bypass cache."""
        transcriber = CachedHookTranscriber(use_lyrics_first=False)

        # Pre-populate cache
        transcriber._cache["/tmp/test.mp3"] = HookResult(
            hook="cached",
            confidence=0.9,
            occurrences=3,
            all_phrases=[],
            transcription=""
        )

        # Mock transcriber to return different result
        with patch.object(transcriber.transcriber, 'detect_hook') as mock_transcribe:
            mock_transcribe.return_value = HookResult(
                hook="fresh",
                confidence=0.8,
                occurrences=2,
                all_phrases=[],
                transcription=""
            )

            result = transcriber.detect_hook(
                audio_path="/tmp/test.mp3",
                skip_cache=True
            )

            # Should get fresh result, not cached
            mock_transcribe.assert_called_once()
            assert result.hook == "fresh"


class TestCachedHookTranscriberStats:
    """Tests for statistics tracking."""

    @patch('core.hook_transcriber.LyricsFirstHookDetector')
    def test_stats_track_lyrics_source(self, MockDetector):
        """Stats should track when hook came from lyrics vs transcription."""
        mock_detector_instance = MockDetector.return_value
        mock_lyrics_result = Mock()
        mock_lyrics_result.source = "lyrics"  # Hook from lyrics
        mock_lyrics_result.to_hook_result.return_value = HookResult(
            hook="lyrics hook",
            confidence=0.9,
            occurrences=3,
            all_phrases=[],
            transcription="",
            lyrics_verified=True,
            lyrics_source="lrclib",
            lyrics_match_type="exact"
        )
        mock_detector_instance.detect_hook.return_value = mock_lyrics_result

        transcriber = CachedHookTranscriber(use_lyrics_first=True)
        transcriber._lyrics_first_detector = mock_detector_instance
        transcriber._use_lyrics_first = True

        transcriber.detect_hook(
            audio_path="/tmp/test.mp3",
            artist="Artist",
            title="Title"
        )

        stats = transcriber.get_stats()
        assert stats['lyrics_first_hits'] == 1
        assert stats['lyrics_verified'] == 1

    @patch('core.hook_transcriber.LyricsFirstHookDetector')
    def test_stats_track_transcription_source(self, MockDetector):
        """Stats should track when hook came from transcription."""
        mock_detector_instance = MockDetector.return_value
        mock_lyrics_result = Mock()
        mock_lyrics_result.source = "transcription"  # Hook from transcription, not lyrics
        mock_lyrics_result.to_hook_result.return_value = HookResult(
            hook="transcribed hook",
            confidence=0.7,
            occurrences=2,
            all_phrases=[],
            transcription="full text"
        )
        mock_detector_instance.detect_hook.return_value = mock_lyrics_result

        transcriber = CachedHookTranscriber(use_lyrics_first=True)
        transcriber._lyrics_first_detector = mock_detector_instance
        transcriber._use_lyrics_first = True

        transcriber.detect_hook(
            audio_path="/tmp/test.mp3",
            artist="Artist",
            title="Title"
        )

        stats = transcriber.get_stats()
        assert stats['lyrics_first_hits'] == 1
        # lyrics_verified should NOT be incremented since source was transcription
        assert stats['lyrics_verified'] == 0
