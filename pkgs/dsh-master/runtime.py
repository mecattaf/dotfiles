"""Freeze an installed Master graph without replacing any live profile path.

The only outputs are content-addressed snapshots and GC roots below the DSH
home. This module never installs packages, builds, or controls a DSH instance.
"""
from __future__ import annotations

import errno
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import tempfile

import yaml

BACKENDS = {
    "dsh-superagent": "index.js",
    "dsh-superagent-scheduled": "scheduled-watch.js",
    "dsh-superagent-workflow": "workflow.js",
}
OMIT = {".git", ".cache", "cache", ".npm", ".npmrc", ".pnpm-store", "_cacache"}
PACKAGE_NAME = re.compile(r"(?:@[A-Za-z0-9_.-]+/)?[A-Za-z0-9_.-]+")
STORE_PATH = re.compile(r"^(/nix/store/[0-9a-z]{32}-[^/]+)(?:/|$)")


class SnapshotError(Exception):
    pass


def json_bytes(value):
    return (json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n").encode()


def digest(data):
    return hashlib.sha256(data).hexdigest()


def file_digest(path):
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()


def inside(path, root):
    return path == root or root in path.parents


def store_root(path):
    match = STORE_PATH.match(str(path))
    if not match:
        raise SnapshotError(f"external link is mutable: {path}")
    return match[1]


def private_directory(path):
    if not path.exists() and not path.is_symlink():
        path.mkdir(mode=0o700, exist_ok=True)
    info = path.lstat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
        raise SnapshotError(f"{path}: expected a real owner-only directory")


def read_json(path):
    with path.open(encoding="utf-8") as stream:
        return json.load(stream)


def lock_matches(profile, package):
    for path in [profile / "pnpm-lock.yaml", profile / "node_modules/.pnpm/lock.yaml"]:
        if not path.is_file():
            raise SnapshotError(f"installed graph has no lockfile: {path}")
        locked = yaml.safe_load(path.read_text())["importers"]["."]["dependencies"]
        for name, spec in package["dependencies"].items():
            if locked.get(name, {}).get("specifier") != spec:
                raise SnapshotError(f"installed lockfile does not match {name}")


def copy_tree(source, target, graph_source, graph_target, store_roots):
    """Copy regular bytes; internal links become relocatable, external ones immutable."""
    info = source.lstat()
    if stat.S_ISLNK(info.st_mode):
        resolved = source.resolve(strict=True)
        if inside(resolved, graph_source):
            destination = graph_target / resolved.relative_to(graph_source)
            target.symlink_to(os.path.relpath(destination, target.parent))
        else:
            store_roots.add(store_root(resolved))
            target.symlink_to(resolved)
    elif stat.S_ISDIR(info.st_mode):
        target.mkdir(mode=0o700)
        for child in sorted(source.iterdir()):
            if child.name not in OMIT and not child.name.startswith(".env"):
                copy_tree(child, target / child.name, graph_source, graph_target, store_roots)
    elif stat.S_ISREG(info.st_mode):
        descriptor = os.open(source, os.O_RDONLY | os.O_NOFOLLOW)
        with os.fdopen(descriptor, "rb") as incoming, target.open("xb") as outgoing:
            current = os.fstat(incoming.fileno())
            if not stat.S_ISREG(current.st_mode) or (current.st_dev, current.st_ino) != (info.st_dev, info.st_ino):
                raise SnapshotError(f"source changed while copying: {source}")
            shutil.copyfileobj(incoming, outgoing, length=1024 * 1024)
            outgoing.flush()
            os.fsync(outgoing.fileno())
        target.chmod(0o755 if info.st_mode & 0o111 else 0o644)
    else:
        raise SnapshotError(f"not a regular package file: {source}")


def packages(modules):
    """Installed package roots, excluding inner source/example package manifests."""
    for folder, directories, files in os.walk(modules, followlinks=False):
        directories[:] = sorted(name for name in directories if name not in OMIT)
        path = Path(folder)
        package_root = path.parent.name == "node_modules" or (path.parent.name.startswith("@") and path.parent.parent.name == "node_modules")
        if package_root and "package.json" in files:
            yield path, read_json(path / "package.json")


def resolve_dependency(package, name, modules):
    if not PACKAGE_NAME.fullmatch(name) or name in [".", ".."]:
        raise SnapshotError(f"invalid installed dependency name: {name}")
    for parent in [package, *package.parents]:
        if not inside(parent, modules.parent):
            break
        candidate = parent / "node_modules" / name
        if (candidate / "package.json").is_file():
            return candidate
    return None


def prepare_peers(modules, dsh):
    required = set()
    for _, package in packages(modules):
        required.update(name for field in ["dependencies", "peerDependencies"] for name in package.get(field, {}) if name.startswith("@deepseek-ai/"))
    if not required:
        return set()
    installation = Path(dsh).resolve(strict=True).parent.parent / "lib/node_modules/@deepseek-ai/dsh"
    store_roots = {store_root(installation.resolve(strict=True))}
    scope = modules / "@deepseek-ai"
    scope.mkdir(exist_ok=True)
    for name in sorted(required):
        candidate = installation / "node_modules" / name
        # Browser packages are provided by DSH's client module graph, not
        # necessarily published as Node packages in the native installation.
        if not candidate.exists() and browser_peer(name):
            continue
        target = candidate.resolve(strict=True)
        if not (target / "package.json").is_file():
            raise SnapshotError(f"DSH installation has no peer {name}")
        store_roots.add(store_root(target))
        link = modules / name
        if link.exists() or link.is_symlink():
            if not link.is_symlink() or link.resolve(strict=True) != target:
                raise SnapshotError(f"installed graph duplicates the native DSH peer {name}")
        else:
            link.symlink_to(target)
    return store_roots


def browser_peer(name):
    return name.startswith("@deepseek-ai/dsh-client-") or name in ["react", "react-dom"]


def check_dependencies(modules):
    unprovided_peers = []
    for folder, package in packages(modules):
        optional = set(package.get("optionalDependencies", {}))
        optional.update(name for name, options in package.get("peerDependenciesMeta", {}).items() if options.get("optional"))
        optional.update(name for name in package.get("peerDependencies", {}) if browser_peer(name))
        for name in set(package.get("dependencies", {})):
            if name not in optional and resolve_dependency(folder, name, modules) is None:
                raise SnapshotError(f"missing installed dependency {name} required by {package.get('name', folder.name)}")
        for name in package.get("peerDependencies", {}):
            if name not in optional and resolve_dependency(folder, name, modules) is None:
                if name.startswith("@deepseek-ai/"):
                    raise SnapshotError(f"missing native DSH peer {name}")
                # Some bundled SDKs declare type-only peers that the already
                # qualified installed graph does not provide. Retain that
                # declaration and report it; never install a different graph.
                unprovided_peers.append({"package": package.get("name", folder.name), "peer": name})
    return sorted(unprovided_peers, key=lambda row: (row["package"], row["peer"]))


def inventory(root):
    rows = {}
    for folder, directories, files in os.walk(root, followlinks=False):
        for name in sorted(directories + files):
            path = Path(folder) / name
            relative = str(path.relative_to(root))
            info = path.lstat()
            if path.is_symlink():
                # Every retained relative link must still resolve after omitted
                # cache/VCS files have gone. Do not accidentally publish a hole.
                path.resolve(strict=True)
                rows[relative] = {"link": os.readlink(path)}
            elif stat.S_ISREG(info.st_mode):
                rows[relative] = {"sha256": file_digest(path), "executable": bool(info.st_mode & 0o111)}
            elif stat.S_ISDIR(info.st_mode):
                rows[relative] = {"directory": True}
            else:
                raise SnapshotError(f"invalid snapshot entry: {path}")
    return rows


def overlay_templates(manifest):
    found = {}
    for row in manifest["profiles"]["master"]["expect"]:
        if row["id"] in BACKENDS:
            found[row["id"]] = row
    if set(found) != set(BACKENDS) or any(row.get("disabled") is not False for row in found.values()):
        raise SnapshotError("new manifest must enable all three Master backend rows")
    rows = [{"id": name, "disabled": True} for name in BACKENDS]
    inserted = []
    for name, file in BACKENDS.items():
        row = {"id": name + "-runtime", "name": "@RUNTIME@/node_modules/dsh-superagent/lib/" + file}
        if found[name].get("config") is not None:
            row["config"] = found[name]["config"]
        inserted.append(row)
    rows.append({"insert": inserted})
    return rows


def run_nix(nix_store, arguments):
    result = subprocess.run([nix_store, *arguments], capture_output=True, text=True, timeout=60, check=False)
    if result.returncode:
        raise SnapshotError(f"nix-store {arguments[0]} failed (exit {result.returncode})")


def pin_store_roots(parent, roots, nix_store):
    if not roots:
        return
    # Every root must already be valid locally. Legacy nix-store has no
    # --offline flag; disable both substitution and all builders for realise.
    run_nix(nix_store, ["--check-validity", *sorted(roots)])
    directory = parent / ".nix-gcroots"
    private_directory(directory)
    for root in sorted(roots):
        link = directory / Path(root).name
        if link.is_symlink() and os.readlink(link) == root:
            continue
        if link.exists() or link.is_symlink():
            raise SnapshotError(f"GC root already has another target: {link}")
        run_nix(nix_store, ["--option", "substitute", "false", "--option", "max-jobs", "0", "--option", "builders", "", "--add-root", str(link), "--indirect", "--realise", root])
        if not link.is_symlink() or str(link.resolve(strict=True)) != root:
            raise SnapshotError(f"nix-store did not retain {root}")


def freeze(root):
    for folder, directories, files in os.walk(root, topdown=False, followlinks=False):
        for name in files:
            path = Path(folder) / name
            if not path.is_symlink():
                path.chmod(0o555 if path.stat().st_mode & 0o111 else 0o444)
        Path(folder).chmod(0o555)


def check_readonly(root):
    for folder, directories, files in os.walk(root, followlinks=False):
        for path in [Path(folder), *(Path(folder) / name for name in directories + files)]:
            info = path.lstat()
            if not stat.S_ISLNK(info.st_mode) and (info.st_uid != os.getuid() or info.st_mode & 0o222):
                raise SnapshotError("existing content-addressed runtime is no longer owner-held and read-only")


def discard(root):
    if root.exists():
        for folder, _, _ in os.walk(root, followlinks=False):
            Path(folder).chmod(0o700)
        shutil.rmtree(root)


def snapshot(source, installed_profile, home, nix_store="nix-store"):
    source, profile, home = Path(source).resolve(strict=True), Path(installed_profile).resolve(strict=True), Path(home).resolve(strict=True)
    manifest = read_json(source / "manifest.json")
    selected = manifest["profiles"].get(profile.name)
    if not selected:
        raise SnapshotError("installed source must name one profile from the new manifest")
    package = read_json(profile / "package.json")
    if digest((profile / "package.json").read_bytes()) != selected["files"]["package.json"]:
        raise SnapshotError("installed source package.json differs from the new manifest")
    lock_matches(profile, package)
    templates = overlay_templates(manifest)
    parent = home / "master-runtimes"
    private_directory(parent)
    stage = Path(tempfile.mkdtemp(prefix=".staging-", dir=parent))
    try:
        roots = set()
        graph = (profile / "node_modules").resolve(strict=True)
        copy_tree(graph, stage / "node_modules", graph, stage / "node_modules", roots)
        for name in ["package.json", "pnpm-lock.yaml"]:
            copy_tree(profile / name, stage / name, graph, stage / "node_modules", roots)
        if read_json(stage / "package.json") != package:
            raise SnapshotError("source package changed during snapshot")
        lock_matches(stage, package)
        roots.update(prepare_peers(stage / "node_modules", manifest["dsh"]))
        unprovided_peers = check_dependencies(stage / "node_modules")
        for file in BACKENDS.values():
            if not (stage / "node_modules/dsh-superagent/lib" / file).is_file():
                raise SnapshotError(f"installed source has no backend lib/{file}")
        (stage / "source-manifest.json").write_bytes(json_bytes(manifest))
        metadata = {
            "format": "dsh-master-runtime/1", "profile": profile.name,
            "sourceProfile": str(profile), "pins": package["dependencies"],
            "dsh": manifest["dsh"], "storeRoots": sorted(roots),
            "unprovidedDeclaredPeers": unprovided_peers,
            "overlay": templates, "files": inventory(stage),
        }
        metadata_bytes = json_bytes(metadata)
        content_hash = digest(metadata_bytes)
        destination = parent / content_hash
        overlay = json_bytes(json.loads(json.dumps(templates).replace("@RUNTIME@", str(destination))))
        (stage / "snapshot.json").write_bytes(metadata_bytes)
        (stage / "floor.patch.yml").write_bytes(overlay)
        pin_store_roots(parent, roots, nix_store)
        if destination.exists() or destination.is_symlink():
            if destination.is_symlink() or (destination / "snapshot.json").read_bytes() != metadata_bytes or (destination / "floor.patch.yml").read_bytes() != overlay:
                raise SnapshotError("existing content-addressed runtime has changed")
            check_readonly(destination)
            actual = inventory(destination)
            actual.pop("snapshot.json", None)
            actual.pop("floor.patch.yml", None)
            if actual != metadata["files"]:
                raise SnapshotError("existing content-addressed runtime payload has changed")
            reused = True
        else:
            freeze(stage)
            try:
                stage.rename(destination)
            except OSError as error:
                if error.errno not in [errno.EEXIST, errno.ENOTEMPTY]:
                    raise
                # A concurrent publisher won. Re-enter verification rather
                # than replace its immutable directory.
                return snapshot(source, installed_profile, home, nix_store)
            descriptor = os.open(parent, os.O_RDONLY | os.O_DIRECTORY)
            try:
                os.fsync(descriptor)
            finally:
                os.close(descriptor)
            reused = False
        return {"generation": str(destination), "contentHash": content_hash, "overlay": str(destination / "floor.patch.yml"), "reused": reused, "pins": package["dependencies"], "storeRoots": sorted(roots)}
    finally:
        discard(stage)
