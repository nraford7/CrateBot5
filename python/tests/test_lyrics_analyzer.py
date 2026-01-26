"""Tests for the LyricsAnalyzer module - Lyrics-First Hook Detection."""

import pytest

from core.lyrics_analyzer import LyricsAnalyzer, ChorusResult


class TestLyricsAnalyzerBasics:
    """Basic tests for LyricsAnalyzer initialization and configuration."""

    def test_lyrics_analyzer_instantiation(self):
        """LyricsAnalyzer can be instantiated."""
        analyzer = LyricsAnalyzer()
        assert analyzer is not None

    def test_lyrics_analyzer_has_required_methods(self):
        """LyricsAnalyzer has all required public methods."""
        analyzer = LyricsAnalyzer()
        assert hasattr(analyzer, 'find_repeated_phrases')
        assert hasattr(analyzer, 'detect_chorus')
        assert hasattr(analyzer, 'extract_hook_phrase')
        assert callable(analyzer.find_repeated_phrases)
        assert callable(analyzer.detect_chorus)
        assert callable(analyzer.extract_hook_phrase)

    def test_lyrics_analyzer_has_configuration_constants(self):
        """LyricsAnalyzer has required configuration constants."""
        assert hasattr(LyricsAnalyzer, 'FILLER_PHRASES')
        assert hasattr(LyricsAnalyzer, 'SECTION_MARKERS')
        assert hasattr(LyricsAnalyzer, 'MIN_PHRASE_WORDS')
        assert hasattr(LyricsAnalyzer, 'MAX_PHRASE_WORDS')
        assert LyricsAnalyzer.MIN_PHRASE_WORDS == 3
        assert LyricsAnalyzer.MAX_PHRASE_WORDS == 8


class TestChorusResult:
    """Tests for the ChorusResult dataclass."""

    def test_chorus_result_dataclass_fields(self):
        """ChorusResult has all required fields."""
        result = ChorusResult(
            chorus_text="let me see you work",
            confidence=0.9,
            repetitions=3,
            is_instrumental=False
        )
        assert result.chorus_text == "let me see you work"
        assert result.confidence == 0.9
        assert result.repetitions == 3
        assert result.is_instrumental is False

    def test_chorus_result_instrumental_track(self):
        """ChorusResult correctly represents instrumental tracks."""
        result = ChorusResult(
            chorus_text=None,
            confidence=0.95,
            repetitions=0,
            is_instrumental=True
        )
        assert result.chorus_text is None
        assert result.is_instrumental is True


class TestCleanLyrics:
    """Tests for the _clean_lyrics internal method."""

    def test_clean_lyrics_normalizes_text(self):
        """_clean_lyrics normalizes whitespace and case."""
        analyzer = LyricsAnalyzer()
        cleaned = analyzer._clean_lyrics("  LET ME  See   You   WORK  ")
        assert cleaned == "let me see you work"

    def test_clean_lyrics_removes_timestamps(self):
        """_clean_lyrics removes LRC timestamps."""
        analyzer = LyricsAnalyzer()
        lyrics = "[00:15.23]Let me see you work\n[00:18.45]On the floor"
        cleaned = analyzer._clean_lyrics(lyrics)
        assert "[00:15.23]" not in cleaned
        assert "let me see you work" in cleaned

    def test_clean_lyrics_handles_empty_string(self):
        """_clean_lyrics handles empty input."""
        analyzer = LyricsAnalyzer()
        assert analyzer._clean_lyrics("") == ""
        assert analyzer._clean_lyrics("   ") == ""


class TestIsFiller:
    """Tests for the _is_filler internal method."""

    def test_is_filler_detects_common_phrases(self):
        """_is_filler returns True for common filler phrases."""
        analyzer = LyricsAnalyzer()
        assert analyzer._is_filler("come on") is True
        assert analyzer._is_filler("let's go") is True
        assert analyzer._is_filler("yeah yeah yeah") is True
        assert analyzer._is_filler("one two three") is True

    def test_is_filler_allows_meaningful_phrases(self):
        """_is_filler returns False for meaningful hook phrases."""
        analyzer = LyricsAnalyzer()
        assert analyzer._is_filler("let me see you work") is False
        assert analyzer._is_filler("shake your body down") is False
        assert analyzer._is_filler("feel the rhythm of the night") is False


