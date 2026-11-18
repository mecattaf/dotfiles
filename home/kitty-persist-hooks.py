#!/usr/bin/env python3
"""Install kitty-persist's agent hooks into Claude Code and Codex, and check the result.

The install itself is `kitty-persist harness install NAME` (the program owns
the hook entries, the safe write and Codex's trust hashes). This wrapper adds
what this fleet's layout needs around it:

- Claude Code: both seats' settings.json are symlinks to one shared file
  (home/claude-settings.py). The install is pointed at the directory of that
  file, so its temp-file-and-rename lands on the real file and never replaces
  a seat link (the next activation would back the file up and restore the
  link without the hooks).
- Codex: ~/.codex/config.toml is mutable and unmanaged. After the install,
  every value outside `hooks` and every comment line must still be there.
- Neither file may gain a notification override (Claude
  `preferredNotifChannel`, Codex `notify` or `tui.notifications`).

A failed check puts the previous bytes back (only if nothing else wrote the
file meanwhile) and is reported; it never stops the rest of the activation.
`--dry-run` runs the same install and checks on copies in a temporary
directory and prints the difference, touching nothing.

Usage:
  kitty-persist-hooks.py install|uninstall --program PATH --home HOME
      [--claude-dir DIR] [--claude-seat DIR ...] [--codex-home DIR] [--dry-run]
"""
import argparse
import difflib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import tomllib

TIMEOUT = 30
CLAUDE_NOTIFY = ("preferredNotifChannel",)


class Refused(Exception):
    pass


def comments(text):
    """The comment lines of a TOML text, but the install's own (they name kitty-persist)."""
    return sorted(
        line.strip() for line in text.splitlines()
        if line.strip().startswith("#") and "kitty-persist" not in line
    )


def without(mapping, key):
    return {k: v for k, v in mapping.items() if k != key}


def run_program(program, verb, name, env):
    """Run `kitty-persist harness VERB NAME`; its own lines go to stdout."""
    result = subprocess.run(
        [program, "harness", verb, name],
        env=env,
        stdin=subprocess.DEVNULL,
        capture_output=True,
        text=True,
        timeout=TIMEOUT,
    )
    for line in (result.stdout + result.stderr).splitlines():
        print(f"  {name}: {line}")
    if result.returncode != 0:
        raise Refused(f"kitty-persist harness {verb} {name} exited {result.returncode}")


def check_claude(before, after_text, verb):
    try:
        after = json.loads(after_text)
    except ValueError as error:
        raise Refused(f"settings.json is no longer JSON: {error}")
    if not isinstance(after, dict):
        raise Refused("settings.json is no longer a JSON object")
    old = json.loads(before) if before is not None else {}
    for key in CLAUDE_NOTIFY:
        if key in after and key not in old:
            raise Refused(f"a notification override was added: {key}")
    if without(after, "hooks") != without(old, "hooks"):
        changed = sorted(k for k in set(after) | set(old) if k != "hooks" and after.get(k) != old.get(k))
        raise Refused(f"settings outside `hooks` changed: {', '.join(changed)}")
    # Every hook group that was there before is still there.
    old_hooks = old.get("hooks") or {}
    new_hooks = after.get("hooks") or {}
    for event, groups in old_hooks.items():
        for group in groups if isinstance(groups, list) else []:
            if group_is_ours(group):
                continue
            if group not in (new_hooks.get(event) or []):
                raise Refused(f"an existing {event} hook was removed or changed")
    ours = [g for groups in new_hooks.values() if isinstance(groups, list) for g in groups if group_is_ours(g)]
    if verb == "install" and not ours:
        raise Refused("no `kitty-persist hook claude` entry was added")
    if verb == "uninstall" and ours:
        raise Refused("a `kitty-persist hook claude` entry is still there")


def group_is_ours(group):
    return isinstance(group, dict) and any(
        isinstance(h, dict) and "kitty-persist hook claude" in str(h.get("command", ""))
        for h in group.get("hooks") or []
    )


def codex_commands(value):
    """Every `command` string anywhere under a TOML value."""
    if isinstance(value, dict):
        for k, v in value.items():
            if k == "command" and isinstance(v, str):
                yield v
            else:
                yield from codex_commands(v)
    elif isinstance(value, list):
        for v in value:
            yield from codex_commands(v)


