"""
Essentia Pre-trained Model Integration for CrateBot

Extracts high-level semantic audio features using Essentia's pre-trained
TensorFlow models. Features include:

1. Basic mood (happy, sad, aggressive, relaxed) - 4 features
2. Danceability, voice/instrumental, arousal/valence - 4 features
3. MTG-Jamendo mood/theme predictions (56 classes) - 56 features
4. Discogs519 genre/style predictions (519 classes) - 519 features

Total: 583 features from Essentia models.

The MTG-Jamendo model was trained on real Jamendo audio data.
The Discogs519 model was trained on 4M+ tracks from Discogs.
"""

import os
import logging
import urllib.request
import ssl
from pathlib import Path
from typing import Dict, Any, Optional, List, Callable
import numpy as np

from .paths import get_cratebot_dir

logger = logging.getLogger(__name__)

# Optional Essentia import with graceful degradation
try:
    from essentia.standard import MonoLoader, TensorflowPredictMusiCNN, TensorflowPredict2D
    HAS_ESSENTIA = True
except ImportError:
    HAS_ESSENTIA = False

# Check for EffNet support (newer Essentia versions)
try:
    from essentia.standard import TensorflowPredictEffnetDiscogs
    HAS_EFFNET = True
except ImportError:
    HAS_EFFNET = False

# Check for MAEST support (for Discogs519)
try:
    from essentia.standard import TensorflowPredictMAEST, TensorflowPredict
    from essentia import Pool
    HAS_MAEST = True
except ImportError:
    HAS_MAEST = False

# Constants
ESSENTIA_SAMPLE_RATE = 16000  # Required for MusiCNN, EffNet, and MAEST models

# Feature counts
ESSENTIA_BASIC_FEATURE_COUNT = 8     # Original MusiCNN features
ESSENTIA_JAMENDO_FEATURE_COUNT = 56  # MTG-Jamendo mood/theme classes
ESSENTIA_DISCOGS_FEATURE_COUNT = 519 # Discogs519 genre/style classes
ESSENTIA_FEATURE_COUNT = (ESSENTIA_BASIC_FEATURE_COUNT +
                          ESSENTIA_JAMENDO_FEATURE_COUNT +
                          ESSENTIA_DISCOGS_FEATURE_COUNT)  # 583 total

# MTG-Jamendo mood/theme classes (56 tags)
MTG_JAMENDO_MOODTHEME_CLASSES = [
    "action", "adventure", "advertising", "background", "ballad", "calm",
    "children", "christmas", "commercial", "cool", "corporate", "dark",
    "deep", "documentary", "drama", "dramatic", "dream", "emotional",
    "energetic", "epic", "fast", "film", "fun", "funny", "game", "groovy",
    "happy", "heavy", "holiday", "hopeful", "inspiring", "love", "meditative",
    "melancholic", "melodic", "motivational", "movie", "nature", "party",
    "positive", "powerful", "relaxing", "retro", "romantic", "sad", "sexy",
    "slow", "soft", "soundscape", "space", "sport", "summer", "trailer",
    "travel", "upbeat", "uplifting"
]

