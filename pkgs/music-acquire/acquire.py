#!/usr/bin/env python3
"""Executable entry point for the packaged music-acquire utility."""

from music_acquire.cli import main


if __name__ == "__main__":
    raise SystemExit(main())
