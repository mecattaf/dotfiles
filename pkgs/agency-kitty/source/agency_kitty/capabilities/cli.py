"""Called by `agency-kitty capability ...`; all terminal writes name a target."""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

from . import harness, harness_state, images, notifications, targets, transcripts
from ..transport import NAS_HOST, ssh_command_argv


def _target(parser: argparse.ArgumentParser) -> None:
    parser.add_argument("--window-id", type=int, required=True)
    parser.add_argument("--child-pid", type=int, required=True)
    parser.add_argument("--host", required=True)
    parser.add_argument("--session", required=True)
    parser.add_argument("--kitty-socket", required=True)
    parser.add_argument("--kitten-path", required=True)
    parser.add_argument("--harness-session", default="")


def _snapshot(args) -> targets.Target:
    if args.window_id <= 0 or args.child_pid <= 0 or not args.host or not args.session:
        raise ValueError("the target must name a window, child, remote host and session")
    target = targets.Target(args.window_id, args.child_pid, args.host, args.session, args.harness_session)
    target.validate()
    return target


def _deliver(args, kind: str, value: str) -> None:
    if kind=='paste' and args.harness_session:
        # Explicit gesture work only, after staging and before the nonblocking
        # GUI callback. This is not an atomic cross-host input transaction.
        command = ssh_command_argv([getattr(args,'remote_program','agency-kitty'),'capability','validate-harness',
                                   '--session-id',args.session,'--harness-session',args.harness_session])
        result = json.loads(images.command_bytes(command,4096,timeout=6))
        if result != {'version':1,'valid':True}:
            raise RuntimeError('harness is no longer verified foreground; zero input sent')
    targets.deliver(args.kitty_socket, args.kitten_path, _snapshot(args), kind, value)


def _private_snapshot(data: str) -> str:
    root = Path(os.environ.get("XDG_CACHE_HOME", str(Path.home() / ".cache"))) / "agency-kitty" / "history"
    root.mkdir(mode=0o700, parents=True, exist_ok=True)
    if root.is_symlink() or root.stat().st_uid != os.getuid():
        raise ValueError("history cache is not a private user directory")
    root.chmod(0o700)
    fd, name = tempfile.mkstemp(prefix="history-", suffix=".md", dir=root)
    with os.fdopen(fd, "w") as stream:
        stream.write(data)
    return name


def parser() -> argparse.ArgumentParser:
    cli = argparse.ArgumentParser(prog="agency-kitty capability")
    commands = cli.add_subparsers(dest="command", required=True)
    for verb in ("image", "files"):
        command = commands.add_parser(verb, help="stage clipboard/image files on the named remote host and paste their paths")
        _target(command)
        command.add_argument("--file", action="append", default=[])
        command.add_argument("--remote-program", default="agency-kitty")
    store = commands.add_parser("image-store", help="NAS helper: read validated image bytes from stdin, return one private path")
    store.add_argument("extension", choices=tuple(images.MIME_EXTENSIONS.values()))
    prune = commands.add_parser("prune-images", help="explicitly remove this helper's image files older than a chosen age")
    prune.add_argument("--older-than-hours", type=float, default=24)
    transcript = commands.add_parser("transcript", help="export an explicit Claude/Codex JSONL file, beyond the terminal viewport")
    transcript.add_argument("--path", required=True)
    transcript.add_argument("--harness", required=True, choices=("claude", "codex"))
    transcript.add_argument("--include-tools", action="store_true")
    transcript.add_argument("--stdout", action="store_true")
    fetch = commands.add_parser("fetch-transcript", help="fetch the exact remote harness transcript into a read-only local nvim view")
    _target(fetch)
    fetch.add_argument("--path", required=True)
    fetch.add_argument("--harness", required=True, choices=("claude", "codex"))
    fetch.add_argument("--remote-program", default="agency-kitty")
    voice = commands.add_parser("voice-text", help="paste stdin literally into the captured destination; never submit")
    _target(voice)
    notify = commands.add_parser("notify", help="write a native OSC 99 notification to stdout")
    notify.add_argument("title")
    notify.add_argument("--body", default="")
    notify.add_argument("--id", default="agency")
    notify.add_argument("--timeout-ms", type=int, default=5000)
    sound = commands.add_parser("sound", help="play an existing private/themed asset on this seat")
    sound.add_argument("event", choices=tuple(notifications.SOUND_FILES))
    terminal = commands.add_parser("terminal-context", help="capture the exact managed remote shell PTY once")
    terminal.add_argument("--owner-pid", type=int, required=True)
    validity = commands.add_parser('validate-harness',help='bounded metadata check for an explicit pending paste')
    validity.add_argument('--session-id',required=True)
    validity.add_argument('--harness-session',required=True)
    for verb in ("bind-harness", "harness-event"):
        bind = commands.add_parser(verb, help="harness hook: exact transcript binding or turn completion/attention metadata")
        bind.add_argument("--harness", choices=("claude", "codex"), required=True)
        bind.add_argument("--stdout", action="store_true", help="emit escapes to stdout for explicit use/testing; hook default writes /dev/tty")
    return cli


