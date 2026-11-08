"""One-time retained PTY startup; exec fish after capturing hook context.

This file can be invoked directly by the holder's native child launcher. It is
not a resident relay and never reads terminal input or output.
"""
from __future__ import annotations

import os
from pathlib import Path
import sys


def main() -> None:
    # An installed entry-point can add site-packages only to its own sys.path.
    # Resolve this exact package for the directly invoked bootstrap as well.
    sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
    from agency_kitty.capabilities.harness import capture_terminal_context
    env = dict(os.environ)
    env.update(capture_terminal_context())
    os.execvpe("fish", ["fish", "--login", "--interactive"], env)
    raise AssertionError("exec returned")


if __name__ == "__main__":
    main()
