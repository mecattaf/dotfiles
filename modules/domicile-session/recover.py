"""Console recovery for one Domicile desktop. No user-manager mutation."""
import argparse
import datetime
import errno
import json
import os
from pathlib import Path
import select
import shlex
import signal
import socket
import stat
import struct
import subprocess
import sys
import tempfile

DOMICILE = "@domicile@/bin/domicile"
BUILDER = "@domicile@/libexec/domicile/builder"
RESCUE = "@rescue@"
EXTENSIONS = ("ts", "tsx", "js", "mjs", "json")


def xdg(name, fallback):
    value = os.environ.get(name, "")
    return Path(value) if value.startswith("/") else Path.home() / fallback


def config_file():
    if "DOMICILE_CONFIG_FILE" in os.environ:
        explicit = Path(os.environ["DOMICILE_CONFIG_FILE"])
        if not explicit.is_absolute() or explicit.suffix.removeprefix(".") not in EXTENSIONS:
            raise RuntimeError("DOMICILE_CONFIG_FILE must name an absolute "
                               "domicile .ts/.tsx/.js/.mjs/.json file")
        return explicit
    directory = xdg("XDG_CONFIG_HOME", ".config") / "domicile"
    # Include broken symlinks: these must report a failure, not run defaults.
    found = [directory / ("domicile." + ext) for ext in EXTENSIONS
             if os.path.lexists(directory / ("domicile." + ext))]
    if len(found) != 1:
        raise RuntimeError(f"Keep exactly one domicile.{{{','.join(EXTENSIONS)}}} in "
                           f"{directory}; found {len(found)}: "
                           + ", ".join(map(str, found)))
    return found[0]


def run(argv, log, env=None):
    log.write("$ " + shlex.join(map(str, argv)) + "\n")
    log.flush()
    try:
        result = subprocess.run(argv, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                                text=True, timeout=60, env=env)
    except subprocess.TimeoutExpired as error:
        if error.stdout:
            log.write(error.stdout.decode(errors="replace") if isinstance(error.stdout, bytes)
                      else error.stdout)
        raise RuntimeError("Command timed out after 60 seconds; see the saved log") from error
    log.write(result.stdout)
    log.flush()
    if result.returncode:
        raise RuntimeError(f"{Path(argv[0]).name} exited {result.returncode}:\n{result.stdout.strip()}")
    return result.stdout


