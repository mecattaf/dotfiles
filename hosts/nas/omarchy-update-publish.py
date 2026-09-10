#!/usr/bin/env python3
"""Manually publish an immutable Omarchy candidate; never activate a laptop."""

import argparse
import datetime
import fcntl
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
from urllib.parse import urlsplit
from urllib.request import Request, urlopen


DEVICES = ("xps", "zenbook-duo")
STORE_PATH = re.compile(r"/nix/store/[0-9abcdfghijklmnpqrsvwxyz]{32}-[^/\s]+")


def run(*args, timeout=14400):
    # Do not include argv in errors: attic login's token is an argument.
    result = subprocess.run(args, text=True, stdout=subprocess.PIPE, timeout=timeout)
    if result.returncode:
        raise RuntimeError(f"{args[0]} failed (exit {result.returncode})")
    return result.stdout.strip()


def immutable_source(source, revision):
    if not re.fullmatch(r"[0-9a-f]{40}", revision):
        raise ValueError("revision must be a full lowercase 40-character Git commit")
    local_path = None
    if source.startswith("/"):
        local_path = Path(source).resolve()
        source = "git+" + Path(source).resolve().as_uri()
    elif source.startswith("https://"):
        source = "git+" + source
    parts = urlsplit(source)
    if parts.scheme not in ("git+https", "git+file") or parts.query or parts.fragment:
        raise ValueError("source must be an absolute Git checkout or git+https URL without query/fragment")
    result = source + "?rev=" + revision
    # Private NAS transport deliberately carries only the reviewed tip, not
    # the repository's credential-bearing historical objects. Nix requires
    # this explicit fetcher flag even for a local shallow checkout.
    if local_path is not None and run("git", "-C", str(local_path),
                                     "rev-parse", "--is-shallow-repository", timeout=30) == "true":
        result += "&shallow=1"
    return result


def login():
    token = run("atticd-atticadm", "make-token", "--sub", "omarchy-update-center",
                "--validity", "1d", "--pull", "fleet", "--push", "fleet", timeout=60)
    run("attic", "login", "omarchy-local", "http://127.0.0.1:8080", token, timeout=60)


def push(paths):
    # Include upstream paths too: an overseas owner needs one complete cache.
    run("attic", "push", "--jobs", "3", "--ignore-upstream-cache-filter",
        "omarchy-local:fleet", *paths)


