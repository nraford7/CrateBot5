"""
Vibe Generator - LLM-powered descriptive tag generation for audio files.

Uses Claude API to generate evocative vibe descriptions based on audio
features and existing ID3 tags.

Format: [VIBE GENRE], [MEMORABLE HOOK], [WHEN/WHERE]

Examples:
- "HYPNOTIC MINIMAL, BASSLINE BURROWING INTO YOUR SKULL, WAREHOUSE 4AM"
- "WARM DEEPHOUSE, JAZZ PIANO DRIPPING NOSTALGIA, SUNSET TERRACE"
- "GRITTY ACID, 303 SCREAMING BLOODY MURDER, SECRET WEAPON"

Output is stored in the Composer (TCOM) ID3 tag.
An expanded natural language description is stored in the Description (TXXX) tag.
"""

import os
import random
from typing import Dict, Any, Optional, List
from dataclasses import dataclass
import json

from .paths import get_cratebot_dir
# Optional anthropic import
try:
    import anthropic
    HAS_ANTHROPIC = True
except ImportError:
    HAS_ANTHROPIC = False

# Retry logic for API calls
try:
    from tenacity import (
        retry,
        stop_after_attempt,
        wait_exponential,
        retry_if_exception_type,
        before_sleep_log,
    )
    HAS_TENACITY = True
except ImportError:
    HAS_TENACITY = False

import logging
logger = logging.getLogger(__name__)

# Import tag lexicon with user-defined meanings
try:
    from core.tag_lexicon import TAG_LEXICON_PROMPT
    from core.constants import CLAUDE_MODEL, CLAUDE_MAX_TOKENS_VIBE, VIBE_TEMPERATURE
    HAS_LEXICON = True
except ImportError:
    try:
        from src.core.tag_lexicon import TAG_LEXICON_PROMPT
        from src.core.constants import CLAUDE_MODEL, CLAUDE_MAX_TOKENS_VIBE, VIBE_TEMPERATURE
        HAS_LEXICON = True
    except ImportError:
        TAG_LEXICON_PROMPT = ""
        HAS_LEXICON = False
        # Fallback constants if imports fail
        CLAUDE_MODEL = "claude-sonnet-4-20250514"
        CLAUDE_MAX_TOKENS_VIBE = 150
        VIBE_TEMPERATURE = 0.9


@dataclass
class VibeContext:
    """Context data for vibe generation."""
    # Audio features
    tempo: float
    energy: float
    danceability: float
    mood_happy: float
    mood_sad: float
    mood_aggressive: float
    mood_relaxed: float
    voice_instrumental: float  # 0=instrumental, 1=vocal
    arousal: float  # 1-9 scale
    valence: float  # 1-9 scale

    # ID3 tags
    title: Optional[str] = None
    artist: Optional[str] = None
    album: Optional[str] = None
    genre: Optional[str] = None
    comments: Optional[List[str]] = None

    # Scene/origin (estimated)
    scene: Optional[str] = None
    scene_description: Optional[str] = None

    # Detected sounds from PANNs (concrete elements)
    detected_instruments: Optional[List[str]] = None
    detected_drums: Optional[List[str]] = None
    detected_vocals: Optional[List[str]] = None
    detected_genres: Optional[List[str]] = None
    detected_mood: Optional[List[str]] = None

    # Transcribed vocal hook (from HookTranscriber or Claude)
    vocal_hook: Optional[str] = None
    vocal_hook_occurrences: int = 0

    # Full transcription for Claude to identify hook (preferred over pre-computed hook)
    vocal_transcription: Optional[str] = None

    def to_prompt_context(self) -> str:
        """Format context for LLM prompt."""
        lines = []

        # Audio characteristics
        lines.append("## Audio Analysis")
        lines.append(f"- Tempo: {self.tempo:.0f} BPM")
        lines.append(f"- Energy level: {self._describe_scale(self.energy, 'low', 'medium', 'high')}")
        lines.append(f"- Danceability: {self._describe_scale(self.danceability, 'not danceable', 'somewhat danceable', 'very danceable')}")

        # Voice
        if self.voice_instrumental < 0.3:
            lines.append(f"- Type: Instrumental")
        elif self.voice_instrumental > 0.7:
            lines.append(f"- Type: Vocal")
        else:
            lines.append(f"- Type: Mixed vocal/instrumental")

        # Combined emotional analysis (replaces separate mood/arousal/valence)
        emotional_quadrant = self._get_emotional_quadrant()
        dominant_vibe = self._get_dominant_vibe()
        lines.append(f"- Emotional character: {emotional_quadrant}")
        lines.append(f"- Dominant vibe: {dominant_vibe}")

        # Detected sounds from PANNs (concrete elements)
        # Put genre FIRST and prominently - this is critical for accurate tagging
        if self.detected_genres:
            lines.append(f"\n## DETECTED GENRE (use this!)")
            lines.append(f"- Primary style: {self.detected_genres[0]}")
            if len(self.detected_genres) > 1:
                lines.append(f"- Secondary: {', '.join(self.detected_genres[1:3])}")

        detected_parts = []
        if self.detected_instruments:
            detected_parts.append(f"Instruments: {', '.join(self.detected_instruments[:4])}")
        if self.detected_drums:
            detected_parts.append(f"Drums: {', '.join(self.detected_drums[:3])}")
        if self.detected_vocals:
            detected_parts.append(f"Vocals: {', '.join(self.detected_vocals[:2])}")
        if self.detected_mood:
            detected_parts.append(f"Mood: {', '.join(self.detected_mood[:2])}")

        if detected_parts:
            lines.append("\n## Detected Sounds")
            for part in detected_parts:
                lines.append(f"- {part}")

        # Transcribed vocals - prefer full transcription for Claude to analyze
        if self.vocal_transcription:
            lines.append(f"\n## VOCAL TRANSCRIPTION (identify the hook!)")
            lines.append(f"Transcribed lyrics/vocals from this track:")
            lines.append(f"\"{self.vocal_transcription}\"")
            lines.append(f"→ Find the most memorable/catchy hook phrase from above (if any)")
        elif self.vocal_hook:
            # Fallback to pre-computed hook if no transcription
            lines.append(f"\n## VOCAL HOOK (include in vibe!)")
            lines.append(f"- Hook: \"{self.vocal_hook}\"")
            if self.vocal_hook_occurrences > 0:
                lines.append(f"- Repeated {self.vocal_hook_occurrences}x in track")

        # Existing metadata
        if any([self.title, self.artist, self.album, self.genre, self.comments]):
            lines.append("\n## Existing Tags")
            if self.title:
                lines.append(f"- Title: {self.title}")
            if self.artist:
                lines.append(f"- Artist: {self.artist}")
            if self.album:
                lines.append(f"- Album: {self.album}")
            if self.genre:
                lines.append(f"- Genre: {self.genre}")
            if self.comments:
                comments_str = ", ".join(self.comments[:5])  # Limit to 5
                lines.append(f"- Comments/Tags: {comments_str}")

        # Scene/origin - disabled for now (was too formulaic)
        # if self.scene:
        #     lines.append(f"\n## Scene/Origin")
        #     lines.append(f"- Scene: {self.scene}")
        #     if self.scene_description:
        #         lines.append(f"- Style: {self.scene_description}")

        return "\n".join(lines)

    def _describe_scale(self, value: float, low: str, mid: str, high: str) -> str:
        """Convert 0-1 value to descriptive text."""
        if value < 0.33:
            return low
        elif value < 0.66:
            return mid
        else:
            return high

    def _get_emotional_quadrant(self) -> str:
        """
        Map arousal + valence to emotional quadrant using circumplex model.

        High arousal + High valence = Euphoric/Energetic/Uplifting
        High arousal + Low valence = Aggressive/Tense/Driving
        Low arousal + High valence = Peaceful/Dreamy/Warm
        Low arousal + Low valence = Melancholic/Introspective/Dark
        """
        # Normalize arousal from 1-9 to 0-1 scale
        arousal_norm = (self.arousal - 1) / 8.0
        valence_norm = (self.valence - 1) / 8.0

        high_arousal = arousal_norm > 0.5
        high_valence = valence_norm > 0.5

        # Get intensity modifier
        if arousal_norm > 0.75:
            intensity = "intensely "
        elif arousal_norm > 0.6:
            intensity = ""
        elif arousal_norm < 0.25:
            intensity = "subtly "
        else:
            intensity = ""

        if high_arousal and high_valence:
            return f"{intensity}euphoric/energetic/uplifting"
        elif high_arousal and not high_valence:
            return f"{intensity}aggressive/tense/driving"
        elif not high_arousal and high_valence:
            return f"{intensity}peaceful/dreamy/warm"
        else:  # low arousal, low valence
            return f"{intensity}melancholic/introspective/dark"

    def _get_dominant_vibe(self) -> str:
        """
        Determine dominant vibe from explicit mood scores.

        Returns the primary mood, and secondary if it's significant.
        """
        moods = [
            ('happy/joyful', self.mood_happy),
            ('sad/emotional', self.mood_sad),
            ('aggressive/intense', self.mood_aggressive),
            ('relaxed/hypnotic', self.mood_relaxed),
        ]

        # Sort by score descending
        sorted_moods = sorted(moods, key=lambda x: x[1], reverse=True)

        primary_name, primary_score = sorted_moods[0]
        secondary_name, secondary_score = sorted_moods[1]

        # If no strong signal, return neutral
        if primary_score < 0.3:
            return "neutral/balanced"

        # If secondary is significant (within 70% of primary), mention both
        if secondary_score > primary_score * 0.7 and secondary_score > 0.25:
            return f"{primary_name} with {secondary_name} undertones"

        # Strong primary mood
        if primary_score > 0.6:
            return f"strongly {primary_name}"

        return primary_name


