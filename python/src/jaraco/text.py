"""Minimal jaraco.text utilities used by pkg_resources."""

from typing import Iterable, Iterator, Union


def yield_lines(text: Union[str, Iterable[str]]) -> Iterator[str]:
    """Yield lines from a string or an iterable of strings."""
    if isinstance(text, (str, bytes)):
        for line in str(text).splitlines():
            yield line
        return
    for item in text:
        if item is None:
            continue
        for line in str(item).splitlines():
            yield line


def drop_comment(line: str) -> str:
    """Strip comments from a line."""
    return line.split('#', 1)[0].rstrip()


def join_continuation(lines: Iterable[str]) -> Iterator[str]:
    """Join lines that end with a backslash continuation."""
    buffer = ""
    for line in lines:
        if line.endswith('\\'):
            buffer += line[:-1]
            continue
        if buffer:
            line = buffer + line
            buffer = ""
        if line:
            yield line
    if buffer:
        yield buffer