def check_codex(before, after_text, verb):
    try:
        after = tomllib.loads(after_text)
    except tomllib.TOMLDecodeError as error:
        raise Refused(f"config.toml is no longer TOML: {error}")
    old = tomllib.loads(before) if before is not None else {}
    if "notify" in after and "notify" not in old:
        raise Refused("a notification override was added: notify")
    if "notifications" in (after.get("tui") or {}) and "notifications" not in (old.get("tui") or {}):
        raise Refused("a notification override was added: tui.notifications")
    if without(after, "hooks") != without(old, "hooks"):
        changed = sorted(k for k in set(after) | set(old) if k != "hooks" and after.get(k) != old.get(k))
        raise Refused(f"config outside `hooks` changed: {', '.join(changed)}")
    lost = [c for c in comments(before or "") if comments(after_text).count(c) < comments(before or "").count(c)]
    if lost:
        raise Refused(f"{len(set(lost))} comment line(s) were dropped")
    ours = [c for c in codex_commands(after.get("hooks") or {}) if "kitty-persist hook codex" in c]
    theirs_before = [c for c in codex_commands(old.get("hooks") or {}) if "kitty-persist hook codex" not in c]
    theirs_after = [c for c in codex_commands(after.get("hooks") or {}) if "kitty-persist hook codex" not in c]
    if sorted(theirs_before) != sorted(theirs_after):
        raise Refused("an existing Codex hook was removed or changed")
    if verb == "install" and not ours:
        raise Refused("no `kitty-persist hook codex` entry was added")
    if verb == "uninstall" and ours:
        raise Refused("a `kitty-persist hook codex` entry is still there")
    if verb == "install":
        state = (after.get("hooks") or {}).get("state") or {}
        if not any(isinstance(v, dict) and str(v.get("trusted_hash", "")).startswith("sha256:") for v in state.values()):
            print("  codex: no trusted_hash recorded; Codex asks to trust the new hooks on its next start")


def read(path):
    try:
        return path.read_text()
    except FileNotFoundError:
        return None


def restore(path, before, after_text, mode):
    """Put `before` back, unless the file changed again since the install."""
    if read(path) != after_text:
        print(f"  {path}: changed again since the install; left as it is")
        return
    if before is None:
        path.unlink()
        return
    fd, name = tempfile.mkstemp(prefix=".kitty-persist-restore-", dir=path.parent)
    with os.fdopen(fd, "w") as out:
        out.write(before)
        out.flush()
        os.fsync(out.fileno())
    os.chmod(name, mode)
    os.replace(name, path)
    print(f"  {path}: previous content restored")


def one(name, verb, program, path, env, check, dry_run, seats=()):
    """Install or uninstall one harness on one file; True when it checked out."""
    if path.is_symlink():
        print(f"{name}: {path} is a symlink; refusing (the install must target the real file)")
        return False
    before = read(path)
    if before is None and name == "claude":
        print(f"{name}: {path} does not exist yet (home/claude-settings.py seeds it); skipped")
        return True
    mode = path.stat().st_mode & 0o7777 if before is not None else 0o600
    links = {seat: os.path.realpath(seat) for seat in seats if seat.is_symlink()}
    print(f"{name}: {verb} into {path}{' (dry run, on a copy)' if dry_run else ''}")
    try:
        run_program(program, verb, name, env)
        after_text = read(path)
        if after_text is None:
            raise Refused(f"{path} is gone")
        check(before, after_text, verb)
        if before is not None and path.stat().st_mode & 0o7777 != mode:
            raise Refused(f"mode changed from {mode:o} to {path.stat().st_mode & 0o7777:o}")
        for seat, target in links.items():
            if not seat.is_symlink() or os.path.realpath(seat) != target:
                raise Refused(f"{seat} is no longer the link to {target}")
    except (Refused, subprocess.TimeoutExpired, OSError) as error:
        print(f"{name}: FAILED: {error}")
        after_text = read(path)
        if after_text is not None and after_text != before:
            restore(path, before, after_text, mode)
        return False
    if dry_run:
        diff = difflib.unified_diff(
            (before or "").splitlines(True), (after_text or "").splitlines(True),
            fromfile=f"{name} before", tofile=f"{name} after",
        )
        sys.stdout.writelines(diff)
    elif before == after_text:
        print(f"{name}: unchanged")
    return True


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("verb", choices=["install", "uninstall"])
    parser.add_argument("--program", required=True)
    parser.add_argument("--home", type=Path, required=True)
    parser.add_argument("--claude-dir", type=Path)
    parser.add_argument("--claude-seat", type=Path, action="append", default=[])
    parser.add_argument("--codex-home", type=Path)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args(argv)

    program = shutil.which(args.program) or args.program
    base = dict(os.environ, HOME=str(args.home))
    base.pop("CLAUDE_CONFIG_DIR", None)
    base.pop("CODEX_HOME", None)
    ok = True
    with tempfile.TemporaryDirectory(prefix="kitty-persist-hooks-") as scratch:
        if args.claude_dir is not None:
            directory = args.claude_dir
            seats = [seat / "settings.json" for seat in args.claude_seat]
            if args.dry_run:
                directory = Path(scratch) / "claude"
                directory.mkdir()
                if (args.claude_dir / "settings.json").exists():
                    shutil.copy2(args.claude_dir / "settings.json", directory / "settings.json")
                seats = []
            env = dict(base, CLAUDE_CONFIG_DIR=str(directory))
            ok &= one("claude", args.verb, program, directory / "settings.json", env, check_claude, args.dry_run, seats)
        if args.codex_home is not None:
            directory = args.codex_home
            if args.dry_run:
                directory = Path(scratch) / "codex"
                directory.mkdir()
                if (args.codex_home / "config.toml").exists():
                    shutil.copy2(args.codex_home / "config.toml", directory / "config.toml")
            elif not directory.exists():
                directory.mkdir(mode=0o700, parents=True)
            env = dict(base, CODEX_HOME=str(directory))
            ok &= one("codex", args.verb, program, directory / "config.toml", env, check_codex, args.dry_run)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
