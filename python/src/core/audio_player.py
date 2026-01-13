"""
Audio Player for Audio Tagger

Simple audio playback component using pygame for MP3 playback
with play/pause and seek functionality.

Note: pygame is imported lazily to avoid SDL crashes on macOS ARM64.
The SDL library can crash during dlopen before Python exception handling runs.
"""

import os
import threading
from typing import Optional, Callable, TYPE_CHECKING
from enum import Enum

# Lazy import state - pygame is only loaded when actually needed
_pygame = None
_pygame_initialized = False
_pygame_error: Optional[str] = None


def _ensure_pygame() -> bool:
    """
    Lazily import and initialize pygame.

    Returns True if pygame is available, False otherwise.
    This defers the SDL load until audio playback is actually requested,
    preventing server crashes on startup.
    """
    global _pygame, _pygame_initialized, _pygame_error

    if _pygame_initialized:
        return _pygame is not None

    _pygame_initialized = True

    try:
        import pygame as pg
        pg.mixer.init(frequency=44100, size=-16, channels=2, buffer=2048)
        _pygame = pg
        return True
    except ImportError as e:
        _pygame_error = f"pygame not installed: {e}"
        return False
    except Exception as e:
        _pygame_error = f"pygame initialization failed: {e}"
        return False


# For backward compatibility - these are computed lazily via functions
def is_pygame_available() -> bool:
    """Check if pygame is available (lazy initialization)."""
    return _ensure_pygame()


def get_pygame_error() -> Optional[str]:
    """Get pygame error message if unavailable."""
    _ensure_pygame()
    return _pygame_error


class PlaybackState(Enum):
    """Audio playback states."""
    STOPPED = "stopped"
    PLAYING = "playing"
    PAUSED = "paused"


