#!/usr/bin/env python3
"""A12 - the Serif fvar-default move, as a TOLERANCE test over a GRID.

    tests/a12.py <capture-dir> <out-dir>

v1's wording ("bbox-identical to the same instances taken from the untouched
source") is FALSE and this file is the refutation, lifted from
$P3/refute-C8/a12_grid.py.  Moving an fvar default NECESSARILY re-rounds the
base glyf outlines (432 of 747 glyphs rewritten) and rebases gvar (7,688 ->
10,359 tuples).  What is preserved is fidelity within a measured tolerance:

    control point   <= 2 units at 2000 upm   (worst observed 1.5015)
    RAW glyph bbox  <= 1 unit                (worst observed 0.5000)
    advance         <= 1 unit                (worst exactly -1 u on 93
                                              glyph-instances, concentrated at
                                              wght 600)

THREE IMPLEMENTATION RULES, EACH FROM A MEASURED FALSE FAILURE:

 1. The grid MUST include off-default opsz AND off-endpoint wght.  v1's 3x2
    grid is exactly why this was missed: at opsz=16 the raw bboxes ARE
    identical at wght 300/400/800, so a literal v1 implementation PASSES while
    283 glyphs have moved.  The grid here is wght {300,400,500,600,700,800} x
    opsz {16,24,32,48} = 24 probes.

 2. NEVER compare `tuple(round(x) for x in bounds)`.  Banker's rounding flips
    at half-integer coordinates (77.5 vs 77.49683 -> 78 vs 77) and produced
    742 false failures.  Compare the RAW floats against a tolerance.

 3. The advance tolerance is 1 unit, not 0.

Also: do NOT assert the STAT ElidedFallbackNameID STRING against the source.
S9 deliberately resets it from `Text Regular` to `Regular`.  Assert only that
it is non-zero.  And compare fvar instances by RESOLVED STRING, never by
nameID: S9 reassigns nameIDs (unshare -> re-point -> strip -> gc).
"""
from __future__ import annotations

import argparse
import os
import sys

from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.recordingPen import DecomposingRecordingPen
from fontTools.ttLib import TTFont
from fontTools.varLib.instancer import instantiateVariableFont as inst

PT_TOL, BB_TOL, ADV_TOL = 2.0, 1.0, 1
WGHT = (300, 400, 500, 600, 700, 800)
OPSZ = (16, 24, 32, 48)
WANT_AXES = [("wght", 300, 400, 800), ("opsz", 16, 16, 48)]

# where the repaired Serif may live, most specific first.  Running on the S2b
# output (before normalize) is preferred because then the name-table
# assertions are exact; on the shipped face they are string comparisons.
CANDIDATES = [
    os.path.join("work", "s2b", "AnthropicSerif-Roman.ttf"),
    os.path.join("work", "serif-s2b", "AnthropicSerif-Roman.ttf"),
    os.path.join("work", "AnthropicSerif-Roman-s2b.ttf"),
    os.path.join("desktop", "AnthropicSerif-Roman.ttf"),
]


