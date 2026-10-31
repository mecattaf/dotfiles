#!/usr/bin/env python3
"""Copy completed client downloads to this host; Substrate owns recurrence."""

import argparse
from datetime import datetime, timezone
import fcntl
import json
import os
from pathlib import Path
import re
import shlex
import signal
import socket
import subprocess
import sys
import tempfile
import uuid


SSH = "ssh"
RSYNC = "rsync"
# Both peers use the stable NixOS per-user profile. The remote login shell
# expands its own USER, so neither its PATH nor a personal home path is needed.
REMOTE_HELPER = '"/etc/profiles/per-user/$USER/bin/downloads-mirror"'
REMOTE_RSYNC = "/etc/profiles/per-user/$USER/bin/rsync"
SSH_OPTIONS = [
    "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=yes",
    "-o", "ForwardAgent=no", "-o", "ConnectTimeout=10",
    "-o", "ServerAliveInterval=15", "-o", "ServerAliveCountMax=2",
]


def now():
    return datetime.now(timezone.utc).isoformat()


def download_directory(home=None, config_home=None):
    """Read XDG's assignment as data. Never evaluate a shell fragment."""
    home = Path(home or Path.home())
    config = Path(config_home or os.environ.get("XDG_CONFIG_HOME", home / ".config"))
    for line in (config / "user-dirs.dirs").read_text().splitlines():
        match = re.fullmatch(r'\s*XDG_DOWNLOAD_DIR\s*=\s*("(?:[^"\\]|\\.)*")\s*(?:#.*)?', line)
        if not match:
            continue
        value = match[1][1:-1]
        if value == "$HOME" or value.startswith("$HOME/"):
            value = str(home) + value[5:]
        elif value == "${HOME}" or value.startswith("${HOME}/"):
            value = str(home) + value[7:]
        value = re.sub(r'\\([\\"$`])', r'\1', value)
        path = Path(value)
        if not path.is_absolute() or path in (Path("/"), home):
            raise ValueError("XDG download directory must be an absolute directory other than home or root")
        if any(ord(c) < 32 or ord(c) == 127 for c in str(path)):
            raise ValueError("XDG download directory contains a control character")
        if path.resolve() in (Path("/"), home.resolve()):
            raise ValueError("XDG download directory resolves to home or root")
        return path
    raise ValueError("XDG_DOWNLOAD_DIR is missing from user-dirs.dirs")


def state_directory():
    return Path(os.environ.get("XDG_STATE_HOME", Path.home() / ".local/state")) / "downloads-mirror"


def write_json(path, value):
    with tempfile.NamedTemporaryFile(mode="w", dir=path.parent, prefix=path.name + ".", delete=False) as stream:
        temporary = Path(stream.name)
        stream.write(json.dumps(value, indent=2) + "\n")
    temporary.replace(path)


def request_transfer():
    state = state_directory()
    state.mkdir(parents=True, exist_ok=True, mode=0o700)
    write_json(state / "request.json", {"id": uuid.uuid4().hex, "requested_at": now()})


def drain_pending(source, dry_run=False):
    """Coalesce events during a copy into another pass, without a polling loop."""
    pending = state_directory() / "request.json"
    while True:
        before = pending.read_bytes() if pending.exists() else b""
        code = sync_once(source, dry_run)
        if code or not pending.exists() or pending.read_bytes() == before:
            return code


def background(source):
    request_transfer()
    state = state_directory()
    with (state / "worker.log").open("a") as log:
        process = subprocess.Popen(
            [sys.executable, str(Path(__file__).resolve()), "--source", source, "--drain-pending"],
            stdin=subprocess.DEVNULL, stdout=log, stderr=subprocess.STDOUT,
            start_new_session=True,
        )
    print(json.dumps({"status": "launched", "pid": process.pid,
                      "receipt": str(state / "status.json")}))
    return 0


