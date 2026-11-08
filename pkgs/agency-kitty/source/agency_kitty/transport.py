"""Command construction only. Stock Kitty/OpenSSH carry all terminal bytes."""

from __future__ import annotations

from dataclasses import dataclass
import json
import shlex
import subprocess

from .sessions import Session, SessionError, validate_id

NAS_HOST = "nas"
NAS_TAILNET = "100.65.85.114"
SSH_OPTIONS = ("-o", f"Hostname={NAS_TAILNET}", "-o", "HostKeyAlias=nas", "-o", "StrictHostKeyChecking=yes",
               "-o", "BatchMode=yes", "-o", "ForwardAgent=no", "-o", "ClearAllForwardings=yes",
               "-o", "ControlMaster=no", "-o", "ControlPath=none", "-o", "ConnectTimeout=10",
               "-o", "ServerAliveInterval=15", "-o", "ServerAliveCountMax=3")
KITTEN_OPTIONS = ("--kitten=share_connections=no", "--kitten=forward_remote_control=no")


def ssh_command_argv(args: list[str] | tuple[str, ...], *, tty: bool = False,
                     ssh: str = "ssh") -> list[str]:
    """Build one exactly quoted remote command for the fixed NAS SSH identity.

    OpenSSH forwards a command string, not a remote argv array. shlex.join is
    intentional here: local shell=False alone would not protect remote paths.
    """
    if not args or any(not isinstance(arg, str) or "\0" in arg for arg in args):
        raise SessionError("a nonempty remote argv without NUL is required")
    return [ssh, "-t" if tty else "-T", *SSH_OPTIONS, "--", NAS_HOST, shlex.join(args)]


@dataclass(frozen=True)
class SSHTransport:
    kitten: str = "kitten"
    ssh: str = "ssh"
    remote_program: str = "agency-kitty"

    def _remote(self, *args: str) -> list[str]:
        return [self.remote_program, "remote", *args]

    def attach_argv(self, session: Session, *, create: bool = False) -> list[str]:
        if session.status == "closed":
            raise SessionError("cannot attach a closed session")
        remote = self._remote("attach", "--id", validate_id(session.id))
        if create:
            remote += ["--create", "--cwd", session.cwd, "--metadata", json.dumps({
                "title": session.title, "workspace_id": session.workspace_id,
                "chat_ids": list(session.chat_ids),
            }, ensure_ascii=False, separators=(",", ":"))]
        # Unlike an interactive login, kitten ssh with a remote command does
        # not allocate a PTY automatically. Force it for single-key input.
        return [self.kitten, "ssh", "-tt", *KITTEN_OPTIONS, *SSH_OPTIONS, NAS_HOST, shlex.join(remote)]

    def direct_argv(self) -> list[str]:
        return [self.kitten, "ssh", *KITTEN_OPTIONS, *SSH_OPTIONS, NAS_HOST]

    def interactive_argv(self, remote: list[str]) -> list[str]:
        return [self.kitten, "ssh", "-tt", *KITTEN_OPTIONS, *SSH_OPTIONS,
                NAS_HOST, shlex.join(remote)]

    def command_argv(self, action: str, session_id: str | None = None, *args: str) -> list[str]:
        if action not in {"create", "list", "describe", "rebind", "link", "close", "capture", "health"}:
            raise SessionError("unsupported remote control action")
        if action not in {"list", "health"} and session_id is None:
            raise SessionError("the action requires an explicit session id")
        remote = self._remote(action)
        if session_id is not None:
            remote += ["--id", validate_id(session_id)]
        remote += list(args)
        return ssh_command_argv(remote, ssh=self.ssh)

    def create_argv(self, session: Session) -> list[str]:
        args = ["--cwd", session.cwd, "--title", session.title]
        if session.workspace_id is not None:
            args += ["--workspace-id", session.workspace_id]
        for chat_id in session.chat_ids:
            args += ["--chat-id", chat_id]
        return self.command_argv("create", session.id, *args)

    def run_json(self, action: str, session_id: str | None = None, *args: str,
                 timeout: float = 10) -> dict | list:
        from .server import bounded_run
        result = bounded_run(self.command_argv(action, session_id, *args), timeout=timeout)
        if result.returncode:
            raise SessionError("NAS request failed: " + result.stderr.decode("utf-8", "replace")[:512])
        return json.loads(result.stdout)
