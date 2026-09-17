#!/usr/bin/env python3
"""fontbuilder stage S6 - ligature vertical alignment (after S5, before S7).

Fira Code and Anthropic Mono put their math strokes on different axes (host
hyphen centre 735, Fira rescaled 642: 93 units = 1.98 px at 16 pt on a scale-2
output against a 3.37 px dash). This stage re-seats each copied lig.N glyph by
a delta measured DIRECTLY from the two fonts' own drawings of the ligature's
constituent characters, so it is right for every weight and for the italics:

    dy(lig) = mean over c in set(constituents(lig)) of
                ( ycentre_host(c) - ycentre_donor(c) * host_em/donor_em )

  * ANCHOR veto: if any constituent is in ANCHOR the ligature keeps Fira's
    drawing verbatim (dy = 0). The veto leaves the outline SHAPE untouched; on
    italics the uniform shear below still applies to every lig.N.
  * clamp: |dy| > 0.08 em -> skip and log (asciicircum_equal, -164..-168).
  * --mode none: dy = 0 for every ligature (the honest fallback, Fira's art as
    copied); the shear still applies on italics. Exists so the align gate can
    compare anchor vs none by looking.
  * --slant 10 (italics): shear every lig.N by tan(10 deg) about y=540 (half
    the host's 1080 ink x-height; the host's own italic measures 9.97-10.01 deg
    with pivot 534-539). MEASURED DEFECT FIX: the shear moves xMin but hmtx kept
    the pre-shear lsb, and FontForge inside nerd-font-patcher re-seats every
    outline so xMin == stored lsb, translating each sheared ligature by up to
    120 units. On the sheared path lsb is set to xMin. Roman lsb is untouched.

Measured outcome on all 12 faces: {shift: 100, anchor-veto: 35, clamped: 1},
dy range -61..+93 (63 of 100 shifts below +76; slash-family -61 self-corrects).
Known accepted residuals (pinned by tests, TOL=70): bar in || vs {| [| (53.5 u),
equal in == vs #= (66.75 u), underscore in __ vs _ (104.5 u, vetoed).
"""
import argparse
import collections
import importlib.util
import json
import math

from fontTools.pens.boundsPen import BoundsPen
from fontTools.ttLib import TTFont

ANCHOR = {"numbersign", "percent", "w", "dollar", "braceleft", "braceright",
          "bracketleft", "bracketright", "parenleft", "parenright", "ampersand",
          "at", "underscore", "backslash", "asterisk"}


def lig_map(ligatures_py, donor):
    """Reconstruct lig.N -> spec exactly as ligaturize.py numbered them."""
    spec = importlib.util.spec_from_file_location("lg", ligatures_py)
    m = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(m)
    gs = donor.getGlyphSet()
    out, n = {}, 0
    for sp in sorted(m.ligatures, key=lambda l: len(l["chars"])):
        fn = sp["firacode_ligature_name"]
        if fn is None or fn not in gs:
            continue
        n += 1
        out["lig.%d" % n] = sp
    return out


def centres(font):
    gs = font.getGlyphSet()
    upm = font["head"].unitsPerEm
    out = {}
    for n in gs.keys():
        bp = BoundsPen(gs)
        try:
            gs[n].draw(bp)
        except Exception:  # noqa: BLE001
            continue
        if bp.bounds:
            out[n] = ((bp.bounds[1] + bp.bounds[3]) / 2.0, bp.bounds)
    return out, upm


def shear_glyph(glyf, gname, tan, pivot, hmtx):
    g = glyf[gname]
    if g.numberOfContours <= 0:
        return
    for i in range(len(g.coordinates)):
        x, y = g.coordinates[i]
        g.coordinates[i] = (int(round(x + tan * (y - pivot))), y)
    g.recalcBounds(glyf)
    adv, _ = hmtx[gname]
    hmtx[gname] = (adv, g.xMin)


def run(inp, out, ligatures_py, donor_otf, mode="anchor", slant=None, report=None, clamp_em=0.08):
    f = TTFont(inp, recalcTimestamp=False)
    donor = TTFont(donor_otf, lazy=True)
    hc, hupm = centres(f)
    dc, dupm = centres(donor)
    scale = hupm / float(dupm)
    clamp = clamp_em * hupm
    glyf = f["glyf"]
    mp = lig_map(ligatures_py, donor)
    log = []
    for gname, sp in mp.items():
        if gname not in glyf.glyphs:
            continue
        cs = sp["chars"]
        lig = sp["firacode_ligature_name"].replace(".liga", "")
        if mode == "none":
            log.append(dict(glyph=gname, lig=lig, dy=0, mode="none"))
            continue
        if set(cs) & ANCHOR:
            log.append(dict(glyph=gname, lig=lig, dy=0, mode="anchor-veto"))
            continue
        ds = [hc[c][0] - dc[c][0] * scale for c in set(cs) if c in hc and c in dc]
        if not ds:
            log.append(dict(glyph=gname, lig=lig, dy=0, mode="no-reference"))
            continue
        dy = int(round(sum(ds) / len(ds)))
        if abs(dy) > clamp:
            log.append(dict(glyph=gname, lig=lig, dy=dy, mode="clamped"))
            continue
        if dy:
            g = glyf[gname]
            for i in range(len(g.coordinates)):
                x, y = g.coordinates[i]
                g.coordinates[i] = (x, y + dy)
            g.recalcBounds(glyf)
        log.append(dict(glyph=gname, lig=lig, dy=dy, mode="shift"))
    sheared = 0
    pivot = None
    if slant:
        tan = math.tan(math.radians(abs(slant)))
        xh = hc[f.getBestCmap()[ord("x")]][1][3]
        pivot = xh / 2.0
        for gname in mp:
            if gname in glyf.glyphs:
                shear_glyph(glyf, gname, tan, pivot, f["hmtx"])
                sheared += 1
    names = [n for n in glyf.keys() if glyf[n].numberOfContours]
    f["head"].yMin = min(glyf[n].yMin for n in names)
    f["head"].yMax = max(glyf[n].yMax for n in names)
    f.save(out)
    modes = dict(collections.Counter(l["mode"] for l in log))
    hist = sorted(collections.Counter(l["dy"] for l in log if l["mode"] == "shift").items())
    rep = dict(mode=mode, host_upm=hupm, donor_upm=dupm, scale=scale, slant=slant, pivot=pivot,
               sheared=sheared, modes=modes, dy_histogram=hist, ligatures=log)
    if report:
        with open(report, "w", encoding="utf-8") as fh:
            json.dump(rep, fh, indent=1)
    print("align: mode=%s modes=%s sheared=%d dy=[%s..%s]" % (
        mode, modes, sheared, hist[0][0] if hist else "-", hist[-1][0] if hist else "-"))
    return rep


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--in", dest="inp", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--mode", choices=["anchor", "none"], default="anchor")
    ap.add_argument("--ligatures", required=True, help="Ligaturizer's ligatures.py")
    ap.add_argument("--donor", required=True, help="the FiraCode-*.otf used by S5")
    ap.add_argument("--slant", type=float, default=None)
    ap.add_argument("--report")
    a = ap.parse_args()
    run(a.inp, a.out, a.ligatures, a.donor, a.mode, a.slant, a.report)
