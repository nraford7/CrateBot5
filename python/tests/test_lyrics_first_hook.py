"""Tests for the LyricsFirstHookDetector module - Main coordinator for lyrics-first hook detection.

This module tests the LyricsFirstHookDetector which coordinates:
1. Fetching lyrics via LyricsVerifier
2. Analyzing lyrics for hooks via LyricsAnalyzer
3. Falling back to Whisper transcription when lyrics unavailable
4. Optionally verifying lyrics-detected hooks appear in audio

Part of the Lyrics-First Hook Detection pipeline (Task 3).
"""

import pytest
from unittest.mock import Mock, patch
from dataclasses import dataclass

from core.lyrics_first_hook import LyricsFirstHookDetector, LyricsFirstResult


class TestLyricsFirstResultDataclass:
    """Tests for the LyricsFirstResult dataclass."""

    def test_lyrics_first_result_has_required_fields(self):
        """LyricsFirstResult has all required fields."""
        result = LyricsFirstResult(
            hook="let me see you work",
            confidence=0.9,
            source="lyrics",
            occurrences=3,
            lyrics_source="lrclib",
            audio_verified=True,
            all_candidates=[("let me see you work", 3), ("on the floor", 2)],
            full_transcription=None
        )
        assert result.hook == "let me see you work"
        assert result.confidence == 0.9
        assert result.source == "lyrics"
        assert result.occurrences == 3
        assert result.lyrics_source == "lrclib"
        assert result.audio_verified is True
        assert len(result.all_candidates) == 2
        assert result.full_transcription is None

    def test_lyrics_first_result_no_hook(self):
        """LyricsFirstResult correctly represents no hook found."""
        result = LyricsFirstResult(
            hook=None,
            confidence=0.0,
            source="none",
            occurrences=0,
            lyrics_source=None,
            audio_verified=False,
            all_candidates=[],
            full_transcription=None
        )
        assert result.hook is None
        assert result.source == "none"

    def test_to_hook_result_conversion(self):
        """LyricsFirstResult.to_hook_result() provides backwards compatibility."""
        result = LyricsFirstResult(
            hook="feel the rhythm",
            confidence=0.85,
            source="lyrics",
            occurrences=2,
            lyrics_source="lyrics.ovh",
            audio_verified=False,
            all_candidates=[("feel the rhythm", 2)],
            full_transcription="feel the rhythm tonight feel the rhythm"
        )
        hook_result = result.to_hook_result()
        # Should convert to HookResult format
        assert hook_result.hook == "feel the rhythm"
        assert hook_result.confidence == 0.85
        assert hook_result.occurrences == 2
        assert hook_result.transcription == "feel the rhythm tonight feel the rhythm"


class TestLyricsFirstHookDetectorInit:
    """Tests for LyricsFirstHookDetector initialization."""

    def test_detector_instantiation_default_params(self):
        """LyricsFirstHookDetector can be instantiated with defaults."""
        detector = LyricsFirstHookDetector()
        assert detector is not None
        assert detector._enable_transcription_fallback is True
        assert detector._whisper_model == "medium"
        assert detector._enable_audio_verification is False

    def test_detector_custom_params(self):
        """LyricsFirstHookDetector accepts custom parameters."""
        detector = LyricsFirstHookDetector(
            enable_transcription_fallback=False,
            whisper_model="large-v3",
            enable_audio_verification=True
        )
        assert detector._enable_transcription_fallback is False
        assert detector._whisper_model == "large-v3"
        assert detector._enable_audio_verification is True

    def test_detector_lazy_loads_components(self):
        """LyricsFirstHookDetector lazy-loads components on first use."""
        detector = LyricsFirstHookDetector()
        # Components should not be loaded yet
        assert detector._lyrics_verifier is None
        assert detector._lyrics_analyzer is None
        assert detector._hook_transcriber is None


