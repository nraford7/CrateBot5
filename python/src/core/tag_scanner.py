import os
import re
import sys
import logging
from pathlib import Path
from typing import Dict, List, Set, Tuple, Optional
from collections import defaultdict
from difflib import SequenceMatcher
from tqdm import tqdm

from .tag_manager import TagManager
from .constants import ACTUAL_GENRE_VALUES, DEFAULT_GENRE_FOR_TIMING

logger = logging.getLogger(__name__)

def normalize_tag(tag: str) -> str:
    """Normalize a tag to a standard form for comparison."""
    # Lowercase and strip
    normalized = tag.lower().strip()
    # Remove extra whitespace
    normalized = re.sub(r'\s+', ' ', normalized)
    return normalized


def similarity(a: str, b: str) -> float:
    """Calculate similarity ratio between two strings."""
    return SequenceMatcher(None, normalize_tag(a), normalize_tag(b)).ratio()


def find_canonical_tag(tag: str, existing_tags: Dict[str, int]) -> Tuple[str, bool]:
    """
    Find if a similar tag already exists. Returns (canonical_tag, is_new).
    Uses fuzzy matching to detect similar tags like "Hi Hats" vs "high hats".
    """
    if not existing_tags:
        return tag, True

    normalized_new = normalize_tag(tag)

    # First check for exact normalized match
    for existing, count in existing_tags.items():
        if normalize_tag(existing) == normalized_new:
            return existing, False

    # Then check for fuzzy matches (threshold 0.85 for similar spellings)
    best_match = None
    best_score = 0.0

    for existing in existing_tags.keys():
        score = similarity(tag, existing)
        if score > best_score and score >= 0.85:
            best_score = score
            best_match = existing

    if best_match:
        return best_match, False

    # No match found - this is a new tag
    # Return title-cased version for consistency
    return tag.title(), True


def merge_similar_tags(tags_with_counts: Dict[str, int]) -> Dict[str, int]:
    """
    Merge similar tags into canonical forms.
    Returns a new dict with merged counts.
    """
    merged = {}

    # Sort by count descending so most common version becomes canonical
    sorted_tags = sorted(tags_with_counts.items(), key=lambda x: -x[1])

    for tag, count in sorted_tags:
        canonical, is_new = find_canonical_tag(tag, merged)
        if is_new:
            merged[canonical] = count
        else:
            merged[canonical] += count

    return merged


