#!/usr/bin/env python3
"""fontbuilder stage S0 - verify the capture tree against the pinned digests.

This is the stage that makes the whole package INERT. `pkgs/fontbuilder` ships
scripts and JSON and no font bytes; it will build and its checkPhase will pass
on a machine that has never seen ~/colors. Running it against anything other
than the exact captured source tree exits 2 and prints one line.
"""
import hashlib
import os
import sys

EXIT_BAD_SOURCES = 2


def digest(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def check(src_dir, sha_file):
    """Return a list of (relpath, reason) for every entry that does not match."""
    bad = []
    with open(sha_file, "r", encoding="utf-8") as fh:
        for line in fh:
            line = line.rstrip("\n")
            if not line.strip():
                continue
            want, _, rel = line.partition("  ")
            rel = rel.strip()
            path = os.path.join(src_dir, rel)
            if not os.path.isfile(path):
                bad.append((rel, "missing"))
                continue
            got = digest(path)
            if got != want:
                bad.append((rel, "sha256 %s != pinned %s" % (got, want)))
    return bad


def main(argv):
    if len(argv) != 3:
        print("usage: verify_sources.py <capture-dir> <sources.sha256>", file=sys.stderr)
        return EXIT_BAD_SOURCES
    bad = check(argv[1], argv[2])
    if bad:
        print("fontbuilder: source tree does not match the pinned digests", file=sys.stderr)
        for rel, why in bad:
            print("  %s: %s" % (rel, why), file=sys.stderr)
        return EXIT_BAD_SOURCES
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