class TestDetectHookWithLyricsFound:
    """Test: Return hook from lyrics when available."""

    @patch('core.lyrics_first_hook.LyricsVerifier')
    @patch('core.lyrics_first_hook.LyricsAnalyzer')
    def test_detect_hook_with_lyrics_found(self, MockAnalyzer, MockVerifier):
        """When lyrics are available, return hook from lyrics analysis."""
        # Setup mocks
        mock_verifier_instance = MockVerifier.return_value
        mock_analyzer_instance = MockAnalyzer.return_value

        # Mock lyrics found
        mock_lyrics_result = Mock()
        mock_lyrics_result.found = True
        mock_lyrics_result.lyrics = "Let me see you work\nOn the floor\nLet me see you work"
        mock_lyrics_result.source = "lrclib"
        mock_verifier_instance.get_lyrics.return_value = mock_lyrics_result

        # Mock chorus detection
        mock_chorus_result = Mock()
        mock_chorus_result.chorus_text = "let me see you work"
        mock_chorus_result.confidence = 0.9
        mock_chorus_result.repetitions = 3
        mock_chorus_result.is_instrumental = False
        mock_analyzer_instance.detect_chorus.return_value = mock_chorus_result
        mock_analyzer_instance.find_repeated_phrases.return_value = [
            ("let me see you work", 3),
            ("on the floor", 2)
        ]

        detector = LyricsFirstHookDetector()
        result = detector.detect_hook(
            audio_path="/path/to/track.mp3",
            artist="Test Artist",
            title="Test Song"
        )

        assert result.hook == "let me see you work"
        assert result.source == "lyrics"
        assert result.lyrics_source == "lrclib"
        assert result.confidence > 0.5


class TestDetectHookNoLyricsNoFallback:
    """Test: Return None when no lyrics and fallback disabled."""

    @patch('core.lyrics_first_hook.LyricsVerifier')
    def test_detect_hook_no_lyrics_no_fallback(self, MockVerifier):
        """When lyrics not found and fallback disabled, return None hook."""
        mock_verifier_instance = MockVerifier.return_value

        # Mock no lyrics found
        mock_lyrics_result = Mock()
        mock_lyrics_result.found = False
        mock_lyrics_result.lyrics = None
        mock_lyrics_result.source = "none"
        mock_verifier_instance.get_lyrics.return_value = mock_lyrics_result

        detector = LyricsFirstHookDetector(enable_transcription_fallback=False)
        result = detector.detect_hook(
            audio_path="/path/to/track.mp3",
            artist="Unknown Artist",
            title="Unknown Song"
        )

        assert result.hook is None
        assert result.source == "none"
        assert result.confidence == 0.0


class TestDetectHookUsesTranscriptionFallback:
    """Test: Fall back to transcription when no lyrics available."""

    @patch('core.lyrics_first_hook.HookTranscriber')
    @patch('core.lyrics_first_hook.LyricsVerifier')
    def test_detect_hook_uses_transcription_fallback(self, MockVerifier, MockTranscriber):
        """When no lyrics found, fall back to Whisper transcription."""
        mock_verifier_instance = MockVerifier.return_value
        mock_transcriber_instance = MockTranscriber.return_value

        # Mock no lyrics found
        mock_lyrics_result = Mock()
        mock_lyrics_result.found = False
        mock_lyrics_result.lyrics = None
        mock_verifier_instance.get_lyrics.return_value = mock_lyrics_result

        # Mock transcription fallback
        mock_hook_result = Mock()
        mock_hook_result.hook = "transcribed hook phrase"
        mock_hook_result.confidence = 0.7
        mock_hook_result.occurrences = 2
        mock_hook_result.all_phrases = [("transcribed hook phrase", 2)]
        mock_hook_result.transcription = "full transcription text"
        mock_transcriber_instance.is_available = True
        mock_transcriber_instance.detect_hook.return_value = mock_hook_result

        detector = LyricsFirstHookDetector(enable_transcription_fallback=True)
        result = detector.detect_hook(
            audio_path="/path/to/track.mp3",
            artist="Unknown Artist",
            title="Unknown Song"
        )

        assert result.hook == "transcribed hook phrase"
        assert result.source == "transcription"
        assert result.full_transcription == "full transcription text"


