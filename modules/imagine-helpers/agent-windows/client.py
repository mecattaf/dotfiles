#!/usr/bin/env python3
"""Prepared client endpoint. Never falls back to the focus-taking launcher."""
import fcntl
import hashlib
import json
import os
from pathlib import Path
import socket
import stat
import struct
import subprocess
import sys
import time
import uuid
sys.path.insert(0, str(Path(__file__).resolve().parent))
from transport import failure, validate

ROOT = ".local/state/kitty-dsh/agent-windows"

def tag(request):
    if request["kind"] == "terminal": return "agencyagent" + request["requestId"].replace("-", "")
    value = str(uuid.UUID(bytes=hashlib.sha256(request["requestId"].encode()).digest()[:16], version=4))
    return "agencychata6e17a11" + value.replace("-", "")[8:]

def private(path, directory=False):
    info = path.lstat()
    if info.st_uid != os.getuid() or info.st_mode & 0o077 or not (stat.S_ISDIR(info.st_mode) if directory else stat.S_ISREG(info.st_mode)):
        raise ValueError("not-ready")

def load(path):
    private(path); raw = path.read_bytes()
    if len(raw) > 16384: raise ValueError("not-ready")
    return json.loads(raw)

def discover(config):
    root = Path(config["runtimeDirectory"]); private(root, directory=True)
    found = []
    for p in root.glob("domicile-ipc.*.sock"):
        s = p.lstat()
        if not stat.S_ISSOCK(s.st_mode) or s.st_uid != os.getuid() or stat.S_IMODE(s.st_mode) != 0o600: continue
        with socket.socket(socket.AF_UNIX) as peer:
            peer.settimeout(.2)
            try:
                peer.connect(str(p))
                _, uid, _ = struct.unpack("3i", peer.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, 12))
                if uid == os.getuid(): found.append(str(p))
            except (OSError, TimeoutError): pass
    if len(found) != 1: raise ValueError("not-ready")
    return found[0]

def request(value):
    validate(value, ["zenbook"])
    # Chat viewers opened a NAS chat page that is retired. Refuse before any
    # Imagine placement is reserved; terminals are unaffected.
    if value["kind"] == "chat": return failure(value, "unavailable")
    config = load(Path.home()/".config/dsh-domicile/client.json")
    if config["desktopId"] != value["desktop"]: return failure(value, "not-ready")
    root = Path.home()/ROOT; root.mkdir(parents=True, mode=0o700, exist_ok=True); private(root, True)
    # A single request in flight across every NAS agent connection.
    fd = os.open(root/"active.lock", os.O_RDWR | os.O_CREAT | os.O_NOFOLLOW, 0o600)
    with os.fdopen(fd, "r+") as lock:
        try: fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except BlockingIOError: return failure(value, "busy")
        directory = root/value["requestId"].replace("-", "")
        directory.mkdir(mode=0o700, exist_ok=True); private(directory, True)
        payload = dict(value, tag=tag(value))
        source = directory/"request.json"
        if source.exists():
            if load(source) != payload: return failure(value, "request-conflict")
        else:
            with os.fdopen(os.open(source, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600), "w") as f:
                json.dump(payload, f)
        reply = directory/"reply.json"
        if reply.exists(): return load(reply)
        if (directory/"accepted.json").exists(): return failure(value, "outcome-unknown")
        binary = config["domicileBinary"]
        if not binary.startswith("/nix/store/"): return failure(value, "not-ready")
        result = subprocess.run([binary, "send-shell", "imagine", "agent-window-v1",
            directory.name, value["desktop"]], env=dict(os.environ, DOMICILE_SOCK=discover(config)),
            stdin=subprocess.DEVNULL, capture_output=True, timeout=5)
        if result.returncode: return failure(value, "not-ready")
        deadline = time.monotonic() + 105
        while time.monotonic() < deadline:
            if reply.exists():
                # The enclosing directory is private; normalize SDK-created
                # metadata files before returning a verified fixed receipt.
                reply.chmod(0o600)
                return load(reply)
            # Missing handler means no accepted marker. Fail quickly, without
            # spawning a window or trying the old native exec path.
            if deadline-time.monotonic() < 102 and not (directory/"accepted.json").exists():
                return failure(value, "not-ready")
            time.sleep(.05)
        return failure(value, "outcome-unknown")

def launch(value):
    original = {k:v for k,v in value.items() if k != "tag"}; validate(original, ["zenbook"])
    if value.get("tag") != tag(original): raise ValueError("invalid-arguments")
    if value["kind"] == "chat": raise ValueError("unavailable")
    directory = Path.home()/ROOT/value["requestId"].replace("-", "")
    logfd = os.open(directory/"terminal.log", os.O_WRONLY | os.O_CREAT | os.O_APPEND | os.O_NOFOLLOW, 0o600)
    shell = str(Path.home()/".local/bin/domicile-terminal")
    with os.fdopen(logfd, "ab") as log:
        child = subprocess.Popen(["/etc/profiles/per-user/tom/bin/kitty", "--class", value["tag"],
            "--title", "NAS terminal", "--override", "shell="+shell, "-e", shell, "--cwd", value["cwd"]],
            stdin=subprocess.DEVNULL, stdout=log, stderr=log, start_new_session=True)
    return dict(tag=value["tag"], pid=child.pid)

if __name__ == "__main__":
    value = {}
    try:
        value = json.loads(sys.stdin.buffer.read(16385))
        result = launch(value) if sys.argv[1:] == ["--launch"] else request(value) if sys.argv[1:] == [] else failure(value, "invalid-arguments")
    except Exception:
        result = failure(value if isinstance(value, dict) else {}, "unavailable")
    print(json.dumps(result))
