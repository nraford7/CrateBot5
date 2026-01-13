"""
Centralized Tag Taxonomy Transformation for CrateBot4

Single source of truth for transforming raw ID3 tags to canonical taxonomy.
Used by both training data collection and tagging output.

Taxonomy:
- genre: Actual music genres (House, Techno, Jungle, etc.)
- timing: Energy curve position (Start, Build, Peak, Sustain, Release)
- mood: Emotional character (Happy, Dark, Emotional, etc.)
- descriptive: Sonic characteristics (comma-separated)
"""

import logging
from typing import Dict, Any, List, Optional, Set

from .constants import ACTUAL_GENRE_VALUES, DEFAULT_GENRE_FOR_TIMING
from .tag_scanner import normalize_tag

logger = logging.getLogger(__name__)


def transform_raw_tags_to_taxonomy(
    raw_tags: Dict[str, Any],
    tag_sources: Optional[Dict[str, str]] = None,
    lexicon: Optional[Any] = None,
    actual_genres: Optional[Set[str]] = None
) -> Dict[str, str]:
    """
    Transform raw ID3 tags to canonical taxonomy.

    Handles Genre/Timing split logic consistently for training and tagging.

    The key transformation is splitting the Genre ID3 tag into:
    - Actual genres (House, Techno, etc.) stay in 'genre'
    - Timing values (Start, Build, Peak, etc.) move to 'timing'
    - If a timing value is in Genre, the track defaults to House genre

    Args:
        raw_tags: Raw tags from TagManager.read_tags()
        tag_sources: Optional mapping of category -> ID3 frame for custom sources
        lexicon: Optional Lexicon for vocabulary mapping
        actual_genres: Optional set of actual genre values (defaults to ACTUAL_GENRE_VALUES)

    Returns:
        Dict with keys: genre, timing, mood, descriptive
    """
    if actual_genres is None:
        actual_genres = ACTUAL_GENRE_VALUES

    # Normalize actual genres for case-insensitive comparison
    actual_genres_normalized = {normalize_tag(g) for g in actual_genres}

    # Determine if we have a separate timing frame
    use_timing_frame = bool(tag_sources and tag_sources.get('timing_frame'))

    # Extract genre value from raw tags
    genre_value = _get_tag_value(raw_tags, 'genre', tag_sources)
    timing_value = ''

    if use_timing_frame:
        # Separate timing field exists (explicit timing source)
        timing_value = _get_tag_value(raw_tags, 'timing', tag_sources)
    elif genre_value:
        # Split Genre tag into genre vs timing
        normalized_genre = normalize_tag(genre_value)

        if normalized_genre in actual_genres_normalized:
            # This is an actual genre - keep it
            pass
        else:
            # This is a timing value - move to timing, default to House
            timing_value = genre_value
            genre_value = DEFAULT_GENRE_FOR_TIMING

    # Extract mood (from Album or custom frame)
    mood_value = _get_tag_value(raw_tags, 'mood', tag_sources)
    if not mood_value:
        # Fallback to album field
        mood_value = raw_tags.get('album', '')

    mood = mood_value.strip() if isinstance(mood_value, str) else ''

    # Extract descriptive (from Comments or custom frame)
    descriptive_value = _get_tag_value(raw_tags, 'descriptive', tag_sources)
    if not descriptive_value:
        # Fallback to comments field
        descriptive_value = raw_tags.get('comments', '')

    if isinstance(descriptive_value, list):
        descriptive_value = ', '.join(descriptive_value)

    descriptive = descriptive_value.strip() if isinstance(descriptive_value, str) else ''

    return {
        'genre': genre_value.strip() if isinstance(genre_value, str) else '',
        'timing': timing_value.strip() if isinstance(timing_value, str) else '',
        'mood': mood,
        'descriptive': descriptive,
    }


