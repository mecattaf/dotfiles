#!/usr/bin/env python3
"""Run the real `kitty-persist harness install NAME --dir DIR`, then spoil its result.

Usage: spoil.py MODE PROGRAM harness install|uninstall NAME --dir DIR

The faults an install could have, for the guard tests of
home/kitty-persist-hooks.py: fail (exit 3, nothing run), notify (a
notification override), clobber (a setting outside `hooks`), drop-comments
(Codex comments lost), store-path (an entry naming a store path instead of the
bare program), unlink-seat (the seat link replaced by a file).
"""
import json
import os
from pathlib import Path
import subprocess
import sys

mode, program, *argv = sys.argv[1:]
if mode == "fail":
    print("spoil: failing on purpose", file=sys.stderr)
    sys.exit(3)
rc = subprocess.run([program, *argv]).returncode
if rc != 0 or argv[1] != "install":
    sys.exit(rc)
name, directory = argv[2], Path(argv[argv.index("--dir") + 1])


def edit(path, change):
    if path.exists():
        path.write_text(change(path.read_text()))  # through a link, onto its target


store = "/nix/store/00000000000000000000000000000000-kitty-persist/bin/kitty-persist"
if name == "claude":
    settings = directory / "settings.json"
    if mode == "notify":
        edit(settings, lambda t: json.dumps(dict(json.loads(t), preferredNotifChannel="terminal_bell"), indent=2) + "\n")
    elif mode == "clobber":
        edit(settings, lambda t: json.dumps(dict(json.loads(t), model="other"), indent=2) + "\n")
    elif mode == "store-path":
        edit(settings, lambda t: t.replace('"kitty-persist hook claude', f'"{store} hook claude'))
    elif mode == "unlink-seat" and settings.is_symlink():
        text = settings.read_text()
        settings.unlink()
        settings.write_text(text)
elif name == "codex":
    config, hooks = directory / "config.toml", directory / "hooks.json"
    if mode == "notify":
        edit(config, lambda t: 'notify = ["say"]\n' + t)
    elif mode == "drop-comments":
        edit(config, lambda t: "".join(line for line in t.splitlines(True) if not line.lstrip().startswith("#")))
    elif mode == "store-path":
        edit(hooks, lambda t: t.replace('"kitty-persist hook codex', f'"{store} hook codex'))
sys.exit(0)