class TestDetectHookVerifiesAgainstAudio:
    """Test: Verify lyrics-detected hook appears in audio transcription."""

    @patch('core.lyrics_first_hook.HookTranscriber')
    @patch('core.lyrics_first_hook.LyricsAnalyzer')
    @patch('core.lyrics_first_hook.LyricsVerifier')
    def test_detect_hook_verifies_against_audio(self, MockVerifier, MockAnalyzer, MockTranscriber):
        """When verify_audio=True, verify hook appears in transcription."""
        mock_verifier_instance = MockVerifier.return_value
        mock_analyzer_instance = MockAnalyzer.return_value
        mock_transcriber_instance = MockTranscriber.return_value

        # Mock lyrics found
        mock_lyrics_result = Mock()
        mock_lyrics_result.found = True
        mock_lyrics_result.lyrics = "Let me see you work on the floor"
        mock_lyrics_result.source = "lrclib"
        mock_verifier_instance.get_lyrics.return_value = mock_lyrics_result

        # Mock chorus detection
        mock_chorus_result = Mock()
        mock_chorus_result.chorus_text = "let me see you work"
        mock_chorus_result.confidence = 0.9
        mock_chorus_result.repetitions = 2
        mock_chorus_result.is_instrumental = False
        mock_analyzer_instance.detect_chorus.return_value = mock_chorus_result
        mock_analyzer_instance.find_repeated_phrases.return_value = [("let me see you work", 2)]

        # Mock transcription for verification
        mock_hook_result = Mock()
        mock_hook_result.hook = "let me see you work"
        mock_hook_result.transcription = "let me see you work on the floor tonight"
        mock_transcriber_instance.is_available = True
        mock_transcriber_instance.transcribe.return_value = Mock(
            text="let me see you work on the floor tonight"
        )

        detector = LyricsFirstHookDetector(enable_audio_verification=True)
        result = detector.detect_hook(
            audio_path="/path/to/track.mp3",
            artist="Test Artist",
            title="Test Song",
            verify_audio=True
        )

        assert result.hook == "let me see you work"
        assert result.audio_verified is True


class TestDetectHookNoArtistTitle:
    """Test: Handle missing artist/title gracefully."""

    @patch('core.lyrics_first_hook.HookTranscriber')
    def test_detect_hook_no_artist_title(self, MockTranscriber):
        """When no artist/title provided, skip lyrics lookup and use transcription."""
        mock_transcriber_instance = MockTranscriber.return_value

        # Mock transcription
        mock_hook_result = Mock()
        mock_hook_result.hook = "some transcribed hook"
        mock_hook_result.confidence = 0.6
        mock_hook_result.occurrences = 2
        mock_hook_result.all_phrases = [("some transcribed hook", 2)]
        mock_hook_result.transcription = "full transcription"
        mock_transcriber_instance.is_available = True
        mock_transcriber_instance.detect_hook.return_value = mock_hook_result

        detector = LyricsFirstHookDetector()
        # No artist or title provided
        result = detector.detect_hook(audio_path="/path/to/track.mp3")

        # Should still work via transcription fallback
        assert result.hook == "some transcribed hook"
        assert result.source == "transcription"
        assert result.lyrics_source is None


class TestConfidenceBoostedWhenLyricsVerified:
    """Test: Higher confidence for lyrics-sourced hooks verified in audio."""

    @patch('core.lyrics_first_hook.HookTranscriber')
    @patch('core.lyrics_first_hook.LyricsAnalyzer')
    @patch('core.lyrics_first_hook.LyricsVerifier')
    def test_confidence_boosted_when_lyrics_verified(self, MockVerifier, MockAnalyzer, MockTranscriber):
        """Confidence should be higher when lyrics hook is verified in audio."""
        mock_verifier_instance = MockVerifier.return_value
        mock_analyzer_instance = MockAnalyzer.return_value
        mock_transcriber_instance = MockTranscriber.return_value

        # Mock lyrics found
        mock_lyrics_result = Mock()
        mock_lyrics_result.found = True
        mock_lyrics_result.lyrics = "Feel the rhythm of the night"
        mock_lyrics_result.source = "lrclib"
        mock_verifier_instance.get_lyrics.return_value = mock_lyrics_result

        # Mock chorus detection
        mock_chorus_result = Mock()
        mock_chorus_result.chorus_text = "feel the rhythm"
        mock_chorus_result.confidence = 0.7
        mock_chorus_result.repetitions = 2
        mock_chorus_result.is_instrumental = False
        mock_analyzer_instance.detect_chorus.return_value = mock_chorus_result
        mock_analyzer_instance.find_repeated_phrases.return_value = [("feel the rhythm", 2)]

        # Mock transcription shows hook is present (verified)
        mock_transcriber_instance.is_available = True
        mock_transcriber_instance.transcribe.return_value = Mock(
            text="feel the rhythm of the night feel the rhythm"
        )

        detector = LyricsFirstHookDetector(enable_audio_verification=True)

        # Test without audio verification
        result_unverified = detector.detect_hook(
            audio_path="/path/to/track.mp3",
            artist="Test Artist",
            title="Test Song",
            verify_audio=False
        )

        # Test with audio verification
        result_verified = detector.detect_hook(
            audio_path="/path/to/track.mp3",
            artist="Test Artist",
            title="Test Song",
            verify_audio=True
        )

        # Verified hook should have higher confidence
        assert result_verified.audio_verified is True
        assert result_verified.confidence >= result_unverified.confidence


