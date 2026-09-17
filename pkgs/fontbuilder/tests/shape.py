#!/usr/bin/env python3
"""A2 - KITTY SHAPING, through kitty's own renderer.

    tests/shape.py <out-dir>

`'x -> y'` must group (2,2,...) and `'c ==> d'` must group (3,3,...): that is
the ligature actually firing, not a substring of the family name suggesting it.
Then U+E0B0, U+F001, U+276F, U+2588, U+28FF, U+2800, U+03BB, U+0410, U+2718,
U+1D538 and U+F07E5 must each shape to ONE non-.notdef glyph FROM THE MAIN
FONT - a fallback here is the silent failure mode the 2026-08-21 incident was
made of.

ONE PROCESS PER FALLBACK LOOKUP.  Batching more than two get_fallback_font()
calls trips kitty's "Too many fallback fonts" limit, after which every later
call returns "returned a result with an exception set" - a silent false pass.
This runner therefore spawns a fresh `kitty +runpy` per codepoint that needs a
fallback decision, and a single one for the ligature-grouping half.

`kitty +runpy` wants a tty, so every call is wrapped in
`script -qec '...' /dev/null`.  No compositor and no kitty window: +runpy is
headless python inside kitty's runtime.  FONTCONFIG_FILE and XDG_CACHE_HOME are
both redirected under <out>/verify; fc-cache is never invoked.
"""
from __future__ import annotations

import json
import os
import shlex
import subprocess
import sys

from fontTools.ttLib import TTFont

# family string -> the face it must resolve to.  The bare nameID4 forms are
# used here deliberately: shape_string takes a family, not a FontSpec, and
# these are exactly the strings A1 demotes but does not forbid.
FAMILIES = {"AnthropicMono NFM": "Regular",
            "AnthropicMono NFM SemiBold": "SemiBold",
            "AnthropicMono NFM Italic": "Italic",
            "AnthropicMono NFM SemiBold Italic": "SemiBoldItalic"}
LIGATURES = [("x -> y", 2), ("c ==> d", 3), ("a != b", 2), ("p <=> q", 3), ("f /= g", 2)]
CODEPOINTS = [("U+E0B0", ""), ("U+F001", ""), ("U+276F", "❯"),
              ("U+2588", "█"), ("U+28FF", "⣿"), ("U+2800", "⠀"),
              ("U+03BB", "λ"), ("U+0410", "А"), ("U+2718", "✘"),
              ("U+1D538", "\U0001D538"), ("U+F07E5", "\U000F07E5")]

LIG_PROBE = r'''
import json, os
from kitty.fonts.render import shape_string
out = {}
for fam in json.loads(os.environ["A2_FAMILIES"]):
    rows = {}
    for text in json.loads(os.environ["A2_TEXTS"]):
        # a run is (chars_consumed, cells_occupied, primary_glyph, glyph_tuple);
        # the GROUP is the first pair, never the glyph id
        rows[text] = [[r[0], r[1]] for r in shape_string(text, family=fam, size=16.0)]
    out[fam] = rows
open(os.environ["A2_JSON"], "w").write(json.dumps(out))
'''

# ONE codepoint per process.  cell_count is the number of cells the glyph
# occupies; glyph id 0 is .notdef.
CP_PROBE = r'''
import json, os
from kitty.fonts.render import shape_string
fam = os.environ["A2_FAMILY"]
ch = json.loads(os.environ["A2_CHAR"])
# path= loads THIS face as the main font: the question is whether kitty shapes
# the codepoint from the face itself or reaches for a fallback, and a bare
# family string (the demoted nameID4 form) can resolve to a different face or
# to none under a private fontconfig - measured 2026-09-17 on "AnthropicMono NFM
# SemiBold Italic", which shaped from a fallback while the family=/style= form
# resolved correctly.
res = shape_string(ch, family=fam, size=16.0, path=os.environ["A2_PATH"])
out = {"runs": [[r[0], r[1], r[2], r[3]] for r in res]}
open(os.environ["A2_JSON"], "w").write(json.dumps(out, default=str))
'''


# This runner spawns ~45 kitty processes (one per fallback lookup - see the
# module docstring).  Measured once in 7 consecutive suite runs: a single spawn
# produced no JSON with no diagnostic, which would have been an unreproducible
# FAIL.  Two defences: every probe gets its OWN result path, so no two runs can
# ever read a stale file, and a spawn that yields nothing is retried once
# before it is believed.  A real shaping failure still fails - it produces JSON
# with the wrong contents, not no JSON.
SPAWN_ATTEMPTS = 2


def runpy(probe_path, env_extra, jsonpath):
    inner = ("exec(compile(open(%s).read(), 'a2_probe', 'exec'), {'__name__': '__main__'})"
             % repr(probe_path))
    last = None
    for attempt in range(SPAWN_ATTEMPTS):
        env = dict(os.environ)
        env.update(env_extra)
        env["A2_JSON"] = jsonpath
        if os.path.exists(jsonpath):
            os.unlink(jsonpath)
        last = subprocess.run(["script", "-qec", "kitty +runpy " + shlex.quote(inner), "/dev/null"],
                              capture_output=True, text=True, env=env, check=False)
        if os.path.exists(jsonpath):
            with open(jsonpath) as fh:
                return json.load(fh), last
        if attempt + 1 < SPAWN_ATTEMPTS:
            print("shape: kitty produced no JSON for %s, retrying once"
                  % os.path.basename(jsonpath), file=sys.stderr)
    return None, last


