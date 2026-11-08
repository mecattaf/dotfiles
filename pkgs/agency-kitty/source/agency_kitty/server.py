"""NAS endpoint for explicitly identified persistent PTYs and bounded capture.

There is no network daemon here. OpenSSH authenticates each invocation. Attach
replaces this Python process with zmx, leaving the ordinary byte path native.
"""

from __future__ import annotations

import argparse
import base64
import json
import os
from pathlib import Path
import selectors
import shutil
import stat
import subprocess
import sys
import time

from .sessions import Session, SessionError, SessionStore, validate_cwd, validate_id
from .direct_registry import DirectRegistry

ZMX_VERSION = "1.0.1-agency.3"
HOLDER_NAMESPACES = {
    "1.0.1-agency.3": "zmx-3",
    "1.0.1-agency.4": "zmx-4",
    "1.0.1-agency.4-vt1": "zmx-4-vt1",
}
MAX_RESPONSE_BYTES = 1024 * 1024


def fish_integration_env(env: dict) -> dict:
    """Restore stock integration for the fish we launch behind a remote command.

    Use the package-declared NAS integration when available, otherwise the
    SSH kitten's installation. The holder knows it launches fish and rearms
    its vendor integration without sourcing a shell fragment here.
    """
    result = dict(env)
    configured = result.get("AGENCY_KITTY_FISH_INTEGRATION_DIR")
    kitty_bin = result.get("SSH_KITTEN_KITTY_DIR")
    if not configured and not kitty_bin:
        return result
    directory = Path(configured or kitty_bin)
    if not directory.is_absolute():
        raise SessionError("Kitty integration directory must be absolute")
    integration = directory if configured else directory.parent.parent / "shell-integration"
    script = integration / "fish/vendor_conf.d/kitty-shell-integration.fish"
    try:
        info = script.lstat()
    except FileNotFoundError as exc:
        raise SessionError("declared Kitty fish integration is unavailable") from exc
    if not stat.S_ISREG(info.st_mode) or info.st_uid not in {0, os.getuid()} or info.st_mode & 0o022:
        raise SessionError("Kitty fish integration must be an owned, non-writable regular file")
    previous = result.get("XDG_DATA_DIRS", "")
    paths = [str(integration)] + [path for path in previous.split(os.pathsep) if path and path != str(integration)]
    result["XDG_DATA_DIRS"] = os.pathsep.join(paths)
    result["KITTY_FISH_XDG_DATA_DIR"] = str(integration)
    result["KITTY_SHELL_INTEGRATION"] = result.get("AGENCY_KITTY_SHELL_INTEGRATION", "enabled")
    return result


def bounded_run(argv: list[str], *, env: dict | None = None, timeout: float = 5,
                max_bytes: int = MAX_RESPONSE_BYTES) -> subprocess.CompletedProcess:
    """Read a subprocess under output and time bounds, killing it on failure."""
    process = subprocess.Popen(argv, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                               stderr=subprocess.PIPE, env=env)
    selector = selectors.DefaultSelector()
    result = {"stdout": bytearray(), "stderr": bytearray()}
    assert process.stdout is not None and process.stderr is not None
    for name, stream in (("stdout", process.stdout), ("stderr", process.stderr)):
        os.set_blocking(stream.fileno(), False)
        selector.register(stream, selectors.EVENT_READ, name)
    deadline = time.monotonic() + timeout
    total = 0
    try:
        while selector.get_map():
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise SessionError("holder command timed out")
            for key, _ in selector.select(min(remaining, 0.1)):
                chunk = os.read(key.fileobj.fileno(), 65536)
                if not chunk:
                    selector.unregister(key.fileobj)
                    continue
                total += len(chunk)
                if total > max_bytes:
                    raise SessionError("holder response exceeds output limit")
                result[key.data].extend(chunk)
        return subprocess.CompletedProcess(argv, process.wait(timeout=max(0.01, deadline - time.monotonic())),
                                           bytes(result["stdout"]), bytes(result["stderr"]))
    finally:
        selector.close()
        if process.poll() is None:
            process.kill()
            process.wait()
        process.stdout.close()
        process.stderr.close()


