#!/usr/bin/env python3
"""A stand-in for `kitty-persist harness install|uninstall claude|codex`.

It writes the way the real install is specified to (one entry per event
running `kitty-persist hook NAME EVENT`, temp file plus rename onto the path it
is given, idempotent, uninstall removes exactly its entries), so the tests of
home/kitty-persist-hooks.py can show what that wrapper keeps and refuses.
STUB_MODE makes it misbehave: drop-comments, notify, clobber, bad-json, fail.
Not the product; it knows nothing of trust hashes beyond writing one.
"""
import hashlib
import json
import os
from pathlib import Path
import sys
import tempfile

CLAUDE_EVENTS = ["SessionStart", "UserPromptSubmit", "PostToolUse", "PermissionRequest", "Stop", "StopFailure", "SessionEnd"]
CODEX_EVENTS = ["SessionStart", "UserPromptSubmit", "PostToolUse", "PermissionRequest", "Stop", "SessionEnd"]
BEGIN = "# kitty-persist hooks (stub) begin"
END = "# kitty-persist hooks (stub) end"
mode = os.environ.get("STUB_MODE", "good")


def publish(path, text):
    old_mode = path.stat().st_mode & 0o7777 if path.exists() else 0o600
    fd, name = tempfile.mkstemp(dir=path.parent)
    with os.fdopen(fd, "w") as out:
        out.write(text)
    os.chmod(name, old_mode)
    os.replace(name, path)


def ours(group, name):
    return any(f"kitty-persist hook {name}" in h.get("command", "") for h in group.get("hooks", []))


def claude(verb):
    path = Path(os.environ.get("CLAUDE_CONFIG_DIR", Path.home() / ".claude")) / "settings.json"
    data = json.loads(path.read_text()) if path.exists() else {}
    hooks = data.setdefault("hooks", {})
    for event in CLAUDE_EVENTS:
        groups = [g for g in hooks.get(event, []) if not ours(g, "claude")]
        if verb == "install":
            groups.append({"hooks": [{"type": "command", "command": f"kitty-persist hook claude {event}", "timeout": 3}]})
        if groups:
            hooks[event] = groups
        else:
            hooks.pop(event, None)
    if not hooks:
        data.pop("hooks")
    if mode == "notify":
        data["preferredNotifChannel"] = "terminal_bell"
    if mode == "clobber":
        data["model"] = "other"
    text = json.dumps(data, indent=2) + "\n"
    if mode == "bad-json":
        text = text[:-3]
    if path.exists() and path.read_text() == text:
        print("no change")
        return
    publish(path, text)
    print(f"{verb}ed {len(CLAUDE_EVENTS)} entries in {path}")


def codex(verb):
    path = Path(os.environ.get("CODEX_HOME", Path.home() / ".codex")) / "config.toml"
    text = path.read_text() if path.exists() else ""
    if BEGIN in text:
        head, rest = text.split(BEGIN, 1)
        text = head.rstrip("\n") + "\n" + rest.split(END, 1)[1].lstrip("\n")
        if text == "\n":
            text = ""
    if verb == "install":
        lines = [BEGIN]
        states = []
        for event in CODEX_EVENTS:
            command = f"kitty-persist hook codex {event}"
            lines.append(f"[[hooks.{event}]]")
            lines.append(f'hooks = [{{ type = "command", command = "{command}", timeout = 3 }}]')
            digest = hashlib.sha256(command.encode()).hexdigest()
            states.append(f'"{path}:{event}:0:0" = {{ trusted_hash = "sha256:{digest}" }}')
        lines.append("[hooks.state]")
        lines.extend(states)
        lines.append(END)
        text = (text.rstrip("\n") + "\n\n" if text.strip() else "") + "\n".join(lines) + "\n"
    if mode == "drop-comments":
        text = "\n".join(line for line in text.splitlines() if not line.strip().startswith("#")) + "\n"
    if mode == "notify":
        text = 'notify = ["say"]\n' + text
    if path.exists() and path.read_text() == text:
        print("no change")
        return
    publish(path, text)
    print(f"{verb}ed {len(CODEX_EVENTS)} entries in {path}")


def main(argv):
    if mode == "fail":
        print("stub: failing on purpose", file=sys.stderr)
        return 3
    if len(argv) != 3 or argv[0] != "harness" or argv[1] not in ("install", "uninstall"):
        print("usage: harness install|uninstall NAME", file=sys.stderr)
        return 64
    {"claude": claude, "codex": codex}[argv[2]](argv[1])
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
