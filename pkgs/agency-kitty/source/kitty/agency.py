"""Small native Kitty gestures. Loaded with exec(), which supplies no __file__.

No ordinary key or terminal output passes through this module. Async clipboard,
SSH and transcript work runs in a background CLI, never a hidden overlay (Kitty
buffers keys to hidden overlays until they signal ready).
"""
from __future__ import annotations

import base64
import json
import re
import os
from pathlib import Path
import sys
import uuid
from urllib.parse import unquote, urlsplit


def main(args):
    return None


def _path() -> str:
    here = globals().get("__file__")
    if here:
        return os.path.realpath(here)
    # Kitty runner prepends the custom kitten's directory before exec().
    return os.path.realpath(os.path.join(sys.path[0], "agency.py"))


_KITTEN_PATH = _path()


def _program() -> str:
    configured = os.environ.get("AGENCY_KITTY_BIN") or os.environ.get("AGENCY_KITTY_COMMAND")
    if configured:
        return configured
    # A GUI launched before a profile update may retain its old PATH. Nix
    # installs this asset under share/agency-kitty, beside that package's bin.
    path = Path(_KITTEN_PATH)
    candidates = [path.parents[index] / "bin" / "agency-kitty" for index in (3, 2) if len(path.parents) > index]
    candidates.append(Path.home() / ".local" / "bin" / "agency-kitty")
    for candidate in candidates:
        if os.access(candidate, os.X_OK):
            return str(candidate)
    return "agency-kitty"


def _notify(boss, window, title: str, body: str = "", timeout: int = 1600) -> None:
    manager = boss.notification_manager
    command = manager.create_notification_cmd()
    command.title = title
    command.body = body
    command.application_name = "Agency Kitty"
    command.timeout = timeout
    command.identifier = f"agency-{window.id}"
    command.actions = frozenset()  # copying must never focus/switch a window
    command.sound_name = "silent"
    manager.notify_with_command(command, window.id)


def _target(window) -> dict:
    return {"window_id": window.id, "child_pid": getattr(window.child, "root_pid", window.child.pid),
            "host": window.user_vars.get("agency_host", ""),
            "session": window.user_vars.get("agency_session", ""),
            "harness_session": window.user_vars.get("agency_harness_session", ""),
            "harness_invocation": window.user_vars.get("agency_harness_invocation", "")}


def _matches(window, target: dict) -> bool:
    return (_valid_target(target) and window is not None and not getattr(window, "destroyed", False)
            and _target(window) == target)


def _valid_target(target):
    if target.get("host") != "nas":
        return False
    try:
        parsed = uuid.UUID(target.get("session", ""))
        return str(parsed) == target["session"] and parsed.version == 4
    except (ValueError, AttributeError, TypeError):
        return False


def _background(boss, window, action: str, extra: list[str]) -> None:
    target = _target(window)
    if not _valid_target(target):
        _notify(boss, window, "No managed remote session", "This action requires an explicitly tagged session.")
        return
    # A Kitty launched from another terminal can inherit its parent's control
    # socket. The runtime's own listening_on always takes precedence.
    listening = getattr(boss, "listening_on", "")
    socket = listening if isinstance(listening, str) else ""
    if not socket:
        socket = os.environ.get("KITTY_LISTEN_ON", "")
    if not socket:
        _notify(boss, window, "Kitty control socket unavailable")
        return
    argv = [_program(), "capability", action, "--kitty-socket", socket, "--kitten-path", _KITTEN_PATH]
    for name, value in target.items():
        argv += ["--" + name.replace("_", "-"), str(value)]
    boss.run_background_process(argv + extra)


def _deliver(boss, callback_window, envelope: str) -> bool:
    if len(envelope) > 1400000:
        raise ValueError("capability response exceeds limit")
    message = json.loads(base64.b64decode(envelope, altchars=b"-_", validate=True))
    target = message["target"]
    window = boss.window_id_map.get(target["window_id"])
    if window is not callback_window or not _matches(window, target):
        # Window closed, reused or rebound while asynchronous work was pending.
        # Never fall back to the active window, and never retry the paste.
        return False
    kind, value = message["kind"], message["value"]
    if not isinstance(value, str):
        raise ValueError("capability value must be text")
    if kind == 'paste' and target.get('harness_session') and not re.fullmatch(r'[0-9a-f]{64}',target.get('harness_invocation','')):
        return False  # old bound targets have no invocation identity to compare
    if kind == "paste-clipboard":
        from kitty.clipboard import get_clipboard_string
        value = get_clipboard_string()
        kind = "paste"
    if kind == "paste":
        if not window.screen.in_bracketed_paste_mode and any(c in value for c in "\r\n\x1b"):
            _notify(boss, window, "Paste refused", "The destination does not support literal multiline paste.")
            return False
        window.paste_text(value)  # Kitty owns terminal-mode-aware paste framing
    elif kind == "open-transcript":
        path = Path(value)
        if not path.is_absolute() or not path.is_file():
            raise ValueError("transcript snapshot is unavailable")
        boss.call_remote_control(window, ("launch", "--type=overlay", "--title=Session history", "nvim", "-R", "--", str(path)))
    elif kind == "error":
        _notify(boss, window, "Agency Kitty", value, 6000)
    else:
        raise ValueError("unknown capability result")
    return True