class TagScanner:
    def __init__(self, tag_manager: TagManager = None):
        self.tag_manager = tag_manager or TagManager()

    def scan_directory(self, directory_path: str, recursive: bool = True, tag_sources: Optional[Dict[str, Optional[str]]] = None) -> Dict[str, Dict]:
        """
        Scan all MP3s and discover unique tag values.

        Returns new taxonomy structure:
        - genre: actual genre values (from Genre ID3 tag, filtered)
        - timing: timing values (from Genre ID3 tag, split out)
        - mood: mood values (from Album ID3 tag)
        - descriptive: descriptive tags (from Comments ID3 tag)

        The Genre ID3 tag is split: values in ACTUAL_GENRE_VALUES go to 'genre',
        all others are treated as timing values (those tracks default to House genre).
        """
        mp3_files = self._find_mp3_files(directory_path, recursive)

        if not mp3_files:
            raise ValueError(f"No MP3 files found in {directory_path}")

        logger.info("Scanning %d MP3 files for tags...", len(mp3_files))

        discovered_tags = {
            'genre': defaultdict(int),       # actual genres (DiscoFunk, PartyBreaks, House)
            'timing': defaultdict(int),      # timing values split from genre tag
            'mood': defaultdict(int),        # from album tag
            'descriptive': defaultdict(int), # from comments tag
        }

        files_with_tags = {
            'genre': 0,
            'timing': 0,
            'mood': 0,
            'descriptive': 0,
        }

        # Normalize ACTUAL_GENRE_VALUES for case-insensitive comparison
        actual_genres_normalized = {normalize_tag(g) for g in ACTUAL_GENRE_VALUES}

        show_progress = sys.stderr.isatty() and os.environ.get('CRATEBOT_DISABLE_PROGRESS') != '1'
        class FrameLexicon:
            def __init__(self, mapping: Dict[str, Optional[str]]):
                self.mapping = mapping

            def get_id3_frame(self, category: str) -> Optional[str]:
                return self.mapping.get(category)

        lexicon = None
        if tag_sources:
            lexicon = FrameLexicon({
                'genre': tag_sources.get('genre_frame'),
                'timing': tag_sources.get('timing_frame'),
                'mood': tag_sources.get('mood_frame'),
                'descriptive': tag_sources.get('comments_frame'),
            })

        use_timing_frame = bool(tag_sources and tag_sources.get('timing_frame'))

        for mp3_path in tqdm(mp3_files, desc="Scanning tags", disable=not show_progress):
            try:
                tags = self.tag_manager.read_tags(mp3_path, lexicon=lexicon)
                if not tags:
                    continue

                # Genre tag (TCON) - split into genre vs timing
                if 'genre' in tags and tags['genre'].strip():
                    genre_value = tags['genre'].strip()
                    if use_timing_frame:
                        discovered_tags['genre'][genre_value] += 1
                        files_with_tags['genre'] += 1
                    else:
                        normalized_value = normalize_tag(genre_value)

                        if normalized_value in actual_genres_normalized:
                            # This is an actual genre (DiscoFunk, PartyBreaks)
                            discovered_tags['genre'][genre_value] += 1
                            files_with_tags['genre'] += 1
                        else:
                            # This is a timing value - track defaults to House genre
                            discovered_tags['timing'][genre_value] += 1
                            files_with_tags['timing'] += 1
                            # Also count House as a genre for these tracks
                            discovered_tags['genre'][DEFAULT_GENRE_FOR_TIMING] += 1
                            files_with_tags['genre'] += 1

                # Timing tag (explicit frame)
                if use_timing_frame and 'timing' in tags and tags['timing'].strip():
                    timing_value = tags['timing'].strip()
                    discovered_tags['timing'][timing_value] += 1
                    files_with_tags['timing'] += 1

                # Album tag (TALB) -> mood
                mood_value = tags.get('mood') or tags.get('album')
                if isinstance(mood_value, str) and mood_value.strip():
                    mood = mood_value.strip()
                    discovered_tags['mood'][mood] += 1
                    files_with_tags['mood'] += 1

                # Comments tag (COMM) -> descriptive
                comments_value = tags.get('descriptive') or tags.get('comments')
                if comments_value:
                    comments = comments_value
                    if isinstance(comments, list):
                        # Join multiple frames with comma, not space
                        comments = ', '.join(comments)

                    # Split by comma and clean up
                    comment_tags = [c.strip() for c in comments.split(',') if c.strip()]
                    if comment_tags:
                        files_with_tags['descriptive'] += 1
                        for tag in comment_tags:
                            discovered_tags['descriptive'][tag] += 1

            except Exception as e:
                continue

        # Merge similar tags
        merged_genre = merge_similar_tags(dict(discovered_tags['genre']))
        merged_timing = merge_similar_tags(dict(discovered_tags['timing']))
        merged_mood = merge_similar_tags(dict(discovered_tags['mood']))
        merged_descriptive = merge_similar_tags(dict(discovered_tags['descriptive']))

        # Convert to sorted lists with counts
        result = {
            'genre': {
                'values': sorted(merged_genre.items(), key=lambda x: -x[1]),
                'total_files': files_with_tags['genre'],
            },
            'timing': {
                'values': sorted(merged_timing.items(), key=lambda x: -x[1]),
                'total_files': files_with_tags['timing'],
            },
            'mood': {
                'values': sorted(merged_mood.items(), key=lambda x: -x[1]),
                'total_files': files_with_tags['mood'],
            },
            'descriptive': {
                'values': sorted(merged_descriptive.items(), key=lambda x: -x[1]),
                'total_files': files_with_tags['descriptive'],
            },
            'total_mp3s': len(mp3_files),
        }

        return result

    def _find_mp3_files(self, directory_path: str, recursive: bool) -> List[str]:
        path = Path(directory_path)
        pattern = '**/*.mp3' if recursive else '*.mp3'
        return sorted([str(f) for f in path.glob(pattern)])


