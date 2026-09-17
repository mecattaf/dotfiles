#!/usr/bin/env python3
"""A3/A4/A5/A8 as a standalone runner over a directory of built faces.

Thin wrapper so the assertions can be pointed at any tree by hand:
    python3 tests/coverage.py <dir-of-ttfs>
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "lib"))


def main(argv):
    if len(argv) != 2:
        print("usage: coverage.py <dir-of-ttfs>", file=sys.stderr)
        return 2
    from assert_output import check_face  # noqa: PLC0415

    fails = 0
    for name in sorted(os.listdir(argv[1])):
        if not name.endswith(".ttf"):
            continue
        for line in check_face(os.path.join(argv[1], name)):
            print("FAIL %s: %s" % (name, line))
            fails += 1
    print("coverage: %d failure(s)" % fails)
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
