#!/usr/bin/env python3
"""Keep Claude's shared, user-editable settings outside the dotfiles checkout."""
import argparse
import json
import os
from pathlib import Path
import tempfile


def initialize(home: Path, template: Path):
    seats = [home / name / "settings.json" for name in (".claude", ".claude-work", ".claude-3")]
    target = home / ".local/state/claude/settings.json"
    target.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
    if not target.exists():
        settings = json.loads(template.read_text())
        existing = [seat for seat in seats if seat.exists()]
        if existing:
            # Preserve the user's current model, effort, plugins and preferences.
            settings.update(json.loads(existing[0].read_text()))
        fd, name = tempfile.mkstemp(prefix=".settings-", dir=target.parent)
        temporary = Path(name)
        try:
            with os.fdopen(fd, "w") as out:
                json.dump(settings, out, indent=2)
                out.write("\n")
                out.flush()
                os.fsync(out.fileno())
            # Publish only complete JSON, without overwriting concurrent initialization.
            try:
                os.link(temporary, target)
            except FileExistsError:
                pass
        finally:
            temporary.unlink()
    json.loads(target.read_text())  # Refuse invalid state before touching links.
    for seat in seats:
        seat.parent.mkdir(parents=True, exist_ok=True)
        if seat.is_symlink() and seat.resolve() == target:
            continue
        if seat.exists() and seat.read_bytes() != target.read_bytes():
            # Preserve any independently edited seat before joining shared state.
            fd, backup = tempfile.mkstemp(prefix=seat.parent.name + "-", suffix=".json", dir=target.parent)
            with os.fdopen(fd, "wb") as out:
                out.write(seat.read_bytes())
            print(f"Preserved separate Claude settings: {backup}")
        with tempfile.TemporaryDirectory(prefix=".settings-", dir=seat.parent) as directory:
            temporary = Path(directory) / "settings.json"
            temporary.symlink_to(target)
            os.replace(temporary, seat)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--home", type=Path, required=True)
    parser.add_argument("--template", type=Path, required=True)
    args = parser.parse_args()
    initialize(args.home, args.template)
