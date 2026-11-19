#!/usr/bin/env python3
"""Install kitty-persist's agent hooks into Claude Code and Codex, and check the result.

The install itself is the program's own `kitty-persist harness install NAME
--dir DIR`, once per configuration directory: the program owns the hook
entries (each runs the bare `kitty-persist hook NAME EVENT`, found on PATH), the
format-keeping edit, the safe write and Codex's trust hashes. This wrapper adds
the checks this fleet's layout needs around it:

- Claude Code: every seat's settings.json is a link to one shared file
  (home/claude-settings.py). The program follows the link and replaces its
  target, so the install for the first seat writes the shared file and the
  install for the next seat finds the entries and changes nothing. Afterwards
  every seat link must still be a link to the same file.
- Codex: ~/.codex/config.toml is mutable and unmanaged; the entries go to
  hooks.json beside it and only the trust records (`hooks.state`) to
  config.toml. Every value outside `hooks` and every comment line must still be
  there.
- Every entry the program wrote runs the bare program name, no store path
  (a store path would change Codex's trust hash with every update).
- No file may gain a notification override (Claude `preferredNotifChannel`,
  Codex `notify` or `tui.notifications`), and hooks that were not ours stay
  as they were.

A failed check puts the previous bytes of every file back (only a file that
nothing else wrote meanwhile) and exits 1; the activation step that runs this
reports it and goes on. `--dry-run` runs the same installs and checks on
copies (the seat links recreated around a copy of the shared file) and prints
the difference, touching nothing.

Usage:
  kitty-persist-hooks.py install|uninstall --program PATH --home HOME
      [--claude-seat DIR ...] [--codex-home DIR] [--dry-run]
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


def ours(name, command):
    """Whether a hook command is one the program writes for harness `name`."""
    return isinstance(command, str) and command.startswith(f"kitty-persist hook {name} ")


def written_by_us(name, command):
    """A command naming our hook in any other way (a path before the program name, say)."""
    return isinstance(command, str) and f"hook {name} " in command and "kitty-persist" in command


def commands(value):
    """Every `command` string anywhere under a JSON or TOML value."""
    if isinstance(value, dict):
        for k, v in value.items():
            if k == "command" and isinstance(v, str):
                yield v
            else:
                yield from commands(v)
    elif isinstance(value, list):
        for v in value:
            yield from commands(v)


def without(mapping, key):
    return {k: v for k, v in mapping.items() if k != key}


def comments(text):
    """The comment lines of a TOML text."""
    return sorted(line.strip() for line in (text or "").splitlines() if line.strip().startswith("#"))


def read(path):
    try:
        return path.read_text()
    except FileNotFoundError:
        return None


def run_program(program, verb, name, directory, env):
    """`kitty-persist harness VERB NAME --dir DIR`; its own lines are printed."""
    result = subprocess.run(
        [program, "harness", verb, name, "--dir", str(directory)],
        env=env, stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=TIMEOUT,
    )
    for line in (result.stdout + result.stderr).splitlines():
        print(f"  {name} {directory}: {line}")
    if result.returncode != 0:
        raise Refused(f"kitty-persist harness {verb} {name} --dir {directory} exited {result.returncode}")


def hook_groups(settings):
    """Foreign hook groups (not ours), and our commands, of a hooks mapping."""
    foreign, mine = [], []
    for event, groups in (settings.get("hooks") or {}).items() if isinstance(settings, dict) else []:
        for group in groups if isinstance(groups, list) else []:
            cmds = list(commands(group))
            if cmds and all(ours_any(c) for c in cmds):
                mine.extend(cmds)
            else:
                foreign.append((event, group))
    return foreign, mine


def ours_any(command):
    return ours("claude", command) or ours("codex", command) or written_by_us("claude", command) or written_by_us("codex", command)


def check_entries(name, before, after, verb):
    """Shared rules for a hooks file (Claude settings.json, Codex hooks.json)."""
    foreign_before, _ = hook_groups(before)
    foreign_after, mine = hook_groups(after)
    if foreign_before != foreign_after:
        raise Refused(f"an existing {name} hook was removed or changed")
    stray = [c for c in mine if not ours(name, c)]
    if stray:
        raise Refused(f"an entry does not run the bare program name: {stray[0]!r}")
    if verb == "install" and not mine:
        raise Refused(f"no `kitty-persist hook {name}` entry was added")
    if verb == "uninstall" and mine:
        raise Refused(f"a `kitty-persist hook {name}` entry is still there")
    return mine


def parse_json(text, what):
    if text is None:
        return {}
    try:
        value = json.loads(text)
    except ValueError as error:
        raise Refused(f"{what} is not JSON: {error}")
    if not isinstance(value, dict):
        raise Refused(f"{what} is not a JSON object")
    return value


def check_claude(files, before, after, verb):
    (path,) = files
    old, new = parse_json(before[path], str(path)), parse_json(after[path], str(path))
    for key in CLAUDE_NOTIFY:
        if key in new and key not in old:
            raise Refused(f"a notification override was added: {key}")
    if without(new, "hooks") != without(old, "hooks"):
        changed = sorted(k for k in set(new) | set(old) if k != "hooks" and new.get(k) != old.get(k))
        raise Refused(f"settings outside `hooks` changed: {', '.join(changed)}")
    mine = check_entries("claude", old, new, verb)
    if verb == "install":
        print(f"  claude: {len(mine)} kitty-persist hook entries")


def check_codex(files, before, after, verb):
    hooks_json, config = files
    old_hooks = parse_json(before[hooks_json], str(hooks_json))
    new_hooks = parse_json(after[hooks_json], str(hooks_json))
    mine = check_entries("codex", old_hooks, new_hooks, verb)
    try:
        old = tomllib.loads(before[config] or "")
        new = tomllib.loads(after[config] or "")
    except tomllib.TOMLDecodeError as error:
        raise Refused(f"config.toml is not TOML: {error}")
    if "notify" in new and "notify" not in old:
        raise Refused("a notification override was added: notify")
    if "notifications" in (new.get("tui") or {}) and "notifications" not in (old.get("tui") or {}):
        raise Refused("a notification override was added: tui.notifications")
    if without(new, "hooks") != without(old, "hooks"):
        changed = sorted(k for k in set(new) | set(old) if k != "hooks" and new.get(k) != old.get(k))
        raise Refused(f"config.toml outside `hooks` changed: {', '.join(changed)}")
    if without(new.get("hooks") or {}, "state") != without(old.get("hooks") or {}, "state"):
        raise Refused("config.toml `hooks` changed outside the trust records")
    lost = [c for c in set(comments(before[config])) if comments(after[config]).count(c) < comments(before[config]).count(c)]
    if lost:
        raise Refused(f"{len(lost)} comment line(s) were dropped from config.toml")
    trusted = [v for v in ((new.get("hooks") or {}).get("state") or {}).values()
               if isinstance(v, dict) and str(v.get("trusted_hash", "")).startswith("sha256:")]
    if verb == "install":
        print(f"  codex: {len(mine)} kitty-persist hook entries, {len(trusted)} trust records")
        if len(trusted) < len(mine):
            print("  codex: fewer trust records than entries; Codex asks to trust the rest on its next start")


def restore(path, before, now, mode):
    """Put `before` back, unless the file changed again since the install."""
    if read(path) != now:
        print(f"  {path}: changed again since the install; left as it is")
        return
    if before is None:
        path.unlink()
        print(f"  {path}: removed again")
        return
    fd, name = tempfile.mkstemp(prefix=".kitty-persist-restore-", dir=path.parent)
    with os.fdopen(fd, "w") as out:
        out.write(before)
        out.flush()
        os.fsync(out.fileno())
    os.chmod(name, mode)
    os.replace(name, path)
    print(f"  {path}: previous content restored")


def links_of(paths):
    return {p: os.path.realpath(p) for p in paths if p.is_symlink()}


def run_harness(name, verb, program, dirs, files, env, check, dry_run, seat_files=()):
    """Install or uninstall harness `name` in each of `dirs`; `files` are the files it may write."""
    before = {f: read(f) for f in files}
    modes = {f: (f.stat().st_mode & 0o7777) for f in files if before[f] is not None}
    links = links_of(seat_files)
    print(f"{name}: {verb} in {', '.join(map(str, dirs))}{' (dry run, on copies)' if dry_run else ''}")
    try:
        for directory in dirs:
            run_program(program, verb, name, directory, env)
        after = {f: read(f) for f in files}
        check(files, before, after, verb)
        for f, mode in modes.items():
            if after[f] is not None and f.stat().st_mode & 0o7777 != mode:
                raise Refused(f"{f}: mode changed from {mode:o} to {f.stat().st_mode & 0o7777:o}")
        for seat, target in links.items():
            if not seat.is_symlink() or os.path.realpath(seat) != target:
                raise Refused(f"{seat} is no longer the link to {target}")
    except (Refused, subprocess.TimeoutExpired, OSError) as error:
        print(f"{name}: FAILED: {error}")
        for f in files:
            now = read(f)
            if now != before[f]:
                restore(f, before[f], now, modes.get(f, 0o600))
        return False
    for f in files:
        if after[f] == before[f]:
            print(f"{name}: {f} unchanged")
        elif dry_run:
            sys.stdout.writelines(difflib.unified_diff(
                (before[f] or "").splitlines(True), (after[f] or "").splitlines(True),
                fromfile=f"{f.name} before", tofile=f"{f.name} after"))
    return True


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("verb", choices=["install", "uninstall"])
    parser.add_argument("--program", required=True)
    parser.add_argument("--home", type=Path, required=True)
    parser.add_argument("--claude-seat", type=Path, action="append", default=[])
    parser.add_argument("--codex-home", type=Path)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args(argv)

    program = shutil.which(args.program) or args.program
    env = dict(os.environ, HOME=str(args.home))
    for key in ("CLAUDE_CONFIG_DIR", "CODEX_HOME", "KITTY_PERSIST_ID"):
        env.pop(key, None)
    ok = True
    with tempfile.TemporaryDirectory(prefix="kitty-persist-hooks-") as scratch:
        scratch = Path(scratch)
        if args.claude_seat:
            seats = [s for s in args.claude_seat if (s / "settings.json").exists()]
            for s in args.claude_seat:
                if s not in seats:
                    print(f"claude: {s}/settings.json does not exist yet (home/claude-settings.py seeds it); skipped")
            if args.dry_run and seats:
                # The same layout on copies: each seat's link (or file) recreated around a copy.
                copies, targets = [], {}
                for i, seat in enumerate(seats):
                    real = Path(os.path.realpath(seat / "settings.json"))
                    copy = scratch / f"seat{i}"
                    copy.mkdir()
                    if (seat / "settings.json").is_symlink():
                        if real not in targets:
                            targets[real] = scratch / f"shared{len(targets)}" / "settings.json"
                            targets[real].parent.mkdir()
                            shutil.copy2(real, targets[real])
                        (copy / "settings.json").symlink_to(targets[real])
                    else:
                        shutil.copy2(real, copy / "settings.json")
                    copies.append(copy)
                seats = copies
            files = sorted({Path(os.path.realpath(s / "settings.json")) for s in seats})
            for target in files:
                group = [s for s in seats if Path(os.path.realpath(s / "settings.json")) == target]
                ok &= run_harness("claude", args.verb, program, group, [target], env, check_claude,
                                  args.dry_run, [s / "settings.json" for s in group])
        if args.codex_home is not None:
            directory = args.codex_home
            if args.dry_run:
                directory = scratch / "codex"
                directory.mkdir()
                for f in ("config.toml", "hooks.json"):
                    if (args.codex_home / f).exists():
                        shutil.copy2(args.codex_home / f, directory / f)
            elif not directory.exists():
                directory.mkdir(mode=0o700, parents=True)
            files = [directory / "hooks.json", directory / "config.toml"]
            ok &= run_harness("codex", args.verb, program, [directory], files, env, check_codex, args.dry_run)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