class TestReturnsAllCandidateHooks:
    """Test: Return multiple hook candidates."""

    @patch('core.lyrics_first_hook.LyricsAnalyzer')
    @patch('core.lyrics_first_hook.LyricsVerifier')
    def test_returns_all_candidate_hooks(self, MockVerifier, MockAnalyzer):
        """Should return all candidate hooks, not just the best one."""
        mock_verifier_instance = MockVerifier.return_value
        mock_analyzer_instance = MockAnalyzer.return_value

        # Mock lyrics found
        mock_lyrics_result = Mock()
        mock_lyrics_result.found = True
        mock_lyrics_result.lyrics = "Work it out\nFeel the beat\nWork it out\nMove your feet\nWork it out"
        mock_lyrics_result.source = "lrclib"
        mock_verifier_instance.get_lyrics.return_value = mock_lyrics_result

        # Mock chorus detection with multiple candidates
        mock_chorus_result = Mock()
        mock_chorus_result.chorus_text = "work it out"
        mock_chorus_result.confidence = 0.8
        mock_chorus_result.repetitions = 3
        mock_chorus_result.is_instrumental = False
        mock_analyzer_instance.detect_chorus.return_value = mock_chorus_result
        mock_analyzer_instance.find_repeated_phrases.return_value = [
            ("work it out", 3),
            ("feel the beat", 2),
            ("move your feet", 2)
        ]

        detector = LyricsFirstHookDetector()
        result = detector.detect_hook(
            audio_path="/path/to/track.mp3",
            artist="Test Artist",
            title="Test Song"
        )

        assert result.hook == "work it out"  # Best candidate
        assert len(result.all_candidates) >= 2  # Multiple candidates returned
        candidate_hooks = [c[0] for c in result.all_candidates]
        assert "work it out" in candidate_hooks


class TestLyricsFirstHookDetectorMethods:
    """Tests for internal methods."""

    def test_has_required_methods(self):
        """LyricsFirstHookDetector has all required methods."""
        detector = LyricsFirstHookDetector()
        assert hasattr(detector, 'detect_hook')
        assert hasattr(detector, '_get_lyrics')
        assert hasattr(detector, '_detect_from_lyrics')
        assert hasattr(detector, '_detect_from_transcription')
        assert hasattr(detector, '_verify_in_audio')
        assert hasattr(detector, '_calculate_lyrics_confidence')
        assert callable(detector.detect_hook)

    @patch('core.lyrics_first_hook.LyricsVerifier')
    def test_get_lyrics_method(self, MockVerifier):
        """_get_lyrics fetches lyrics via LyricsVerifier."""
        mock_verifier_instance = MockVerifier.return_value
        mock_lyrics_result = Mock()
        mock_lyrics_result.found = True
        mock_lyrics_result.lyrics = "test lyrics"
        mock_verifier_instance.get_lyrics.return_value = mock_lyrics_result

        detector = LyricsFirstHookDetector()
        result = detector._get_lyrics("Artist", "Title")

        assert result is not None
        mock_verifier_instance.get_lyrics.assert_called_once_with("Artist", "Title")