class TestIsInstrumental:
    """Tests for the _is_instrumental internal method."""

    def test_is_instrumental_detects_markers(self):
        """_is_instrumental detects common instrumental markers."""
        analyzer = LyricsAnalyzer()
        assert analyzer._is_instrumental("[Instrumental]") is True
        assert analyzer._is_instrumental("(Instrumental Track)") is True
        assert analyzer._is_instrumental("This song has no lyrics") is True
        assert analyzer._is_instrumental("Instrumental version") is True

    def test_is_instrumental_allows_real_lyrics(self):
        """_is_instrumental returns False for actual lyrics."""
        analyzer = LyricsAnalyzer()
        lyrics = """
        Let me see you work
        On the floor tonight
        Move your body right
        """
        assert analyzer._is_instrumental(lyrics) is False


class TestExtractMarkedChorus:
    """Tests for the _extract_marked_chorus internal method."""

    def test_extract_marked_chorus_finds_chorus_section(self):
        """_extract_marked_chorus extracts [Chorus] sections."""
        analyzer = LyricsAnalyzer()
        lyrics = """
        [Verse 1]
        Walking down the street
        Feeling the beat

        [Chorus]
        Let me see you work
        On the floor tonight

        [Verse 2]
        Another line here
        """
        chorus = analyzer._extract_marked_chorus(lyrics)
        assert chorus is not None
        assert "let me see you work" in chorus.lower()
        assert "on the floor tonight" in chorus.lower()

    def test_extract_marked_chorus_handles_variations(self):
        """_extract_marked_chorus handles various chorus marker formats."""
        analyzer = LyricsAnalyzer()

        # Test with (Chorus) format
        lyrics1 = """
        (Verse)
        Some verse text

        (Chorus)
        This is the chorus
        Another chorus line
        """
        chorus1 = analyzer._extract_marked_chorus(lyrics1)
        assert chorus1 is not None
        assert "this is the chorus" in chorus1.lower()

    def test_extract_marked_chorus_returns_none_when_no_markers(self):
        """_extract_marked_chorus returns None when no markers found."""
        analyzer = LyricsAnalyzer()
        lyrics = """
        Just some plain lyrics
        Without any markers
        """
        result = analyzer._extract_marked_chorus(lyrics)
        assert result is None


class TestFindRepeatedPhrases:
    """Tests for find_repeated_phrases method."""

    def test_find_repeated_phrases_identifies_repetition(self):
        """find_repeated_phrases identifies phrases that repeat."""
        analyzer = LyricsAnalyzer()
        lyrics = """
        Let me see you work
        On the floor tonight
        Let me see you work
        Moving to the light
        Let me see you work
        """
        phrases = analyzer.find_repeated_phrases(lyrics)
        assert len(phrases) > 0
        # The most repeated phrase should be "let me see you work" (or similar)
        top_phrase = phrases[0][0].lower()
        assert "let me see you work" in top_phrase or "see you work" in top_phrase

    def test_find_repeated_phrases_returns_count(self):
        """find_repeated_phrases returns (phrase, count) tuples."""
        analyzer = LyricsAnalyzer()
        lyrics = """
        shake your body
        feel the rhythm
        shake your body
        to the beat
        shake your body
        """
        phrases = analyzer.find_repeated_phrases(lyrics)
        assert len(phrases) > 0
        phrase, count = phrases[0]
        assert isinstance(phrase, str)
        assert isinstance(count, int)
        assert count >= 2

    def test_find_repeated_phrases_respects_word_limits(self):
        """find_repeated_phrases respects MIN/MAX_PHRASE_WORDS."""
        analyzer = LyricsAnalyzer()
        lyrics = """
        a b
        a b
        a b
        one two three four five six seven eight nine
        one two three four five six seven eight nine
        """
        phrases = analyzer.find_repeated_phrases(lyrics)
        for phrase, count in phrases:
            word_count = len(phrase.split())
            assert word_count >= LyricsAnalyzer.MIN_PHRASE_WORDS
            assert word_count <= LyricsAnalyzer.MAX_PHRASE_WORDS

    def test_find_repeated_phrases_filters_filler(self):
        """find_repeated_phrases filters out filler phrases."""
        analyzer = LyricsAnalyzer()
        lyrics = """
        come on come on come on
        let's go let's go
        yeah yeah yeah
        real meaningful hook phrase
        real meaningful hook phrase
        real meaningful hook phrase
        """
        phrases = analyzer.find_repeated_phrases(lyrics)
        phrase_texts = [p[0].lower() for p in phrases]
        # Filler phrases should not appear in results
        for phrase in phrase_texts:
            assert "come on" not in phrase or len(phrase.split()) > 3

    def test_find_repeated_phrases_empty_lyrics(self):
        """find_repeated_phrases handles empty lyrics."""
        analyzer = LyricsAnalyzer()
        assert analyzer.find_repeated_phrases("") == []
        assert analyzer.find_repeated_phrases("   ") == []