# Discogs519 genre/style classes (519 classes)
# Format: "Category---Style"
DISCOGS519_CLASSES = [
    "Blues---Boogie Woogie", "Blues---Chicago Blues", "Blues---Country Blues",
    "Blues---Delta Blues", "Blues---East Coast Blues", "Blues---Electric Blues",
    "Blues---Harmonica Blues", "Blues---Jump Blues", "Blues---Louisiana Blues",
    "Blues---Memphis Blues", "Blues---Modern Electric Blues", "Blues---Piano Blues",
    "Blues---Piedmont Blues", "Blues---Rhythm & Blues", "Blues---Texas Blues",
    "Brass & Military---Brass Band", "Brass & Military---Marches",
    "Brass & Military---Military", "Brass & Military---Pipe & Drum",
    "Children's---Educational", "Children's---Nursery Rhymes", "Children's---Story",
    "Classical---Baroque", "Classical---Choral", "Classical---Classical",
    "Classical---Contemporary", "Classical---Early", "Classical---Impressionist",
    "Classical---Medieval", "Classical---Modern", "Classical---Neo-Classical",
    "Classical---Neo-Romantic", "Classical---Opera", "Classical---Operetta",
    "Classical---Oratorio", "Classical---Post-Modern", "Classical---Renaissance",
    "Classical---Romantic", "Classical---Twelve-tone",
    "Electronic---Abstract", "Electronic---Acid", "Electronic---Acid House",
    "Electronic---Acid Jazz", "Electronic---Ambient", "Electronic---Baltimore Club",
    "Electronic---Bassline", "Electronic---Beatdown", "Electronic---Berlin-School",
    "Electronic---Big Beat", "Electronic---Bleep", "Electronic---Breakbeat",
    "Electronic---Breakcore", "Electronic---Breaks", "Electronic---Broken Beat",
    "Electronic---Chillwave", "Electronic---Chiptune", "Electronic---Dance-pop",
    "Electronic---Dark Ambient", "Electronic---Darkwave", "Electronic---Deep House",
    "Electronic---Deep Techno", "Electronic---Disco", "Electronic---Disco Polo",
    "Electronic---Donk", "Electronic---Doomcore", "Electronic---Downtempo",
    "Electronic---Drone", "Electronic---Drum n Bass", "Electronic---Dub",
    "Electronic---Dub Techno", "Electronic---Dubstep", "Electronic---Dungeon Synth",
    "Electronic---EBM", "Electronic---Electro", "Electronic---Electro House",
    "Electronic---Electroacoustic", "Electronic---Electroclash", "Electronic---Euro House",
    "Electronic---Euro-Disco", "Electronic---Eurobeat", "Electronic---Eurodance",
    "Electronic---Experimental", "Electronic---Footwork", "Electronic---Freestyle",
    "Electronic---Future Jazz", "Electronic---Gabber", "Electronic---Garage House",
    "Electronic---Ghetto", "Electronic---Ghetto House", "Electronic---Ghettotech",
    "Electronic---Glitch", "Electronic---Glitch Hop", "Electronic---Goa Trance",
    "Electronic---Grime", "Electronic---Halftime", "Electronic---Hands Up",
    "Electronic---Happy Hardcore", "Electronic---Hard Beat", "Electronic---Hard House",
    "Electronic---Hard Techno", "Electronic---Hard Trance", "Electronic---Hardcore",
    "Electronic---Hardstyle", "Electronic---Harsh Noise Wall", "Electronic---Hi NRG",
    "Electronic---Hip Hop", "Electronic---Hip-House", "Electronic---House",
    "Electronic---IDM", "Electronic---Illbient", "Electronic---Industrial",
    "Electronic---Italo House", "Electronic---Italo-Disco", "Electronic---Italodance",
    "Electronic---J-Core", "Electronic---Jazzdance", "Electronic---Juke",
    "Electronic---Jumpstyle", "Electronic---Jungle", "Electronic---Latin",
    "Electronic---Leftfield", "Electronic---Lento Violento", "Electronic---Makina",
    "Electronic---Minimal", "Electronic---Minimal Techno", "Electronic---Modern Classical",
    "Electronic---Musique Concrète", "Electronic---Neo Trance", "Electronic---Neofolk",
    "Electronic---New Age", "Electronic---New Beat", "Electronic---New Wave",
    "Electronic---Noise", "Electronic---Nu-Disco", "Electronic---Power Electronics",
    "Electronic---Progressive Breaks", "Electronic---Progressive House",
    "Electronic---Progressive Trance", "Electronic---Psy-Trance",
    "Electronic---Rhythmic Noise", "Electronic---Schranz", "Electronic---Sound Collage",
    "Electronic---Speed Garage", "Electronic---Speedcore", "Electronic---Synth-pop",
    "Electronic---Synthwave", "Electronic---Tech House", "Electronic---Tech Trance",
    "Electronic---Techno", "Electronic---Trance", "Electronic---Tribal",
    "Electronic---Tribal House", "Electronic---Trip Hop", "Electronic---Tropical House",
    "Electronic---UK Funky", "Electronic---UK Garage", "Electronic---Vaporwave",
    "Electronic---Witch House",
    "Folk, World, & Country---Aboriginal", "Folk, World, & Country---African",
    "Folk, World, & Country---Andalusian Classical", "Folk, World, & Country---Andean Music",
    "Folk, World, & Country---Appalachian Music", "Folk, World, & Country---Basque Music",
    "Folk, World, & Country---Bhangra", "Folk, World, & Country---Bluegrass",
    "Folk, World, & Country---Cajun", "Folk, World, & Country---Canzone Napoletana",
    "Folk, World, & Country---Carnatic", "Folk, World, & Country---Catalan Music",
    "Folk, World, & Country---Celtic", "Folk, World, & Country---Chacarera",
    "Folk, World, & Country---Chinese Classical", "Folk, World, & Country---Chutney",
    "Folk, World, & Country---Copla", "Folk, World, & Country---Country",
    "Folk, World, & Country---Cretan", "Folk, World, & Country---Dangdut",
    "Folk, World, & Country---Fado", "Folk, World, & Country---Flamenco",
    "Folk, World, & Country---Folk", "Folk, World, & Country---Funaná",
    "Folk, World, & Country---Gamelan", "Folk, World, & Country---Ghazal",
    "Folk, World, & Country---Gospel", "Folk, World, & Country---Griot",
    "Folk, World, & Country---Hawaiian", "Folk, World, & Country---Highlife",
    "Folk, World, & Country---Hillbilly", "Folk, World, & Country---Hindustani",
    "Folk, World, & Country---Honky Tonk", "Folk, World, & Country---Indian Classical",
    "Folk, World, & Country---Kaseko", "Folk, World, & Country---Klezmer",
    "Folk, World, & Country---Laïkó", "Folk, World, & Country---Luk Thung",
    "Folk, World, & Country---Maloya", "Folk, World, & Country---Mbalax",
    "Folk, World, & Country---Min'yō", "Folk, World, & Country---Mizrahi",
    "Folk, World, & Country---Nhạc Vàng", "Folk, World, & Country---Nordic",
    "Folk, World, & Country---Népzene", "Folk, World, & Country---Ottoman Classical",
    "Folk, World, & Country---Overtone Singing", "Folk, World, & Country---Pacific",
    "Folk, World, & Country---Pasodoble", "Folk, World, & Country---Persian Classical",
    "Folk, World, & Country---Phleng Phuea Chiwit", "Folk, World, & Country---Polka",
    "Folk, World, & Country---Qawwali", "Folk, World, & Country---Raï",
    "Folk, World, & Country---Rebetiko", "Folk, World, & Country---Romani",
    "Folk, World, & Country---Salegy", "Folk, World, & Country---Sea Shanties",
    "Folk, World, & Country---Soukous", "Folk, World, & Country---Séga",
    "Folk, World, & Country---Volksmusik", "Folk, World, & Country---Western Swing",
    "Folk, World, & Country---Zouk", "Folk, World, & Country---Zydeco",
    "Folk, World, & Country---Éntekhno",
    "Funk / Soul---Afrobeat", "Funk / Soul---Bayou Funk", "Funk / Soul---Boogie",
    "Funk / Soul---Contemporary R&B", "Funk / Soul---Disco", "Funk / Soul---Free Funk",
    "Funk / Soul---Funk", "Funk / Soul---Gogo", "Funk / Soul---Gospel",
    "Funk / Soul---Minneapolis Sound", "Funk / Soul---Neo Soul",
    "Funk / Soul---New Jack Swing", "Funk / Soul---P.Funk", "Funk / Soul---Psychedelic",
    "Funk / Soul---Rhythm & Blues", "Funk / Soul---Soul", "Funk / Soul---Swingbeat",
    "Funk / Soul---UK Street Soul",
    "Hip Hop---Bass Music", "Hip Hop---Beatbox", "Hip Hop---Boom Bap",
    "Hip Hop---Bounce", "Hip Hop---Britcore", "Hip Hop---Cloud Rap",
    "Hip Hop---Conscious", "Hip Hop---Crunk", "Hip Hop---Cut-up/DJ",
    "Hip Hop---DJ Battle Tool", "Hip Hop---Electro", "Hip Hop---Favela Funk",
    "Hip Hop---G-Funk", "Hip Hop---Gangsta", "Hip Hop---Go-Go", "Hip Hop---Grime",
    "Hip Hop---Hardcore Hip-Hop", "Hip Hop---Hiplife", "Hip Hop---Horrorcore",
    "Hip Hop---Hyphy", "Hip Hop---Instrumental", "Hip Hop---Jazzy Hip-Hop",
    "Hip Hop---Kwaito", "Hip Hop---Miami Bass", "Hip Hop---Pop Rap",
    "Hip Hop---Ragga HipHop", "Hip Hop---RnB/Swing", "Hip Hop---Screw",
    "Hip Hop---Thug Rap", "Hip Hop---Trap", "Hip Hop---Trip Hop", "Hip Hop---Turntablism",
    "Jazz---Afro-Cuban Jazz", "Jazz---Afrobeat", "Jazz---Avant-garde Jazz",
    "Jazz---Big Band", "Jazz---Bop", "Jazz---Bossa Nova", "Jazz---Cape Jazz",
    "Jazz---Contemporary Jazz", "Jazz---Cool Jazz", "Jazz---Dixieland",
    "Jazz---Easy Listening", "Jazz---Free Improvisation", "Jazz---Free Jazz",
    "Jazz---Fusion", "Jazz---Gypsy Jazz", "Jazz---Hard Bop", "Jazz---Jazz-Funk",
    "Jazz---Jazz-Rock", "Jazz---Latin Jazz", "Jazz---Modal", "Jazz---Post Bop",
    "Jazz---Ragtime", "Jazz---Smooth Jazz", "Jazz---Soul-Jazz", "Jazz---Space-Age",
    "Jazz---Swing",
    "Latin---Afro-Cuban", "Latin---Axé", "Latin---Bachata", "Latin---Baião",
    "Latin---Batucada", "Latin---Beguine", "Latin---Bolero", "Latin---Boogaloo",
    "Latin---Bossanova", "Latin---Carimbó", "Latin---Cha-Cha", "Latin---Charanga",
    "Latin---Choro", "Latin---Compas", "Latin---Conjunto", "Latin---Corrido",
    "Latin---Cubano", "Latin---Cumbia", "Latin---Danzon", "Latin---Descarga",
    "Latin---Forró", "Latin---Gaita", "Latin---Guaguancó", "Latin---Guajira",
    "Latin---Guaracha", "Latin---Jibaro", "Latin---Lambada", "Latin---MPB",
    "Latin---Mambo", "Latin---Mariachi", "Latin---Marimba", "Latin---Merengue",
    "Latin---Música Criolla", "Latin---Norteño", "Latin---Nueva Cancion",
    "Latin---Nueva Trova", "Latin---Pachanga", "Latin---Plena", "Latin---Porro",
    "Latin---Quechua", "Latin---Ranchera", "Latin---Reggaeton", "Latin---Rumba",
    "Latin---Salsa", "Latin---Samba", "Latin---Samba-Canção", "Latin---Son",
    "Latin---Son Montuno", "Latin---Sonero", "Latin---Tango", "Latin---Tejano",
    "Latin---Timba", "Latin---Trova", "Latin---Vallenato",
    "Non-Music---Audiobook", "Non-Music---Comedy", "Non-Music---Dialogue",
    "Non-Music---Education", "Non-Music---Erotic", "Non-Music---Field Recording",
    "Non-Music---Health-Fitness", "Non-Music---Interview", "Non-Music---Monolog",
    "Non-Music---Movie Effects", "Non-Music---Poetry", "Non-Music---Political",
    "Non-Music---Promotional", "Non-Music---Public Broadcast", "Non-Music---Radioplay",
    "Non-Music---Religious", "Non-Music---Sermon", "Non-Music---Sound Art",
    "Non-Music---Sound Poetry", "Non-Music---Special Effects", "Non-Music---Speech",
    "Non-Music---Spoken Word", "Non-Music---Technical", "Non-Music---Therapy",
    "Pop---Ballad", "Pop---Barbershop", "Pop---Bollywood", "Pop---Break-In",
    "Pop---Bubblegum", "Pop---Chanson", "Pop---City Pop", "Pop---Enka",
    "Pop---Ethno-pop", "Pop---Europop", "Pop---Indie Pop", "Pop---J-pop",
    "Pop---K-pop", "Pop---Karaoke", "Pop---Kayōkyoku", "Pop---Levenslied",
    "Pop---Light Music", "Pop---Music Hall", "Pop---Novelty", "Pop---Parody",
    "Pop---Schlager", "Pop---Vocal",
    "Reggae---Calypso", "Reggae---Dancehall", "Reggae---Dub", "Reggae---Dub Poetry",
    "Reggae---Lovers Rock", "Reggae---Mento", "Reggae---Ragga", "Reggae---Reggae",
    "Reggae---Reggae Gospel", "Reggae---Reggae-Pop", "Reggae---Rocksteady",
    "Reggae---Roots Reggae", "Reggae---Ska", "Reggae---Soca", "Reggae---Steel Band",
    "Rock---AOR", "Rock---Acid Rock", "Rock---Acoustic", "Rock---Alternative Rock",
    "Rock---Arena Rock", "Rock---Art Rock", "Rock---Atmospheric Black Metal",
    "Rock---Avantgarde", "Rock---Beat", "Rock---Black Metal", "Rock---Blues Rock",
    "Rock---Brit Pop", "Rock---Classic Rock", "Rock---Coldwave", "Rock---Country Rock",
    "Rock---Crust", "Rock---Death Metal", "Rock---Deathcore", "Rock---Deathrock",
    "Rock---Depressive Black Metal", "Rock---Doo Wop", "Rock---Doom Metal",
    "Rock---Dream Pop", "Rock---Emo", "Rock---Ethereal", "Rock---Experimental",
    "Rock---Folk Metal", "Rock---Folk Rock", "Rock---Funeral Doom Metal",
    "Rock---Funk Metal", "Rock---Garage Rock", "Rock---Glam", "Rock---Goregrind",
    "Rock---Goth Rock", "Rock---Gothic Metal", "Rock---Grindcore", "Rock---Groove Metal",
    "Rock---Grunge", "Rock---Hard Rock", "Rock---Hardcore", "Rock---Heavy Metal",
    "Rock---Horror Rock", "Rock---Indie Rock", "Rock---Industrial",
    "Rock---Industrial Metal", "Rock---J-Rock", "Rock---Jangle Pop", "Rock---K-Rock",
    "Rock---Krautrock", "Rock---Lo-Fi", "Rock---Lounge", "Rock---Math Rock",
    "Rock---Melodic Death Metal", "Rock---Melodic Hardcore", "Rock---Metalcore",
    "Rock---Mod", "Rock---NDW", "Rock---Neofolk", "Rock---New Wave", "Rock---No Wave",
    "Rock---Noise", "Rock---Noisecore", "Rock---Nu Metal", "Rock---Oi",
    "Rock---Parody", "Rock---Pop Punk", "Rock---Pop Rock", "Rock---Pornogrind",
    "Rock---Post Rock", "Rock---Post-Hardcore", "Rock---Post-Metal", "Rock---Post-Punk",
    "Rock---Power Metal", "Rock---Power Pop", "Rock---Power Violence", "Rock---Prog Rock",
    "Rock---Progressive Metal", "Rock---Psychedelic Rock", "Rock---Psychobilly",
    "Rock---Pub Rock", "Rock---Punk", "Rock---Rock & Roll", "Rock---Rock Opera",
    "Rock---Rockabilly", "Rock---Shoegaze", "Rock---Ska", "Rock---Skiffle",
    "Rock---Sludge Metal", "Rock---Soft Rock", "Rock---Southern Rock", "Rock---Space Rock",
    "Rock---Speed Metal", "Rock---Stoner Rock", "Rock---Surf", "Rock---Swamp Pop",
    "Rock---Symphonic Rock", "Rock---Technical Death Metal", "Rock---Thrash",
    "Rock---Twist", "Rock---Viking Metal", "Rock---Yé-Yé",
    "Stage & Screen---Musical", "Stage & Screen---Score", "Stage & Screen---Soundtrack",
    "Stage & Screen---Theme"
]

