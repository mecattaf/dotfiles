#!/usr/bin/env python3
"""Make a diagnostic source variant; it must never serve production sessions.

Only attached-byte latency is meaningful: reconnect and capture are knowingly
broken in this variant. Its distinct version is rejected by the NAS adapter.
"""

import argparse
from pathlib import Path
import shutil


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True, type=Path)
    parser.add_argument("--destination", required=True, type=Path)
    args = parser.parse_args()
    if args.destination.exists():
        raise SystemExit("diagnostic destination already exists; it is never overwritten")
    version = (args.source / "build.zig.zon").read_text()
    if '.version = "1.0.1-agency.2"' not in version:
        raise SystemExit("only the exact qualified version-2 source is supported")
    shutil.copytree(args.source, args.destination,
                    ignore=shutil.ignore_patterns(".git", ".zig-cache", "zig-out", "zig-pkg"))
    path = args.destination / "src/loop.zig"
    content = path.read_text()
    needle = "vt_stream.nextSlice(buf[0..n]);"
    if content.count(needle) != 1:
        raise SystemExit("unexpected shadow parser source shape")
    path.write_text(content.replace(needle, "// Diagnostic build: skip shadow parsing for attached-byte comparison."))
    (args.destination / "build.zig.zon").write_text(version.replace('"1.0.1-agency.2"', '"1.0.1-agency.2-noshadow"'))


if __name__ == "__main__":
    main()