def main(argv):
    if len(argv) != 2:
        print("usage: shape.py <out-dir>", file=sys.stderr)
        return 2
    out = os.path.abspath(argv[1])
    verify = os.path.join(out, "verify")
    xdg = os.path.join(verify, "xdg")
    os.makedirs(xdg, exist_ok=True)

    here = os.path.dirname(os.path.abspath(__file__))
    tpl = open(os.path.join(here, "fonts.conf.in")).read()
    cachedir = os.path.join(verify, "cache-a2")
    os.makedirs(cachedir, exist_ok=True)
    conf = os.path.join(verify, "fonts-a2.conf")
    dirs = "\n".join("  <dir>%s</dir>" % os.path.join(out, d) for d in ("nf", "desktop"))
    with open(conf, "w") as fh:
        fh.write(tpl.replace("@CACHEDIR@", cachedir).replace("@FONTDIR@", dirs))
    base = {"FONTCONFIG_FILE": conf, "XDG_CACHE_HOME": xdg}
    os.environ.pop("FONTCONFIG_PATH", None)

    lig_probe = os.path.join(verify, "a2_lig_probe.py")
    with open(lig_probe, "w") as fh:
        fh.write(LIG_PROBE)
    cp_probe = os.path.join(verify, "a2_cp_probe.py")
    with open(cp_probe, "w") as fh:
        fh.write(CP_PROBE)
    cpdir = os.path.join(verify, "a2-codepoints")
    os.makedirs(cpdir, exist_ok=True)

    fails, report = [], {}

    env = dict(base)
    env["A2_FAMILIES"] = json.dumps(sorted(FAMILIES))
    env["A2_TEXTS"] = json.dumps([t for t, _ in LIGATURES])
    res, p = runpy(lig_probe, env, os.path.join(verify, "a2-lig.json"))
    if res is None:
        fails.append("A2 ligatures: the probe produced no JSON. kitty stderr: %s"
                     % (p.stderr or p.stdout or "").strip()[-600:])
    else:
        report["ligatures"] = res
        for fam in sorted(FAMILIES):
            rows = res.get(fam, {})
            for text, want in LIGATURES:
                groups = rows.get(text)
                if groups is None:
                    fails.append("A2 %s: no shaping result for %r" % (fam, text))
                elif [want, want] not in groups:
                    fails.append("A2 %s: %r groups %s, expected a (%d,%d) run - the ligature "
                                 "did not fire" % (fam, text, groups, want, want))

    # ONE PROCESS PER CODEPOINT (the fallback limit).  "from the MAIN font" is
    # asserted by comparing kitty's glyph id against the glyph index the face
    # itself gives for that codepoint - a fallback font would hand back a
    # different index.  That is the check the 2026-08-21 incident needed.
    report["codepoints"] = {}
    for fam, style in sorted(FAMILIES.items()):
        report["codepoints"][fam] = {}
        face = os.path.join(out, "nf", "AnthropicMonoNerdFontMono-%s.ttf" % style)
        if not os.path.exists(face):
            fails.append("A2 %s: no face at %s" % (fam, face))
            continue
        tf = TTFont(face, recalcTimestamp=False, recalcBBoxes=False)
        cmap = tf.getBestCmap()
        for label, ch in CODEPOINTS:
            env = dict(base)
            env["A2_FAMILY"] = fam
            env["A2_PATH"] = face
            env["A2_CHAR"] = json.dumps(ch)
            safe = "%s-%s" % (fam.replace(" ", "_"), label.replace("+", ""))
            res, p = runpy(cp_probe, env, os.path.join(cpdir, "%s.json" % safe))
            if res is None:
                fails.append("A2 %s %s: the probe produced no JSON. kitty stderr: %s"
                             % (fam, label, (p.stderr or p.stdout or "").strip()[-400:]))
                continue
            runs = res["runs"]
            report["codepoints"][fam][label] = runs
            if len(runs) != 1:
                fails.append("A2 %s %s: shaped to %d runs, expected 1" % (fam, label, len(runs)))
                continue
            nchars, cells, gid, _gids = runs[0]
            if gid == 0:
                fails.append("A2 %s %s: shaped to .notdef" % (fam, label))
                continue
            if cells != 1:
                fails.append("A2 %s %s: occupies %s cells, expected 1" % (fam, label, cells))
            cp = ord(ch)
            name = cmap.get(cp)
            if name is None:
                fails.append("A2 %s %s: the face does not map this codepoint at all" % (fam, label))
                continue
            want_gid = tf.getGlyphID(name)
            if gid != want_gid:
                fails.append("A2 %s %s: kitty shaped glyph id %d, the face's own index for %r "
                             "is %d - this came from a FALLBACK font, not the main one"
                             % (fam, label, gid, name, want_gid))

    with open(os.path.join(verify, "shape.json"), "w") as fh:
        json.dump({"report": report, "failures": fails}, fh, indent=1, default=str)
    for f in fails:
        print("FAIL", f)
    print("shape: %d failure(s) -> %s/shape.json" % (len(fails), verify))
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