# Model configuration
MODEL_BASE_URL = "https://essentia.upf.edu/models"

MODEL_CONFIGS = {
    # MusiCNN embedding model (for basic mood classifiers)
    'musicnn_embedding': {
        'url': f"{MODEL_BASE_URL}/feature-extractors/musicnn/msd-musicnn-1.pb",
        'filename': 'msd-musicnn-1.pb',
        'output_layer': 'model/dense/BiasAdd',
    },
    # Basic mood classifiers (MusiCNN-based)
    'mood_happy': {
        'url': f"{MODEL_BASE_URL}/classification-heads/mood_happy/mood_happy-msd-musicnn-1.pb",
        'filename': 'mood_happy-msd-musicnn-1.pb',
    },
    'mood_sad': {
        'url': f"{MODEL_BASE_URL}/classification-heads/mood_sad/mood_sad-msd-musicnn-1.pb",
        'filename': 'mood_sad-msd-musicnn-1.pb',
    },
    'mood_aggressive': {
        'url': f"{MODEL_BASE_URL}/classification-heads/mood_aggressive/mood_aggressive-msd-musicnn-1.pb",
        'filename': 'mood_aggressive-msd-musicnn-1.pb',
    },
    'mood_relaxed': {
        'url': f"{MODEL_BASE_URL}/classification-heads/mood_relaxed/mood_relaxed-msd-musicnn-1.pb",
        'filename': 'mood_relaxed-msd-musicnn-1.pb',
    },
    'danceability': {
        'url': f"{MODEL_BASE_URL}/classification-heads/danceability/danceability-msd-musicnn-1.pb",
        'filename': 'danceability-msd-musicnn-1.pb',
    },
    'voice_instrumental': {
        'url': f"{MODEL_BASE_URL}/classification-heads/voice_instrumental/voice_instrumental-msd-musicnn-1.pb",
        'filename': 'voice_instrumental-msd-musicnn-1.pb',
    },
    'arousal_valence': {
        'url': f"{MODEL_BASE_URL}/classification-heads/emomusic/emomusic-msd-musicnn-2.pb",
        'filename': 'emomusic-msd-musicnn-2.pb',
    },
    # Discogs-EffNet embedding model (for MTG-Jamendo classifier)
    'discogs_effnet_embedding': {
        'url': f"{MODEL_BASE_URL}/feature-extractors/discogs-effnet/discogs-effnet-bs64-1.pb",
        'filename': 'discogs-effnet-bs64-1.pb',
        'output_layer': 'PartitionedCall:1',
    },
    # MTG-Jamendo mood/theme classifier (56 classes)
    'mtg_jamendo_moodtheme': {
        'url': f"{MODEL_BASE_URL}/classification-heads/mtg_jamendo_moodtheme/mtg_jamendo_moodtheme-discogs-effnet-1.pb",
        'filename': 'mtg_jamendo_moodtheme-discogs-effnet-1.pb',
    },
    # MAEST embedding model (for Discogs519 classifier)
    'maest_embedding': {
        'url': f"{MODEL_BASE_URL}/feature-extractors/maest/discogs-maest-30s-pw-519l-2.pb",
        'filename': 'discogs-maest-30s-pw-519l-2.pb',
        'output_layer': 'PartitionedCall/Identity_12',
    },
    # Discogs519 genre/style classifier (519 classes)
    'discogs519': {
        'url': f"{MODEL_BASE_URL}/classification-heads/genre_discogs519/genre_discogs519-discogs-maest-30s-pw-519l-1.pb",
        'filename': 'genre_discogs519-discogs-maest-30s-pw-519l-1.pb',
    },
}


