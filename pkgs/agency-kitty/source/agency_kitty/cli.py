"""Human launcher and capability router. Never handles live terminal bytes."""
from __future__ import annotations

import argparse
import base64
import dataclasses
import json
import os
import posixpath
from pathlib import Path, PurePosixPath
import shlex
import stat
import subprocess
import sys

from .catalogue import chat_id, local_inventory, project_catalogue, session_id
from .sessions import Session, SessionError, SessionStore, validate_cwd
from .transport import SSHTransport, ssh_command_argv


def clean_environment() -> dict[str, str]:
    return {k: v for k, v in os.environ.items()
            if not k.startswith(("HERDR_", "DOMICILE_HERDR_"))
            and k not in ("CLAUDECODE", "CLAUDE_CODE_ENTRYPOINT", "CODEX_THREAD_ID")}


def transport() -> SSHTransport:
    return SSHTransport(kitten=os.environ.get("AGENCY_KITTY_KITTEN", "kitten"),
                        ssh=os.environ.get("AGENCY_KITTY_SSH", "ssh"),
                        remote_program=os.environ.get("AGENCY_KITTY_REMOTE_PROGRAM", "agency-kitty"),
                        interactive_transport=os.environ.get("AGENCY_KITTY_SSH_TRANSPORT", "plain"))


def command_path() -> str:
    return os.environ.get("AGENCY_KITTY_COMMAND", "agency-kitty")


def reconnect_requested(carrier: SSHTransport | None = None) -> bool:
    value = os.environ.get('AGENCY_KITTY_RECONNECT', '0')
    if value not in {'0', '1'}:
        raise SessionError('AGENCY_KITTY_RECONNECT must be 0 or 1')
    if value == '1' and (carrier or transport()).interactive_transport != 'plain':
        raise SessionError('automatic reconnect requires the plain SSH transport')
    return value == '1'


def source_session(value: dict) -> Session:
    allowed = {field.name for field in dataclasses.fields(Session)}
    return Session.from_dict({k: v for k, v in value.items() if k in allowed})


def emit_metadata(session: Session, *, persistent: bool = True) -> None:
    values = {"agency_host": session.host, "agency_session": session.id, "agency_directory": session.cwd,
              "agency_mode": "persistent" if persistent else "direct", "agency_resumable": "1" if persistent else "0"}
    values["agency_chat"] = session.chat_ids[0] if session.chat_ids else ""
    values["agency_chats"] = json.dumps(session.chat_ids, ensure_ascii=False, separators=(",", ":"))
    values["agency_workspace"] = session.workspace_id or ""
    for key in ("agency_harness", "agency_harness_session", "agency_transcript", "agency_attention", "agency_status", "agency_program_status", "agency_editor_request"):
        values[key] = ""
    for key, value in values.items():
        encoded = base64.b64encode(value.encode()).decode()
        os.write(1, f"\x1b]1337;SetUserVar={key}={encoded}\x1b\\".encode())


def attach(session: Session, *, execute: bool = True) -> list[str] | int:
    carrier = transport()
    argv = carrier.attach_argv(session)
    if not execute:
        return argv
    if not sys.stdin.isatty() or not sys.stdout.isatty():
        raise SessionError("attachment requires an interactive Kitty terminal")
    reconnect = reconnect_requested(carrier)
    emit_metadata(session)
    if reconnect:
        from .attachment import supervise
        return supervise(session, argv, carrier, env=clean_environment())
    os.execvpe(argv[0], argv, clean_environment())
    raise AssertionError("exec returned")


def create(args: argparse.Namespace, store: SessionStore) -> Session:
    import uuid
    # The NAS owns creation. A caller already on NAS may share that canonical
    # store, so do not pre-create locally and collide with the remote receipt.
    session = Session(id=str(uuid.uuid4()), cwd=args.directory, title=args.title,
                      chat_ids=args.chat_id, workspace_id=args.workspace_id)
    from .server import bounded_run
    result = bounded_run(transport().create_argv(session), timeout=15)
    if result.returncode:
        raise SessionError("NAS session creation failed: " + result.stderr.decode("utf-8", "replace")[:512])
    remote = source_session(json.loads(result.stdout))
    if (remote.id, remote.cwd, remote.chat_ids, remote.workspace_id, remote.title) != (session.id, session.cwd, session.chat_ids, session.workspace_id, session.title):
        raise SessionError("NAS creation receipt did not match this request")
    try:
        existing = store.get(remote.id)
    except SessionError as error:
        if not str(error).startswith("unknown session:"):
            raise
        store.create(session_id=remote.id, cwd=remote.cwd, title=remote.title,
                     chat_ids=remote.chat_ids, workspace_id=remote.workspace_id,
                     holder_version=remote.holder_version)
    else:
        if (existing.cwd, existing.chat_ids, existing.workspace_id, existing.holder_version) != (remote.cwd, remote.chat_ids, remote.workspace_id, remote.holder_version):
            raise SessionError("local metadata collided with the NAS creation receipt")
    return remote