def main(argv: list[str] | None = None) -> int:
    args = parser().parse_args(argv)
    callback = args.command in {"image", "files", "fetch-transcript", "voice-text"}
    try:
        if callback:
            _snapshot(args)
        if args.command == "image-store":
            print(images.store_image(images.read_bounded(sys.stdin.buffer), args.extension))
        elif args.command == "prune-images":
            print(images.prune_images(older_than=args.older_than_hours * 3600))
        elif args.command in {"image", "files"}:
            if args.command == "files" and not args.file:
                raise ValueError("files requires at least one --file image path")
            if len(args.file) > 16:
                raise ValueError("image batches may contain at most 16 files")
            if args.file:
                # One bounded image is resident at a time. Finish staging the
                # whole explicit batch before sending any input to the TUI.
                payloads = (images.file_image(path) for path in args.file)
            else:
                image = images.clipboard_image()
                if image is None:
                    _deliver(args, "paste-clipboard", "")
                    return 0
                payloads = [image]
            staged = [images.stage_remote(args.host, image, args.remote_program) for image in payloads]
            # Codex classifies each bracketed-paste event as one image path;
            # joining several paths would silently become ordinary text.
            for index, path in enumerate(staged):
                _deliver(args, "paste", images.paste_path(path) + (" " if index + 1 < len(staged) else ""))
        elif args.command == "transcript":
            text, _ = transcripts.markdown(args.path, args.harness, args.include_tools)
            if args.stdout:
                sys.stdout.write(text)
            else:
                print(_private_snapshot(text))
        elif args.command == "fetch-transcript":
            if args.host != NAS_HOST:
                raise ValueError("transcript sidechannel only supports the pinned NAS identity")
            remote = ssh_command_argv([args.remote_program, "capability", "transcript", "--path", args.path, "--harness", args.harness, "--stdout"])
            data = images.command_bytes(remote, 128 * 1024 * 1024, timeout=30)
            local = _private_snapshot(data.decode("utf-8"))
            _deliver(args, "open-transcript", local)
        elif args.command == "voice-text":
            text = images.read_bounded(sys.stdin.buffer, 256 * 1024).decode("utf-8", "strict")
            _deliver(args, "paste", text)
        elif args.command == "notify":
            sys.stdout.buffer.write(notifications.osc99(args.title, args.body, args.id, args.timeout_ms))
        elif args.command == "sound":
            notifications.play_sound(args.event)
        elif args.command == "terminal-context":
            print(json.dumps(harness.capture_terminal_context(args.owner_pid)))
        elif args.command == 'validate-harness':
            if not args.harness_session or len(args.harness_session)>256 or any(ord(c)<32 for c in args.harness_session):
                raise ValueError('invalid exact harness session identity')
            print(json.dumps({'version':1,'valid':harness_state.can_target(args.session_id,args.harness_session)}))
        elif args.command in {"bind-harness", "harness-event"}:
            # No transcript content is read, and no hook output enters model context.
            managed = os.environ.get("AGENCY_KITTY_SESSION", "")
            if not managed:
                return 0
            payload = json.loads(images.read_bounded(sys.stdin.buffer, 2 * 1024 * 1024))
            emit = harness.binding if args.command == "bind-harness" else harness.attention
            wire = emit(payload, args.harness, managed, os.environ.get("CODEX_THREAD_ID", ""))
            if wire:
                harness_state.record_event(payload, args.harness, managed,
                                           inherited_id=os.environ.get("CODEX_THREAD_ID", ""))
            if args.stdout:
                sys.stdout.buffer.write(wire)
            elif wire:
                harness.write_terminal(wire, os.environ.get("AGENCY_KITTY_TERMINAL", ""))
        return 0
    except (ValueError, OSError, RuntimeError, TimeoutError, subprocess.TimeoutExpired) as exc:
        message = str(exc)
        if callback:
            try:
                _deliver(args, "error", message)
            except Exception:
                pass  # original failure remains visible on stderr, never retry paste
        print(f"agency-kitty capability: {message}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
