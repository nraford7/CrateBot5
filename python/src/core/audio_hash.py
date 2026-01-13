"""Audio hashing for override system."""
import hashlib
from pathlib import Path

import librosa


def compute_audio_hash(audio_path: str, duration: float = 30.0) -> str:
    """
    Compute SHA256 hash of first N seconds of audio.

    Args:
        audio_path: Path to audio file
        duration: Seconds of audio to hash (default: 30)

    Returns:
        64-character hex string (SHA256)
    """
    # Load first N seconds of audio
    y, sr = librosa.load(audio_path, sr=22050, duration=duration, mono=True)

    # Convert to bytes for hashing
    audio_bytes = y.tobytes()

    # Compute SHA256
    return hashlib.sha256(audio_bytes).hexdigest()