class TestEdgeCases:
    """Edge cases and error handling."""

    @patch('core.lyrics_first_hook.LyricsVerifier')
    @patch('core.lyrics_first_hook.LyricsAnalyzer')
    def test_instrumental_track(self, MockAnalyzer, MockVerifier):
        """Handle instrumental tracks correctly."""
        mock_verifier_instance = MockVerifier.return_value
        mock_analyzer_instance = MockAnalyzer.return_value

        # Mock lyrics found but instrumental
        mock_lyrics_result = Mock()
        mock_lyrics_result.found = True
        mock_lyrics_result.lyrics = "[Instrumental]"
        mock_lyrics_result.source = "lrclib"
        mock_verifier_instance.get_lyrics.return_value = mock_lyrics_result

        # Mock chorus detection returns instrumental
        mock_chorus_result = Mock()
        mock_chorus_result.chorus_text = None
        mock_chorus_result.confidence = 0.95
        mock_chorus_result.repetitions = 0
        mock_chorus_result.is_instrumental = True
        mock_analyzer_instance.detect_chorus.return_value = mock_chorus_result

        detector = LyricsFirstHookDetector(enable_transcription_fallback=False)
        result = detector.detect_hook(
            audio_path="/path/to/track.mp3",
            artist="DJ Producer",
            title="Instrumental Beat"
        )

        assert result.hook is None

    @patch('core.lyrics_first_hook.LyricsVerifier')
    def test_lyrics_api_error_handled(self, MockVerifier):
        """Handle API errors gracefully."""
        mock_verifier_instance = MockVerifier.return_value
        mock_verifier_instance.get_lyrics.side_effect = Exception("API Error")

        detector = LyricsFirstHookDetector(enable_transcription_fallback=False)
        result = detector.detect_hook(
            audio_path="/path/to/track.mp3",
            artist="Test Artist",
            title="Test Song"
        )

        # Should handle error gracefully
        assert result is not None
        assert result.hook is None or result.source == "transcription"

    def test_empty_audio_path_raises(self):
        """Empty audio path should raise or return gracefully."""
        detector = LyricsFirstHookDetector(enable_transcription_fallback=False)
        # Should either raise ValueError or return empty result
        try:
            result = detector.detect_hook(audio_path="")
            assert result.hook is None
        except ValueError:
            pass  # Also acceptable


class TestIntegration:
    """Integration tests for complete workflow."""

    @patch('core.lyrics_first_hook.HookTranscriber')
    @patch('core.lyrics_first_hook.LyricsAnalyzer')
    @patch('core.lyrics_first_hook.LyricsVerifier')
    def test_full_lyrics_workflow(self, MockVerifier, MockAnalyzer, MockTranscriber):
        """Complete workflow: lyrics found -> analyze -> return hook."""
        mock_verifier_instance = MockVerifier.return_value
        mock_analyzer_instance = MockAnalyzer.return_value
        mock_transcriber_instance = MockTranscriber.return_value

        # Setup complete mock chain
        mock_lyrics_result = Mock()
        mock_lyrics_result.found = True
        mock_lyrics_result.lyrics = "Shake your body down to the ground\nShake your body down\nMove around"
        mock_lyrics_result.source = "lrclib"
        mock_verifier_instance.get_lyrics.return_value = mock_lyrics_result

        mock_chorus_result = Mock()
        mock_chorus_result.chorus_text = "shake your body down"
        mock_chorus_result.confidence = 0.85
        mock_chorus_result.repetitions = 2
        mock_chorus_result.is_instrumental = False
        mock_analyzer_instance.detect_chorus.return_value = mock_chorus_result
        mock_analyzer_instance.find_repeated_phrases.return_value = [
            ("shake your body down", 2)
        ]
        mock_analyzer_instance.extract_hook_phrase.return_value = "shake your body down"

        detector = LyricsFirstHookDetector()
        result = detector.detect_hook(
            audio_path="/path/to/track.mp3",
            artist="Test Artist",
            title="Test Song"
        )

        assert result.hook == "shake your body down"
        assert result.source == "lyrics"
        assert result.lyrics_source == "lrclib"
        assert result.confidence > 0

    @patch('core.lyrics_first_hook.HookTranscriber')
    @patch('core.lyrics_first_hook.LyricsVerifier')
    def test_full_transcription_fallback_workflow(self, MockVerifier, MockTranscriber):
        """Complete workflow: no lyrics -> transcription fallback -> return hook."""
        mock_verifier_instance = MockVerifier.return_value
        mock_transcriber_instance = MockTranscriber.return_value

        # No lyrics found
        mock_lyrics_result = Mock()
        mock_lyrics_result.found = False
        mock_lyrics_result.lyrics = None
        mock_verifier_instance.get_lyrics.return_value = mock_lyrics_result

        # Transcription fallback works
        mock_hook_result = Mock()
        mock_hook_result.hook = "feel the beat drop"
        mock_hook_result.confidence = 0.65
        mock_hook_result.occurrences = 3
        mock_hook_result.all_phrases = [("feel the beat drop", 3)]
        mock_hook_result.transcription = "feel the beat drop in the night feel the beat drop"
        mock_transcriber_instance.is_available = True
        mock_transcriber_instance.detect_hook.return_value = mock_hook_result

        detector = LyricsFirstHookDetector(enable_transcription_fallback=True)
        result = detector.detect_hook(
            audio_path="/path/to/track.mp3",
            artist="Unknown",
            title="Unknown"
        )

        assert result.hook == "feel the beat drop"
        assert result.source == "transcription"
        assert result.full_transcription is not None