def prepare_watch():
    directory = download_directory()
    directory.mkdir(parents=True, exist_ok=True)
    config = Path(os.environ.get("XDG_CONFIG_HOME", Path.home() / ".config"))
    dropin = config / "systemd/user/downloads-mirror-watch.path.d/xdg-directory.conf"
    dropin.parent.mkdir(parents=True, exist_ok=True)
    # PathChanged takes the absolute path verbatim, including spaces; it does
    # not strip shell quotes. Only systemd's percent specifiers need escaping.
    value = str(directory).replace("%", "%%")
    content = '[Path]\nPathChanged=\nPathChanged=' + value + '\n'
    with tempfile.NamedTemporaryFile(mode="w", dir=dropin.parent, delete=False) as stream:
        temporary = Path(stream.name)
        stream.write(content)
    temporary.replace(dropin)


def notify_receiver():
    # The source only signals an event. The NAS holds and uses its own SSH key
    # for the pull; no credentials or agent sockets cross hosts.
    try:
        result = subprocess.run(
            [SSH, *SSH_OPTIONS, "nas", REMOTE_HELPER + " --background"],
            capture_output=True, text=True, timeout=30,
        )
    except subprocess.TimeoutExpired:
        print(json.dumps({"status": "deferred", "reason": "receiver-timeout"}))
        return 0
    if result.returncode == 255:
        print(json.dumps({"status": "deferred", "reason": "receiver-unreachable"}))
        return 0
    if result.returncode:
        print(result.stderr, file=sys.stderr)
        return 1
    print(result.stdout, end="")
    return 0


def copy_command(source, source_directory, destination, state, run_id, dry_run=False):
    # --protect-args keeps spaces, quotes, glob characters and shell syntax in
    # filenames out of the remote shell. No --delete or --inplace is permitted.
    command = [
        RSYNC, "--archive", "--no-owner", "--no-group", "--protect-args",
        "--rsync-path=" + REMOTE_RSYNC,
        "--safe-links", "--partial", f"--partial-dir={state / 'partials'}",
        "--backup", f"--backup-dir={state / 'overwritten' / run_id}",
        "--timeout=45", "--stats", "--human-readable",
        "--exclude=*.crdownload", "--exclude=*.part", "--exclude=*.partial",
        "--exclude=*.tmp", "--exclude=.org.chromium.*",
        "--rsh=" + shlex.join([SSH, *SSH_OPTIONS]),
    ]
    if dry_run:
        command.append("--dry-run")
    command += ["--", f"{source}:{source_directory}/", str(destination) + "/"]
    return command


