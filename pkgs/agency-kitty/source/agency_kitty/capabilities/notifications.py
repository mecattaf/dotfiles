"""OSC 99 and private local sound paths; no desktop-wide event loop."""
from __future__ import annotations

import base64
import os
from pathlib import Path
import subprocess

CLAUDE_AUDIO = Path(os.environ.get("AGENCY_KITTY_AUDIO_DIR", str(Path.home() / ".local" / "share" / "agency-kitty" / "audio")))
SOUND_FILES = {
    "startup": CLAUDE_AUDIO / "startup.mp3",
    "voice-start": CLAUDE_AUDIO / "enter_voice_mode.mp3",
    "voice-end": CLAUDE_AUDIO / "exit_voice_mode.mp3",
    "disconnected": CLAUDE_AUDIO / "disconnected.mp3",
    "done": Path("/run/current-system/sw/share/sounds/freedesktop/stereo/complete.oga"),
    "attention": Path("/run/current-system/sw/share/sounds/freedesktop/stereo/message.oga"),
}


def osc99(title: str, body: str = "", identifier: str = "agency", timeout_ms: int = 5000) -> bytes:
    """Encode payloads; pasted titles can never inject a second terminal escape."""
    if not identifier or any(c not in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-" for c in identifier):
        raise ValueError("invalid notification identifier")
    if len(title.encode()) + len(body.encode()) > 65536:
        raise ValueError("notification exceeds 64 KiB")
    def b64(value: str) -> str:
        return base64.b64encode(value.encode()).decode("ascii")
    base = f"i={identifier}:e=1:w={max(0, timeout_ms)}:a=-focus"
    if body:
        return (f"\x1b]99;{base}:d=0:p=title;{b64(title)}\x1b\\"
                f"\x1b]99;i={identifier}:e=1:d=1:p=body;{b64(body)}\x1b\\").encode()
    return f"\x1b]99;{base}:d=1:p=title;{b64(title)}\x1b\\".encode()


def play_sound(event: str) -> None:
    if event not in SOUND_FILES:
        raise ValueError("unknown sound event")
    path = SOUND_FILES[event]
    if not path.is_file():
        raise FileNotFoundError(f"sound asset is unavailable locally: {path}")
    # No proprietary assets are copied into the package. Playback is only from
    # the explicit invocation on the seat which owns those private files.
    result = subprocess.run(["mpv", "--no-video", "--really-quiet", "--", str(path)], timeout=10, check=False)
    if result.returncode:
        raise RuntimeError(f"sound player exited {result.returncode}")