class EssentiaModelManager:
    """
    Handles Essentia model downloading and path management.

    Models are stored in ~/.cratebot/essentia_models/
    """

    def __init__(self, models_dir: Optional[str] = None):
        if models_dir:
            self.models_dir = Path(models_dir)
        else:
            self.models_dir = get_cratebot_dir() / "essentia_models"

    def get_model_path(self, model_name: str) -> Path:
        config = MODEL_CONFIGS.get(model_name, {})
        filename = config.get('filename', f'{model_name}.pb')
        return self.models_dir / filename

    def is_model_available(self, model_name: str) -> bool:
        return self.get_model_path(model_name).exists()

    def all_models_available(self, include_jamendo: bool = True, include_discogs: bool = True) -> bool:
        required = list(MODEL_CONFIGS.keys())
        if not include_jamendo:
            required = [m for m in required if m not in ['discogs_effnet_embedding', 'mtg_jamendo_moodtheme']]
        if not include_discogs:
            required = [m for m in required if m not in ['maest_embedding', 'discogs519']]
        return all(self.is_model_available(name) for name in required)

    def basic_models_available(self) -> bool:
        """Check if basic MusiCNN models are available."""
        basic_models = ['musicnn_embedding', 'mood_happy', 'mood_sad', 'mood_aggressive',
                       'mood_relaxed', 'danceability', 'voice_instrumental', 'arousal_valence']
        return all(self.is_model_available(name) for name in basic_models)

    def jamendo_models_available(self) -> bool:
        """Check if MTG-Jamendo models are available."""
        return (self.is_model_available('discogs_effnet_embedding') and
                self.is_model_available('mtg_jamendo_moodtheme'))

    def discogs_models_available(self) -> bool:
        """Check if Discogs519 models are available."""
        return (self.is_model_available('maest_embedding') and
                self.is_model_available('discogs519'))

    def get_missing_models(self) -> List[str]:
        return [name for name in MODEL_CONFIGS.keys() if not self.is_model_available(name)]

    def get_total_download_size_mb(self) -> float:
        # MusiCNN ~85MB, Discogs-EffNet ~20MB, Jamendo ~5MB, MAEST ~120MB, Discogs519 ~5MB
        return 235.0

    def download_models(self, progress_callback: Optional[Callable[[str, int, int], None]] = None) -> bool:
        missing = self.get_missing_models()
        if not missing:
            return True

        self.models_dir.mkdir(parents=True, exist_ok=True)

        ssl_context = ssl.create_default_context()
        ssl_context.check_hostname = False
        ssl_context.verify_mode = ssl.CERT_NONE

        total = len(missing)
        for idx, model_name in enumerate(missing):
            if progress_callback:
                progress_callback(model_name, idx + 1, total)

            config = MODEL_CONFIGS[model_name]
            url = config['url']
            dest_path = self.get_model_path(model_name)

            try:
                logger.info("Downloading %s...", model_name)
                req = urllib.request.Request(url, headers={'User-Agent': 'CrateBot/1.0'})
                with urllib.request.urlopen(req, context=ssl_context) as response:
                    with open(dest_path, 'wb') as out_file:
                        out_file.write(response.read())
                logger.info("  Saved to %s", dest_path)
            except Exception as e:
                logger.error("Error downloading %s: %s", model_name, e)
                if dest_path.exists():
                    dest_path.unlink()
                return False

        return True

    def clear_models(self) -> int:
        count = 0
        for model_name in MODEL_CONFIGS.keys():
            path = self.get_model_path(model_name)
            if path.exists():
                path.unlink()
                count += 1
        return count