def sync_once(source, dry_run=False):
    if not re.fullmatch(r"[a-zA-Z0-9][a-zA-Z0-9_.-]*", source):
        raise ValueError("source must be an SSH host alias")
    state = state_directory()
    state.mkdir(parents=True, exist_ok=True, mode=0o700)
    state.chmod(0o700)
    lock = (state / "lock").open("a")
    try:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
    except BlockingIOError:
        print(json.dumps({"status": "busy", "source": source}))
        return 0
    run_id = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ-") + uuid.uuid4().hex[:8]
    runs = state / "runs"
    runs.mkdir(exist_ok=True)
    report = {"id": run_id, "started_at": now(), "status": "running", "pid": os.getpid(),
              "source": source, "receiver": socket.gethostname(), "dry_run": dry_run,
              "log": str(runs / (run_id + ".log"))}

    def save():
        write_json(runs / (run_id + ".json"), report)
        write_json(state / "status.json", report)

    save()
    code = 1
    try:
        destination = download_directory()
        # The remote helper resolves its own XDG config after fleet adoption.
        # Its JSON framing keeps banners and malformed output from becoming paths.
        remote = subprocess.run(
            [SSH, *SSH_OPTIONS, source, REMOTE_HELPER + " --print-directory"],
            capture_output=True, text=True, timeout=30,
        )
        if remote.returncode == 255:
            report.update(status="deferred", reason="client-unreachable", ssh_exit=255)
            (runs / (run_id + ".log")).write_text(remote.stderr)
            code = 0
        else:
            if remote.returncode:
                raise RuntimeError(f"source download lookup failed (SSH exit {remote.returncode}): {remote.stderr.strip()}")
            source_directory = json.loads(remote.stdout)["directory"]
            path = Path(source_directory)
            if not path.is_absolute() or path == Path("/") or any(ord(c) < 32 for c in source_directory):
                raise ValueError("source helper returned an unsafe directory")
            report.update(source_directory=source_directory, destination=str(destination))
            save()
            if not dry_run:
                destination.mkdir(parents=True, exist_ok=True)
                (state / "partials").mkdir(exist_ok=True)
            with (runs / (run_id + ".log")).open("w") as log:
                transfer = subprocess.Popen(
                    copy_command(source, source_directory, destination, state, run_id, dry_run),
                    stdout=log, stderr=subprocess.STDOUT,
                )
                try:
                    transfer.wait(timeout=270)
                except BaseException:
                    # Give rsync time to retain its resumable partial before
                    # the command returns to the scheduler.
                    transfer.terminate()
                    try:
                        transfer.wait(timeout=15)
                    except subprocess.TimeoutExpired:
                        transfer.kill()
                        transfer.wait()
                    raise
            report["transfer_exit"] = transfer.returncode
            if transfer.returncode == 0:
                report["status"] = "preview" if dry_run else "completed"
                code = 0
            elif transfer.returncode in (24, 30, 255):
                report.update(status="deferred", reason="source-changed-or-disconnected")
                code = 0
            else:
                report.update(status="failed", reason="transfer-error")
    except subprocess.TimeoutExpired:
        report.update(status="deferred", reason="time-budget-exhausted")
        code = 0
    except InterruptedError:
        report.update(status="interrupted", reason="termination-requested")
    except (OSError, ValueError, KeyError, RuntimeError) as error:
        report.update(status="failed", reason=str(error))
    finally:
        report["finished_at"] = now()
        save()
        lock.close()
    print(json.dumps(report))
    return code


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    action = parser.add_mutually_exclusive_group()
    action.add_argument("--print-directory", action="store_true", help="resolve this host's XDG download location")
    action.add_argument("--status", action="store_true", help="show the last transfer receipt")
    action.add_argument("--background", action="store_true", help="request a detached copy, coalescing overlapping events")
    action.add_argument("--notify", action="store_true", help="notify the NAS that client downloads changed")
    action.add_argument("--prepare-watch", action="store_true", help="prepare the local XDG watcher path during activation")
    action.add_argument("--drain-pending", action="store_true", help=argparse.SUPPRESS)
    parser.add_argument("--source", default="client", help="OpenSSH source host alias (default: client)")
    parser.add_argument("--dry-run", action="store_true", help="inspect transfers without changing downloads")
    args = parser.parse_args()
    os.umask(0o077)
    def interrupted(_signal, _frame):
        raise InterruptedError("termination requested")
    for number in (signal.SIGTERM, signal.SIGHUP, signal.SIGINT):
        signal.signal(number, interrupted)
    if args.dry_run and (args.background or args.notify or args.prepare_watch):
        parser.error("--dry-run cannot be combined with a background or watcher action")
    if args.prepare_watch:
        prepare_watch()
        return 0
    if args.notify:
        return notify_receiver()
    if args.background:
        return background(args.source)
    if args.print_directory:
        print(json.dumps({"directory": str(download_directory())}))
        return 0
    if args.status:
        path = state_directory() / "status.json"
        result = json.loads(path.read_text()) if path.exists() else {"status": "never-run"}
        if result["status"] == "running":
            try:
                os.kill(result["pid"], 0)
            except ProcessLookupError:
                result.update(status="interrupted", reason="transfer-process-exited")
        print(json.dumps(result, indent=2))
        return 0
    if not args.drain_pending:
        request_transfer()
    return drain_pending(args.source, args.dry_run)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError) as error:
        print(f"downloads-mirror: {error}", file=sys.stderr)
        sys.exit(1)
