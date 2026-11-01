"""Extract a pinned Docker archive in a Nix builder without privileged metadata.

Container userspace keeps its file bytes and link semantics. Ownership,
setuid/setgid bits and device nodes are irrelevant to an unprivileged inference
process, and cannot be restored in a Nix build sandbox. Python's data filter
also prevents an archive entry from escaping the output directory.
"""

from __future__ import annotations

import json
from pathlib import Path, PurePosixPath
import posixpath
import shutil
import sys
import tarfile


def remove(path):
    if path.is_symlink() or path.is_file():
        path.unlink()
    elif path.is_dir():
        shutil.rmtree(path)


def unpack(archive_path, output):
    output.mkdir(parents=True, exist_ok=True)
    output = output.resolve()
    with tarfile.open(archive_path) as archive:
        manifests = json.load(archive.extractfile("manifest.json"))
        if len(manifests) != 1:
            raise ValueError("expected exactly one pinned image")
        for layer_name in manifests[0]["Layers"]:
            print("Unpacking layer", layer_name, flush=True)
            with tarfile.open(fileobj=archive.extractfile(layer_name), mode="r:*") as layer:
                members = layer.getmembers()
                # OCI whiteouts remove lower-layer files, regardless of their
                # position relative to new files in the current layer's tar.
                for member in sorted(members, key=lambda item: not PurePosixPath(item.name).name.startswith(".wh.")):
                    name = PurePosixPath(member.name)
                    if name.is_absolute() or ".." in name.parts:
                        raise ValueError(f"unsafe archive path: {member.name}")
                    path = output / member.name
                    if not path.parent.resolve().is_relative_to(output):
                        raise ValueError(f"archive parent escapes output: {member.name}")
                    if name.name == ".wh..wh..opq":
                        if path.parent.exists():
                            for child in path.parent.iterdir():
                                remove(child)
                        continue
                    if name.name.startswith(".wh."):
                        remove(path.with_name(name.name[4:]))
                        continue
                    if not (member.isdir() or member.isfile() or member.issym() or member.islnk()):
                        continue
                    if member.issym() and member.linkname.startswith("/"):
                        member = member.replace(linkname=posixpath.relpath(member.linkname, "/" + str(name.parent)))
                    elif member.islnk():
                        member = member.replace(linkname=member.linkname.lstrip("/"))
                    member = member.replace(mode=member.mode & 0o777, uid=None, gid=None, uname=None, gname=None)
                    layer.extract(member, output, filter="data")


if __name__ == "__main__":
    unpack(Path(sys.argv[1]), Path(sys.argv[2]))