class AudioPlayer:
    """
    Simple audio player using pygame for MP3 playback.

    Features:
    - Load and play MP3 files
    - Play, pause, stop controls
    - Seek to position
    - Get current position and duration
    - Callback on playback completion
    """

    def __init__(self):
        """Initialize the audio player."""
        if not _ensure_pygame():
            raise ImportError(
                f"pygame is required for audio playback but could not be initialized: {_pygame_error}\n"
                "Install with: pip install pygame"
            )

        self.current_file: Optional[str] = None
        self.state = PlaybackState.STOPPED
        self.duration: float = 0.0
        self._position_offset: float = 0.0
        self._on_complete: Optional[Callable] = None

        # Monitor thread
        self._monitor_thread: Optional[threading.Thread] = None
        self._monitor_running = False

    def load(self, file_path: str) -> bool:
        """
        Load an audio file for playback.

        Args:
            file_path: Path to the MP3 file

        Returns:
            True on success, False on failure
        """
        if not os.path.exists(file_path):
            return False

        self.stop()

        try:
            _pygame.mixer.music.load(file_path)
            self.current_file = file_path

            # Get duration using mutagen
            try:
                from mutagen.mp3 import MP3
                audio = MP3(file_path)
                self.duration = audio.info.length
            except Exception:
                # Fallback: estimate duration (won't be accurate)
                self.duration = 0.0

            self.state = PlaybackState.STOPPED
            self._position_offset = 0.0
            return True

        except Exception as e:
            print(f"Error loading audio: {e}")
            return False

    def play(self) -> None:
        """Start or resume playback."""
        if not self.current_file:
            return

        if self.state == PlaybackState.PAUSED:
            _pygame.mixer.music.unpause()
        else:
            _pygame.mixer.music.play()

        self.state = PlaybackState.PLAYING
        self._start_monitor()

    def pause(self) -> None:
        """Pause playback."""
        if self.state == PlaybackState.PLAYING:
            _pygame.mixer.music.pause()
            self.state = PlaybackState.PAUSED

    def stop(self) -> None:
        """Stop playback and reset position."""
        self._stop_monitor()
        try:
            _pygame.mixer.music.stop()
        except Exception:
            pass
        self.state = PlaybackState.STOPPED
        self._position_offset = 0.0

    def seek(self, position: float) -> None:
        """
        Seek to a position in the audio.

        Args:
            position: Position in seconds
        """
        if not self.current_file:
            return

        was_playing = self.state == PlaybackState.PLAYING

        try:
            # _pygame.mixer.music doesn't support true seeking for all formats
            # We reload and start from the position
            _pygame.mixer.music.load(self.current_file)
            _pygame.mixer.music.play(start=position)
            self._position_offset = position

            if not was_playing:
                _pygame.mixer.music.pause()
                self.state = PlaybackState.PAUSED
            else:
                self.state = PlaybackState.PLAYING
                self._start_monitor()

        except Exception as e:
            print(f"Seek error: {e}")

    def get_position(self) -> float:
        """
        Get current playback position in seconds.

        Returns:
            Position in seconds
        """
        if self.state == PlaybackState.STOPPED:
            return 0.0

        try:
            # pygame returns position in milliseconds
            pos_ms = _pygame.mixer.music.get_pos()
            if pos_ms < 0:
                return self._position_offset
            return self._position_offset + (pos_ms / 1000.0)
        except Exception:
            return self._position_offset

    def get_duration(self) -> float:
        """
        Get total duration in seconds.

        Returns:
            Duration in seconds
        """
        return self.duration

    def is_playing(self) -> bool:
        """Check if currently playing."""
        return self.state == PlaybackState.PLAYING

    def is_paused(self) -> bool:
        """Check if currently paused."""
        return self.state == PlaybackState.PAUSED

    def toggle_play_pause(self) -> None:
        """Toggle between play and pause states."""
        if self.state == PlaybackState.PLAYING:
            self.pause()
        else:
            self.play()

    def set_on_complete(self, callback: Callable) -> None:
        """
        Set callback for when playback completes.

        Args:
            callback: Function to call when playback ends
        """
        self._on_complete = callback

    def set_volume(self, volume: float) -> None:
        """
        Set playback volume.

        Args:
            volume: Volume level from 0.0 to 1.0
        """
        try:
            _pygame.mixer.music.set_volume(max(0.0, min(1.0, volume)))
        except Exception:
            pass

    def get_volume(self) -> float:
        """
        Get current volume level.

        Returns:
            Volume from 0.0 to 1.0
        """
        try:
            return _pygame.mixer.music.get_volume()
        except Exception:
            return 1.0

    def _start_monitor(self) -> None:
        """Start the playback monitoring thread."""
        if self._monitor_running:
            return

        self._monitor_running = True
        self._monitor_thread = threading.Thread(target=self._monitor_playback, daemon=True)
        self._monitor_thread.start()

    def _stop_monitor(self) -> None:
        """Stop the playback monitoring thread."""
        self._monitor_running = False
        if self._monitor_thread and self._monitor_thread.is_alive():
            self._monitor_thread.join(timeout=0.5)
        self._monitor_thread = None

    def _monitor_playback(self) -> None:
        """Monitor playback status and detect completion."""
        import time

        while self._monitor_running and self.state == PlaybackState.PLAYING:
            try:
                if not _pygame.mixer.music.get_busy():
                    # Playback finished
                    self.state = PlaybackState.STOPPED
                    self._position_offset = 0.0
                    if self._on_complete:
                        try:
                            self._on_complete()
                        except Exception:
                            pass
                    break
            except Exception:
                break

            time.sleep(0.1)

        self._monitor_running = False

    def cleanup(self) -> None:
        """Clean up resources."""
        self.stop()
        try:
            _pygame.mixer.music.unload()
        except Exception:
            pass

    def __del__(self):
        """Destructor to clean up resources."""
        try:
            self.cleanup()
        except Exception:
            pass


def is_audio_player_available() -> bool:
    """
    Check if audio playback is available.

    Returns:
        True if pygame is available and initialized
    """
    return is_pygame_available()


def get_audio_player_error() -> Optional[str]:
    """
    Get the error message if audio player is not available.

    Returns:
        Error message or None if available
    """
    if is_pygame_available():
        return None
    return get_pygame_error()