def _drop_image_paths(drop: dict) -> list[str]:
    """Pure URI inspection: disk reads and MIME verification belong to worker."""
    raw = drop.get("text/uri-list", b"")
    if not isinstance(raw, bytes) or len(raw) > 65536:
        return []
    try:
        lines = raw.decode("utf-8", "strict").splitlines()
    except UnicodeError:
        return []
    paths = []
    for line in lines:
        if not line or line.startswith("#"):
            continue
        uri = urlsplit(line)
        if uri.scheme != "file" or uri.netloc not in {"", "localhost"} or uri.query or uri.fragment:
            return []
        path = unquote(uri.path)
        if not path.startswith("/") or any(ord(c) < 32 for c in path):
            return []
        if Path(path).suffix.lower() not in {".png", ".jpg", ".jpeg", ".gif", ".webp"}:
            return []
        paths.append(path)
    return paths if 0 < len(paths) <= 16 else []


def arm_drops(boss, window, quiet=False) -> bool:
    """One instance method, exact supported runtime, no global monkey patch.

    Kitty 0.48/0.50 have no public on_drop watcher. This narrow API adapter is
    intentionally version-qualified; new Kitty versions need qualification.
    """
    from kitty.constants import version
    target = _target(window)
    if not _valid_target(target):
        return False
    if tuple(version) not in {(0, 48, 0), (0, 50, 0)} or not callable(getattr(window, "on_drop", None)):
        if not quiet:
            _notify(boss, window, "Image drop bridge unavailable", "This Kitty version has not been qualified; clipboard paste remains available.")
        return False
    if getattr(window, "agency_drop_adapter", False) and getattr(window, "agency_drop_target", None) == target:
        return True
    original = getattr(window, "agency_original_on_drop", window.on_drop)

    def on_drop(drop):
        if _matches(window, target) and (paths := _drop_image_paths(drop)):
            extra = []
            for path in paths:
                extra += ["--file", path]
            _background(boss, window, "files", extra)
            return
        original(drop)  # all unrelated windows/drop content preserve native behavior

    window.on_drop = on_drop
    window.agency_drop_adapter = True
    window.agency_original_on_drop = original
    window.agency_drop_target = target
    return True


def apply_harness_binding(boss, window, value: str, unbind: bool = False) -> None:
    if len(value) > 16384:
        raise ValueError("harness binding exceeds limit")
    event = json.loads(value)
    if event.get("managed_session") != window.user_vars.get("agency_session"):
        return
    identity, name = event.get("session_id"), event.get("harness")
    invocation = event.get('invocation','')
    if not isinstance(invocation,str) or invocation and not re.fullmatch(r'[0-9a-f]{64}',invocation):
        raise ValueError('invalid harness invocation generation')
    if not isinstance(identity, str) or not identity or name not in {"claude", "codex"}:
        raise ValueError("invalid harness binding")
    if unbind:
        if (window.user_vars.get("agency_harness_session") != identity or window.user_vars.get("agency_harness") != name
                or window.user_vars.get('agency_harness_invocation','') != invocation):
            return  # an old or background session cannot clear a newer binding
        for key in ("agency_harness", "agency_transcript", "agency_harness_session", "agency_harness_invocation"):
            window.set_user_var(key, None)
    else:
        path = event.get("path")
        if path is not None and (not isinstance(path, str) or not Path(path).is_absolute() or any(ord(c) < 32 for c in path)):
            raise ValueError("invalid harness transcript path")
        window.set_user_var("agency_harness", name)
        window.set_user_var("agency_transcript", path)
        window.set_user_var("agency_harness_session", identity)
        window.set_user_var('agency_harness_invocation',invocation or None)
    # Completion belongs to one occupant, and is restored separately on
    # reconnect. A new/start or matching/end must not retain an old cue.
    window.set_user_var("agency_attention", None)
    window.set_user_var("agency_status", None)


