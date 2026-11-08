"""An intentional native session menu, with no allocation during discovery."""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from typing import Sequence

from ..catalogue import chat_id, project_catalogue
from ..sessions import validate_cwd
from ..transport import SSHTransport
from .images import run_bounded

MAX_CATALOGUE_BYTES = 1024 * 1024


def display(value: str) -> str:
    # fzf receives plain labels, never ANSI, tabs/newlines, or bidi controls.
    import unicodedata
    return "".join(c for c in value if not unicodedata.category(c).startswith("C"))[:512]


def choices(values: list, *, linked_chat: str | None = None) -> dict[str, list[str]]:
    projected = project_catalogue(values, linked_chat=linked_chat)
    result = {"new\tNew persistent NAS terminal": ["open"]}
    for item in projected["sessions"]:
        if item["liveness"] != "running" or not item["resumable"]:
            continue
        label = (f'{item["terminalId"]}\t{display(item["title"])}'
                 f'  ·  {display(item["directory"])}')
        if item["chatIds"]:
            label += "  ·  " + ", ".join(item["chatIds"][:4])
        result[label] = ["resume", item["terminalId"]]
    return result


def read_catalogue(transport: SSHTransport) -> list:
    receipt = run_bounded(transport.command_argv("list"), max_stdout=MAX_CATALOGUE_BYTES,
                          max_stderr=65536, timeout=10)
    if receipt.returncode:
        raise RuntimeError("NAS session discovery failed; no terminal was allocated")
    value = json.loads(receipt.stdout)
    if not isinstance(value, list):
        raise ValueError("NAS session catalogue must be a list")
    # All metadata must validate before offering even the explicit New action.
    try:
        project_catalogue(value)
    except (KeyError, TypeError) as error:
        raise ValueError("invalid NAS session metadata") from error
    return value


def select(rows: Sequence[str]) -> str | None:
    """fzf owns only this intentionally opened menu TTY, never a worker overlay."""
    payload = ("\n".join(rows) + "\n").encode()
    if len(payload) > 2 * MAX_CATALOGUE_BYTES:
        raise ValueError("session menu exceeds its bound")
    argv = ["fzf", "--no-multi", "--no-sort", "--delimiter=\t", "--with-nth=2..",
            "--prompt=NAS sessions › ", "--header=Enter: open / resume   Esc: cancel",
            "--border=none", "--no-preview", "--layout=reverse"]
    # fzf renders on this menu's controlling TTY. Only a single, bounded chosen
    # row returns on stdout; no shell, preview command, or user fzf config runs.
    env = dict(os.environ)
    env.pop("FZF_DEFAULT_OPTS", None)
    env.pop("FZF_DEFAULT_OPTS_FILE", None)
    proc = subprocess.Popen(argv, stdin=subprocess.PIPE, stdout=subprocess.PIPE, env=env)
    try:
        assert proc.stdin is not None and proc.stdout is not None
        proc.stdin.write(payload)
        proc.stdin.close()
        answer = proc.stdout.read(4097)
        if len(answer) > 4096:
            raise ValueError("session selection exceeds its bound")
        code = proc.wait()
        if code in (1, 130):
            return None
        if code:
            raise RuntimeError(f"session chooser failed ({code}); no terminal was allocated")
        return answer.decode("utf-8", "strict").removesuffix("\n")
    finally:
        if proc.poll() is None:
            proc.kill()
        proc.wait()
        for stream in (proc.stdin, proc.stdout):
            if stream is not None:
                stream.close()


def parser() -> argparse.ArgumentParser:
    value = argparse.ArgumentParser(prog="agency-kitty choose")
    value.add_argument("--directory", default="/home/tom")
    value.add_argument("--workspace-id")
    value.add_argument("--chat-id", action="append", default=[])
    value.add_argument("--linked-chat", help="show only sessions already linked to this DSH chat")
    return value


def new_args(args: argparse.Namespace) -> list[str]:
    cwd = validate_cwd(args.directory)
    workspace = args.workspace_id
    if workspace is not None and (not workspace or len(workspace) > 128
            or any(ord(c) < 32 or 127 <= ord(c) < 160 for c in workspace)):
        raise ValueError("invalid Imagine workspace reference")
    chats = list(dict.fromkeys(chat_id(value) for value in args.chat_id))
    if len(chats) > 64:
        raise ValueError("too many linked DSH chats")
    result = ["--directory", cwd]
    if workspace is not None:
        result += ["--workspace-id", workspace]
    for value in chats:
        result += ["--chat-id", value]
    return result


def main(argv: Sequence[str] | None = None) -> int:
    args = parser().parse_args(argv)
    try:
        context = new_args(args)
        if args.linked_chat is not None:
            chat_id(args.linked_chat)
        transport = SSHTransport(ssh=os.environ.get("AGENCY_KITTY_SSH", "ssh"),
                                 remote_program=os.environ.get("AGENCY_KITTY_REMOTE_PROGRAM", "agency-kitty"))
        rows = choices(read_catalogue(transport), linked_chat=args.linked_chat)
        selected = select(list(rows))
        if selected is None:
            return 0
        if selected not in rows:
            raise ValueError("unknown terminal selection; no terminal was allocated")
        action = rows[selected]
        if action == ["open"]:
            action = [*action, *context]
        command = os.environ.get("AGENCY_KITTY_COMMAND", "agency-kitty")
        # Existing selection revalidates the UUID through the public resume
        # action. It never falls back to creation when an old PTY has exited.
        return subprocess.run([command, *action], check=False).returncode
    except (OSError, RuntimeError, ValueError, subprocess.SubprocessError) as error:
        print(f"agency-kitty: {error}", file=sys.stderr)
        return 1
