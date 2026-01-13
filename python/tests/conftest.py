"""
Shared pytest fixtures for Audio Tagger tests.
"""

import pytest
import tempfile
import shutil
import os
import sys
from pathlib import Path

# Add src to path for imports during testing
sys.path.insert(0, str(Path(__file__).parent.parent / "src"))


@pytest.fixture
def temp_dir():
    """Create a temporary directory for test files."""
    path = tempfile.mkdtemp()
    yield path
    shutil.rmtree(path, ignore_errors=True)


@pytest.fixture
def project_root():
    """Return the project root directory."""
    return Path(__file__).parent.parent


@pytest.fixture
def test_audio_path(project_root):
    """
    Path to test audio fixture.

    Note: You need to place a small test MP3 file at tests/fixtures/test_audio.mp3
    A 5-10 second audio clip is sufficient for testing.
    """
    fixture_path = project_root / "tests" / "fixtures" / "test_audio.mp3"
    if not fixture_path.exists():
        pytest.skip(f"Test audio fixture not found at {fixture_path}")
    return fixture_path


@pytest.fixture
def mock_feature_vector():
    """97-dimensional feature vector for testing."""
    import numpy as np
    np.random.seed(42)  # Reproducible
    return np.random.randn(97).astype(np.float32)


@pytest.fixture
def mock_training_data(mock_feature_vector):
    """
    Generate mock training data for model tests.

    Creates 50 samples with 5 genres, 5 albums, and various comments.
    """
    import numpy as np
    np.random.seed(42)

    genres = ['Tech House', 'Deep House', 'Minimal', 'Techno', 'Disco']
    albums = ['Peak', 'Build', 'Start', 'Sustain', 'Release']
    comment_tags = ['Driving', 'Hypnotic', 'Melodic', 'Dark', 'Funky',
                    'Groovy', 'Minimal', 'Bouncy', 'Rolling', 'Punchy']

    training_data = []
    for i in range(50):
        # Create varied feature vectors
        feature_vec = mock_feature_vector + np.random.randn(97).astype(np.float32) * 0.5

        # Assign tags based on index for reproducibility
        genre = genres[i % len(genres)]
        album = albums[i % len(albums)]
        # Pick 2-4 random comment tags
        num_comments = 2 + (i % 3)
        comments = ', '.join(comment_tags[j % len(comment_tags)] for j in range(i, i + num_comments))

        training_data.append({
            'file_path': f'/fake/path/track_{i}.mp3',
            'file_name': f'track_{i}.mp3',
            'feature_vector': feature_vec,
            'tags': {
                'genre': genre,
                'album': album,
                'comments': comments,
            }
        })

    return training_data


@pytest.fixture
def mock_selected_tags():
    """Selected tags for training tests."""
    return {
        'genre': ['Tech House', 'Deep House', 'Minimal', 'Techno', 'Disco'],
        'album': ['Peak', 'Build', 'Start', 'Sustain', 'Release'],
        'comments': ['Driving', 'Hypnotic', 'Melodic', 'Dark', 'Funky',
                     'Groovy', 'Minimal', 'Bouncy', 'Rolling', 'Punchy'],
    }


@pytest.fixture
def mock_training_data_v2(mock_feature_vector):
    """
    Generate mock training data for new 4-classifier model tests.

    Creates 120 samples with genres, timing, moods, and descriptive tags.
    (120 ensures at least 20 samples per mood with 6 moods, meeting MIN_SAMPLES_PER_CLASS=10)
    """
    import numpy as np
    np.random.seed(42)

    genres = ['House', 'Techno', 'Jungle/DnB', 'Rap', 'DiscoFunk']
    timing = ['Start', 'Build', 'Peak', 'Sustain', 'Release']
    moods = ['Happy', 'Dark', 'Emotional', 'Aggressive', 'Dreamy', 'Groovy']
    descriptive_tags = ['Driving', 'Hypnotic', 'Melodic', 'Punchy',
                        'Rolling', 'Bouncy', 'Minimal', 'Funky', 'Groovy', 'Deep']

    training_data = []
    for i in range(120):
        # Create varied feature vectors
        feature_vec = mock_feature_vector + np.random.randn(97).astype(np.float32) * 0.5

        # Assign tags based on index for reproducibility
        genre = genres[i % len(genres)]
        tim = timing[i % len(timing)]
        mood = moods[i % len(moods)]
        # Pick 2-4 random descriptive tags
        num_desc = 2 + (i % 3)
        descriptive = ', '.join(descriptive_tags[j % len(descriptive_tags)] for j in range(i, i + num_desc))

        training_data.append({
            'file_path': f'/fake/path/track_{i}.mp3',
            'file_name': f'track_{i}.mp3',
            'feature_vector': feature_vec,
            'tags': {
                'genre': genre,
                'timing': tim,
                'mood': mood,
                'descriptive': descriptive,
            }
        })

    return training_data


@pytest.fixture
def mock_selected_tags_v2():
    """Selected tags for new 4-classifier training tests."""
    return {
        'genre': ['House', 'Techno', 'Jungle/DnB', 'Rap', 'DiscoFunk'],
        'timing': ['Start', 'Build', 'Peak', 'Sustain', 'Release'],
        'mood': ['Happy', 'Dark', 'Emotional', 'Aggressive', 'Dreamy', 'Groovy'],
        'descriptive': ['Driving', 'Hypnotic', 'Melodic', 'Punchy',
                        'Rolling', 'Bouncy', 'Minimal', 'Funky', 'Groovy', 'Deep'],
    }


@pytest.fixture
def temp_cache_db(temp_dir):
    """Create a temporary cache database path."""
    return os.path.join(temp_dir, "test_cache.db")


@pytest.fixture
def temp_model_path(temp_dir):
    """Create a temporary model file path."""
    return os.path.join(temp_dir, "test_model.pkl")
