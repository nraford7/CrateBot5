"""
Centralized constants and configuration values for Audio Tagger.

All magic numbers and thresholds should be defined here for easy tuning.
"""

# =============================================================================
# Tag Matching
# =============================================================================
FUZZY_MATCH_THRESHOLD = 0.85  # Minimum similarity for fuzzy tag matching

# =============================================================================
# Review Confidence Thresholds
# =============================================================================
GENRE_CONFIDENCE_THRESHOLD = 0.6   # Below this, flag for review
ALBUM_CONFIDENCE_THRESHOLD = 0.6   # Below this, flag for review
COMMENTS_CONFIDENCE_THRESHOLD = 0.4  # Below this, flag for review

# =============================================================================
# Training Configuration
# =============================================================================
MIN_TRAINING_SAMPLES = 20          # Minimum total samples required
MIN_SAMPLES_PER_CLASS = 10         # Minimum samples per tag class
DEFAULT_TEST_SIZE = 0.2            # Train/test split ratio

# =============================================================================
# Comment Tag Prediction Thresholds
# =============================================================================
COMMENT_MIN_SCORE = 0.2            # Minimum score to consider a tag
COMMENT_CATEGORY_THRESHOLD = 0.3   # Threshold for category inclusion
VOCAL_CONFIDENCE_THRESHOLD = 0.4   # Threshold for vocal presence detection

# =============================================================================
# Audio Analysis
# =============================================================================
DEFAULT_SAMPLE_RATE = 22050        # librosa default
ANALYSIS_DURATION_FULL = 60.0      # Full analysis duration (seconds)
ANALYSIS_DURATION_FAST = 45.0      # Fast analysis duration (seconds)
ANALYSIS_DURATION_CACHED = 30.0    # Cached analyzer duration (seconds)
ANALYSIS_START_OFFSET = 0.33       # Start at 33% into track (skip intro)

# =============================================================================
# Feature Cache
# =============================================================================
CACHE_VERSION = 7                  # Increment to invalidate cache (v7: added CLAP + Jamendo)
CACHE_MTIME_TOLERANCE = 1.0        # Seconds tolerance for file modification

# =============================================================================
# Embedding/Similarity
# =============================================================================
EMBEDDING_DIM = 16                 # Dimension for synthesis embeddings
LIKENESS_SIGMOID_CENTER = 3.0      # Center for likeness score sigmoid

# =============================================================================
# API Configuration
# =============================================================================
CLAUDE_MODEL = "claude-sonnet-4-20250514"
CLAUDE_MAX_TOKENS_VIBE = 150
VIBE_TEMPERATURE = 0.9

# =============================================================================
# New Taxonomy (v2)
# =============================================================================

CANONICAL_GENRES = [
    "House",
    "Techno",
    "Jungle",
    "Rap",
    "DiscoFunk",
    "PartyBreaks",
    "Acapella",
    "Dub/Reggae",
]

CANONICAL_TIMING = [
    "Start",
    "Build",
    "Peak",
    "Sustain",
    "Release",
]

CANONICAL_MOODS = [
    "Happy",
    "Dark",
    "Emotional",
    "Aggressive",
    "Dreamy",
    "Groovy",
]

TAXONOMY_ID3_MAPPING = {
    "genre": "TCON",
    "timing": "TALB",
    "mood": "TIT1",
    "descriptive": "COMM",
}

# =============================================================================
# Genre/Timing Split Logic (for training data migration)
# =============================================================================
# Values in the Genre ID3 tag that are ACTUAL genres (not timing)
# Everything else in the Genre tag is assumed to be a timing value,
# and those tracks default to "House" genre.
ACTUAL_GENRE_VALUES = {
    "House",
    "Techno",
    "Jungle",
    "Rap",
    "DiscoFunk",
    "PartyBreaks",
    "Acapella",
    "Dub/Reggae",
}
DEFAULT_GENRE_FOR_TIMING = "House"