class TagSelector:
    def __init__(self):
        pass

    def interactive_select(self, discovered_tags: Dict) -> Dict[str, List[str]]:
        """Interactive CLI for selecting which tags to train on (new taxonomy)."""
        from rich.console import Console
        from rich.table import Table
        from rich.prompt import Prompt, Confirm

        console = Console()

        console.print("\n[bold cyan]═══ Tag Selection for Training ═══[/bold cyan]\n")
        console.print(f"Scanned {discovered_tags['total_mp3s']} MP3 files\n")

        selected_tags = {}

        # Genre selection (single-class) - from Genre ID3 tag (filtered)
        selected_tags['genre'] = self._select_category(
            console,
            "Genre",
            "Musical genre/style (single value per track)",
            discovered_tags['genre'],
            min_select=2
        )

        # Timing selection (single-class) - split from Genre ID3 tag
        selected_tags['timing'] = self._select_category(
            console,
            "Timing",
            "Set timing/energy position (single value per track)",
            discovered_tags['timing'],
            min_select=2
        )

        # Mood selection (single-class) - from Album ID3 tag
        selected_tags['mood'] = self._select_category(
            console,
            "Mood",
            "Emotional tone/vibe (single value per track)",
            discovered_tags['mood'],
            min_select=2
        )

        # Descriptive selection (multi-label) - from Comments ID3 tag
        selected_tags['descriptive'] = self._select_category(
            console,
            "Descriptive",
            "Character/vibes/instruments (multiple values per track)",
            discovered_tags['descriptive'],
            min_select=3
        )

        # Summary
        console.print("\n[bold green]═══ Selection Summary ═══[/bold green]")
        console.print(f"Genre tags: {len(selected_tags['genre'])} selected")
        console.print(f"Timing tags: {len(selected_tags['timing'])} selected")
        console.print(f"Mood tags: {len(selected_tags['mood'])} selected")
        console.print(f"Descriptive tags: {len(selected_tags['descriptive'])} selected")

        return selected_tags

    def _select_category(self, console, category_name: str, description: str,
                         category_data: Dict, min_select: int = 2) -> List[str]:
        """Select tags for a single category."""
        from rich.table import Table
        from rich.prompt import Prompt, Confirm

        values = category_data['values']
        total_files = category_data['total_files']

        console.print(f"\n[bold yellow]── {category_name} ──[/bold yellow]")
        console.print(f"[dim]{description}[/dim]")
        console.print(f"Found in {total_files} files\n")

        if not values:
            console.print(f"[red]No {category_name} tags found in your files.[/red]")
            return []

        # Display table of discovered values
        table = Table(show_header=True, header_style="bold")
        table.add_column("#", style="dim", width=4)
        table.add_column("Value", style="cyan")
        table.add_column("Count", justify="right", style="green")

        for idx, (value, count) in enumerate(values, 1):
            display_value = value[:50] + "..." if len(value) > 50 else value
            table.add_row(str(idx), display_value, str(count))

        console.print(table)

        # Selection prompt
        console.print(f"\n[dim]Enter numbers separated by commas (e.g., 1,2,3,5)")
        console.print(f"Or 'all' to select all, 'none' to skip[/dim]")

        while True:
            selection = Prompt.ask(f"Select {category_name} tags")

            if selection.lower() == 'all':
                return [v[0] for v in values]

            if selection.lower() == 'none':
                if min_select > 0:
                    console.print(f"[red]You must select at least {min_select} tags for {category_name}[/red]")
                    continue
                return []

            try:
                indices = [int(x.strip()) for x in selection.split(',')]
                selected = []
                for idx in indices:
                    if 1 <= idx <= len(values):
                        selected.append(values[idx - 1][0])
                    else:
                        console.print(f"[red]Invalid number: {idx}[/red]")

                if len(selected) < min_select:
                    console.print(f"[red]Please select at least {min_select} tags[/red]")
                    continue

                return selected

            except ValueError:
                console.print("[red]Invalid input. Use numbers separated by commas.[/red]")
                continue