def apply_harness_event(boss, window, value: str) -> None:
    if len(value) > 16384:
        raise ValueError("harness event exceeds limit")
    event = json.loads(value)
    if (event.get("managed_session") != window.user_vars.get("agency_session")
            or event.get("session_id") != window.user_vars.get("agency_harness_session")
            or event.get('invocation','') != window.user_vars.get('agency_harness_invocation','')
            or event.get("harness") != window.user_vars.get("agency_harness")):
        return
    state = event.get("state")
    if state not in {"working", "done", "waiting"}:
        return
    # DSH/Imagine can consume this small public event. Notification and sound
    # policy stay with that consumer; no duplicate popup/sound is generated here.
    visible = {"session": event["managed_session"], "harness": event["harness"],
               "harness_session": event["session_id"], "state": state}
    if isinstance(event.get("turn_id"), str):
        visible["turn_id"] = event["turn_id"]
    window.set_user_var("agency_attention", None if state == 'working' else json.dumps(visible))
    window.set_user_var("agency_status", state)


def arm_copy_feedback(boss, window) -> bool:
    """Selection-complete callback only, native clipboard copy happens first."""
    from kitty.constants import version
    if tuple(version) not in {(0, 48, 0), (0, 50, 0)}:
        return False
    if not _valid_target(_target(window)):
        return False
    registered = getattr(boss, "agency_copy_windows", None)
    if registered is None:
        registered = boss.agency_copy_windows = {}
    registered[window.id] = _target(window)
    if getattr(boss, "agency_copy_original", None) is not None:
        return True
    original = boss.set_primary_selection
    boss.agency_copy_original = original

    def set_primary_selection():
        original()
        selected = boss.active_window
        target = registered.get(selected.id) if selected is not None else None
        if target is None or not _matches(selected, target):
            return
        from kitty.fast_data_types import get_options
        if get_options().copy_on_select == "clipboard" and selected.text_for_selection():
            _copied(boss, selected)

    boss.set_primary_selection = set_primary_selection
    boss.agency_copy_wrapper = set_primary_selection
    return True


def disarm_copy_feedback(boss, window) -> None:
    registered = getattr(boss, "agency_copy_windows", {})
    registered.pop(window.id, None)
    if not registered and getattr(boss, "agency_copy_wrapper", None) is boss.set_primary_selection:
        boss.set_primary_selection = boss.agency_copy_original
        del boss.agency_copy_original, boss.agency_copy_wrapper


def _copied(boss, window):
    window.set_user_var("agency_feedback", json.dumps({"event": "copied", "window_id": window.id}))
    _notify(boss, window, "Copied")


def handle_result(args, answer, target_window_id, boss):
    window = boss.window_id_map.get(target_window_id)
    if window is None:
        return
    action = args[1] if len(args) > 1 else ""
    if action == "_deliver":
        if len(args) != 3:
            raise ValueError("malformed capability callback")
        return _deliver(boss, window, args[2])
    elif action == "copy":
        if window.text_for_selection():
            window.copy_to_clipboard()
            _copied(boss, window)
    elif action == "image":
        if window.user_vars.get('nvim') == '1':
            # The primary local Nvim UI keeps native Visual Block mode.
            # Kitty encodes the key for that UI's negotiated keyboard mode.
            window.send_key('ctrl+v')
        else:
            _background(boss, window, "image", [])
    elif action == "files":
        _background(boss, window, "files", args[2:])
    elif action == "arm-drops":
        arm_drops(boss, window)
        arm_copy_feedback(boss, window)
    elif action == "editor-tree":
        # The editor helper owns its native dock/split and Nvim directory UI.
        parent = str(Path(_KITTEN_PATH).parent)
        config = os.environ.get("KITTY_CONFIG_DIRECTORY", str(Path.home() / ".config" / "kitty"))
        for directory in (config, parent):
            if directory not in sys.path:
                sys.path.insert(0, directory)
        import agency_editor
        agency_editor.sidebar(boss, window, args[2:])
    elif action == "transcript":
        path = window.user_vars.get("agency_transcript", "")
        harness = window.user_vars.get("agency_harness", "")
        if not path or harness not in {"claude", "codex"}:
            # Keep the established native shell scrollback gesture intact.
            # combine() resolves the user's configured action alias in Kitty.
            if not boss.combine("kitty_scrollback_nvim", window):
                window.show_scrollback()
            return
        _background(boss, window, "fetch-transcript", ["--path", path, "--harness", harness])
    else:
        _notify(boss, window, "Unknown Agency Kitty action", action)


handle_result.no_ui = True
