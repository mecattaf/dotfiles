#!/usr/bin/env python3
"""Cell geometry, INFORMATIONAL - no assertion, nothing here can fail a build.

    tests/geometry.py <out-dir>

Prints the terminal cell width x height at 16.0 pt for 96 and 192 dpi, for the
new face and for the currently installed Liga SFMono, straight out of kitty's
own `create_test_font_group` (via kitty.fonts.render.setup_for_testing).  These
are the numbers quoted in the kitty.conf comment: the Anthropic cell is taller,
so the same pixel height gives fewer rows, and `modify_font cell_height -6%` is
the lever if that density is wanted back.

It runs under a config that carries BOTH <out>/nf and the system font dirs,
because Liga SFMono is a system font and the comparison is the whole point.
`kitty +runpy` wants a tty, so the call is wrapped in
`script -qec '...' /dev/null`.  No window is opened.  fc-cache is never
invoked; FONTCONFIG_FILE and XDG_CACHE_HOME are both redirected.

Exit status is 0 unless kitty itself could not be run.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shlex
import subprocess
import sys

FAMILIES = ["AnthropicMono NFM", "Liga SFMono Nerd Font", "JetBrainsMono NFM"]
SIZES = [16.0]
DPIS = [96.0, 192.0]

PROBE = r'''
import json, os
from kitty.fonts.render import setup_for_testing
rows = []
for fam in json.loads(os.environ["GEO_FAMILIES"]):
    for size in json.loads(os.environ["GEO_SIZES"]):
        for dpi in json.loads(os.environ["GEO_DPIS"]):
            try:
                with setup_for_testing(fam, size, dpi) as (sprites, cw, ch):
                    rows.append([fam, size, dpi, cw, ch])
            except Exception as e:
                rows.append([fam, size, dpi, None, str(e)])
open(os.environ["GEO_JSON"], "w").write(json.dumps(rows))
'''


def system_font_dirs():
    dirs = []
    for p in ["/etc/fonts/fonts.conf", "/etc/fonts/conf.d/00-nixos-cache.conf"]:
        try:
            text = open(p).read()
        except OSError:
            continue
        for d in re.findall(r"<dir>([^<]+)</dir>", text):
            if os.path.isdir(d) and d not in dirs:
                dirs.append(d)
    return dirs


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("--src", default=None, help="accepted and ignored (uniform driver CLI)")
    ap.add_argument("--allow-partial", action="store_true",
                    help="accepted and ignored; this test asserts nothing")
    a = ap.parse_args(argv[1:])
    out = os.path.abspath(a.out)
    verify = os.path.join(out, "verify")
    xdg = os.path.join(verify, "xdg")
    cachedir = os.path.join(verify, "cache-geometry")
    os.makedirs(xdg, exist_ok=True)
    os.makedirs(cachedir, exist_ok=True)

    here = os.path.dirname(os.path.abspath(__file__))
    tpl = open(os.path.join(here, "fonts.conf.in")).read()
    dirs = [os.path.join(out, "nf"), os.path.join(out, "desktop")] + system_font_dirs()
    body = "\n".join("  <dir>%s</dir>" % d for d in dirs)
    conf = os.path.join(verify, "fonts-geometry.conf")
    with open(conf, "w") as fh:
        fh.write(tpl.replace("@CACHEDIR@", cachedir).replace("@FONTDIR@", body))

    probe = os.path.join(verify, "geo_probe.py")
    with open(probe, "w") as fh:
        fh.write(PROBE)
    jsonpath = os.path.join(verify, "geometry.json")
    if os.path.exists(jsonpath):
        os.unlink(jsonpath)

    env = dict(os.environ)
    env["FONTCONFIG_FILE"] = conf
    env["XDG_CACHE_HOME"] = xdg
    env.pop("FONTCONFIG_PATH", None)
    env["GEO_FAMILIES"] = json.dumps(FAMILIES)
    env["GEO_SIZES"] = json.dumps(SIZES)
    env["GEO_DPIS"] = json.dumps(DPIS)
    env["GEO_JSON"] = jsonpath
    inner = ("exec(compile(open(%s).read(), 'geo_probe', 'exec'), {'__name__': '__main__'})"
             % repr(probe))
    # one retry: a kitty spawn that yields nothing is a flake, not a result
    for _ in range(2):
        p = subprocess.run(["script", "-qec", "kitty +runpy " + shlex.quote(inner), "/dev/null"],
                           capture_output=True, text=True, env=env, check=False)
        if os.path.exists(jsonpath):
            break
    if not os.path.exists(jsonpath):
        print("geometry: kitty produced no result:", (p.stderr or p.stdout or "").strip()[-600:],
              file=sys.stderr)
        return 1

    rows = json.load(open(jsonpath))
    print("%-24s %6s %6s %7s %7s %8s" % ("family", "size", "dpi", "cell_w", "cell_h", "w/h"))
    base = {}
    for fam, size, dpi, cw, ch in rows:
        if cw is None:
            print("%-24s %6.1f %6.0f   ERR %s" % (fam, size, dpi, ch))
            continue
        print("%-24s %6.1f %6.0f %7d %7d %8.4f" % (fam, size, dpi, cw, ch, cw / ch))
        base.setdefault((size, dpi), {})[fam] = (cw, ch)
    print()
    for key in sorted(base):
        cells = base[key]
        if FAMILIES[0] in cells and FAMILIES[1] in cells:
            aw, ah = cells[FAMILIES[0]]
            lw, lh = cells[FAMILIES[1]]
            print("at %.1f pt / %.0f dpi: %s is %+.2f%% wide and %+.2f%% tall relative to %s"
                  % (key[0], key[1], FAMILIES[1], (lw / aw - 1) * 100, (lh / ah - 1) * 100,
                     FAMILIES[0]))
    print("\ngeometry: informational only, no assertion -> %s" % jsonpath)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