class HolderBackend:
    """Pinned zmx adapter; never shares sockets with a general zmx installation."""

    def __init__(self, *, binary: str | None = None, env: dict | None = None, version: str | None = None):
        self.binary = binary or os.environ.get("AGENCY_KITTY_ZMX_BINARY", "zmx")
        self.env = dict(os.environ if env is None else env)
        self.version = version or self.env.get("AGENCY_KITTY_HOLDER_VERSION", ZMX_VERSION)
        if self.version not in HOLDER_NAMESPACES:
            raise SessionError("unsupported holder version selection")
        runtime = Path(self.env.get("XDG_RUNTIME_DIR", f"/run/user/{os.getuid()}"))
        directory = runtime / "agency-kitty" / HOLDER_NAMESPACES[self.version]
        # UUIDs plus this prefix must fit sockaddr_un on Linux (107 bytes).
        if len(os.fsencode(directory)) + 1 + 36 > 107:
            raise SessionError("private holder socket path is too long")
        self.env.update(ZMX_DIR=str(directory), ZMX_DIR_MODE="700", ZMX_LOG_MODE="600",
                        ZMX_NO_DETACH_KEY="1", ZMX_SESSION_PREFIX="", ZMX_SESSION="")
        self.socket_dir = directory

    def _run(self, *args: str, max_bytes: int = MAX_RESPONSE_BYTES) -> subprocess.CompletedProcess:
        try:
            return bounded_run([self.binary, *args], env=self.env, max_bytes=max_bytes)
        except FileNotFoundError as exc:
            raise SessionError(f"zmx {self.version} is required for persistent attachment") from exc

    def check_version(self) -> None:
        result = self._run("version", max_bytes=16384)
        first = result.stdout.decode("utf-8", "replace").splitlines()[:1]
        if result.returncode or not first or first[0].split() != ["zmx", self.version]:
            raise SessionError(f"holder must be exactly zmx {self.version}; stock zmx does not enforce attachment and queue guarantees")

    def names(self) -> set[str]:
        result = self._run("list", "--short", max_bytes=65536)
        if result.returncode:
            # Upstream list returns success even when no sessions exist.
            raise SessionError("holder inventory failed: " + result.stderr.decode("utf-8", "replace")[:512])
        return set(result.stdout.decode("utf-8", "strict").splitlines())

    def describe(self, session: Session) -> dict:
        self.require_session_version(session)
        value = session.to_dict()
        value.update(provider="agency-kitty", transport="zmx", holder_version=self.version,
                     live=session.id in self.names(), cached_status=session.status,
                     mode="persistent", resumable=True)
        return value

    def rebind(self, session: Session) -> dict:
        """Off-path typed state for a fresh native client of an existing PTY."""
        self.check_version()
        value = self.describe(session)
        if value.get('live') is not True or session.status == 'closed':
            raise SessionError('saved PTY is unavailable; no replacement was allocated')
        from .capabilities.harness_state import read_rebind
        from .editor_requests import read_rebind as editor_rebind
        wire = read_rebind(session.id) + editor_rebind(session.id)
        if len(wire) > 49152:
            raise SessionError('typed attachment metadata exceeds its bound')
        reply = {'version': 1, 'session': value, 'socket': str(self.socket_dir / session.id),
                 'rebind': base64.b64encode(wire).decode('ascii'), 'requiresSshPty': False}
        if len(json.dumps(reply, ensure_ascii=False).encode()) > 131072:
            raise SessionError('typed attachment response exceeds its bound')
        return reply

    def require_session_version(self, session: Session) -> None:
        if session.holder_version != self.version:
            raise SessionError(f"session needs holder {session.holder_version}; its matching package must be retained")

    def prepare_attach(self, session: Session, store: SessionStore) -> tuple[list[str], dict]:
        self.check_version()
        self.require_session_version(session)
        if session.status == "closed":
            raise SessionError("session was closed; its identity cannot be reused")
        live = session.id in self.names()
        if not live and session.status != "created":
            raise SessionError("saved PTY is unavailable; no replacement was allocated")
        argv = [self.binary, "attach", session.id]
        if not live:
            if not Path(session.cwd).is_dir():
                raise SessionError("saved NAS directory is unavailable")
            fish = shutil.which("fish", path=self.env.get("PATH"))
            if fish is None:
                raise SessionError("fish is required for the NAS terminal")
            argv += [sys.executable, str(Path(__file__).with_name("shell.py"))]
        env = fish_integration_env(self.env)
        env["ZMX_ATTACH_ONLY"] = "1" if live else "0"
        env["AGENCY_KITTY_SESSION"] = session.id
        env["AGENCY_KITTY_HOST"] = "nas"
        # Resolve before changing durable status, so an absent binary cannot
        # leave a never-launched session looking active.
        resolved = shutil.which(self.binary, path=env.get("PATH"))
        if resolved is None:
            raise SessionError("holder executable disappeared before attachment")
        argv[0] = resolved
        return argv, env

    def capture(self, session: Session, rows: int = 512) -> dict:
        self.require_session_version(session)
        if not 0 <= rows <= 5000:
            raise SessionError("capture rows must be between 0 and 5000")
        if session.id not in self.names():
            raise SessionError("saved PTY is unavailable")
        result = self._run("history", "--scrollback", str(rows), session.id)
        if result.returncode:
            raise SessionError("terminal capture failed")
        return {"session_id": session.id, "format": "text/plain", "rows": rows,
                "text": result.stdout.decode("utf-8", "replace"), "source": "terminal-state",
                "complete_transcript": False}

    def close(self, session: Session, store: SessionStore) -> dict:
        self.require_session_version(session)
        self.check_version()
        if session.id in self.names():
            result = self._run("kill", session.id)
            if result.returncode:
                raise SessionError("holder refused to close the exact session")
        store.mark_closed(session.id)
        return {"session_id": session.id, "closed": True}


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="agency-kitty remote")
    subparsers = parser.add_subparsers(dest="action", required=True)
    direct = subparsers.add_parser("direct")
    direct.add_argument("--id", required=True, type=validate_id)
    direct.add_argument("--cwd", required=True, type=validate_cwd)
    direct.add_argument("--title", default="NAS terminal")
    direct.add_argument("--workspace-id")
    direct.add_argument("--chat-id", action="append", default=[])
    direct.add_argument("--window-class")
    direct.add_argument("--kitty-window-id", type=int)
    for action in ("create", "attach", "list", "describe", "rebind", "link", "close", "capture", "health", "archive-direct"):
        command = subparsers.add_parser(action)
        if action not in {"list", "health"}:
            command.add_argument("--id", required=True, type=validate_id)
        if action == "create":
            command.add_argument("--cwd", required=True, type=validate_cwd)
            command.add_argument("--title", default="")
            command.add_argument("--workspace-id")
            command.add_argument("--chat-id", action="append", default=[])
        if action == "attach":
            # Atomic create+attach exists for the Python API. Normal CLI uses
            # a separate explicit create receipt, then attach of that exact id.
            command.add_argument("--create", action="store_true")
            command.add_argument("--cwd", type=validate_cwd)
            command.add_argument("--metadata", default="{}")
        if action == "link":
            command.add_argument("--workspace-id")
            command.add_argument("--chat-id", action="append", default=[])
            command.add_argument("--title")
        if action == "capture":
            command.add_argument("--rows", type=int, default=512)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    try:
        if args.action == "direct":
            if not sys.stdin.isatty() or not sys.stdout.isatty():
                raise SessionError("direct attachment requires an interactive PTY")
            if not Path(args.cwd).is_dir():
                raise SessionError("NAS directory is unavailable")
            env = fish_integration_env(dict(os.environ))
            env.update(AGENCY_KITTY_SESSION=args.id, AGENCY_KITTY_HOST="nas",
                       AGENCY_KITTY_PERSISTENT="0")
            from .capabilities.harness import capture_terminal_context
            env.update(capture_terminal_context())
            os.chdir(args.cwd)
            DirectRegistry().register(Session(id=args.id, cwd=os.getcwd(), title=args.title,
                chat_ids=args.chat_id, workspace_id=args.workspace_id), env['AGENCY_KITTY_TERMINAL'],
                window_class=args.window_class, kitty_window_id=args.kitty_window_id)
            os.execvpe("fish", ["fish", "--login", "--interactive"], env)
            raise AssertionError("exec returned")
        store = SessionStore()
        registry = DirectRegistry(store)
        if args.action == 'archive-direct':
            print(json.dumps(registry.archive_ended(args.id), ensure_ascii=False))
            return 0
        if args.action == 'list':
            # Ordinary direct sessions need neither a holder binary nor a
            # holder control call merely to expose their own live metadata.
            persistent = store.list()
            value = registry.list()
            if persistent:
                backend = HolderBackend()
                backend.check_version()
                live = backend.names()
                value = [{**s.to_dict(), 'mode': 'persistent', 'resumable': True,
                          'live': s.id in live if s.holder_version == backend.version else None}
                         for s in persistent] + value
            from .catalogue import bound_inventory
            bound_inventory(value)
            print(json.dumps(value, ensure_ascii=False))
            return 0
        if args.action not in {'create', 'health'}:
            direct = registry.get(args.id)
            if direct is not None:
                if args.action == 'describe':
                    value = direct
                elif args.action == 'link':
                    value = registry.add_links(args.id, chat_ids=args.chat_id,
                                               workspace_id=args.workspace_id, title=args.title)
                else:
                    raise SessionError('direct terminals cannot be resumed, captured or closed through the holder API')
                print(json.dumps(value, ensure_ascii=False))
                return 0
        backend = HolderBackend()
        if args.action == "create":
            if not Path(args.cwd).is_dir():
                raise SessionError("NAS directory is unavailable")
            value = store.create(session_id=args.id, cwd=args.cwd, title=args.title,
                                 workspace_id=args.workspace_id, chat_ids=args.chat_id,
                                 holder_version=backend.version).to_dict()
        elif args.action == "health":
            backend.check_version()
            value = {"host": "nas", "holder": "zmx", "version": backend.version,
                     "socket_dir": str(backend.socket_dir), "persistent_default": False}
        else:
            if args.action == "attach" and args.create:
                if not args.cwd or len(args.metadata) > 16384:
                    raise SessionError("explicit creation requires bounded metadata and cwd")
                metadata = json.loads(args.metadata)
                if not isinstance(metadata, dict) or metadata.keys() - {"title", "workspace_id", "chat_ids"}:
                    raise SessionError("invalid creation metadata")
                store.create(session_id=args.id, cwd=args.cwd, holder_version=backend.version, **metadata)
            session = store.get(args.id)
            if args.action == "attach":
                if not sys.stdin.isatty() or not sys.stdout.isatty():
                    raise SessionError("persistent attachment requires an interactive PTY")
                command, env = backend.prepare_attach(session, store)
                from .capabilities.harness_state import read_rebind
                rebind = read_rebind(session.id)
                from .editor_requests import read_rebind as editor_rebind
                rebind += editor_rebind(session.id)
                if env["ZMX_ATTACH_ONLY"] != "1":
                    os.chdir(session.cwd)
                store.update(session.id, status="active")
                try:
                    if rebind:
                        os.write(1, rebind)
                    os.execvpe(command[0], command, env)
                except OSError:
                    if store.get(session.id).status == "active":
                        store.update(session.id, status=session.status)
                    raise
                raise AssertionError("exec returned")
            if args.action == "describe":
                backend.check_version()
                value = backend.describe(session)
            elif args.action == 'rebind':
                value = backend.rebind(session)
            elif args.action == "close":
                value = backend.close(session, store)
            elif args.action == "capture":
                backend.check_version()
                value = backend.capture(session, args.rows)
            elif args.action == "link":
                value = store.add_links(session.id, chat_ids=args.chat_id,
                                        workspace_id=args.workspace_id, title=args.title).to_dict()
        print(json.dumps(value, ensure_ascii=False))
        return 0
    except (SessionError, OSError, UnicodeError, json.JSONDecodeError) as exc:
        print(f"agency-kitty: {exc}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