class SceneEstimator:
    """
    Estimates the geographic/cultural scene origin of a track based on
    audio characteristics and existing tags.

    Returns scene names like "Berlin", "Chicago", "Detroit", "London", etc.
    that represent the stylistic lineage of the track.
    """

    # Scene profiles with audio characteristics and keyword associations
    # Each scene has evocative venue/time references for the movement_name tag
    SCENE_PROFILES = {
        "Berlin": {
            "description": "Berlin techno / industrial",
            "venues": ["Tresor basement", "Berghain Panorama Bar", "About Blank garden", "Griessmuehle 5am", "Kraftwerk main hall"],
            "audio": {
                "mood_aggressive": (0.35, 1.0),  # (min, max)
                "danceability": (0.5, 1.0),
                "tempo": (125, 150),
                "voice_instrumental": (0.0, 0.4),  # Mostly instrumental
            },
            "keywords": ["minimal", "industrial", "dark", "hypnotic", "warehouse",
                        "techno", "driving", "pounding", "relentless", "stripped"],
            "genres": ["techno", "minimal", "industrial", "dark techno"],
            "weight": 1.0,
        },
        "Detroit": {
            "description": "Detroit techno / electro",
            "venues": ["Movement Festival main stage", "TV Lounge late night", "Marble Bar backroom", "The Works 3am"],
            "audio": {
                "mood_sad": (0.2, 0.7),
                "arousal": (4, 8),
                "tempo": (120, 140),
            },
            "keywords": ["futuristic", "soul", "strings", "electro", "cosmic",
                        "machine", "funk", "robotic", "underground resistance"],
            "genres": ["techno", "electro", "detroit"],
            "weight": 1.0,
        },
        "Chicago": {
            "description": "Chicago house / acid",
            "venues": ["The Warehouse midnight", "Smartbar peak hour", "Medusa's all ages", "Gramaphone Records basement", "Queen! at Smartbar"],
            "audio": {
                "mood_happy": (0.3, 1.0),
                "danceability": (0.6, 1.0),
                "voice_instrumental": (0.3, 1.0),  # Often vocal
            },
            "keywords": ["soulful", "vocal", "piano", "organ", "jacking", "acid",
                        "303", "gospel", "warm", "classic", "jack"],
            "genres": ["house", "acid", "deep house", "gospel house", "jack"],
            "weight": 1.0,
        },
        "London": {
            "description": "London bass music / breaks",
            "venues": ["Fabric Room 1", "Ministry of Sound box", "Corsica Studios 4am", "XOYO Friday", "Plastic People basement"],
            "audio": {
                "tempo": (130, 180),
                "mood_aggressive": (0.2, 0.8),
            },
            "keywords": ["breakbeat", "jungle", "garage", "bass", "grime", "dubstep",
                        "uk", "rave", "breaks", "drum and bass", "dnb", "2step"],
            "genres": ["jungle", "dnb", "drum and bass", "garage", "uk garage",
                      "dubstep", "grime", "breaks", "breakbeat"],
            "weight": 1.0,
        },
        "Ibiza": {
            "description": "Ibiza / Balearic",
            "venues": ["DC10 Circoloco terrace", "Space closing party", "Amnesia foam room", "Cafe del Mar sunset", "Pacha main room"],
            "audio": {
                "mood_happy": (0.4, 1.0),
                "mood_relaxed": (0.25, 0.8),
                "arousal": (4, 8),
            },
            "keywords": ["melodic", "progressive", "balearic", "sunset", "euphoric",
                        "anthem", "vocal", "uplifting", "trance", "summer"],
            "genres": ["trance", "progressive", "balearic", "progressive house"],
            "weight": 1.0,
        },
        "New York": {
            "description": "NYC disco / garage",
            "venues": ["Paradise Garage 4am", "The Loft Sunday afternoon", "Body & Soul party", "Output rooftop", "Elsewhere Hall"],
            "audio": {
                "danceability": (0.6, 1.0),
                "mood_happy": (0.35, 1.0),
            },
            "keywords": ["disco", "funk", "loft", "paradise garage", "vocal",
                        "diva", "boogie", "soulful", "club", "freestyle"],
            "genres": ["disco", "house", "garage", "disco house", "boogie"],
            "weight": 0.9,  # Slightly lower to avoid over-matching
        },
        "San Francisco": {
            "description": "SF disco / cosmic",
            "venues": ["Honey Soundsystem party", "Sunset at Dolores Park", "EndUp Sunday morning", "Monarch basement"],
            "audio": {
                "mood_relaxed": (0.3, 0.8),
                "valence": (5, 9),
                "mood_happy": (0.3, 1.0),
            },
            "keywords": ["disco", "funky", "edit", "cosmic", "re-edit", "nu-disco",
                        "psychedelic", "west coast", "italo"],
            "genres": ["disco house", "nu-disco", "cosmic", "italo disco"],
            "weight": 0.85,
        },
        "Manchester": {
            "description": "Manchester acid / rave",
            "venues": ["Hacienda Friday night", "Warehouse Project peak", "Hidden club 3am", "White Hotel basement"],
            "audio": {
                "mood_aggressive": (0.15, 0.55),
                "tempo": (120, 135),
            },
            "keywords": ["acid", "rave", "hacienda", "808", "madchester",
                        "second summer of love", "bleep"],
            "genres": ["acid house", "rave", "bleep techno"],
            "weight": 0.8,
        },
        "Miami": {
            "description": "Miami bass / Latin",
            "venues": ["Club Space terrace sunrise", "III Points Festival", "Do Not Sit poolside", "Heart Nightclub"],
            "audio": {
                "danceability": (0.7, 1.0),
                "mood_happy": (0.4, 1.0),
            },
            "keywords": ["bass", "booty", "latin", "freestyle", "electro",
                        "caribbean", "reggaeton"],
            "genres": ["miami bass", "freestyle", "latin house", "reggaeton"],
            "weight": 0.75,
        },
        "Amsterdam": {
            "description": "Amsterdam trance / gabber",
            "venues": ["Paradiso main hall", "De School all night", "Shelter basement", "ADE showcase"],
            "audio": {
                "tempo": (135, 180),
                "mood_aggressive": (0.3, 1.0),
                "arousal": (6, 9),
            },
            "keywords": ["trance", "gabber", "hardcore", "hardstyle", "dutch",
                        "euphoric", "anthem"],
            "genres": ["trance", "gabber", "hardcore", "hardstyle"],
            "weight": 0.85,
        },
        "Paris": {
            "description": "French touch / filter house",
            "venues": ["Rex Club 2am", "Concrete barge party", "Silencio late night", "Garage cocktail lounge"],
            "audio": {
                "danceability": (0.6, 1.0),
                "mood_happy": (0.4, 1.0),
            },
            "keywords": ["french", "filter", "disco", "touch", "funky",
                        "sample", "vocal chop", "ed banger"],
            "genres": ["french house", "filter house", "french touch", "nu-disco"],
            "weight": 0.8,
        },
        "Jamaica": {
            "description": "Jamaican dub / dancehall",
            "venues": ["King Tubby studio session", "Dancehall street party", "Sound system clash", "Studio One vibes"],
            "audio": {
                "mood_relaxed": (0.3, 0.9),
            },
            "keywords": ["dub", "reggae", "dancehall", "riddim", "sound system",
                        "delay", "echo", "roots", "steppers"],
            "genres": ["dub", "reggae", "dancehall", "dub techno"],
            "weight": 0.85,
        },
        "Barcelona": {
            "description": "Barcelona terrace / Mediterranean",
            "venues": ["Sonar Festival day stage", "Razzmatazz Loft", "Nitsa rooftop", "Primavera Sound tent"],
            "audio": {
                "mood_happy": (0.35, 1.0),
                "danceability": (0.5, 1.0),
                "mood_relaxed": (0.2, 0.6),
            },
            "keywords": ["terrace", "mediterranean", "melodic", "sunset", "beach",
                        "spanish", "festival", "outdoor"],
            "genres": ["tech house", "melodic house", "progressive"],
            "weight": 0.75,
        },
        "Tokyo": {
            "description": "Tokyo underground / future",
            "venues": ["Womb main room 5am", "Contact basement", "Vent late night", "Dommune broadcast"],
            "audio": {
                "danceability": (0.5, 1.0),
                "mood_aggressive": (0.1, 0.5),
            },
            "keywords": ["japanese", "future", "experimental", "ambient", "noise",
                        "j-pop", "city pop", "shibuya"],
            "genres": ["house", "techno", "ambient", "experimental"],
            "weight": 0.7,
        },
    }

    def __init__(self):
        """Initialize the scene estimator."""
        pass

    def estimate_scene(
        self,
        audio_features: Dict[str, Any],
        tags: Dict[str, Any]
    ) -> Dict[str, Any]:
        """
        Estimate the most likely scene/origin for a track.

        Args:
            audio_features: Dictionary from audio analyzer
            tags: Dictionary from TagManager.read_tags()

        Returns:
            Dict with:
                - 'scene': Primary scene name (e.g., "Berlin")
                - 'confidence': Confidence score (0.0-1.0)
                - 'description': Scene description (e.g., "Berlin techno / industrial")
                - 'runner_up': Second-best scene if close
        """
        scores = {}

        for scene_name, profile in self.SCENE_PROFILES.items():
            score = self._score_scene(scene_name, profile, audio_features, tags)
            scores[scene_name] = score * profile.get('weight', 1.0)

        # Sort by score
        sorted_scenes = sorted(scores.items(), key=lambda x: x[1], reverse=True)

        if not sorted_scenes or sorted_scenes[0][1] == 0:
            return {
                'scene': 'Underground warehouse 3am',  # Fallback
                'scene_short': 'Underground',
                'confidence': 0.0,
                'description': 'Underground electronic',
                'runner_up': None,
            }

        top_scene, top_score = sorted_scenes[0]
        max_possible = 3.0  # Approximate max score
        profile = self.SCENE_PROFILES[top_scene]

        # Pick a random venue from the scene's venues list
        venues = profile.get('venues', [f"{top_scene} underground"])
        venue = random.choice(venues) if venues else top_scene

        result = {
            'scene': venue,  # Now returns evocative venue name
            'scene_short': top_scene,  # Original scene name for reference
            'confidence': min(1.0, top_score / max_possible),
            'description': profile['description'],
            'runner_up': None,
        }

        # Check for close runner-up
        if len(sorted_scenes) > 1:
            runner_up_scene, runner_up_score = sorted_scenes[1]
            if runner_up_score > top_score * 0.7:  # Within 30%
                result['runner_up'] = runner_up_scene

        return result

    def _score_scene(
        self,
        scene_name: str,
        profile: Dict[str, Any],
        audio_features: Dict[str, Any],
        tags: Dict[str, Any]
    ) -> float:
        """
        Score how well a track matches a scene profile.

        Returns a score from 0.0 to ~3.0 based on:
        - Audio characteristic matches (0-1)
        - Keyword matches in tags (0-1)
        - Genre matches (0-1)
        """
        score = 0.0

        # 1. Audio characteristics (up to 1.0)
        audio_score = self._score_audio_match(profile.get('audio', {}), audio_features)
        score += audio_score

        # 2. Keyword matches in comments/tags (up to 1.0)
        keyword_score = self._score_keyword_match(profile.get('keywords', []), tags)
        score += keyword_score

        # 3. Genre matches (up to 1.0)
        genre_score = self._score_genre_match(profile.get('genres', []), tags)
        score += genre_score

        return score

    def _score_audio_match(
        self,
        audio_profile: Dict[str, tuple],
        audio_features: Dict[str, Any]
    ) -> float:
        """Score audio characteristic matches."""
        if not audio_profile:
            return 0.0

        matches = 0
        total = len(audio_profile)

        for feature_name, (min_val, max_val) in audio_profile.items():
            # Map feature names to audio_features keys
            key_map = {
                'mood_aggressive': 'essentia_mood_aggressive',
                'mood_happy': 'essentia_mood_happy',
                'mood_sad': 'essentia_mood_sad',
                'mood_relaxed': 'essentia_mood_relaxed',
                'danceability': 'essentia_danceability',
                'voice_instrumental': 'essentia_voice_instrumental',
                'arousal': 'essentia_arousal',
                'valence': 'essentia_valence',
                'tempo': 'tempo',
            }

            actual_key = key_map.get(feature_name, feature_name)
            value = audio_features.get(actual_key)

            if value is None:
                continue

            # Normalize arousal/valence from 1-9 to 0-1 for comparison
            if feature_name in ('arousal', 'valence'):
                # Keep as-is for tempo-style range comparison
                pass

            if min_val <= value <= max_val:
                matches += 1
            elif value < min_val:
                # Partial credit for being close
                distance = (min_val - value) / max(min_val, 0.1)
                matches += max(0, 1 - distance)
            else:
                distance = (value - max_val) / max(max_val, 0.1)
                matches += max(0, 1 - distance)

        return matches / total if total > 0 else 0.0

    def _score_keyword_match(
        self,
        keywords: List[str],
        tags: Dict[str, Any]
    ) -> float:
        """Score keyword matches in tags."""
        if not keywords:
            return 0.0

        # Collect all text from tags
        text_sources = []

        if tags.get('comments'):
            comments = tags['comments']
            if isinstance(comments, list):
                text_sources.extend(comments)
            else:
                text_sources.append(comments)

        if tags.get('genre'):
            text_sources.append(tags['genre'])

        if tags.get('album'):
            text_sources.append(tags['album'])

        if tags.get('title'):
            text_sources.append(tags['title'])

        # Combine and lowercase
        all_text = ' '.join(text_sources).lower()

        # Count keyword matches
        matches = sum(1 for kw in keywords if kw.lower() in all_text)

        # Normalize: 2+ matches = full score, 1 match = 0.5
        if matches >= 2:
            return 1.0
        elif matches == 1:
            return 0.5
        return 0.0

    def _score_genre_match(
        self,
        genres: List[str],
        tags: Dict[str, Any]
    ) -> float:
        """Score genre matches."""
        if not genres:
            return 0.0

        tag_genre = (tags.get('genre') or '').lower()

        # Also check album tag (often used for sub-genre info)
        tag_album = (tags.get('album') or '').lower()

        for genre in genres:
            genre_lower = genre.lower()
            if genre_lower in tag_genre or genre_lower in tag_album:
                return 1.0
            # Partial match
            if any(word in tag_genre for word in genre_lower.split()):
                return 0.7

        return 0.0

    def get_scene_description(self, scene: str) -> str:
        """Get the full description for a scene."""
        profile = self.SCENE_PROFILES.get(scene, {})
        return profile.get('description', scene)


