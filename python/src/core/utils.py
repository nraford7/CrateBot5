"""Shared utility functions for Audio Tagger."""

from typing import Set

from .tag_scanner import normalize_tag, similarity


def matches_selected_tag(value: str, selected_tags: Set[str], threshold: float = 0.85) -> bool:
    """
    Check if a value matches any selected tag using exact or fuzzy matching.

    Args:
        value: The tag value to check
        selected_tags: Set of valid tag values
        threshold: Fuzzy match threshold (default 0.85)

    Returns:
        True if value matches any selected tag
    """
    if not value:
        return False
    normalized = normalize_tag(value)
    for selected in selected_tags:
        if normalize_tag(selected) == normalized:
            return True
        if similarity(value, selected) >= threshold:
            return True
    return False
