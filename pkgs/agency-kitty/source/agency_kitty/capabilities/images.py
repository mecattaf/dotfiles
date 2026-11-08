"""Local clipboard/file -> private NAS file. No clipboard daemon or input proxy."""
from __future__ import annotations

from dataclasses import dataclass
import os
from pathlib import Path
import re
import selectors
import stat
import subprocess
import time
import uuid
from typing import BinaryIO

from ..transport import NAS_HOST, ssh_command_argv

MAX_IMAGE_BYTES = 16 * 1024 * 1024
MIME_EXTENSIONS = {
    "image/png": "png", "image/jpeg": "jpg",
    "image/gif": "gif", "image/webp": "webp",
}


@dataclass(frozen=True)
class Image:
    mime: str
    data: bytes

    @property
    def extension(self) -> str:
        return MIME_EXTENSIONS[self.mime]


def image_mime(data: bytes) -> str:
    if not data or len(data) > MAX_IMAGE_BYTES:
        raise ValueError("image is empty or exceeds 16 MiB")
    if data.startswith(b"\x89PNG\r\n\x1a\n"):
        return "image/png"
    if data.startswith(b"\xff\xd8\xff"):
        return "image/jpeg"
    if data.startswith((b"GIF87a", b"GIF89a")):
        return "image/gif"
    if len(data) >= 12 and data[:4] == b"RIFF" and data[8:12] == b"WEBP":
        return "image/webp"
    raise ValueError("expected PNG, JPEG, GIF or WebP image bytes")


def read_bounded(stream: BinaryIO, limit: int = MAX_IMAGE_BYTES) -> bytes:
    data = stream.read(limit + 1)
    if len(data) > limit:
        raise ValueError(f"payload exceeds {limit} bytes")
    return data


def run_bounded(argv: list[str], *, input_data: bytes | None = None,
                max_stdout: int = 65536, max_stderr: int = 65536,
                timeout: float = 5.0) -> subprocess.CompletedProcess:
    """Bound allocations and wall time while concurrently streaming input/output."""
    proc = subprocess.Popen(argv, stdin=subprocess.PIPE if input_data else subprocess.DEVNULL,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    result = {"stdout": bytearray(), "stderr": bytearray()}
    limits = {"stdout": max_stdout, "stderr": max_stderr}
    offset = 0
    deadline = time.monotonic() + timeout
    try:
        assert proc.stdout is not None and proc.stderr is not None
        with selectors.DefaultSelector() as selector:
            for name, stream in (("stdout", proc.stdout), ("stderr", proc.stderr)):
                os.set_blocking(stream.fileno(), False)
                selector.register(stream, selectors.EVENT_READ, name)
            if input_data and proc.stdin is not None:
                os.set_blocking(proc.stdin.fileno(), False)
                selector.register(proc.stdin, selectors.EVENT_WRITE, "stdin")
            while selector.get_map():
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    raise TimeoutError(f"{argv[0]} did not finish within {timeout:g}s")
                for key, _ in selector.select(min(remaining, 0.1)):
                    if key.data == "stdin":
                        try:
                            offset += os.write(key.fileobj.fileno(), input_data[offset:offset + 65536])
                        except BrokenPipeError:
                            offset = len(input_data)
                        if offset == len(input_data):
                            selector.unregister(key.fileobj)
                            key.fileobj.close()
                        continue
                    block = os.read(key.fileobj.fileno(), min(65536, limits[key.data] - len(result[key.data]) + 1))
                    if not block:
                        selector.unregister(key.fileobj)
                        continue
                    result[key.data].extend(block)
                    if len(result[key.data]) > limits[key.data]:
                        raise ValueError(f"{argv[0]} {key.data} exceeds {limits[key.data]} bytes")
        code = proc.wait(timeout=max(0.01, deadline - time.monotonic()))
        return subprocess.CompletedProcess(argv, code, bytes(result["stdout"]), bytes(result["stderr"]))
    finally:
        if proc.poll() is None:
            proc.kill()
        proc.wait()
        for stream in (proc.stdout, proc.stderr, proc.stdin):
            if stream is not None:
                stream.close()


def command_bytes(argv: list[str], limit: int, timeout: float = 5.0) -> bytes:
    result = run_bounded(argv, max_stdout=limit, timeout=timeout)
    if result.returncode:
        raise RuntimeError(f"{argv[0]} exited {result.returncode}: " + result.stderr.decode("utf-8", "replace")[-1000:])
    return result.stdout


def clipboard_image() -> Image | None:
    types = command_bytes(["wl-paste", "--list-types"], 65536).decode("utf-8", "replace").splitlines()
    for mime in MIME_EXTENSIONS:
        if mime in types:
            data = command_bytes(["wl-paste", "--no-newline", "--type", mime], MAX_IMAGE_BYTES)
            actual = image_mime(data)
            if actual != mime:
                raise ValueError(f"clipboard advertised {mime} but supplied {actual}")
            return Image(mime, data)
    return None


def file_image(path: str | Path) -> Image:
    with Path(path).expanduser().open("rb") as stream:
        if not stat.S_ISREG(os.fstat(stream.fileno()).st_mode):
            raise ValueError("image source must be a regular file")
        data = read_bounded(stream)
    return Image(image_mime(data), data)



def paste_path(path: str) -> str:
    """One shell-escaped path understood by Fish, Codex and Claude's paste parser.

    Backslash escaping also handles apostrophes; POSIX quote concatenation
    generated by shlex.quote is not understood by Claude's image-path parser.
    """
    if not path.startswith("/") or any(ord(c) < 32 or ord(c) == 127 for c in path):
        raise ValueError("image paste requires an absolute path without controls")
    safe = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_@%+=:,./-"
    return "".join(c if c in safe else "\\" + c for c in path)

def private_image_dir(root: Path | None = None) -> Path:
    if root is None:
        root = Path(os.environ.get("XDG_CACHE_HOME", str(Path.home() / ".cache"))) / "agency-kitty" / "images"
    root = root.expanduser()
    root.mkdir(mode=0o700, parents=True, exist_ok=True)
    info = root.lstat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid():
        raise ValueError("image cache must be a directory owned by this user, not a symlink")
    root.chmod(0o700)
    return root.resolve()


def store_image(data: bytes, extension: str, root: Path | None = None) -> Path:
    actual = image_mime(data)
    if extension != MIME_EXTENSIONS[actual]:
        raise ValueError("image filename extension does not match image bytes")
    directory = private_image_dir(root)
    path = directory / f"image-{uuid.uuid4().hex}.{extension}"
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL | os.O_NOFOLLOW, 0o600)
    try:
        with os.fdopen(fd, "wb") as stream:
            stream.write(data)
    except BaseException:
        path.unlink(missing_ok=True)
        raise
    return path