class VibeGenerator:
    """
    Generate vibe descriptions using Claude API.

    Format: Intuitive adjective stacking (5-8 words, no commas)

    Examples:
    - "DOPE CHUGGING DESERT PEAK GROOVE"
    - "SICK GRINDY AFRO WALKING BASS BUILDER"
    - "DREAMY BROKEN JAZZY ORGAN NOODLE"
    - "FIERCE ARABIC BOOMING BASS SLAMMER"
    """

    SYSTEM_PROMPT = """You are a DJ identifying what makes each track MEMORABLE and DISTINCTIVE. Your job is to create a scannable tag that captures the track's essence in a specific structure.

## THE STRUCTURE: [ENERGY] [DISTINCTIVE THING] [MOMENT]

1. **ENERGY** (1-2 words) - The mood/feel of the track
   → dark, heavy, joyful, grindy, smooth, raw, warm, cold, dreamy, nasty, fierce, lush

2. **DISTINCTIVE THING** (2-4 words) - What makes THIS track stand out
   → The unusual element, the hook, what you'd remember it by
   → Ask: "What would make me pick THIS track over similar ones?"
   → Be specific: "PITCHED VOCAL CHOP" not "VOCALS", "GRINDING SAW BASS" not "BASS"
   → If an instrument is unusual for the genre (flute in techno, steel drums in house), highlight it

3. **MOMENT** (1 word) - What kind of track / when to play it
   → PEAK, BUILDER, OPENER, JOURNEY, SLAMMER, STOMPER, CRUISER, GROOVER, FLOATER

## FINDING THE DISTINCTIVE THING

Look for what's UNUSUAL, not what's typical:
- A walking bassline in house is expected. A walking bassline in techno is notable.
- Standard kick-hat patterns are boring. Unusual percussion or broken rhythms stand out.
- If PANNs detected something unexpected for the genre, that's probably the hook.

The distinctive thing should answer: "What would I tell a friend to listen for?"

## EXAMPLES

DARK GRINDING SAW BASS PEAK
HEAVY ARABIC FLUTE LOOP BUILDER
JOYFUL STEEL DRUMS GROOVE OPENER
SMOOTH WALKING JAZZ BASS CRUISER
GRINDY PITCHED VOCAL CHOP SLAMMER
DREAMY UNDERWATER SYNTH PAD JOURNEY
NASTY DISTORTED KICK STOMPER
RAW TRIBAL CHANTING BUILD
WEIRD DETUNED PIANO STABS HYPNOTIC
FILTHY ACID 303 LINE PEAK
WARM RHODES CHORDS SUNRISE FLOATER
FIERCE AFRO PERCUSSION BREAKDOWN PEAK

## CRITICAL RULES

1. **4-8 WORDS** - Flexible, but structure matters more than count
2. **NO COMMAS** - Space-separated words only
3. **ALL CAPS** - Always
4. **STRUCTURE OVER TEMPLATE** - [ENERGY] [DISTINCTIVE THING] [MOMENT] - not random adjective stacking
5. **DISTINCTIVE BEATS GENERIC** - "WEIRD PITCHED VOCAL" beats "DOPE FUNKY GROOVE"
6. **OUTLIERS ARE HOOKS** - Unusual instruments/sounds for the genre = the memorable thing
""" + (TAG_LEXICON_PROMPT if HAS_LEXICON else "")

    USER_PROMPT_TEMPLATE = """Generate an adjective-stack tag for this track:

{context}

PROCESS:
1. GUT REACTION - What's your first feeling? (dope? sick? beautiful? heavy? weird? insane?)
2. TEXTURE - What does the rhythm feel like physically? (grindy? chugging? bouncy? broken? loopy?)
3. GENRE/REGION - What style or geographic flavor? (use detected genre, or regional marker like AFRO, DESERT, CHICAGO)
4. SONIC STANDOUT - What instrument/element defines it? (walking bass? steel drums? chanting? flute? acid?)
5. ENDING - Anchor noun (GROOVE, BUILD, SLAMMER) or trailing vibe (GROOVY, SICK, SMOOTH)

Stack 5-8 words. No commas. Match the energy - dark tracks get dark words, joyful tracks get bright words.

ALSO: If there's a vocal transcription above, identify the most memorable/catchy hook phrase (3-6 words that would be the earworm). Not filler like "come on" or "let's go" - the ACTUAL memorable phrase.

Respond in this EXACT format:
VIBE: [YOUR 5-8 WORD TAG IN ALL CAPS]
HOOK: [the catchy hook phrase, or NONE if no clear hook]

Example response:
VIBE: FIERCE AFRO BROKEN GRINDY BASS BUILDER
HOOK: killers in the jungle"""

    DESCRIPTION_SYSTEM_PROMPT = """You are a poet channeling music into vivid imagery. Each track evokes a moment, a place, a fleeting scene. Your job is to capture that in a single striking image.

## YOUR MISSION
Transform sound into a sensory snapshot. Not what the track IS, but what it FEELS LIKE. Paint a picture. Set a scene. Evoke a memory that never happened.

## EVOKE THESE DIMENSIONS
- **Place**: abandoned warehouse, neon-lit alley, sun-drenched rooftop, fog-wrapped coastline, basement speakeasy
- **Moment**: 4am revelation, first light through blinds, the drop before the storm, strangers becoming friends
- **Sensation**: sweat on skin, bass in chest, wind through hair, electricity in fingertips
- **Character**: the last dancer standing, shadows moving in unison, a city breathing at night

## STYLE
- Lowercase, poetic, fragmentary
- 10-20 words maximum
- No technical DJ language - pure imagery
- Surprise me. Be weird. Be beautiful. Be memorable.
- Each description must be utterly unique

## EXAMPLES
- "3am in a city that forgot to sleep, neon bleeding through rain-streaked windows"
- "desert highway at dusk, dust devils dancing in the rearview mirror"
- "that moment the basement becomes a cathedral and strangers become congregation"
- "steam rising from concrete after summer rain, bodies moving like smoke"
- "the last hour of the party when time stops and everything glows"
- "midnight swim in black water, stars above, bass below"
- "abandoned factory where machines dream of dancing"
- "sunrise through warehouse skylights, dust motes floating like confetti"
- "two strangers sharing headphones on the night bus home"
- "the weight of a city lifting as the beat drops"
"""

    DESCRIPTION_USER_PROMPT_TEMPLATE = """Evoke this track in 10-20 words of pure imagery.

VIBE TAG: {vibe}
{track_context}
{context}

Close your eyes. Let the sound paint a scene. Where are you? What do you see? What do you feel?

Write a single poetic fragment - lowercase, vivid, surprising. No genre words, no DJ speak. Just the image.

Respond with ONLY the poetic fragment. No quotes."""

    def __init__(self, api_key: Optional[str] = None, model: str = CLAUDE_MODEL):
        """
        Initialize the vibe generator.

        Args:
            api_key: Anthropic API key. If None, reads from config or ANTHROPIC_API_KEY env var.
            model: Claude model to use. Default is defined in constants.py for speed/cost balance.
        """
        if api_key:
            self.api_key = api_key
        else:
            # Use the module-level function that has all fallbacks
            self.api_key = _get_api_key()
        self.model = model
        self._client = None

    @property
    def is_available(self) -> bool:
        """Check if vibe generation is available."""
        return HAS_ANTHROPIC and bool(self.api_key)

    @property
    def client(self) -> "anthropic.Anthropic":
        """Lazy-load the Anthropic client."""
        if not HAS_ANTHROPIC:
            raise RuntimeError("anthropic package not installed. Run: pip install anthropic")
        if not self.api_key:
            raise RuntimeError("No API key. Set ANTHROPIC_API_KEY environment variable.")
        if self._client is None:
            self._client = anthropic.Anthropic(api_key=self.api_key)
        return self._client

    def _call_api(
        self,
        messages: List[Dict[str, str]],
        system: str,
        max_tokens: int,
        temperature: float
    ):
        """
        Make an API call to Claude, with retry logic if tenacity is available.

        Retries on transient errors (rate limits, connection issues, timeouts)
        with exponential backoff.
        """
        return self.client.messages.create(
            model=self.model,
            max_tokens=max_tokens,
            temperature=temperature,
            system=system,
            messages=messages
        )

    def _call_api_with_retry(
        self,
        messages: List[Dict[str, str]],
        system: str,
        max_tokens: int,
        temperature: float
    ):
        """
        Make an API call with retry logic for transient failures.

        Uses tenacity for exponential backoff on:
        - Rate limit errors (429)
        - Connection errors
        - Timeout errors
        """
        if not HAS_TENACITY or not HAS_ANTHROPIC:
            # Fall back to simple call without retry
            return self._call_api(messages, system, max_tokens, temperature)

        # Create retry-decorated version
        @retry(
            stop=stop_after_attempt(3),
            wait=wait_exponential(multiplier=1, min=2, max=10),
            retry=retry_if_exception_type((
                anthropic.RateLimitError,
                anthropic.APIConnectionError,
                anthropic.APITimeoutError,
            )),
            before_sleep=before_sleep_log(logger, logging.WARNING),
            reraise=True
        )
        def _make_request():
            return self._call_api(messages, system, max_tokens, temperature)

        try:
            return _make_request()
        except (anthropic.RateLimitError, anthropic.APIConnectionError, anthropic.APITimeoutError) as e:
            logger.error("API call failed after retries: %s", e)
            raise
        except anthropic.APIError as e:
            # Don't retry on other API errors (invalid request, auth, etc.)
            logger.error("API error (not retrying): %s", e)
            raise

    def generate_vibe(
        self,
        context: VibeContext,
        recent_openers: Optional[List[str]] = None,
        temperature: float = VIBE_TEMPERATURE
    ) -> Dict[str, Optional[str]]:
        """
        Generate a vibe tag for a track, and optionally identify the hook.

        Args:
            context: VibeContext with audio features and metadata
            recent_openers: List of recently used opener words (soft nudge to vary)
            temperature: API temperature for variety (default 0.9)

        Returns:
            Dict with 'vibe' (5-8 words, adjective stack format) and 'hook' (identified phrase or None)
        """
        prompt_context = context.to_prompt_context()
        user_prompt = self.USER_PROMPT_TEMPLATE.format(context=prompt_context)

        # Strong nudge to vary opener words
        if recent_openers and len(recent_openers) > 0:
            openers_str = ", ".join(recent_openers[-6:])  # Last 6
            user_prompt += f"\n\n⚠️ AVOID THESE OPENERS (recently used): {openers_str}\nPick a DIFFERENT first word from the palette. There are 40+ quality openers to choose from."

        response = self._call_api_with_retry(
            messages=[{"role": "user", "content": user_prompt}],
            system=self.SYSTEM_PROMPT,
            max_tokens=CLAUDE_MAX_TOKENS_VIBE,
            temperature=temperature
        )

        # Extract text from response
        raw_response = response.content[0].text.strip()

        # Parse VIBE: and HOOK: from response
        vibe = None
        hook = None

        for line in raw_response.split('\n'):
            line = line.strip()
            if line.upper().startswith('VIBE:'):
                vibe = line[5:].strip().strip('"\'')
            elif line.upper().startswith('HOOK:'):
                hook_text = line[5:].strip().strip('"\'')
                if hook_text.upper() != 'NONE' and hook_text:
                    hook = hook_text.lower()

        # Fallback if format wasn't followed - find first ALL CAPS line that looks like a vibe
        if not vibe:
            for line in raw_response.split('\n'):
                line = line.strip().strip('"\'')
                # Skip lines that look like prompt echoes or instructions
                skip_patterns = ['looking at', 'process:', 'let me', 'based on', 'this track',
                                 'analyzing', 'here is', 'here\'s', 'the vibe', 'i would', 'i\'d']
                if any(pattern in line.lower() for pattern in skip_patterns):
                    continue
                # Look for ALL CAPS lines with 3+ words (likely a vibe)
                words = line.split()
                if len(words) >= 3 and line.isupper():
                    vibe = line
                    break
            # Last resort: take first line but clean it
            if not vibe:
                vibe = raw_response.split('\n')[0].strip('"\'')

        # Clean up vibe - remove common prefixes/suffixes
        vibe = vibe.replace(',', '')
        for prefix in ['VIBE:', 'TAG:', 'HERE:', 'HERE IS:', 'THE VIBE IS:']:
            if vibe.upper().startswith(prefix):
                vibe = vibe[len(prefix):].strip()

        # Ensure reasonable length (truncate if over 8 words)
        words = vibe.split()
        if len(words) > 8:
            vibe = " ".join(words[:8])

        # Convert to ALL CAPS for consistency
        return {'vibe': vibe.upper(), 'hook': hook}

    def generate_description(self, context: VibeContext, vibe: str) -> str:
        """
        Generate a practical description sentence for a track.

        Args:
            context: VibeContext with audio features and metadata
            vibe: The vibe tag (used as input for description generation)

        Returns:
            String description sentence (20-40 words)
        """
        prompt_context = context.to_prompt_context()

        # Build track context from metadata
        track_context_parts = []
        if context.title:
            track_context_parts.append(f"Title: \"{context.title}\"")
        if context.artist:
            track_context_parts.append(f"Artist: {context.artist}")
        if context.genre:
            track_context_parts.append(f"Genre tag: {context.genre}")
        if context.comments:
            track_context_parts.append(f"Existing tags: {', '.join(context.comments[:5])}")
        track_context = "\n".join(track_context_parts) if track_context_parts else ""

        user_prompt = self.DESCRIPTION_USER_PROMPT_TEMPLATE.format(
            vibe=vibe,
            track_context=track_context,
            context=prompt_context
        )

        response = self._call_api_with_retry(
            messages=[{"role": "user", "content": user_prompt}],
            system=self.DESCRIPTION_SYSTEM_PROMPT,
            max_tokens=CLAUDE_MAX_TOKENS_VIBE,
            temperature=0.7  # Slightly lower for descriptions
        )

        # Extract text from response
        description = response.content[0].text.strip()

        # Clean up - remove quotes if present
        description = description.strip('"\'')

        # Ensure it ends with appropriate punctuation
        if description and not description.endswith(('.', '!', '?')):
            description += '.'

        return description

    def generate_vibe_with_description(self, context: VibeContext) -> Dict[str, Any]:
        """
        Generate both a vibe tag and natural language description for a track.

        Args:
            context: VibeContext with audio features and metadata

        Returns:
            Dict with 'vibe', 'description', and 'hook' keys
        """
        vibe_result = self.generate_vibe(context)
        vibe = vibe_result['vibe']
        hook = vibe_result['hook']
        description = self.generate_description(context, vibe)
        return {'vibe': vibe, 'description': description, 'hook': hook}

    def generate_vibe_from_features(
        self,
        audio_features: Dict[str, Any],
        tags: Dict[str, Any]
    ) -> Dict[str, Optional[str]]:
        """
        Generate a vibe tag from raw audio features and ID3 tags.

        Args:
            audio_features: Dictionary from AudioAnalyzer/CachedAnalyzer
            tags: Dictionary from TagManager.read_tags()

        Returns:
            Dict with 'vibe' and 'hook' keys
        """
        # Extract tempo from feature vector or features dict
        tempo = audio_features.get('tempo', 120.0)
        if tempo == 0 and 'feature_vector' in audio_features:
            # Try to get from feature vector (index 3 is tempo in the original)
            fv = audio_features['feature_vector']
            if len(fv) > 3:
                tempo = fv[3] if fv[3] > 0 else 120.0

        # Get energy (RMS energy, typically index 4)
        energy = audio_features.get('rms_energy', 0.5)
        if energy == 0 and 'feature_vector' in audio_features:
            fv = audio_features['feature_vector']
            if len(fv) > 4:
                energy = min(1.0, fv[4])  # Normalize

        # Get Essentia features with defaults
        context = VibeContext(
            tempo=tempo,
            energy=energy,
            danceability=audio_features.get('essentia_danceability', 0.5),
            mood_happy=audio_features.get('essentia_mood_happy', 0.5),
            mood_sad=audio_features.get('essentia_mood_sad', 0.5),
            mood_aggressive=audio_features.get('essentia_mood_aggressive', 0.5),
            mood_relaxed=audio_features.get('essentia_mood_relaxed', 0.5),
            voice_instrumental=audio_features.get('essentia_voice_instrumental', 0.5),
            arousal=audio_features.get('essentia_arousal', 5.0),
            valence=audio_features.get('essentia_valence', 5.0),
            title=tags.get('title'),
            artist=tags.get('artist'),
            album=tags.get('album'),
            genre=tags.get('genre'),
            comments=tags.get('comments') if isinstance(tags.get('comments'), list) else (
                [tags.get('comments')] if tags.get('comments') else None
            )
        )

        return self.generate_vibe(context)

    def generate_vibe_with_description_from_features(
        self,
        audio_features: Dict[str, Any],
        tags: Dict[str, Any]
    ) -> Dict[str, str]:
        """
        Generate both vibe tag and description from raw audio features and ID3 tags.

        Args:
            audio_features: Dictionary from AudioAnalyzer/CachedAnalyzer
            tags: Dictionary from TagManager.read_tags()

        Returns:
            Dict with 'vibe' and 'description' keys
        """
        context = self._build_context(audio_features, tags)
        return self.generate_vibe_with_description(context)

    def _build_context(
        self,
        audio_features: Dict[str, Any],
        tags: Dict[str, Any],
        scene: Optional[str] = None,
        scene_description: Optional[str] = None,
        detections: Optional[Dict[str, Any]] = None,
        vocal_hook: Optional[str] = None,
        vocal_hook_occurrences: int = 0,
        vocal_transcription: Optional[str] = None
    ) -> VibeContext:
        """Build VibeContext from raw audio features, tags, and detected sounds."""
        # Extract tempo from feature vector or features dict
        tempo = audio_features.get('tempo', 120.0)
        if tempo == 0 and 'feature_vector' in audio_features:
            fv = audio_features['feature_vector']
            if len(fv) > 3:
                tempo = fv[3] if fv[3] > 0 else 120.0

        # Get energy (RMS energy, typically index 4)
        energy = audio_features.get('rms_energy', 0.5)
        if energy == 0 and 'feature_vector' in audio_features:
            fv = audio_features['feature_vector']
            if len(fv) > 4:
                energy = min(1.0, fv[4])

        # Extract detected sounds (just the labels, not scores)
        detected_instruments = None
        detected_drums = None
        detected_vocals = None
        detected_genres = None
        detected_mood = None

        if detections:
            if detections.get('instruments'):
                detected_instruments = [label for label, score in detections['instruments'] if score >= 0.1]
            if detections.get('drums'):
                detected_drums = [label for label, score in detections['drums'] if score >= 0.1]
            if detections.get('vocals'):
                detected_vocals = [label for label, score in detections['vocals'] if score >= 0.1]
            if detections.get('genres'):
                detected_genres = [label for label, score in detections['genres'] if score >= 0.1]
            if detections.get('mood'):
                detected_mood = [label.replace(' music', '') for label, score in detections['mood'] if score >= 0.1]

        return VibeContext(
            tempo=tempo,
            energy=energy,
            danceability=audio_features.get('essentia_danceability', 0.5),
            mood_happy=audio_features.get('essentia_mood_happy', 0.5),
            mood_sad=audio_features.get('essentia_mood_sad', 0.5),
            mood_aggressive=audio_features.get('essentia_mood_aggressive', 0.5),
            mood_relaxed=audio_features.get('essentia_mood_relaxed', 0.5),
            voice_instrumental=audio_features.get('essentia_voice_instrumental', 0.5),
            arousal=audio_features.get('essentia_arousal', 5.0),
            valence=audio_features.get('essentia_valence', 5.0),
            title=tags.get('title'),
            artist=tags.get('artist'),
            album=tags.get('album'),
            genre=tags.get('genre'),
            comments=tags.get('comments') if isinstance(tags.get('comments'), list) else (
                [tags.get('comments')] if tags.get('comments') else None
            ),
            scene=scene,
            scene_description=scene_description,
            detected_instruments=detected_instruments,
            detected_drums=detected_drums,
            detected_vocals=detected_vocals,
            detected_genres=detected_genres,
            detected_mood=detected_mood,
            vocal_hook=vocal_hook,
            vocal_hook_occurrences=vocal_hook_occurrences,
            vocal_transcription=vocal_transcription,
        )


