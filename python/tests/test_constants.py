"""Tests for taxonomy constants."""
import pytest
from src.core.constants import (
    CANONICAL_GENRES,
    CANONICAL_TIMING,
    CANONICAL_MOODS,
    TAXONOMY_ID3_MAPPING,
)


def test_canonical_genres_has_9_values():
    assert len(CANONICAL_GENRES) == 9
    assert "House" in CANONICAL_GENRES
    assert "Techno" in CANONICAL_GENRES
    assert "Jungle/DnB" in CANONICAL_GENRES


def test_canonical_timing_has_5_values():
    assert len(CANONICAL_TIMING) == 5
    assert "Start" in CANONICAL_TIMING
    assert "Build" in CANONICAL_TIMING
    assert "Peak" in CANONICAL_TIMING
    assert "Sustain" in CANONICAL_TIMING
    assert "Release" in CANONICAL_TIMING


def test_canonical_moods_has_6_values():
    assert len(CANONICAL_MOODS) == 6
    assert "Happy" in CANONICAL_MOODS
    assert "Dark" in CANONICAL_MOODS
    assert "Groovy" in CANONICAL_MOODS


def test_taxonomy_id3_mapping():
    assert TAXONOMY_ID3_MAPPING["genre"] == "TCON"
    assert TAXONOMY_ID3_MAPPING["timing"] == "TALB"
    assert TAXONOMY_ID3_MAPPING["mood"] == "TIT1"
    assert TAXONOMY_ID3_MAPPING["descriptive"] == "COMM"
