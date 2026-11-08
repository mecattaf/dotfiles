"""Exact-window callback envelopes for asynchronous capability work."""
from __future__ import annotations

import base64
from dataclasses import asdict, dataclass
import json
from pathlib import Path
import socket as sockets

from ..sessions import validate_id
from ..transport import NAS_HOST


@dataclass(frozen=True)
class Target:
    window_id: int
    child_pid: int
    host: str
    session: str
    harness_session: str = ""

    def validate(self) -> None:
        if self.host != NAS_HOST or self.window_id <= 0 or self.child_pid <= 0:
            raise ValueError("target must name one window and the pinned NAS identity")
        validate_id(self.session)

    def matches(self, window) -> bool:
        return (window is not None and not getattr(window, "destroyed", False)
                and window.id == self.window_id
                and getattr(window.child, "root_pid", window.child.pid) == self.child_pid
                and window.user_vars.get("agency_host", "") == self.host
                and window.user_vars.get("agency_session", "") == self.session
                and window.user_vars.get("agency_harness_session", "") == self.harness_session)


def encode(target: Target, kind: str, value: str) -> str:
    raw = json.dumps({"target": asdict(target), "kind": kind, "value": value}, ensure_ascii=False).encode()
    if len(raw) > 1024 * 1024:
        raise ValueError("capability response exceeds 1 MiB")
    return base64.urlsafe_b64encode(raw).decode("ascii")


def decode(envelope: str) -> tuple[Target, str, str]:
    if len(envelope) > 1400000:
        raise ValueError("capability response exceeds limit")
    obj = json.loads(base64.b64decode(envelope, altchars=b"-_", validate=True))
    target = Target(**obj["target"])
    if not isinstance(obj["kind"], str) or not isinstance(obj["value"], str):
        raise ValueError("malformed capability response")
    return target, obj["kind"], obj["value"]


def deliver(socket: str, kitten: str, target: Target, kind: str, value: str) -> None:
    target.validate()
    if not socket.startswith("unix:") or not Path(kitten).is_absolute():
        raise ValueError("an explicit Kitty socket and absolute kitten path are required")
    address = socket[len("unix:"):]
    if address.startswith("@"):
        address = "\0" + address[1:]
    elif not Path(address).is_absolute():
        raise ValueError("Kitty socket must be an absolute or abstract Unix address")
    # Use Kitty's public remote-control protocol directly so a large literal
    # paste cannot exceed the OS's per-argv-string limit. This is a single
    # explicit capability completion, never the ordinary typing/output path.
    command = {"cmd": "kitten", "version": [0, 48, 0], "no_response": False,
               "payload": {"kitten": kitten, "match": f"id:{target.window_id}",
                           "args": ["_deliver", encode(target, kind, value)]}}
    wire = b"\x1bP@kitty-cmd" + json.dumps(command).encode("ascii") + b"\x1b\\"
    with sockets.socket(sockets.AF_UNIX, sockets.SOCK_STREAM) as peer:
        peer.settimeout(8)
        peer.connect(address)
        peer.sendall(wire)
        peer.shutdown(sockets.SHUT_WR)
        response = bytearray()
        while True:
            chunk = peer.recv(65536)
            if not chunk:
                break
            response.extend(chunk)
            if len(response) > 4 * 1024 * 1024:
                raise ValueError("Kitty response exceeds 4 MiB")
    prefix, suffix = b"\x1bP@kitty-cmd", b"\x1b\\"
    if not response.startswith(prefix) or not response.endswith(suffix):
        raise RuntimeError("Kitty returned no valid control response")
    result = json.loads(response[len(prefix):-len(suffix)])
    if not result.get("ok"):
        raise RuntimeError("Kitty delivery refused: " + str(result.get("error", "unknown error")))
    if result.get("data") is False:
        raise RuntimeError("destination changed or literal paste was refused; zero input sent")