def instance_strings(f):
    n = f["name"]
    return [(tuple(sorted(i.coordinates.items())), n.getDebugName(i.subfamilyNameID))
            for i in f["fvar"].instances]


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("capture", help="the READ-ONLY capture dir holding the untouched Serif")
    ap.add_argument("out")
    ap.add_argument("--src", default=None,
                    help="accepted and ignored; the capture dir is the first positional here")
    ap.add_argument("--allow-partial", action="store_true",
                    help="accepted and ignored; A12 needs only the one Serif face")
    a = ap.parse_args(argv[1:])
    capture, out = os.path.abspath(a.capture), os.path.abspath(a.out)
    src = os.path.join(capture, "fonts-ttf", "AnthropicSerif-Roman-Web.ttf")
    dst = None
    for rel in CANDIDATES:
        p = os.path.join(out, rel)
        if os.path.exists(p):
            dst = p
            break
    fails = []
    if not os.path.exists(src):
        print("FAIL A12: no untouched Serif source at %s" % src)
        return 1
    if dst is None:
        print("FAIL A12: no repaired Serif in the out-dir (looked for %s)" % CANDIDATES)
        return 1
    print("A12 source %s" % src)
    print("A12 under test %s" % dst)

    f = TTFont(dst, recalcTimestamp=False)
    s = TTFont(src, recalcTimestamp=False)

    ax = [(a.axisTag, a.minValue, a.defaultValue, a.maxValue) for a in f["fvar"].axes]
    if ax != WANT_AXES:
        fails.append("fvar axes %s != %s" % (ax, WANT_AXES))
    a_i, s_i = instance_strings(f), instance_strings(s)
    if a_i != s_i:
        bad = [(x, y) for x, y in zip(a_i, s_i) if x != y]
        fails.append("named instances differ (coords, resolved subfamily string): %s" % bad[:4])
    if len(f["fvar"].instances) != 12:
        fails.append("%d named instances, expected 12" % len(f["fvar"].instances))
    if f["OS/2"].usWeightClass != 400:
        fails.append("usWeightClass %d != 400" % f["OS/2"].usWeightClass)
    if set(f["gvar"].variations) != set(s["gvar"].variations):
        fails.append("gvar glyph set changed")
    st, ss = f["STAT"].table, s["STAT"].table
    na = len(st.AxisValueArray.AxisValue)
    ns = len(ss.AxisValueArray.AxisValue)
    if na != ns:
        fails.append("STAT AxisValue count %d != %d" % (na, ns))
    if not st.ElidedFallbackNameID:
        # the STRING is deliberately reset by S9 - only non-zero is asserted
        fails.append("STAT ElidedFallbackNameID is 0")

    bad = []
    for w in WGHT:
        for o in OPSZ:
            a = inst(TTFont(src, recalcTimestamp=False), {"wght": w, "opsz": o},
                     inplace=True, updateFontNames=False)
            b = inst(TTFont(dst, recalcTimestamp=False), {"wght": w, "opsz": o},
                     inplace=True, updateFontNames=False)
            if a.getGlyphOrder() != b.getGlyphOrder():
                bad.append(("<glyph order>", w, o, "glyph order"))
                continue
            ga, gb = a.getGlyphSet(), b.getGlyphSet()
            for g in a.getGlyphOrder():
                pa, pb = DecomposingRecordingPen(ga), DecomposingRecordingPen(gb)
                ga[g].draw(pa)
                gb[g].draw(pb)
                if [op for op, _ in pa.value] != [op for op, _ in pb.value]:
                    bad.append((g, w, o, "contour structure"))
                    continue
                for (_, u), (_, v) in zip(pa.value, pb.value):
                    for p, q in zip(u, v):
                        if max(abs(p[0] - q[0]), abs(p[1] - q[1])) > PT_TOL:
                            bad.append((g, w, o, "point > %g u" % PT_TOL))
                if abs(a["hmtx"][g][0] - b["hmtx"][g][0]) > ADV_TOL:
                    bad.append((g, w, o, "advance > %d u" % ADV_TOL))
                Ba, Bb = BoundsPen(ga), BoundsPen(gb)
                ga[g].draw(Ba)
                gb[g].draw(Bb)
                if (Ba.bounds is None) != (Bb.bounds is None):
                    bad.append((g, w, o, "bbox none"))
                elif Ba.bounds and max(abs(x - y) for x, y in zip(Ba.bounds, Bb.bounds)) > BB_TOL:
                    # RAW bbox.  NEVER round() - see rule 2 in the docstring.
                    bad.append((g, w, o, "bbox > %g u" % BB_TOL))
    print("A12 grid: %d probes (wght %s x opsz %s), %d glyph-instance failures"
          % (len(WGHT) * len(OPSZ), list(WGHT), list(OPSZ), len(bad)))
    for x in bad[:10]:
        fails.append("grid %s" % (x,))
    for f_ in fails:
        print("FAIL A12:", f_)
    return 1 if fails else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