def sync_directory(path):
    fd = os.open(path, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(fd)
    finally:
        os.close(fd)


def replace_link(link, target):
    temporary = link.with_name("." + link.name + ".new")
    temporary.unlink(missing_ok=True)
    temporary.symlink_to(target)
    os.replace(temporary, link)
    sync_directory(link.parent)


def retained_releases(state):
    result = set()
    for name in ("current", "previous"):
        link = state / "public" / name
        if link.is_symlink():
            target = link.resolve()
            if target.parent != (state / "public" / "releases").resolve():
                raise ValueError(f"unexpected {name} release target")
            result.add(target.name)
    return result


def prune(state):
    retained = retained_releases(state)
    for release in (state / "public" / "releases").iterdir():
        if release.name not in retained and release.is_dir() and not release.is_symlink():
            shutil.rmtree(release)
    for roots in (state / "roots").iterdir():
        if roots.name not in retained and roots.is_dir() and not roots.is_symlink():
            shutil.rmtree(roots)


def publish(state, source, revision, notes, devices, signing_key):
    source = immutable_source(source, revision)
    if (not notes.strip() or len(notes) > 4000
            or any(ord(character) < 32 and character not in "\n\t" for character in notes)):
        raise ValueError("release notes must be nonempty, at most 4000 characters, and plain text")
    if not devices or len(set(devices)) != len(devices) or any(d not in DEVICES for d in devices):
        raise ValueError("devices must be unique known fleet devices")
    metadata = json.loads(run("nix", "flake", "metadata", "--json",
                              "--no-write-lock-file", "--no-update-lock-file", source))
    if metadata.get("locked", {}).get("rev") != revision:
        raise ValueError("Nix resolved a different source revision")
    releases = state / "public" / "releases"
    releases.mkdir(parents=True, exist_ok=True)
    (state / "roots").mkdir(exist_ok=True)
    # Also reclaim staging roots left by a killed or timed-out earlier run.
    prune(state)
    # Private until complete; nginx cannot see a partial candidate through current.
    release = Path(tempfile.mkdtemp(prefix=revision + "-", dir=releases))
    roots = state / "roots" / release.name
    roots.mkdir()
    switched = False
    try:
        outputs = {}
        for device in devices:
            print(f"Building {device} at {revision}", flush=True)
            output = run("nix", "build", "--print-out-paths", "--out-link", str(roots / device),
                         "--no-write-lock-file", "--no-update-lock-file",
                         "--max-jobs", "1", "--cores", "2", "--option", "builders", "",
                         "--option", "max-silent-time", "1200", "--option", "timeout", "14400",
                         source + f"#nixosConfigurations.{device}.config.system.build.toplevel")
            if not STORE_PATH.fullmatch(output) or f"-nixos-system-{device}-" not in output:
                raise ValueError(f"unexpected system output for {device}")
            outputs[device] = {"toplevel": output}
        login()
        push([entry["toplevel"] for entry in outputs.values()])
        manifest = {
            "schemaVersion": 1,
            "revision": revision,
            "publishedAt": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            "notes": notes,
            "devices": outputs,
        }
        path = release / "manifest.json"
        with path.open("x") as stream:
            json.dump(manifest, stream, sort_keys=True, indent=2)
            stream.write("\n")
            stream.flush()
            os.fsync(stream.fileno())
        run("ssh-keygen", "-Y", "sign", "-f", signing_key, "-n", "fleet-update", str(path), timeout=60)
        signature = release / "manifest.json.sig"
        if not signature.is_file() or not signature.stat().st_size:
            raise ValueError("signing did not produce a signature")
        with signature.open("rb") as stream:
            os.fsync(stream.fileno())
        path.chmod(0o644)
        signature.chmod(0o644)
        release.chmod(0o755)
        sync_directory(release)
        sync_directory(releases)
        current = state / "public" / "current"
        if current.is_symlink():
            replace_link(state / "public" / "previous", os.readlink(current))
        replace_link(current, "releases/" + release.name)
        switched = True
        prune(state)
        print(f"Published {revision} for {', '.join(devices)}; owners must accept on their laptops.")
        return manifest
    finally:
        # If rename succeeded but fsync/pruning failed, never remove the
        # already-visible release and leave current dangling.
        current = state / "public" / "current"
        if current.is_symlink() and current.resolve() == release.resolve():
            switched = True
        if not switched:
            shutil.rmtree(release)
            shutil.rmtree(roots)


def keepalive(state):
    paths = []
    for name in sorted(retained_releases(state)):
        manifest = json.loads((state / "public" / "releases" / name / "manifest.json").read_text())
        paths.extend(value["toplevel"] for value in manifest["devices"].values())
    paths = sorted(set(paths))
    if not paths:
        print("No published releases; nothing to keep alive.")
        return
    if any(not STORE_PATH.fullmatch(path) for path in paths):
        raise ValueError("invalid retained store path")
    login()
    push(paths)
    closure = run("nix-store", "--query", "--requisites", *paths).splitlines()
    # Attic push skips already-cached paths, and narinfo does NOT bump last
    # access. HEAD reaches its NAR handler (which does bump it), without a
    # response body. Keep offers available through Attic's month-cold GC.
    for path in sorted(set(closure)):
        if not STORE_PATH.fullmatch(path):
            raise ValueError("invalid closure store path")
        hash_part = Path(path).name.split("-", 1)[0]
        request = Request(f"http://127.0.0.1:8080/fleet/nar/{hash_part}.nar", method="HEAD")
        with urlopen(request, timeout=30) as response:
            if response.status != 200:
                raise RuntimeError("cache retention probe failed")
    print(f"Kept {len(set(closure))} paths available; no builds or laptop changes.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--state-dir", type=Path, default=Path("/var/lib/omarchy-update-center"))
    parser.add_argument("--signing-key", default="/etc/ssh/ssh_host_ed25519_key")
    parser.add_argument("--keepalive", action="store_true")
    parser.add_argument("--source", help="Git checkout on this NAS, or HTTPS Git URL")
    parser.add_argument("--revision", help="exact 40-character Git commit (required)")
    parser.add_argument("--notes-file", type=Path)
    parser.add_argument("--devices", nargs="+", choices=DEVICES, default=list(DEVICES))
    args = parser.parse_args()
    if not args.keepalive and not (args.source and args.revision and args.notes_file):
        parser.error("publish requires --source, --revision, and --notes-file")
    state = args.state_dir.resolve()
    state.mkdir(parents=True, exist_ok=True)
    private = state / "private"
    private.mkdir(mode=0o700, exist_ok=True)
    os.environ["XDG_CONFIG_HOME"] = str(private / "config")
    os.environ["XDG_CACHE_HOME"] = str(private / "cache")
    os.umask(0o022)
    with (state / "publish.lock").open("w") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
        if args.keepalive:
            keepalive(state)
        else:
            publish(state, args.source, args.revision, args.notes_file.read_text(), args.devices, args.signing_key)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, RuntimeError, subprocess.TimeoutExpired) as error:
        # A TimeoutExpired exception contains argv; report only its type.
        detail = "command timed out" if isinstance(error, subprocess.TimeoutExpired) else str(error)
        print(f"omarchy-update-center: {detail}", file=sys.stderr)
        sys.exit(1)