def prune_images(root: Path | None = None, older_than: float = 86400, now: float | None = None) -> int:
    """Explicit maintenance only; never prune while delivering a new image."""
    if older_than < 0:
        raise ValueError("image retention age must not be negative")
    directory = private_image_dir(root)
    cutoff = (time.time() if now is None else now) - older_than
    removed = 0
    for path in directory.iterdir():
        if not re.fullmatch(r"image-[0-9a-f]{32}\.(png|jpg|gif|webp)", path.name):
            continue
        info = path.lstat()
        if stat.S_ISREG(info.st_mode) and info.st_uid == os.getuid() and info.st_mtime < cutoff:
            path.unlink()
            removed += 1
    return removed


def stage_remote(host: str, image: Image, remote_program: str = "agency-kitty", timeout: float = 30,
                 *, ssh_builder=None) -> str:
    if host != NAS_HOST:
        raise ValueError("image sidechannel only supports the pinned NAS identity")
    if image_mime(image.data) != image.mime:
        raise ValueError("image MIME does not match its bytes")
    # Production always uses the same fixed Tailnet endpoint/host key identity
    # as the terminal transport. The injected builder exists for private sshd
    # qualification; there is no CLI/config option to change this route.
    remote = (ssh_builder or ssh_command_argv)([remote_program, "capability", "image-store", image.extension])
    result = run_bounded(remote, input_data=image.data, max_stdout=16384, timeout=timeout)
    if result.returncode:
        raise RuntimeError(f"remote image staging failed ({result.returncode}): " + result.stderr.decode("utf-8", "replace")[-1000:])
    path = result.stdout.decode("utf-8", "strict").strip()
    if not path.startswith("/") or any(ord(c) < 32 or ord(c) == 127 for c in path) or len(path) > 4096:
        raise ValueError("remote helper returned an invalid absolute path")
    return path