def _get_tag_value(
    raw_tags: Dict[str, Any],
    category: str,
    tag_sources: Optional[Dict[str, str]] = None
) -> str:
    """
    Get tag value for a category, considering custom tag sources.

    Args:
        raw_tags: Raw tags dict
        category: Category to get (genre, timing, mood, descriptive)
        tag_sources: Optional custom source mapping

    Returns:
        Tag value as string, or empty string if not found
    """
    # Check custom source first
    if tag_sources:
        source_key = tag_sources.get(f'{category}_frame')
        if source_key and source_key in raw_tags:
            value = raw_tags[source_key]
            if isinstance(value, list):
                return ', '.join(str(v) for v in value)
            return str(value) if value else ''

    # Fallback to direct category key
    value = raw_tags.get(category, '')
    if isinstance(value, list):
        return ', '.join(str(v) for v in value)
    return str(value) if value else ''


def validate_taxonomy_tags(
    tags: Dict[str, str],
    selected_tags: Dict[str, List[str]]
) -> Dict[str, bool]:
    """
    Validate which taxonomy tags match selected training tags.

    Args:
        tags: Transformed taxonomy tags
        selected_tags: Dict of selected tag lists per category

    Returns:
        Dict indicating which categories have valid matches
    """
    from .utils import matches_selected_tag

    result = {
        'genre': False,
        'timing': False,
        'mood': False,
        'descriptive': False,
    }

    # Check genre
    if tags.get('genre'):
        result['genre'] = matches_selected_tag(
            tags['genre'],
            set(selected_tags.get('genre', []))
        )

    # Check timing
    if tags.get('timing'):
        result['timing'] = matches_selected_tag(
            tags['timing'],
            set(selected_tags.get('timing', []))
        )

    # Check mood
    if tags.get('mood'):
        result['mood'] = matches_selected_tag(
            tags['mood'],
            set(selected_tags.get('mood', []))
        )

    # Check descriptive (any matching tag)
    if tags.get('descriptive'):
        descriptive_list = [t.strip() for t in tags['descriptive'].split(',') if t.strip()]
        selected_descriptive = set(selected_tags.get('descriptive', []))
        result['descriptive'] = any(
            matches_selected_tag(t, selected_descriptive)
            for t in descriptive_list
        )

    return result


def has_any_valid_tag(
    tags: Dict[str, str],
    selected_tags: Dict[str, List[str]]
) -> bool:
    """
    Check if tags have at least one match with selected training tags.

    Used to filter files during training data collection.

    Args:
        tags: Transformed taxonomy tags
        selected_tags: Dict of selected tag lists per category

    Returns:
        True if at least one category has a valid match
    """
    validation = validate_taxonomy_tags(tags, selected_tags)
    return any(validation.values())


def get_canonical_genre(genre_value: str, actual_genres: Optional[Set[str]] = None) -> str:
    """
    Get canonical genre for a value, handling timing values.

    Args:
        genre_value: Raw genre value
        actual_genres: Set of actual genre values

    Returns:
        Canonical genre (or default if value is a timing)
    """
    if actual_genres is None:
        actual_genres = ACTUAL_GENRE_VALUES

    if not genre_value:
        return DEFAULT_GENRE_FOR_TIMING

    actual_genres_normalized = {normalize_tag(g) for g in actual_genres}
    normalized = normalize_tag(genre_value)

    if normalized in actual_genres_normalized:
        return genre_value.strip()
    else:
        return DEFAULT_GENRE_FOR_TIMING


def is_timing_value(genre_value: str, actual_genres: Optional[Set[str]] = None) -> bool:
    """
    Check if a genre value is actually a timing value.

    Args:
        genre_value: Raw genre value to check
        actual_genres: Set of actual genre values

    Returns:
        True if the value is a timing (not a genre)
    """
    if actual_genres is None:
        actual_genres = ACTUAL_GENRE_VALUES

    if not genre_value:
        return False

    actual_genres_normalized = {normalize_tag(g) for g in actual_genres}
    normalized = normalize_tag(genre_value)

    return normalized not in actual_genres_normalized