class VibeCache:
    """
    Simple file-based cache for vibe tags to avoid redundant API calls.

    Cache key is based on audio features hash, so if the audio analysis
    hasn't changed, we can reuse the vibe.
    """

    def __init__(self, cache_dir: Optional[str] = None):
        """
        Initialize the vibe cache.

        Args:
            cache_dir: Directory for cache file. Defaults to ~/.cratebot/
        """
        from pathlib import Path
        if cache_dir:
            self.cache_dir = Path(cache_dir)
        else:
            self.cache_dir = get_cratebot_dir()
        self.cache_file = self.cache_dir / "vibe_cache.json"
        self._cache = None

    def _load_cache(self) -> Dict[str, str]:
        """Load cache from disk."""
        if self._cache is not None:
            return self._cache

        if self.cache_file.exists():
            try:
                with open(self.cache_file, 'r') as f:
                    self._cache = json.load(f)
            except (json.JSONDecodeError, IOError):
                self._cache = {}
        else:
            self._cache = {}

        return self._cache

    def _save_cache(self) -> None:
        """Save cache to disk."""
        self.cache_dir.mkdir(parents=True, exist_ok=True)
        with open(self.cache_file, 'w') as f:
            json.dump(self._cache, f, indent=2)

    def _make_key(self, file_path: str, features: Dict[str, Any]) -> str:
        """Create a cache key from file path and features."""
        import hashlib

        # Use file path + key audio features for cache key
        key_data = {
            'path': file_path,
            'tempo': round(features.get('tempo', 0), 1),
            'danceability': round(features.get('essentia_danceability', 0), 2),
            'mood_happy': round(features.get('essentia_mood_happy', 0), 2),
            'arousal': round(features.get('essentia_arousal', 0), 2),
        }

        key_str = json.dumps(key_data, sort_keys=True)
        return hashlib.md5(key_str.encode()).hexdigest()[:16]

    def get(self, file_path: str, features: Dict[str, Any]) -> Optional[str]:
        """Get cached vibe for a file."""
        cache = self._load_cache()
        key = self._make_key(file_path, features)
        return cache.get(key)

    def set(self, file_path: str, features: Dict[str, Any], vibe: str) -> None:
        """Cache a vibe for a file."""
        cache = self._load_cache()
        key = self._make_key(file_path, features)
        cache[key] = vibe
        self._cache = cache
        self._save_cache()

    def clear(self) -> int:
        """Clear the cache. Returns number of entries removed."""
        cache = self._load_cache()
        count = len(cache)
        self._cache = {}
        self._save_cache()
        return count