def refresh(identity: str, store: SessionStore) -> Session:
    value = transport().run_json("describe", session_id(identity))
    if not isinstance(value, dict) or value.get("id") != identity or value.get("live") is not True:
        raise SessionError("saved NAS PTY is unavailable; no replacement was allocated")
    if value.get('mode', 'persistent') != 'persistent' or value.get('resumable') is False:
        raise SessionError('direct NAS terminals end with their SSH connection and cannot be resumed')
    session = source_session(value)
    try:
        current = store.get(identity)
    except SessionError as error:
        if not str(error).startswith("unknown session:"):
            raise
        store.create(session_id=session.id, cwd=session.cwd, title=session.title,
                     chat_ids=session.chat_ids, workspace_id=session.workspace_id,
                     holder_version=session.holder_version)
    else:
        if current.cwd != session.cwd or current.holder_version != session.holder_version:
            raise SessionError("saved NAS directory changed identity")
        if (current.title, current.workspace_id, current.chat_ids, current.status) != (session.title, session.workspace_id, session.chat_ids, session.status):
            store.update(identity, title=session.title, workspace_id=session.workspace_id,
                         chat_ids=session.chat_ids, status=session.status)
    return session


def launch_argv(session: Session) -> list[str]:
    """The first child attaches exactly; later Kitty tabs create new sessions."""
    common = ["--directory", session.cwd]
    if session.workspace_id is not None:
        common += ["--workspace-id", session.workspace_id]
    for identity in session.chat_ids:
        common += ["--chat-id", identity]
    shell = shlex.join([command_path(), "new", *common])
    return [os.environ.get("AGENCY_KITTY_BINARY", "kitty"),
            "--class", "agencykitty-" + session.id.replace("-", ""),
            "--title", session.title or "NAS terminal", "--override", f"shell={shell}",
            "-e", command_path(), "attach", session.id]