def check():
    directory = xdg("XDG_STATE_HOME", ".local/state") / "domicile-session"
    directory.mkdir(mode=0o700, parents=True, exist_ok=True)
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime("%Y%m%dT%H%M%S.%fZ")
    receipt = directory / f"check-{stamp}-{os.getpid()}.log"
    fd = os.open(receipt, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    with os.fdopen(fd, "w") as log:
        try:
            path = config_file()
            log.write(f"Config: {path}\n")
            if not path.is_file():
                raise RuntimeError(f"Config is missing or not a regular file: {path}")
            with tempfile.TemporaryDirectory(prefix="domicile-check-") as scratch:
                if path.suffix != ".json":
                    output = run([BUILDER, "--evaluate", str(path), "--cache", scratch], log)
                    records = []
                    for line in output.splitlines():
                        try:
                            records.append(json.loads(line))
                        except json.JSONDecodeError:
                            pass
                    evaluated = [r.get("config") for r in records
                                 if isinstance(r, dict) and r.get("step") == "evaluated"]
                    if len(evaluated) != 1 or not isinstance(evaluated[0], str):
                        raise RuntimeError("Builder did not report exactly one evaluated config")
                    run([DOMICILE, "check-config", evaluated[0]], log)
                    run([BUILDER, "--entry", str(path), "--cache", scratch], log)
                else:
                    run([DOMICILE, "check-config", str(path)], log)
                    data = json.loads(path.read_text())
                    if not isinstance(data.get("shell"), str) or not data["shell"]:
                        raise RuntimeError("JSON config must name its shell")
                    shell = data["shell"]
                    if shell.startswith("@domicile-desktop/"):
                        name = shell.removeprefix("@domicile-desktop/").removeprefix("shell-")
                        shipped = Path(DOMICILE).parent.parent / "libexec/domicile/shells" / name / "shell.js"
                        if not shipped.is_file():
                            raise RuntimeError(f"No shipped shell at {shipped}")
                        log.write(f"Shipped shell: {shipped}\n")
                    else:
                        source = Path(shell).expanduser()
                        if not source.is_absolute():
                            source = path.parent / source
                        if not source.is_file():
                            raise RuntimeError(f"No local shell module at {source}. "
                                               "Build external packages separately and name a local module.")
                        run([BUILDER, "--entry", str(source), "--cache", scratch], log)
            log.write("PASS: config checked; source shell built or shipped shell present\n")
            print(f"Domicile config ready: {path}\nCheck log: {receipt}")
        except (OSError, RuntimeError, ValueError) as error:
            log.write(f"FAIL: {error}\n")
            raise RuntimeError(f"{error}\nCheck log: {receipt}") from error


def connect(path):
    if not path:
        raise RuntimeError("No desktop selected. Run domicile-recover status, then use "
                           "--socket PATH (or DOMICILE_SOCK).")
    path = Path(path)
    info = path.stat()
    if not stat.S_ISSOCK(info.st_mode) or info.st_uid != os.getuid():
        raise RuntimeError(f"Not your desktop socket: {path}")
    client = socket.socket(socket.AF_UNIX)
    client.settimeout(5)
    try:
        client.connect(str(path))
        pid, uid, _gid = struct.unpack("3i", client.getsockopt(
            socket.SOL_SOCKET, socket.SO_PEERCRED, struct.calcsize("3i")))
        if uid != os.getuid():
            raise RuntimeError("Socket peer belongs to another user")
        return client, pid
    except BaseException:
        client.close()
        raise


def selected(path):
    client, pid = connect(path)
    # Open a pidfd before checking the executable. A reused PID cannot be signalled.
    try:
        pidfd = os.pidfd_open(pid)
        try:
            if Path(f"/proc/{pid}/exe").resolve() != Path(DOMICILE).resolve():
                raise RuntimeError(f"Socket peer {pid} is not this installation's Domicile launcher")
        except BaseException:
            os.close(pidfd)
            raise
        return client, pid, pidfd
    except BaseException:
        client.close()
        raise


def login_check():
    runtime = os.environ.get("XDG_RUNTIME_DIR")
    if not runtime or not Path(runtime).is_absolute():
        raise RuntimeError("XDG_RUNTIME_DIR must name your login's runtime directory")
    for path in sorted(Path(runtime).glob("domicile-ipc.*.sock")):
        try:
            client, _pid = connect(str(path))
        except OSError as error:
            if error.errno in (errno.ECONNREFUSED, errno.ENOENT):
                continue  # Dead sockets remain as evidence; never unlink them here.
            raise
        else:
            client.close()
            raise RuntimeError(f"A desktop is already listening at {path}. "
                               "Run domicile-recover status; exit that desktop before login.")
    check()


def status():
    runtime = os.environ.get("XDG_RUNTIME_DIR")
    if not runtime or not Path(runtime).is_absolute():
        raise RuntimeError("XDG_RUNTIME_DIR must name your login's runtime directory")
    print("Desktop sockets (select the intended one explicitly):")
    for path in sorted(Path(runtime).glob("domicile-ipc.*.sock")):
        try:
            client, pid, pidfd = selected(str(path))
            try:
                with client:
                    client.sendall(b'{"type":"which_shell"}\n')
                    answer = client.recv(65536).decode(errors="replace").strip()
            finally:
                os.close(pidfd)
            print(f"  {path}: pid {pid}, {answer}")
            print(f"    domicile-recover --socket {shlex.quote(str(path))} rescue")
            print(f"    domicile-recover --socket {shlex.quote(str(path))} exit")
        except (OSError, RuntimeError) as error:
            print(f"  {path}: unavailable: {error}")
    print("Login logs: journalctl -t domicile-session -b\n"
          "Config checks: " + str(xdg("XDG_STATE_HOME", ".local/state") / "domicile-session"))


def recover(path, action):
    client, pid, pidfd = selected(path)
    try:
        if action == "rescue":
            env = dict(os.environ, DOMICILE_SOCK=str(path))
            result = subprocess.run([DOMICILE, "load-shell", RESCUE], env=env, timeout=60)
            if result.returncode:
                raise RuntimeError(f"Rescue shell was refused (exit {result.returncode})")
            print("Rescue shell loaded; windows stay open. Meta+Shift+Return opens a local terminal.\n"
                  "Fix the config and run domicile-recover check before the next login.\n"
                  "A later config edit can reload the configured shell.")
        else:
            signal.pidfd_send_signal(pidfd, signal.SIGTERM)
            poll = select.poll()
            poll.register(pidfd, select.POLLIN)
            if not poll.poll(15000):
                raise RuntimeError(f"Launcher {pid} has not exited after SIGTERM. "
                                   "Inspect its journal; no force kill was sent.")
            print("Domicile launcher exited after SIGTERM. Upstream logs this as an interruption.\n"
                  "The physical console returns to Tom's password-free shell.\n"
                  "Run domicile to enter the installed desktop, or domicile-recover rescue for recovery.\n"
                  "Use domicile-recover check first if you changed the config manually.")
    finally:
        client.close()
        os.close(pidfd)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--socket", default=os.environ.get("DOMICILE_SOCK"),
                        help="exact desktop socket; defaults to DOMICILE_SOCK, never guesses")
    parser.add_argument("action", choices=("check", "login-check", "status", "rescue", "exit"))
    args = parser.parse_args()
    try:
        if args.action == "check":
            check()
        elif args.action == "login-check":
            login_check()
        elif args.action == "status":
            status()
        else:
            recover(args.socket, args.action)
        return 0
    except (OSError, RuntimeError, ValueError, subprocess.TimeoutExpired) as error:
        print(f"Domicile recovery: {error}", file=sys.stderr)
        print("From a physical seat, Ctrl+Alt+F2 opens the recovery console.\n"
              "Run domicile-recover status for desktop sockets and log commands.\n"
              "Leaving the desktop returns to the password-free console; run domicile or domicile-recover rescue there.",
              file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