class CachedVibeGenerator:
    """
    Vibe generator with caching to minimize API calls.

    Wraps VibeGenerator with VibeCache for efficient batch processing.
    Also includes scene estimation for geographic/cultural origin tagging.
    """

    def __init__(
        self,
        api_key: Optional[str] = None,
        model: str = CLAUDE_MODEL,
        cache_dir: Optional[str] = None
    ):
        """
        Initialize cached vibe generator.

        Args:
            api_key: Anthropic API key
            model: Claude model to use
            cache_dir: Directory for cache file
        """
        self.generator = VibeGenerator(api_key=api_key, model=model)
        self.cache = VibeCache(cache_dir=cache_dir)
        self.scene_estimator = SceneEstimator()
        self._stats = {'cache_hits': 0, 'api_calls': 0}
        self._recent_vibes: List[str] = []  # Track recent vibes for variety
        self._max_recent = 10  # How many recent vibes to track

    @property
    def is_available(self) -> bool:
        """Check if vibe generation is available."""
        return self.generator.is_available

    def _track_vibe(self, vibe: str) -> None:
        """Track a vibe for variety enforcement."""
        self._recent_vibes.append(vibe)
        # Keep only the most recent vibes
        if len(self._recent_vibes) > self._max_recent:
            self._recent_vibes.pop(0)

    def _get_recent_openers(self) -> List[str]:
        """
        Extract just the opener words from recent vibes for gentle variety nudging.

        Only tracks the first word (quality opener like DOPE, SICK, FIERCE)
        to softly discourage repetition without being too restrictive.
        """
        if not self._recent_vibes:
            return []

        openers = []
        for vibe in self._recent_vibes[-10:]:  # Last 10 vibes for better variety
            words = vibe.upper().split()
            if words and len(words[0]) > 3:
                openers.append(words[0])

        # Return unique openers, most recent last
        seen = set()
        unique = []
        for opener in openers:
            if opener not in seen:
                seen.add(opener)
                unique.append(opener)
        return unique

    def clear_recent_vibes(self) -> None:
        """Clear the recent vibes tracker (e.g., between sessions)."""
        self._recent_vibes = []

    def generate_vibe(
        self,
        file_path: str,
        audio_features: Dict[str, Any],
        tags: Dict[str, Any],
        skip_cache: bool = False
    ) -> str:
        """
        Generate a vibe tag, using cache when possible.

        Args:
            file_path: Path to the audio file (for cache key)
            audio_features: Dictionary from audio analyzer
            tags: Dictionary from TagManager.read_tags()
            skip_cache: If True, always call API

        Returns:
            String vibe tag
        """
        # Check cache first
        if not skip_cache:
            cached = self.cache.get(file_path, audio_features)
            if cached:
                self._stats['cache_hits'] += 1
                return cached

        # Generate new vibe
        vibe = self.generator.generate_vibe_from_features(audio_features, tags)
        self._stats['api_calls'] += 1

        # Cache it
        self.cache.set(file_path, audio_features, vibe)

        return vibe

    def estimate_scene(
        self,
        audio_features: Dict[str, Any],
        tags: Dict[str, Any]
    ) -> Dict[str, Any]:
        """
        Estimate the scene/origin for a track.

        Args:
            audio_features: Dictionary from audio analyzer
            tags: Dictionary from TagManager.read_tags()

        Returns:
            Dict with 'scene', 'confidence', 'description', 'runner_up'
        """
        return self.scene_estimator.estimate_scene(audio_features, tags)

    def generate_vibe_with_description(
        self,
        file_path: str,
        audio_features: Dict[str, Any],
        tags: Dict[str, Any],
        skip_cache: bool = False,
        detections: Optional[Dict[str, Any]] = None,
        vocal_hook: Optional[str] = None,
        vocal_hook_occurrences: int = 0,
        vocal_transcription: Optional[str] = None
    ) -> Dict[str, Any]:
        """
        Generate vibe tag, description, and scene estimation.

        Args:
            file_path: Path to the audio file (for cache key)
            audio_features: Dictionary from audio analyzer
            tags: Dictionary from TagManager.read_tags()
            skip_cache: If True, always call API
            detections: Optional dict from PANNsAnalyzer.detect_sounds()
            vocal_hook: Optional pre-computed hook (fallback if no transcription)
            vocal_hook_occurrences: Number of times hook appears in track
            vocal_transcription: Full transcription for Claude to identify hook

        Returns:
            Dict with 'vibe', 'description', 'scene', 'hook', and 'detections' keys
        """
        # Estimate scene first (no API call, rule-based)
        scene_result = self.scene_estimator.estimate_scene(audio_features, tags)
        scene = scene_result['scene']
        scene_description = scene_result['description']

        # Check cache first for vibe
        cached_vibe = None
        if not skip_cache:
            cached_vibe = self.cache.get(file_path, audio_features)

        if cached_vibe:
            self._stats['cache_hits'] += 1
            # Generate description using cached vibe (with scene context, detections, and hook)
            context = self.generator._build_context(
                audio_features, tags,
                scene=scene, scene_description=scene_description,
                detections=detections,
                vocal_hook=vocal_hook,
                vocal_hook_occurrences=vocal_hook_occurrences,
                vocal_transcription=vocal_transcription
            )
            description = self.generator.generate_description(context, cached_vibe)
            self._stats['api_calls'] += 1
            # Use pre-computed hook for cached vibes (Claude already picked it)
            return {
                'vibe': cached_vibe,
                'description': description,
                'scene': scene,
                'scene_confidence': scene_result['confidence'],
                'detections': detections,
                'hook': vocal_hook,  # Use pre-computed for cached
            }

        # Build context with scene, detections, and vocal transcription for generation
        context = self.generator._build_context(
            audio_features, tags,
            scene=scene, scene_description=scene_description,
            detections=detections,
            vocal_hook=vocal_hook,
            vocal_hook_occurrences=vocal_hook_occurrences,
            vocal_transcription=vocal_transcription
        )

        # Get recent openers for soft variety nudge
        recent_openers = self._get_recent_openers()

        # Generate vibe with soft variety nudge - now returns {'vibe': ..., 'hook': ...}
        vibe_result = self.generator.generate_vibe(context, recent_openers=recent_openers)
        vibe = vibe_result['vibe']
        claude_hook = vibe_result['hook']  # Hook identified by Claude from transcription
        self._stats['api_calls'] += 1

        # Track this vibe for future variety
        self._track_vibe(vibe)

        # Generate description
        description = self.generator.generate_description(context, vibe)
        self._stats['api_calls'] += 1

        # Cache vibe
        self.cache.set(file_path, audio_features, vibe)

        # Use Claude's hook if available, otherwise fall back to pre-computed
        final_hook = claude_hook if claude_hook else vocal_hook

        return {
            'vibe': vibe,
            'description': description,
            'scene': scene,
            'scene_confidence': scene_result['confidence'],
            'detections': detections,
            'hook': final_hook,
        }

    def get_stats(self) -> Dict[str, int]:
        """Get cache hit/miss statistics."""
        return self._stats.copy()

    def clear_cache(self) -> int:
        """Clear the vibe cache."""
        return self.cache.clear()


def _get_api_key() -> Optional[str]:
    """Get API key from config or environment."""
    # Try environment variable first
    env_key = os.environ.get("ANTHROPIC_API_KEY")
    if env_key:
        return env_key
    # Try to load from config file
    try:
        from src.core.config import config
        return config.get_api_key("anthropic")
    except ImportError:
        try:
            from core.config import config
            return config.get_api_key("anthropic")
        except ImportError:
            pass
    # Direct fallback: read config file directly
    try:
        import json
        config_file = get_cratebot_dir() / "config.json"
        if config_file.exists():
            with open(config_file, 'r') as f:
                data = json.load(f)
                return data.get("anthropic_api_key")
    except Exception:
        pass
    return None


def is_vibe_available() -> bool:
    """Quick check if vibe generation is available."""
    return HAS_ANTHROPIC and bool(_get_api_key())


def get_vibe_status() -> str:
    """Get human-readable vibe generator status."""
    if not HAS_ANTHROPIC:
        return "Not installed (pip install anthropic)"
    if not _get_api_key():
        return "API key needed"
    return "Available"