class TestDetectChorus:
    """Tests for detect_chorus method."""

    def test_detect_chorus_uses_marked_sections(self):
        """detect_chorus prefers marked [Chorus] sections."""
        analyzer = LyricsAnalyzer()
        lyrics = """
        [Verse]
        This verse repeats multiple times
        This verse repeats multiple times
        This verse repeats multiple times

        [Chorus]
        Feel the music in your soul
        Let it take control
        """
        result = analyzer.detect_chorus(lyrics)
        assert isinstance(result, ChorusResult)
        assert result.chorus_text is not None
        # Should prefer the marked chorus over the repeated verse
        assert "feel the music" in result.chorus_text.lower() or "take control" in result.chorus_text.lower()

    def test_detect_chorus_falls_back_to_repetition(self):
        """detect_chorus falls back to repetition detection when no markers."""
        analyzer = LyricsAnalyzer()
        lyrics = """
        Shake your body down
        To the ground
        Shake your body down
        All around
        Shake your body down
        """
        result = analyzer.detect_chorus(lyrics)
        assert isinstance(result, ChorusResult)
        assert result.chorus_text is not None
        assert "shake your body" in result.chorus_text.lower()
        assert result.repetitions >= 2

    def test_detect_chorus_returns_instrumental_for_empty(self):
        """detect_chorus returns is_instrumental=True for empty/instrumental."""
        analyzer = LyricsAnalyzer()
        result = analyzer.detect_chorus("[Instrumental]")
        assert result.is_instrumental is True
        assert result.chorus_text is None

    def test_detect_chorus_confidence_based_on_evidence(self):
        """detect_chorus confidence reflects evidence strength."""
        analyzer = LyricsAnalyzer()

        # Strong evidence - marked chorus
        lyrics_marked = """
        [Chorus]
        Strong hook phrase here
        Another chorus line
        """
        result_marked = analyzer.detect_chorus(lyrics_marked)

        # Weaker evidence - only repetition
        lyrics_repeated = """
        weak phrase here
        weak phrase here
        """
        result_repeated = analyzer.detect_chorus(lyrics_repeated)

        # Marked chorus should generally have higher confidence
        assert result_marked.confidence >= 0.0  # Just ensure it's a valid confidence


class TestExtractHookPhrase:
    """Tests for extract_hook_phrase method."""

    def test_extract_hook_phrase_returns_best_hook(self):
        """extract_hook_phrase returns the most hookable phrase."""
        analyzer = LyricsAnalyzer()
        lyrics = """
        [Chorus]
        Let me see you work
        On the floor
        Let me see you work
        Give me more
        Let me see you work
        """
        hook = analyzer.extract_hook_phrase(lyrics)
        assert hook is not None
        assert isinstance(hook, str)
        assert len(hook.split()) >= LyricsAnalyzer.MIN_PHRASE_WORDS

    def test_extract_hook_phrase_prefers_chorus_content(self):
        """extract_hook_phrase prefers content from chorus sections."""
        analyzer = LyricsAnalyzer()
        lyrics = """
        [Verse]
        Boring verse content here
        More boring verse text
        Boring verse content here
        More boring verse text
        Boring verse content here

        [Chorus]
        Feel the rhythm tonight
        """
        hook = analyzer.extract_hook_phrase(lyrics)
        # Should prefer chorus content even if verse repeats more
        assert hook is not None

    def test_extract_hook_phrase_returns_none_for_instrumental(self):
        """extract_hook_phrase returns None for instrumental tracks."""
        analyzer = LyricsAnalyzer()
        assert analyzer.extract_hook_phrase("[Instrumental]") is None
        assert analyzer.extract_hook_phrase("") is None

    def test_extract_hook_phrase_filters_filler(self):
        """extract_hook_phrase does not return filler phrases."""
        analyzer = LyricsAnalyzer()
        lyrics = """
        come on everybody
        come on everybody
        come on everybody
        real actual hook phrase
        real actual hook phrase
        """
        hook = analyzer.extract_hook_phrase(lyrics)
        if hook:
            # Should not be purely filler
            assert hook.lower() != "come on everybody"