def open_window(session: Session) -> dict:
    # The caller may be a desktop helper whose capture pipes must reach EOF
    # as soon as this receipt exits. Keep native Kitty diagnostics separately;
    # the terminal's app PTY is internal to Kitty and never passes this file.
    store = SessionStore()
    store._prepare()
    root_fd = os.open(store.root, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        info = os.fstat(root_fd)
        if info.st_uid != os.getuid() or info.st_mode & 0o077:
            raise SessionError('launch state directory must be private and owned by this user')
        try:
            os.mkdir('launches', mode=0o700, dir_fd=root_fd)
        except FileExistsError:
            pass
        directory_fd = os.open('launches', os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW, dir_fd=root_fd)
    finally:
        os.close(root_fd)
    try:
        info = os.fstat(directory_fd)
        if info.st_uid != os.getuid() or info.st_mode & 0o077:
            raise SessionError('launch diagnostics directory must be private and owned by this user')
        import uuid
        descriptor = os.open(session.id + '-' + uuid.uuid4().hex + '.log',
                             os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW | os.O_CLOEXEC,
                             0o600, dir_fd=directory_fd)
    finally:
        os.close(directory_fd)
    with os.fdopen(descriptor, 'ab', buffering=0) as diagnostics:
        process = subprocess.Popen(launch_argv(session), stdin=subprocess.DEVNULL,
                                   stdout=diagnostics, stderr=subprocess.STDOUT,
                                   env=clean_environment(), start_new_session=True)
    return {"version": 1, "terminalId": session.id, "launcherPid": process.pid,
            "windowClass": "agencykitty-" + session.id.replace("-", ""),
            "status": "launch-requested"}


def desktop(args: argparse.Namespace) -> int:
    """Domicile entry point; new Kitty tabs preserve the chosen host/mode."""
    import uuid
    child = [command_path(), "direct"]
    window_class = 'agencykitty-rescue'
    if args.kind == "rescue":
        if args.chat_id or args.workspace_id:
            raise SessionError('local rescue terminals do not register NAS chat/workspace links')
        child += ["--local"]
        shell = list(child)
    else:
        identity = str(uuid.uuid4())
        window_class = 'agencykitty-' + identity.replace('-', '')
        child += ['--id', identity, '--window-class', window_class]
        # Tabs share this OS-window class, but each starts a fresh SSH identity.
        shell = [command_path(), 'direct', '--window-class', window_class]
    if args.directory:
        child += ["--directory", args.directory]
        shell += ['--directory', args.directory]
    for name, value in [('workspace-id', args.workspace_id), *[('chat-id', value) for value in args.chat_id]]:
        if value is not None:
            child += ['--' + name, value]
            shell += ['--' + name, value]
    command = [os.environ.get("AGENCY_KITTY_BINARY", "kitty"), "--class", window_class,
               "--title", "Local terminal" if args.kind == "rescue" else "NAS terminal",
               "--override", "shell=" + shlex.join(shell), "-e", *child]
    if args.plan:
        print(json.dumps({"argv": command, "renderer": "kitty", "persistent": False})); return 0
    os.execvpe(command[0], command, clean_environment())
    raise AssertionError("exec returned")


def menu(args: argparse.Namespace) -> int:
    from .capabilities.chooser import new_args
    context = new_args(args)
    if args.linked_chat:
        context += ["--linked-chat", args.linked_chat]
    command = [os.environ.get("AGENCY_KITTY_BINARY", "kitty"), "--class", "agencykitty-menu",
               "--title", "NAS sessions", "-e", command_path(), "choose", *context]
    if args.plan:
        print(json.dumps({"argv": command, "allocatesDuringDiscovery": False})); return 0
    os.execvpe(command[0], command, clean_environment())
    raise AssertionError("exec returned")


def editor(args: argparse.Namespace) -> int:
    if not args.kitty_socket or args.window_id <= 0 or args.child_pid <= 0:
        raise SessionError("editor action requires an exact Kitty socket and window id")
    directory = validate_cwd(args.directory)
    files = [posixpath.normpath(posixpath.join(directory, path)) for path in args.files]
    payload = {"window_id": args.window_id, "session": session_id(args.session),
               "directory": directory, "files": files, "child_pid": args.child_pid}
    for path in args.files:
        if not isinstance(path, str) or any(ord(c) < 32 or ord(c) == 127 for c in path):
            raise SessionError("invalid editor path")
    raw = json.dumps(payload, ensure_ascii=False).encode()
    if len(raw) > 49152:
        raise SessionError("editor request exceeds its bound")
    helper = Path(os.environ.get("AGENCY_KITTY_EDITOR_KITTEN", str(Path.home() / ".config/kitty/agency_editor.py")))
    if not helper.is_absolute():
        raise SessionError("editor kitten must be installed at an absolute path")
    action = "open-editor" if args.action == "edit" else "sidebar"
    argv = [transport().kitten, "@", "--to", args.kitty_socket, "kitten", "--match", f"id:{args.window_id}",
            str(helper), action, base64.b64encode(raw).decode()]
    result = subprocess.run(argv, stdin=subprocess.DEVNULL, timeout=15, env=clean_environment())
    return result.returncode


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(prog="agency-kitty", description=__doc__)
    commands = result.add_subparsers(dest="action", required=True)
    for action in ("open", "new"):
        cmd = commands.add_parser(action, help="create a durable NAS terminal in a new window" if action == "open" else "create and attach in this Kitty window")
        cmd.add_argument("--directory", "--cwd", type=validate_cwd, default="/home/tom")
        cmd.add_argument("--title", default="NAS terminal")
        cmd.add_argument("--chat-id", type=chat_id, action="append", default=[])
        cmd.add_argument("--workspace-id")
        cmd.add_argument("--plan", action="store_true")
    for action in ("attach", "resume", "describe", "close", "capture", "link"):
        cmd = commands.add_parser(action)
        cmd.add_argument("id", type=session_id)
        if action == "resume":
            cmd.add_argument("--plan", action="store_true")
        if action == "capture":
            cmd.add_argument("--rows", type=int, default=512)
        if action == "link":
            cmd.add_argument("--chat-id", type=chat_id, action="append", default=[])
            cmd.add_argument("--workspace-id")
            cmd.add_argument("--title")
    direct = commands.add_parser("direct", help="the direct native SSH reference route")
    direct.add_argument("--directory", "--cwd", type=validate_cwd)
    direct.add_argument("--local", action="store_true")
    direct.add_argument("--plan", action="store_true")
    direct.add_argument('--id', type=session_id)
    direct.add_argument('--window-class')
    direct.add_argument('--workspace-id')
    direct.add_argument('--chat-id', type=chat_id, action='append', default=[])
    launcher = commands.add_parser("desktop", help="open a native Domicile terminal or local rescue window")
    launcher.add_argument("kind", choices=("terminal", "rescue"), nargs="?", default="terminal")
    launcher.add_argument("--directory", "--cwd", type=validate_cwd)
    launcher.add_argument("--plan", action="store_true")
    launcher.add_argument('--workspace-id')
    launcher.add_argument('--chat-id', type=chat_id, action='append', default=[])
    chooser = commands.add_parser("menu", help="open the explicit native saved-session chooser")
    chooser.add_argument("--directory", "--cwd", type=validate_cwd, default="/home/tom")
    chooser.add_argument("--workspace-id")
    chooser.add_argument("--chat-id", type=chat_id, action="append", default=[])
    chooser.add_argument("--linked-chat", type=chat_id)
    chooser.add_argument("--plan", action="store_true")
    for action in ("editor-attach", "editor-tree-attach", "editor-local-attach"):
        cmd = commands.add_parser(action)
        cmd.add_argument("--directory", type=validate_cwd, required=True)
        cmd.add_argument("files", nargs="*")
        if action == 'editor-local-attach':
            cmd.add_argument('--session', type=session_id)
            cmd.add_argument('--request', type=session_id)
    vi = commands.add_parser('vi', help='local native UI for NAS files, with blocking managed NAS callback')
    vi.add_argument('--directory', type=validate_cwd, default=os.getcwd())
    vi.add_argument('files', nargs='*')
    lease = commands.add_parser('editor-lease', help=argparse.SUPPRESS)
    lease.add_argument('--session', type=session_id, required=True)
    lease.add_argument('--request', type=session_id, required=True)
    for action in ("list", "catalogue"):
        cmd = commands.add_parser(action)
        cmd.add_argument("--local", action="store_true", help="read metadata here on NAS, without an SSH hop")
        cmd.add_argument("--json", action="store_true")
        cmd.add_argument("--chat-id", type=chat_id)
        cmd.add_argument("--session-id", type=session_id)
    for action in ("edit", "editor-tree"):
        cmd = commands.add_parser(action)
        cmd.add_argument("--kitty-socket", default=os.environ.get("KITTY_LISTEN_ON"))
        cmd.add_argument("--window-id", type=int, required=True)
        cmd.add_argument("--child-pid", type=int, required=True)
        cmd.add_argument("--session", type=session_id, required=True)
        cmd.add_argument("--directory", type=validate_cwd, required=True)
        cmd.add_argument("files", nargs="*")
    return result


def main(argv: list[str] | None = None) -> int:
    words = list(sys.argv[1:] if argv is None else argv)
    if words and words[0] == "remote":
        from .server import main as remote_main
        return remote_main(words[1:])
    if words and words[0] == "capability":
        from .capabilities.cli import main as capability_main
        return capability_main(words[1:])
    if words and words[0] == "choose":
        from .capabilities.chooser import main as choose_main
        return choose_main(words[1:])
    if words and words[0] == 'harness':
        from .harness_launch import main as harness_main
        return harness_main(words[1:])
    if words == ['desktop-resume-request'] or words == ['desktop-catalogue']:
        from .desktop_catalogue import main as desktop_main
        return desktop_main(['resume' if words[0] == 'desktop-resume-request' else 'frame'])
    args = parser().parse_args(words)
    try:
        # Validate the typed policy before a launcher can allocate NAS state.
        if "AGENCY_KITTY_SSH_TRANSPORT" in os.environ:
            transport()
        if 'AGENCY_KITTY_RECONNECT' in os.environ:
            reconnect_requested()
        if args.action == "desktop":
            return desktop(args)
        if args.action == "menu":
            return menu(args)
        if args.action == "editor-local-attach":
            from .editor_ui import run_local_ui
            return run_local_ui(args.directory, args.files, transport=transport(), session=args.session, request=args.request)
        if args.action == 'editor-lease':
            from .editor_requests import lease
            return lease(args.session, args.request)
        if args.action == 'vi':
            if os.environ.get('AGENCY_KITTY_HOST') == 'nas' or os.environ.get('DSH_EDITOR_ROLE') == 'brain':
                from .editor_requests import request
                return request(args.directory, args.files)
            from .editor_ui import run_local_ui
            return run_local_ui(args.directory, args.files, transport=transport())
        store = SessionStore()
        if args.action in ("edit", "editor-tree"):
            return editor(args)
        if args.action in ("editor-attach", "editor-tree-attach"):
            program = "dsh-editor" if args.action == "editor-attach" else "dsh-editor-tree"
            remote = [program, "--directory", args.directory]
            if args.action == "editor-attach":
                remote += ["--", *args.files]
            elif args.files:
                raise SessionError("the file-tree action accepts a directory only")
            command = transport().interactive_argv(remote)
            os.execvpe(command[0], command, clean_environment())
            raise AssertionError("exec returned")
        if args.action == "direct":
            import uuid
            context = Session(id=args.id or str(uuid.uuid4()), cwd=args.directory or "/home/tom",
                              title='NAS terminal', workspace_id=args.workspace_id, chat_ids=args.chat_id)
            if args.local:
                if args.chat_id or args.workspace_id or args.window_class or args.id:
                    raise SessionError('local fish does not register a NAS terminal identity')
                if args.directory:
                    os.chdir(args.directory)
                command = ["fish", "--login", "--interactive"]
            else:
                remote = [transport().remote_program, "remote", "direct", "--id", context.id,
                          "--cwd", context.cwd]
                if args.window_class is not None:
                    from .direct_registry import _frontend
                    _frontend(args.window_class, None)
                    remote += ['--window-class', args.window_class]
                window_id = os.environ.get('KITTY_WINDOW_ID')
                if window_id is not None:
                    if not window_id.isascii() or not window_id.isdecimal() or not 0 < int(window_id) < 2**31:
                        raise SessionError('Kitty window id must be a bounded positive integer')
                    remote += ['--kitty-window-id', window_id]
                if context.workspace_id is not None:
                    remote += ['--workspace-id', context.workspace_id]
                for identity in context.chat_ids:
                    remote += ['--chat-id', identity]
                command = transport().interactive_argv(remote)
            if args.plan:
                print(json.dumps({"argv": command, "renderer": "kitty", "persistent": False})); return 0
            if not sys.stdin.isatty() or not sys.stdout.isatty():
                raise SessionError("direct attachment requires an interactive terminal")
            if not args.local:
                emit_metadata(context, persistent=False)
            os.execvpe(command[0], command, clean_environment())
        if args.action in ("open", "new"):
            if args.plan:
                import uuid
                session = Session(id=str(uuid.uuid4()), cwd=args.directory, title=args.title,
                                  chat_ids=args.chat_id, workspace_id=args.workspace_id)
                print(json.dumps({"session": session.to_dict(), "create": transport().create_argv(session),
                                  "launch": launch_argv(session), "attach": attach(session, execute=False)})); return 0
            session = create(args, store)
            if args.action == "new":
                return attach(session)
            else:
                print(json.dumps(open_window(session)))
            return 0
        if args.action == "attach":
            return attach(store.get(args.id))
        if args.action == "resume":
            session = refresh(args.id, store)
            print(json.dumps({"launch": launch_argv(session)} if args.plan else open_window(session))); return 0
        if args.action in ("list", "catalogue"):
            values = local_inventory(store) if args.local else transport().run_json("list")
            if not isinstance(values, list):
                raise SessionError("invalid NAS session catalogue")
            if args.session_id:
                values = [value for value in values if (value.id if isinstance(value, Session) else value.get("id")) == args.session_id]
                if not values:
                    raise SessionError("requested terminal is unavailable")
            output = project_catalogue(values, linked_chat=args.chat_id) if args.action == "catalogue" else [
                value.to_dict() if isinstance(value, Session) else value for value in values]
        elif args.action == "link":
            options = [word for identity in args.chat_id for word in ("--chat-id", identity)]
            if args.workspace_id is not None:
                options += ["--workspace-id", args.workspace_id]
            if args.title is not None:
                options += ["--title", args.title]
            output = transport().run_json("link", args.id, *options)
        elif args.action == "capture":
            output = transport().run_json("capture", args.id, "--rows", str(args.rows))
        else:
            output = transport().run_json(args.action, args.id)
        print(json.dumps(output, ensure_ascii=False, indent=2))
        return 0
    except KeyboardInterrupt:
        return 130
    except (OSError, ValueError, subprocess.SubprocessError) as error:
        print(f"agency-kitty: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
