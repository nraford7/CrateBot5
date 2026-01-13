import logging
import os
from typing import Dict, List, Optional, Any, TYPE_CHECKING

from mutagen.mp3 import MP3
from mutagen.id3 import ID3, TIT2, TIT3, TPE1, TPE2, TPE3, TPE4, TALB, TDRC, TCON, COMM, TXXX, TIT1, TCOM, GRP1, TCAT, MVNM, TPUB
from mutagen import MutagenError

from .exceptions import TagError, TagReadError, TagWriteError

if TYPE_CHECKING:
    from .lexicon import Lexicon

logger = logging.getLogger(__name__)


class TagManager:
    def __init__(self):
        self.standard_tags = ['title', 'artist', 'album', 'date', 'genre', 'grouping', 'category', 'composer', 'description', 'movement_name', 'work']
        self.custom_tag_prefix = 'CUSTOM:'

    def _write_to_frame(self, audio, frame: str, value: str) -> None:
        """Write value to specified ID3 frame.

        Args:
            audio: Mutagen MP3 object with tags
            frame: Frame name (e.g., 'TALB', 'TXXX:CUSTOM')
            value: Value to write
        """
        if frame.startswith("TXXX:"):
            # Custom TXXX frame
            desc = frame[5:]  # Everything after "TXXX:"
            # Remove existing TXXX with same description
            for txxx in list(audio.tags.getall("TXXX")):
                if txxx.desc == desc:
                    audio.tags.remove(txxx)
            audio.tags.add(TXXX(encoding=3, desc=desc, text=value))
        elif frame == "TALB":
            if "TALB" in audio.tags:
                audio.tags.delall("TALB")
            audio.tags.add(TALB(encoding=3, text=value))
        elif frame == "TIT1":
            if "TIT1" in audio.tags:
                audio.tags.delall("TIT1")
            audio.tags.add(TIT1(encoding=3, text=value))
        elif frame == "TCON":
            if "TCON" in audio.tags:
                audio.tags.delall("TCON")
            audio.tags.add(TCON(encoding=3, text=value))
        elif frame == "COMM":
            audio.tags.delall("COMM")
            audio.tags.add(COMM(encoding=3, lang='eng', desc='', text=value))
        else:
            # Fallback: write as TXXX with frame name as description
            logger.warning("Unknown frame %s, writing as TXXX", frame)
            audio.tags.add(TXXX(encoding=3, desc=frame, text=value))

    def _read_from_frame(self, audio, frame: str) -> Optional[str]:
        """Read value from specified ID3 frame.

        Args:
            audio: Mutagen MP3 object with tags
            frame: Frame name (e.g., 'TALB', 'TXXX:CUSTOM', 'COMM')

        Returns:
            Value from frame, or None if not found.
        """
        if frame.startswith("TXXX:"):
            desc = frame[5:]
            for txxx in audio.tags.getall("TXXX"):
                if txxx.desc == desc:
                    return str(txxx.text[0]) if txxx.text else None
            return None
        elif frame == "COMM":
            # COMM frames are special - get first one with content
            for comm in audio.tags.getall("COMM"):
                if comm.text and comm.text[0]:
                    return str(comm.text[0])
            return None
        elif frame in audio.tags:
            return str(audio.tags[frame])
        return None

    def _get_frame(self, category: str, default: str, lexicon: Optional['Lexicon'] = None) -> str:
        """Get the ID3 frame for a category from lexicon or use default.

        Args:
            category: Tag category (timing, mood, genre, descriptive)
            default: Default frame if lexicon not provided
            lexicon: Optional Lexicon for frame configuration

        Returns:
            ID3 frame name to use
        """
        if lexicon:
            return lexicon.get_id3_frame(category) or default
        return default

    def read_tags(self, audio_path: str, lexicon: Optional['Lexicon'] = None) -> Dict[str, Any]:
        if not os.path.exists(audio_path):
            raise FileNotFoundError(f"File not found: {audio_path}")
        
        try:
            audio = MP3(audio_path, ID3=ID3)
            tags = {}
            
            if audio.tags is None:
                return tags
            
            if 'TIT2' in audio.tags:
                tags['title'] = str(audio.tags['TIT2'])
            
            if 'TPE1' in audio.tags:
                tags['artist'] = str(audio.tags['TPE1'])
            
            if 'TALB' in audio.tags:
                talb_value = str(audio.tags['TALB'])
                tags['album'] = talb_value

            # Read timing from lexicon-configured frame
            timing_frame = self._get_frame("timing", "TALB", lexicon)
            timing_value = self._read_from_frame(audio, timing_frame)
            if timing_value:
                tags['timing'] = timing_value
            
            if 'TDRC' in audio.tags:
                tags['date'] = str(audio.tags['TDRC'])
            
            # Read genre from lexicon-configured frame
            genre_frame = self._get_frame("genre", "TCON", lexicon)
            genre_value = self._read_from_frame(audio, genre_frame)
            if genre_value:
                tags['genre'] = genre_value

            if 'TIT3' in audio.tags:
                tags['description'] = str(audio.tags['TIT3'])  # Vibe description in Subtitle

            if 'TCOM' in audio.tags:
                tags['composer'] = str(audio.tags['TCOM'])

            # Additional metadata fields
            if 'TPE2' in audio.tags:
                tags['album_artist'] = str(audio.tags['TPE2'])

            if 'TPE3' in audio.tags:
                tags['conductor'] = str(audio.tags['TPE3'])

            if 'TPE4' in audio.tags:
                tags['remixer'] = str(audio.tags['TPE4'])

            if 'TPUB' in audio.tags:
                tags['publisher'] = str(audio.tags['TPUB'])

            # Read Grouping (GRP1) - used for Overall Likeness
            if 'GRP1' in audio.tags:
                tags['grouping'] = str(audio.tags['GRP1'])

            # Read Category (TCAT) - used for Comment Likeness
            if 'TCAT' in audio.tags:
                tags['category'] = str(audio.tags['TCAT'])

            # Read Movement Name (MVNM) - used for Scene/Origin
            if 'MVNM' in audio.tags:
                tags['movement_name'] = str(audio.tags['MVNM'])

            comments = []
            for frame in audio.tags.getall('COMM'):
                if frame.text and frame.text[0]:
                    comments.append(str(frame.text[0]))
            if comments:
                tags['comments'] = comments

            # Read descriptive from lexicon-configured frame
            descriptive_frame = self._get_frame("descriptive", "COMM", lexicon)
            descriptive_value = self._read_from_frame(audio, descriptive_frame)
            if descriptive_value:
                # Parse as comma-split list
                descriptive = [part.strip() for part in descriptive_value.split(',') if part.strip()]
                if descriptive:
                    tags['descriptive'] = descriptive

            # Read Work (TIT1) - used for vocal hooks, visible in iTunes Work column
            if 'TIT1' in audio.tags:
                tags['work'] = str(audio.tags['TIT1'])

            # Read mood from lexicon-configured frame
            mood_frame = self._get_frame("mood", "TIT1", lexicon)
            mood_value = self._read_from_frame(audio, mood_frame)
            if mood_value:
                tags['mood'] = mood_value

            custom_tags = {}
            for frame in audio.tags.getall('TXXX'):
                if frame.desc and frame.text:
                    # Handle special TXXX fields
                    if frame.desc == 'Description' and 'description' not in tags:
                        tags['description'] = str(frame.text[0])
                    elif frame.desc.upper() == 'WORK' and 'work' not in tags:
                        # Fallback: read from TXXX:WORK if TIT1 not present
                        tags['work'] = str(frame.text[0])
                    elif frame.desc not in ('Description', 'WORK'):
                        custom_tags[frame.desc] = str(frame.text[0])
            if custom_tags:
                tags['custom'] = custom_tags
            
            tags['all_text'] = self._extract_all_text_tags(tags)

            return tags

        except MutagenError as e:
            raise TagReadError(f"Error reading tags from {audio_path}: {e}") from e
        except OSError as e:
            raise TagReadError(f"Cannot access file {audio_path}: {e}") from e
    
    def write_tags(self, audio_path: str, tags: Dict[str, Any], overwrite: bool = False, lexicon: Optional['Lexicon'] = None) -> None:
        """
        Write tags to an MP3 file.
        When overwrite=True, only overwrites the specific tags being written (genre, album, comments).
        Preserves other tags like title, artist, date.

        Args:
            audio_path: Path to MP3 file
            tags: Dictionary of tags to write
            overwrite: If True, remove existing tags before writing
            lexicon: Optional Lexicon for ID3 frame configuration
        """
        if not os.path.exists(audio_path):
            raise FileNotFoundError(f"File not found: {audio_path}")

        try:
            audio = MP3(audio_path, ID3=ID3)

            if audio.tags is None:
                audio.add_tags()

            # Only remove specific tags if overwriting, preserve others
            # Note: _write_to_frame already handles clearing for taxonomy fields
            if overwrite:
                # Clear genre frame (lexicon-configurable)
                if 'genre' in tags:
                    genre_frame = self._get_frame("genre", "TCON", lexicon)
                    if not genre_frame.startswith("TXXX:") and genre_frame in audio.tags:
                        audio.tags.delall(genre_frame)
                # Clear timing frame (lexicon-configurable)
                if 'timing' in tags:
                    timing_frame = self._get_frame("timing", "TALB", lexicon)
                    if not timing_frame.startswith("TXXX:") and timing_frame in audio.tags:
                        audio.tags.delall(timing_frame)
                # Also clear TALB for album
                if 'album' in tags and 'TALB' in audio.tags:
                    audio.tags.delall('TALB')
                # Clear descriptive frame (lexicon-configurable)
                if 'descriptive' in tags:
                    desc_frame = self._get_frame("descriptive", "COMM", lexicon)
                    if not desc_frame.startswith("TXXX:"):
                        audio.tags.delall(desc_frame)
                # Also clear COMM for comments
                if 'comments' in tags:
                    audio.tags.delall('COMM')
                if 'composer' in tags and 'TCOM' in audio.tags:
                    audio.tags.delall('TCOM')
                # Clear mood frame (lexicon-configurable)
                if 'mood' in tags:
                    mood_frame = self._get_frame("mood", "TIT1", lexicon)
                    if not mood_frame.startswith("TXXX:") and mood_frame in audio.tags:
                        audio.tags.delall(mood_frame)
                        logger.debug("Cleared old %s data", mood_frame)
                # Clear TIT1 for work and other TIT1-mapped fields
                if ('work' in tags or 'movement_name' in tags):
                    if 'TIT1' in audio.tags:
                        audio.tags.delall('TIT1')
                        logger.debug("Cleared old TIT1 data")

            if 'title' in tags:
                if overwrite and 'TIT2' in audio.tags:
                    audio.tags.delall('TIT2')
                audio.tags.add(TIT2(encoding=3, text=tags['title']))

            if 'artist' in tags:
                if overwrite and 'TPE1' in audio.tags:
                    audio.tags.delall('TPE1')
                audio.tags.add(TPE1(encoding=3, text=tags['artist']))

            if 'album' in tags:
                audio.tags.add(TALB(encoding=3, text=tags['album']))

            # New taxonomy: timing -> configurable frame (default TALB)
            if 'timing' in tags:
                timing_frame = self._get_frame("timing", "TALB", lexicon)
                self._write_to_frame(audio, timing_frame, tags['timing'])

            if 'date' in tags:
                if overwrite and 'TDRC' in audio.tags:
                    audio.tags.delall('TDRC')
                audio.tags.add(TDRC(encoding=3, text=str(tags['date'])))

            # New taxonomy: genre -> configurable frame (default TCON)
            if 'genre' in tags:
                genre_frame = self._get_frame("genre", "TCON", lexicon)
                self._write_to_frame(audio, genre_frame, tags['genre'])

            if 'category' in tags:
                if overwrite and 'TCAT' in audio.tags:
                    audio.tags.delall('TCAT')
                audio.tags.add(TCAT(encoding=3, text=tags['category']))

            if 'composer' in tags:
                if overwrite and 'TCOM' in audio.tags:
                    audio.tags.delall('TCOM')
                audio.tags.add(TCOM(encoding=3, text=tags['composer']))

            if 'movement_name' in tags:
                if overwrite and 'MVNM' in audio.tags:
                    audio.tags.delall('MVNM')
                audio.tags.add(MVNM(encoding=3, text=tags['movement_name']))

            # Additional metadata fields
            if 'album_artist' in tags:
                if overwrite and 'TPE2' in audio.tags:
                    audio.tags.delall('TPE2')
                audio.tags.add(TPE2(encoding=3, text=tags['album_artist']))

            if 'conductor' in tags:
                if overwrite and 'TPE3' in audio.tags:
                    audio.tags.delall('TPE3')
                audio.tags.add(TPE3(encoding=3, text=tags['conductor']))

            if 'remixer' in tags:
                if overwrite and 'TPE4' in audio.tags:
                    audio.tags.delall('TPE4')
                audio.tags.add(TPE4(encoding=3, text=tags['remixer']))

            if 'publisher' in tags:
                if overwrite and 'TPUB' in audio.tags:
                    audio.tags.delall('TPUB')
                audio.tags.add(TPUB(encoding=3, text=tags['publisher']))

            if 'content_group' in tags:
                if overwrite and 'TIT1' in audio.tags:
                    audio.tags.delall('TIT1')
                audio.tags.add(TIT1(encoding=3, text=tags['content_group']))

            if 'comments' in tags:
                if isinstance(tags['comments'], list):
                    for comment in tags['comments']:
                        audio.tags.add(COMM(encoding=3, lang='eng', desc='', text=comment))
                else:
                    audio.tags.add(COMM(encoding=3, lang='eng', desc='', text=tags['comments']))

            # New taxonomy: descriptive -> configurable frame (default COMM)
            # Supports both list and string formats
            if 'descriptive' in tags:
                desc_value = tags['descriptive']
                if isinstance(desc_value, list):
                    # Join list into comma-separated string
                    desc_text = ', '.join(desc_value)
                else:
                    desc_text = desc_value
                descriptive_frame = self._get_frame("descriptive", "COMM", lexicon)
                self._write_to_frame(audio, descriptive_frame, desc_text)

            if 'description' in tags:
                # Write to TIT3 (Subtitle) - visible in Apple Music and Traktor
                if overwrite and 'TIT3' in audio.tags:
                    audio.tags.delall('TIT3')
                audio.tags.add(TIT3(encoding=3, text=tags['description']))

            # TIT1 field priority: mood > work > content_group
            # Only one can be written - mood takes precedence for new taxonomy
            if 'work' in tags and 'mood' not in tags:
                # Write to TIT1 (Content Group / Work) - legacy field, skipped if mood present
                audio.tags.add(TIT1(encoding=3, text=tags['work']))

            # New taxonomy: mood -> configurable frame (default TIT1)
            if 'mood' in tags:
                mood_frame = self._get_frame("mood", "TIT1", lexicon)
                self._write_to_frame(audio, mood_frame, tags['mood'])

            if 'custom' in tags and isinstance(tags['custom'], dict):
                for key, value in tags['custom'].items():
                    audio.tags.add(TXXX(encoding=3, desc=key, text=value))

            # Save with ID3v2.3 for better iTunes compatibility
            audio.save(v2_version=3)

            # Verify write by re-reading
            verify = MP3(audio_path, ID3=ID3)
            logger.debug("Saved tags to: %s", os.path.basename(audio_path))

            # Check what was actually written
            if 'description' in tags:
                if 'TIT3' in verify.tags:
                    logger.debug("Verified description (TIT3): %s...", str(verify.tags['TIT3'])[:40])
                else:
                    logger.warning("Description (TIT3) NOT found after save in %s", audio_path)

            if 'composer' in tags:
                if 'TCOM' in verify.tags:
                    logger.debug("Verified composer: %s", verify.tags['TCOM'])
                else:
                    logger.warning("Composer NOT found after save in %s", audio_path)

            if 'genre' in tags:
                if 'TCON' in verify.tags:
                    logger.debug("Verified genre: %s", verify.tags['TCON'])
                else:
                    logger.warning("Genre NOT found after save in %s", audio_path)

            if 'album' in tags:
                if 'TALB' in verify.tags:
                    logger.debug("Verified album: %s", verify.tags['TALB'])
                else:
                    logger.warning("Album NOT found after save in %s", audio_path)

            if 'work' in tags:
                # Check for TIT1 (Work) frame
                if 'TIT1' in verify.tags:
                    logger.debug("Verified work (TIT1): %s", verify.tags['TIT1'])
                else:
                    logger.warning("Work (TIT1) NOT found after save in %s", audio_path)

        except MutagenError as e:
            raise TagWriteError(f"Error writing tags to {audio_path}: {e}") from e
        except OSError as e:
            raise TagWriteError(f"Cannot access file {audio_path}: {e}") from e

    def write_likeness_scores(
        self,
        audio_path: str,
        comment_likeness: Optional[float] = None,
        overall_likeness: Optional[float] = None
    ) -> None:
        """
        Write likeness scores to standard ID3 tags for iTunes/Traktor compatibility.

        Writes zero-padded integers (0000-1000) to:
        - GRP1 (Grouping) for Overall Likeness
        - TCAT (Category) for Comment Likeness

        Zero-padding ensures correct lexicographic sorting in music players.

        Args:
            audio_path: Path to the MP3 file
            comment_likeness: Comment likeness score (0.0-1.0), or None to skip
            overall_likeness: Overall track likeness score (0.0-1.0), or None to skip
        """
        if comment_likeness is None and overall_likeness is None:
            return

        if not os.path.exists(audio_path):
            raise FileNotFoundError(f"File not found: {audio_path}")

        try:
            audio = MP3(audio_path, ID3=ID3)

            if audio.tags is None:
                audio.add_tags()

            # Write Overall Likeness to GRP1 (Grouping)
            if overall_likeness is not None:
                audio.tags.delall('GRP1')
                score_str = f"{int(overall_likeness * 1000):04d}"
                audio.tags.add(GRP1(encoding=3, text=score_str))

            # Write Comment Likeness to TCAT (Category)
            if comment_likeness is not None:
                audio.tags.delall('TCAT')
                score_str = f"{int(comment_likeness * 1000):04d}"
                audio.tags.add(TCAT(encoding=3, text=score_str))

            audio.save()

        except MutagenError as e:
            raise TagWriteError(f"Error writing likeness scores to {audio_path}: {e}") from e
        except OSError as e:
            raise TagWriteError(f"Cannot access file {audio_path}: {e}") from e

    def read_likeness_scores(self, audio_path: str) -> Dict[str, Optional[float]]:
        """
        Read likeness scores from GRP1 (Grouping) and TCAT (Category) tags.

        Returns:
            Dict with 'comment' and 'overall' keys, values are floats (0.0-1.0) or None
        """
        result = {'comment': None, 'overall': None}

        if not os.path.exists(audio_path):
            return result

        try:
            audio = MP3(audio_path, ID3=ID3)

            if audio.tags is None:
                return result

            # Read Overall Likeness from GRP1 (Grouping)
            if 'GRP1' in audio.tags:
                try:
                    value = str(audio.tags['GRP1'])
                    result['overall'] = int(value) / 1000.0
                except (ValueError, TypeError):
                    pass

            # Read Comment Likeness from TCAT (Category)
            if 'TCAT' in audio.tags:
                try:
                    value = str(audio.tags['TCAT'])
                    result['comment'] = int(value) / 1000.0
                except (ValueError, TypeError):
                    pass

        except Exception:
            pass

        return result

    def _extract_all_text_tags(self, tags: Dict[str, Any]) -> str:
        text_parts = []
        
        for key in self.standard_tags:
            if key in tags:
                text_parts.append(f"{tags[key]}")
        
        if 'comments' in tags:
            if isinstance(tags['comments'], list):
                text_parts.extend(tags['comments'])
            else:
                text_parts.append(tags['comments'])
        
        if 'custom' in tags and isinstance(tags['custom'], dict):
            for key, value in tags['custom'].items():
                text_parts.append(f"{key}: {value}")
        
        return " | ".join(text_parts)
    
    def extract_vocabulary(self, tag_list: List[Dict[str, Any]]) -> Dict[str, Any]:
        vocabulary = {
            'genres': set(),
            'artists': set(),
            'common_words': {},
            'custom_descriptors': {},
            'tag_patterns': []
        }
        
        for tags in tag_list:
            if 'genre' in tags:
                vocabulary['genres'].add(tags['genre'])
            
            if 'artist' in tags:
                vocabulary['artists'].add(tags['artist'])
            
            if 'comments' in tags:
                comments = tags['comments'] if isinstance(tags['comments'], list) else [tags['comments']]
                for comment in comments:
                    words = comment.lower().split()
                    for word in words:
                        vocabulary['common_words'][word] = vocabulary['common_words'].get(word, 0) + 1
            
            if 'custom' in tags and isinstance(tags['custom'], dict):
                for key, value in tags['custom'].items():
                    if key not in vocabulary['custom_descriptors']:
                        vocabulary['custom_descriptors'][key] = []
                    vocabulary['custom_descriptors'][key].append(value)
            
            if 'all_text' in tags:
                vocabulary['tag_patterns'].append(tags['all_text'])
        
        vocabulary['genres'] = list(vocabulary['genres'])
        vocabulary['artists'] = list(vocabulary['artists'])

        return vocabulary

    def cleanup_comment_tags(self, comment: str) -> str:
        """
        Clean up comment tags by fixing spacing and normalization issues.

        Rules:
        - Preserve multi-word tags: "Head Knodding", "Hi Hats", "Soulful / Musical", "Spoken Word"
        - Normalize casing for preserved tags
        - Convert standalone "Soulful" or "Musical" to "Soulful / Musical"
        - Only split space-separated words if BOTH words are known valid tags

        Args:
            comment: Raw comment string

        Returns:
            Cleaned comment string with proper comma separation
        """
        import re

        # Multi-word tags to preserve (lowercase for matching)
        PRESERVE_TAGS = {
            'head knodding': 'Head Knodding',
            'hi hats': 'Hi Hats',
            'soulful / musical': 'Soulful / Musical',
            'soulful/musical': 'Soulful / Musical',
            'spoken word': 'Spoken Word',
            'spokenword': 'Spoken Word',
        }

        # Known valid single-word tags (for splitting detection)
        KNOWN_TAGS = {
            'acapella', 'acid', 'afro', 'arabic', 'arpeggiated', 'asian',
            'beats', 'boomingbass', 'bouncy', 'broken',
            'chanting', 'classic', 'congas',
            'dirty', 'disco', 'dope', 'dreamy', 'driving', 'dubby',
            'electro', 'epic',
            'fun', 'funky',
            'glitchy', 'goofy', 'grindybass', 'grindy', 'guitar',
            'horns', 'hypnotic',
            'jazzy', 'joyful', 'jungle',
            'latin', 'loopy',
            'melodic',
            'organ',
            'pads', 'piano', 'poppy', 'punchy',
            'rap', 'relaxed',
            'singing', 'spiritual', 'strings', 'sweeps', 'swung',
            'tech', 'techno', 'techy', 'tropical',
            'walkingbass', 'weird',
        }

        # Tags to convert to "Soulful / Musical"
        CONVERT_TO_SOULFUL_MUSICAL = {'soulful', 'musical'}

        # First, protect multi-word tags by replacing with placeholders
        protected = comment
        placeholder_map = {}
        for i, (pattern, replacement) in enumerate(PRESERVE_TAGS.items()):
            placeholder = f"__PROTECTED_{i}__"
            # Case-insensitive replacement
            regex = re.compile(re.escape(pattern), re.IGNORECASE)
            if regex.search(protected):
                protected = regex.sub(placeholder, protected)
                placeholder_map[placeholder] = replacement

        # Split by comma first
        parts = [p.strip() for p in protected.split(',') if p.strip()]

        cleaned_tags = []
        for part in parts:
            # Check if this part contains a placeholder
            has_placeholder = any(ph in part for ph in placeholder_map.keys())

            if has_placeholder:
                # Restore the placeholder and add as-is
                for placeholder, replacement in placeholder_map.items():
                    part = part.replace(placeholder, replacement)
                cleaned_tags.append(part.strip())
            else:
                # Check if this might be multiple space-separated tags
                words = part.split()
                if len(words) == 2:
                    # Only split if BOTH words are known tags
                    word1, word2 = words[0].strip(), words[1].strip()
                    word1_is_tag = word1.lower() in KNOWN_TAGS or word1.lower() in CONVERT_TO_SOULFUL_MUSICAL
                    word2_is_tag = word2.lower() in KNOWN_TAGS or word2.lower() in CONVERT_TO_SOULFUL_MUSICAL

                    if word1_is_tag and word2_is_tag:
                        # Split them
                        for word in [word1, word2]:
                            if word.lower() in CONVERT_TO_SOULFUL_MUSICAL:
                                if 'Soulful / Musical' not in cleaned_tags:
                                    cleaned_tags.append('Soulful / Musical')
                            else:
                                cleaned_tags.append(word)
                    else:
                        # Keep as-is, just handle Soulful/Musical conversion
                        if part.strip().lower() in CONVERT_TO_SOULFUL_MUSICAL:
                            if 'Soulful / Musical' not in cleaned_tags:
                                cleaned_tags.append('Soulful / Musical')
                        else:
                            cleaned_tags.append(part.strip())
                elif len(words) == 1:
                    word = part.strip()
                    if word:
                        # Check for Soulful/Musical conversion
                        if word.lower() in CONVERT_TO_SOULFUL_MUSICAL:
                            if 'Soulful / Musical' not in cleaned_tags:
                                cleaned_tags.append('Soulful / Musical')
                        else:
                            cleaned_tags.append(word)
                else:
                    # More than 2 words - keep as-is (might be a phrase or metadata)
                    cleaned_tags.append(part.strip())

        # Remove duplicates while preserving order
        seen = set()
        unique_tags = []
        for tag in cleaned_tags:
            tag_lower = tag.lower()
            if tag_lower not in seen:
                seen.add(tag_lower)
                unique_tags.append(tag)

        return ', '.join(unique_tags)

    def cleanup_comments_in_file(
        self,
        audio_path: str,
        dry_run: bool = True
    ) -> Dict[str, Any]:
        """
        Clean up comment tags in a single MP3 file.

        Args:
            audio_path: Path to MP3 file
            dry_run: If True, don't write changes

        Returns:
            Dict with 'file', 'original', 'cleaned', 'changed' keys
        """
        tags = self.read_tags(audio_path)

        result = {
            'file': audio_path,
            'original': None,
            'cleaned': None,
            'changed': False
        }

        if 'comments' not in tags or not tags['comments']:
            return result

        # Process each comment (usually just one)
        original_comments = tags['comments']
        cleaned_comments = []

        for comment in original_comments:
            # Skip non-tag comments (like energy/key info from other tools)
            if 'Energy' in comment and 'Visit http' in comment:
                cleaned_comments.append(comment)
                continue
            if comment.startswith(('7', '8', '9', '10', '11', '12')) and 'Energy' in comment:
                cleaned_comments.append(comment)
                continue

            cleaned = self.cleanup_comment_tags(comment)
            cleaned_comments.append(cleaned)

        result['original'] = original_comments
        result['cleaned'] = cleaned_comments
        result['changed'] = original_comments != cleaned_comments

        if result['changed'] and not dry_run:
            self.write_tags(audio_path, {'comments': cleaned_comments}, overwrite=True)

        return result