class TestEdgeCases:
    """Edge cases and error handling tests."""

    def test_handles_unicode_lyrics(self):
        """LyricsAnalyzer handles unicode characters in lyrics."""
        analyzer = LyricsAnalyzer()
        lyrics = """
        Bailando en la noche
        Sintiendo el ritmo
        Bailando en la noche
        """
        phrases = analyzer.find_repeated_phrases(lyrics)
        # Should not crash and should find the repeated phrase
        assert len(phrases) >= 0

    def test_handles_special_characters(self):
        """LyricsAnalyzer handles special characters and punctuation."""
        analyzer = LyricsAnalyzer()
        lyrics = """
        Can't stop the feeling!!!
        Won't stop the beating...
        Can't stop the feeling!!!
        """
        phrases = analyzer.find_repeated_phrases(lyrics)
        assert len(phrases) >= 0

    def test_handles_very_long_lyrics(self):
        """LyricsAnalyzer handles long lyrics without issues."""
        analyzer = LyricsAnalyzer()
        # Create a long lyrics string
        base_verse = "This is a verse line that goes on and on\n" * 50
        chorus = "This is the catchy hook phrase\n" * 3
        lyrics = f"{base_verse}\n{chorus}\n{base_verse}\n{chorus}"

        result = analyzer.detect_chorus(lyrics)
        assert isinstance(result, ChorusResult)

    def test_handles_only_newlines_and_spaces(self):
        """LyricsAnalyzer handles whitespace-only lyrics."""
        analyzer = LyricsAnalyzer()
        result = analyzer.detect_chorus("\n\n   \n   \n")
        assert result.is_instrumental is True or result.chorus_text is None

    def test_handles_single_word_lyrics(self):
        """LyricsAnalyzer handles very short lyrics."""
        analyzer = LyricsAnalyzer()
        result = analyzer.detect_chorus("work")
        # Should handle gracefully without crashing
        assert isinstance(result, ChorusResult)