class EssentiaAnalyzer:
    """
    Extract high-level audio features using Essentia pre-trained models.

    Features extracted:
    - Basic mood: happy, sad, aggressive, relaxed (0-1 probability each)
    - Danceability: 0-1 probability
    - Voice/Instrumental: 0-1 (1 = voice, 0 = instrumental)
    - Arousal: 1-9 scale (energy/intensity)
    - Valence: 1-9 scale (positive/negative mood)
    - MTG-Jamendo mood/theme: 56 classes (0-1 probability each)
    - Discogs519 genre/style: 519 classes (0-1 probability each)
    """

    def __init__(self, models_dir: Optional[str] = None, auto_load: bool = True):
        self.model_manager = EssentiaModelManager(models_dir)
        self._models_loaded = False
        self._jamendo_loaded = False
        self._discogs_loaded = False
        self._embedding_model = None
        self._effnet_embedding_model = None
        self._maest_embedding_model = None
        self._classifier_models = {}
        self._jamendo_model = None
        self._discogs_model = None

        if auto_load and self.is_available:
            self._load_models()

    @property
    def is_available(self) -> bool:
        return HAS_ESSENTIA and self.model_manager.basic_models_available()

    @property
    def is_jamendo_available(self) -> bool:
        return HAS_ESSENTIA and HAS_EFFNET and self.model_manager.jamendo_models_available()

    @property
    def is_discogs_available(self) -> bool:
        return HAS_ESSENTIA and HAS_MAEST and self.model_manager.discogs_models_available()

    @property
    def is_essentia_installed(self) -> bool:
        return HAS_ESSENTIA

    @property
    def are_models_downloaded(self) -> bool:
        return self.model_manager.all_models_available()

    def _load_models(self) -> bool:
        if not HAS_ESSENTIA:
            return False

        if not self.model_manager.basic_models_available():
            return False

        if self._models_loaded:
            return True

        try:
            embedding_path = str(self.model_manager.get_model_path('musicnn_embedding'))
            self._embedding_model = TensorflowPredictMusiCNN(
                graphFilename=embedding_path,
                output='model/dense/BiasAdd'
            )

            classifier_names = [
                'mood_happy', 'mood_sad', 'mood_aggressive', 'mood_relaxed',
                'danceability', 'voice_instrumental', 'arousal_valence'
            ]

            for name in classifier_names:
                model_path = str(self.model_manager.get_model_path(name))
                self._classifier_models[name] = TensorflowPredict2D(
                    graphFilename=model_path,
                    output='model/Softmax' if name != 'arousal_valence' else 'model/Identity'
                )

            self._models_loaded = True

            # Try to load Jamendo models (optional)
            self._load_jamendo_models()

            # Try to load Discogs models (optional)
            self._load_discogs_models()

            return True

        except Exception as e:
            logger.error("Error loading Essentia models: %s", e)
            self._models_loaded = False
            return False

    def _load_jamendo_models(self) -> bool:
        if not HAS_EFFNET:
            logger.debug("EffNet not available - skipping Jamendo models")
            return False

        if not self.model_manager.jamendo_models_available():
            logger.debug("Jamendo models not downloaded - skipping")
            return False

        if self._jamendo_loaded:
            return True

        try:
            effnet_path = str(self.model_manager.get_model_path('discogs_effnet_embedding'))
            self._effnet_embedding_model = TensorflowPredictEffnetDiscogs(
                graphFilename=effnet_path,
                output='PartitionedCall:1'
            )

            jamendo_path = str(self.model_manager.get_model_path('mtg_jamendo_moodtheme'))
            self._jamendo_model = TensorflowPredict2D(graphFilename=jamendo_path)

            self._jamendo_loaded = True
            logger.info("MTG-Jamendo mood/theme model loaded (56 classes)")
            return True

        except Exception as e:
            logger.warning("Error loading Jamendo models: %s", e)
            self._jamendo_loaded = False
            return False

    def _load_discogs_models(self) -> bool:
        if not HAS_MAEST:
            logger.debug("MAEST not available - skipping Discogs519 models")
            return False

        if not self.model_manager.discogs_models_available():
            logger.debug("Discogs519 models not downloaded - skipping")
            return False

        if self._discogs_loaded:
            return True

        try:
            maest_path = str(self.model_manager.get_model_path('maest_embedding'))
            self._maest_embedding_model = TensorflowPredictMAEST(
                graphFilename=maest_path,
                output='PartitionedCall/Identity_12'
            )

            # Use TensorflowPredict with Pool for the classifier
            # The model has input node 'embeddings' and output 'PartitionedCall/Identity_1'
            discogs_path = str(self.model_manager.get_model_path('discogs519'))
            self._discogs_model = TensorflowPredict(
                graphFilename=discogs_path,
                inputs=['embeddings'],
                outputs=['PartitionedCall/Identity_1']
            )

            self._discogs_loaded = True
            logger.info("Discogs519 genre/style model loaded (519 classes)")
            return True

        except Exception as e:
            logger.warning("Error loading Discogs519 models: %s", e)
            self._discogs_loaded = False
            return False

    def extract_features(self, audio_path: str) -> Dict[str, Any]:
        if not self.is_available:
            features = self._get_default_features()
            features['essentia_available'] = False
            features['essentia_status'] = 'not_installed' if not HAS_ESSENTIA else 'models_missing'
            return features

        if not self._models_loaded:
            if not self._load_models():
                features = self._get_default_features()
                features['essentia_available'] = False
                features['essentia_status'] = 'load_failed'
                return features

        try:
            audio = MonoLoader(filename=audio_path, sampleRate=ESSENTIA_SAMPLE_RATE)()

            embeddings = self._embedding_model(audio)

            features = {}

            happy_pred = self._classifier_models['mood_happy'](embeddings)
            features['essentia_mood_happy'] = float(np.mean(happy_pred[:, 0]))

            sad_pred = self._classifier_models['mood_sad'](embeddings)
            features['essentia_mood_sad'] = float(np.mean(sad_pred[:, 0]))

            aggressive_pred = self._classifier_models['mood_aggressive'](embeddings)
            features['essentia_mood_aggressive'] = float(np.mean(aggressive_pred[:, 0]))

            relaxed_pred = self._classifier_models['mood_relaxed'](embeddings)
            features['essentia_mood_relaxed'] = float(np.mean(relaxed_pred[:, 0]))

            dance_pred = self._classifier_models['danceability'](embeddings)
            features['essentia_danceability'] = float(np.mean(dance_pred[:, 0]))

            voice_pred = self._classifier_models['voice_instrumental'](embeddings)
            features['essentia_voice_instrumental'] = float(np.mean(voice_pred[:, 0]))

            av_pred = self._classifier_models['arousal_valence'](embeddings)
            av_mean = np.mean(av_pred, axis=0)
            features['essentia_arousal'] = float(av_mean[0]) if len(av_mean) > 0 else 5.0
            features['essentia_valence'] = float(av_mean[1]) if len(av_mean) > 1 else 5.0

            features['essentia_arousal'] = max(1.0, min(9.0, features['essentia_arousal']))
            features['essentia_valence'] = max(1.0, min(9.0, features['essentia_valence']))

            features['essentia_available'] = True
            features['essentia_status'] = 'ok'

            # Extract MTG-Jamendo mood/theme features
            jamendo_features = self._extract_jamendo_features(audio)
            features.update(jamendo_features)

            # Extract Discogs519 genre/style features
            discogs_features = self._extract_discogs_features(audio)
            features.update(discogs_features)

            return features

        except Exception as e:
            logger.warning("Essentia feature extraction failed for %s: %s", audio_path, e)
            features = self._get_default_features()
            features['essentia_available'] = False
            features['essentia_status'] = f'extraction_failed: {str(e)}'
            return features

    def _extract_jamendo_features(self, audio: np.ndarray) -> Dict[str, Any]:
        features = {}

        if not self._jamendo_loaded:
            features['essentia_jamendo_available'] = False
            for tag in MTG_JAMENDO_MOODTHEME_CLASSES:
                features[f'essentia_jamendo_{tag}'] = 0.5
            return features

        try:
            effnet_embeddings = self._effnet_embedding_model(audio)
            predictions = self._jamendo_model(effnet_embeddings)
            avg_predictions = np.mean(predictions, axis=0)

            features['essentia_jamendo_available'] = True

            for i, tag in enumerate(MTG_JAMENDO_MOODTHEME_CLASSES):
                if i < len(avg_predictions):
                    features[f'essentia_jamendo_{tag}'] = float(avg_predictions[i])
                else:
                    features[f'essentia_jamendo_{tag}'] = 0.5

            return features

        except Exception as e:
            logger.debug("Jamendo extraction failed: %s", e)
            features['essentia_jamendo_available'] = False
            for tag in MTG_JAMENDO_MOODTHEME_CLASSES:
                features[f'essentia_jamendo_{tag}'] = 0.5
            return features

    def _extract_discogs_features(self, audio: np.ndarray) -> Dict[str, Any]:
        features = {}

        if not self._discogs_loaded:
            features['essentia_discogs_available'] = False
            for style in DISCOGS519_CLASSES:
                safe_key = style.replace(' ', '_').replace('/', '_').replace('&', 'and').replace("'", "")
                features[f'essentia_discogs_{safe_key}'] = 0.0
            return features

        try:
            # MAEST requires minimum ~30 seconds of audio at 16kHz
            min_samples = int(ESSENTIA_SAMPLE_RATE * 30)
            if len(audio) < min_samples:
                logger.debug("Audio too short for MAEST (%d samples, need %d)", len(audio), min_samples)
                features['essentia_discogs_available'] = False
                for style in DISCOGS519_CLASSES:
                    safe_key = style.replace(' ', '_').replace('/', '_').replace('&', 'and').replace("'", "")
                    features[f'essentia_discogs_{safe_key}'] = 0.0
                return features

            # Get MAEST embeddings - outputs (N, 1, T, 768) where N is number of 30s segments
            maest_embeddings = self._maest_embedding_model(audio)

            # Use Pool to pass embeddings to classifier (supports 4D arrays)
            pool = Pool()
            pool.set('embeddings', maest_embeddings)

            # Run classifier - outputs shape (N, 1, 1, 519)
            predictions = self._discogs_model(pool)['PartitionedCall/Identity_1']

            # Average across all dimensions except the last (519 classes)
            # (N, 1, 1, 519) -> mean over first dims -> (519,)
            avg_predictions = predictions.mean(axis=tuple(range(len(predictions.shape) - 1)))

            features['essentia_discogs_available'] = True

            for i, style in enumerate(DISCOGS519_CLASSES):
                safe_key = style.replace(' ', '_').replace('/', '_').replace('&', 'and').replace("'", "")
                if i < len(avg_predictions):
                    features[f'essentia_discogs_{safe_key}'] = float(avg_predictions[i])
                else:
                    features[f'essentia_discogs_{safe_key}'] = 0.0

            return features

        except Exception as e:
            logger.debug("Discogs519 extraction failed: %s", e)
            features['essentia_discogs_available'] = False
            for style in DISCOGS519_CLASSES:
                safe_key = style.replace(' ', '_').replace('/', '_').replace('&', 'and').replace("'", "")
                features[f'essentia_discogs_{safe_key}'] = 0.0
            return features

    def _get_default_features(self) -> Dict[str, Any]:
        features = {
            'essentia_mood_happy': 0.5,
            'essentia_mood_sad': 0.5,
            'essentia_mood_aggressive': 0.5,
            'essentia_mood_relaxed': 0.5,
            'essentia_danceability': 0.5,
            'essentia_voice_instrumental': 0.5,
            'essentia_arousal': 5.0,
            'essentia_valence': 5.0,
            'essentia_jamendo_available': False,
            'essentia_discogs_available': False,
        }
        for tag in MTG_JAMENDO_MOODTHEME_CLASSES:
            features[f'essentia_jamendo_{tag}'] = 0.5
        for style in DISCOGS519_CLASSES:
            safe_key = style.replace(' ', '_').replace('/', '_').replace('&', 'and').replace("'", "")
            features[f'essentia_discogs_{safe_key}'] = 0.0
        return features

    def get_feature_vector(self, features: Dict[str, Any]) -> np.ndarray:
        """
        Convert Essentia features to a normalized numpy array.

        Returns:
            numpy array of ESSENTIA_FEATURE_COUNT (583) float values
        """
        vector = [
            # Basic MusiCNN features (8)
            features.get('essentia_mood_happy', 0.5),
            features.get('essentia_mood_sad', 0.5),
            features.get('essentia_mood_aggressive', 0.5),
            features.get('essentia_mood_relaxed', 0.5),
            features.get('essentia_danceability', 0.5),
            features.get('essentia_voice_instrumental', 0.5),
            features.get('essentia_arousal', 5.0) / 9.0,
            features.get('essentia_valence', 5.0) / 9.0,
        ]

        # MTG-Jamendo mood/theme features (56)
        for tag in MTG_JAMENDO_MOODTHEME_CLASSES:
            vector.append(features.get(f'essentia_jamendo_{tag}', 0.5))

        # Discogs519 genre/style features (519)
        for style in DISCOGS519_CLASSES:
            safe_key = style.replace(' ', '_').replace('/', '_').replace('&', 'and').replace("'", "")
            vector.append(features.get(f'essentia_discogs_{safe_key}', 0.0))

        return np.array(vector, dtype=np.float32)

    def download_models(self, progress_callback: Optional[Callable[[str, int, int], None]] = None) -> bool:
        return self.model_manager.download_models(progress_callback)

    def get_status(self) -> Dict[str, Any]:
        return {
            'essentia_installed': HAS_ESSENTIA,
            'effnet_available': HAS_EFFNET,
            'maest_available': HAS_MAEST,
            'basic_models_downloaded': self.model_manager.basic_models_available(),
            'jamendo_models_downloaded': self.model_manager.jamendo_models_available(),
            'discogs_models_downloaded': self.model_manager.discogs_models_available(),
            'models_loaded': self._models_loaded,
            'jamendo_loaded': self._jamendo_loaded,
            'discogs_loaded': self._discogs_loaded,
            'missing_models': self.model_manager.get_missing_models(),
            'models_dir': str(self.model_manager.models_dir),
            'is_available': self.is_available,
            'is_jamendo_available': self.is_jamendo_available,
            'is_discogs_available': self.is_discogs_available,
            'feature_count': ESSENTIA_FEATURE_COUNT,
        }


def is_essentia_available() -> bool:
    if not HAS_ESSENTIA:
        return False
    manager = EssentiaModelManager()
    return manager.basic_models_available()


def get_essentia_status() -> str:
    if not HAS_ESSENTIA:
        return "Not installed (pip install essentia-tensorflow)"
    manager = EssentiaModelManager()
    if manager.all_models_available():
        return "Available (with Jamendo + Discogs519)"
    if manager.jamendo_models_available():
        return "Available (with Jamendo)"
    if manager.basic_models_available():
        return "Available (basic only)"
    missing = len(manager.get_missing_models())
    return f"Models needed ({missing} to download)"
