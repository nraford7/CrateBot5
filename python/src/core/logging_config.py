"""
Centralized logging configuration for Audio Tagger.

Usage:
    from .logging_config import get_logger

    logger = get_logger(__name__)
    logger.info("Processing file...")
"""

import logging
import sys
from pathlib import Path
from typing import Optional


# Default log format
DEFAULT_FORMAT = "%(asctime)s - %(name)s - %(levelname)s - %(message)s"
SIMPLE_FORMAT = "%(levelname)s: %(message)s"

# Global state
_configured = False


def configure_logging(
    level: int = logging.INFO,
    log_file: Optional[str] = None,
    format_string: str = DEFAULT_FORMAT,
    simple: bool = False,
) -> None:
    """
    Configure the root logger for Audio Tagger.

    Args:
        level: Logging level (default INFO)
        log_file: Optional file path to write logs
        format_string: Log format string
        simple: Use simple format (level: message) for CLI output
    """
    global _configured

    if simple:
        format_string = SIMPLE_FORMAT

    # Configure root logger
    root_logger = logging.getLogger()
    root_logger.setLevel(level)

    # Remove existing handlers to avoid duplicates
    for handler in root_logger.handlers[:]:
        root_logger.removeHandler(handler)

    # Console handler
    console_handler = logging.StreamHandler(sys.stdout)
    console_handler.setLevel(level)
    console_handler.setFormatter(logging.Formatter(format_string))
    root_logger.addHandler(console_handler)

    # File handler if specified
    if log_file:
        log_path = Path(log_file)
        log_path.parent.mkdir(parents=True, exist_ok=True)
        file_handler = logging.FileHandler(log_file)
        file_handler.setLevel(level)
        file_handler.setFormatter(logging.Formatter(DEFAULT_FORMAT))
        root_logger.addHandler(file_handler)

    _configured = True


def get_logger(name: str) -> logging.Logger:
    """
    Get a logger instance.

    Automatically configures logging on first use if not already configured.

    Args:
        name: Logger name (typically __name__)

    Returns:
        Configured logger instance
    """
    global _configured

    if not _configured:
        # Auto-configure with defaults on first use
        configure_logging(simple=True)

    return logging.getLogger(name)


def set_level(level: int) -> None:
    """
    Set the logging level for all Audio Tagger loggers.

    Args:
        level: Logging level (e.g., logging.DEBUG, logging.INFO)
    """
    # Set for audio-tagger specific loggers
    for name in ["core", "models", "ui"]:
        logger = logging.getLogger(name)
        logger.setLevel(level)

    # Also set root logger
    logging.getLogger().setLevel(level)


def enable_debug() -> None:
    """Enable debug logging."""
    set_level(logging.DEBUG)


def enable_quiet() -> None:
    """Enable quiet mode (warnings and errors only)."""
    set_level(logging.WARNING)