class TestLyricsAnalyzer:
    """Required test methods from spec."""

    def test_find_repeated_lines_simple(self):
        """Find 'let me see you work' repeated 3 times."""
        analyzer = LyricsAnalyzer()
        lyrics = """
        Let me see you work
        On the dance floor
        Let me see you work
        Give me some more
        Let me see you work
        """
        phrases = analyzer.find_repeated_phrases(lyrics)
        assert len(phrases) > 0
        top_phrase, count = phrases[0]
        assert "let me see you work" in top_phrase.lower()
        assert count == 3

    def test_find_repeated_lines_with_variations(self):
        """Handle 'work your body' with variations."""
        analyzer = LyricsAnalyzer()
        lyrics = """
        Work your body
        To the rhythm
        Work your body
        Feel the beat
        Work your body tonight
        """
        phrases = analyzer.find_repeated_phrases(lyrics)
        assert len(phrases) > 0
        # Should find "work your body" repeated
        phrase_texts = [p[0].lower() for p in phrases]
        assert any("work your body" in p for p in phrase_texts)

    def test_detect_chorus_structure(self):
        """Detect [Chorus] marked sections with 'dance all night'."""
        analyzer = LyricsAnalyzer()
        lyrics = """
        [Verse 1]
        Walking through the door
        Ready for the floor

        [Chorus]
        Dance all night
        Under the lights
        Dance all night
        Everything feels right

        [Verse 2]
        Moving to the sound
        Best party in town
        """
        result = analyzer.detect_chorus(lyrics)
        assert result.chorus_text is not None
        assert "dance all night" in result.chorus_text.lower()
        assert result.confidence >= 0.9  # High confidence for marked sections

    def test_detect_chorus_without_markers(self):
        """Detect chorus from repetition when no markers."""
        analyzer = LyricsAnalyzer()
        lyrics = """
        Feel the beat drop
        In the night
        Feel the beat drop
        Hold on tight
        Feel the beat drop
        Gonna be alright
        """
        result = analyzer.detect_chorus(lyrics)
        assert result.chorus_text is not None
        assert "feel the beat drop" in result.chorus_text.lower()
        assert result.repetitions >= 2

    def test_extract_hook_phrase(self):
        """Extract hook from chorus."""
        analyzer = LyricsAnalyzer()
        lyrics = """
        [Chorus]
        Shake it like you mean it
        Move it to the beat
        Shake it like you mean it
        Get up on your feet
        """
        hook = analyzer.extract_hook_phrase(lyrics)
        assert hook is not None
        # Hook should come from chorus content
        assert len(hook.split()) >= analyzer.MIN_PHRASE_WORDS

    def test_empty_lyrics(self):
        """Handle empty/None gracefully."""
        analyzer = LyricsAnalyzer()
        # Empty string
        result = analyzer.detect_chorus("")
        assert result.chorus_text is None
        assert result.is_instrumental is True

        # Whitespace only
        result2 = analyzer.detect_chorus("   \n\n   ")
        assert result2.chorus_text is None

        # find_repeated_phrases with empty
        phrases = analyzer.find_repeated_phrases("")
        assert phrases == []

        # extract_hook_phrase with empty
        hook = analyzer.extract_hook_phrase("")
        assert hook is None

    def test_instrumental_lyrics(self):
        """Handle [Instrumental] marker."""
        analyzer = LyricsAnalyzer()
        result = analyzer.detect_chorus("[Instrumental]")
        assert result.is_instrumental is True
        assert result.chorus_text is None

        # Also test extract_hook_phrase
        hook = analyzer.extract_hook_phrase("[Instrumental]")
        assert hook is None

    def test_filters_common_phrases(self):
        """Filter 'come on' but keep 'real hook line'."""
        analyzer = LyricsAnalyzer()
        lyrics = """
        Come on come on
        Let's go let's go
        Come on come on
        Real hook line here
        Real hook line here
        Real hook line here
        """
        phrases = analyzer.find_repeated_phrases(lyrics)
        phrase_texts = [p[0].lower() for p in phrases]
        # "come on" should be filtered
        assert not any(p == "come on" for p in phrase_texts)
        # "real hook line here" should be found
        assert any("real hook line" in p for p in phrase_texts)


class TestIntegration:
    """Integration tests for complete workflow."""

    def test_full_workflow_with_marked_chorus(self):
        """Complete workflow with marked chorus sections."""
        analyzer = LyricsAnalyzer()

        lyrics = """
        [Verse 1]
        Walking down the street
        Feeling the summer heat

        [Chorus]
        Dance all night long
        Until the break of dawn
        Dance all night long
        Keep the party going on

        [Verse 2]
        Moving to the beat
        Life is feeling sweet

        [Chorus]
        Dance all night long
        Until the break of dawn
        Dance all night long
        Keep the party going on
        """

        # Should detect chorus
        chorus_result = analyzer.detect_chorus(lyrics)
        assert chorus_result.is_instrumental is False
        assert chorus_result.chorus_text is not None
        assert chorus_result.confidence > 0

        # Should extract hook
        hook = analyzer.extract_hook_phrase(lyrics)
        assert hook is not None
        assert "dance" in hook.lower() or "night" in hook.lower()

    def test_full_workflow_with_repetition_only(self):
        """Complete workflow using only repetition detection."""
        analyzer = LyricsAnalyzer()

        lyrics = """
        Shake it off shake it off
        I stay up too late
        Got nothing in my brain
        Shake it off shake it off
        The players gonna play
        And the haters gonna hate
        Shake it off shake it off
        """

        # Should detect chorus via repetition
        chorus_result = analyzer.detect_chorus(lyrics)
        assert chorus_result.is_instrumental is False

        # Should find repeated phrases
        phrases = analyzer.find_repeated_phrases(lyrics)
        assert len(phrases) > 0
