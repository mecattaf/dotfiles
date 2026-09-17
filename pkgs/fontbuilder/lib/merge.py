#!/usr/bin/env python3
"""fontbuilder stage S4 - completeness merge ("the sweep against JetBrains Mono").

Strictly ADDITIVE: a host codepoint is never overwritten. Every grafted glyph is
named <donorGlyphName>.<tag> so the shipped font carries its own provenance in
the post table (PROVENANCE.tsv is regenerated from it, never maintained by hand).

Tags: jb  JetBrains Mono NFM (OFL-1.1)          dv  DejaVu Sans Mono (Bitstream Vera/Arev)
      maple Maple Mono NF (OFL-1.1)               dvr DejaVu REGULAR weight, the weight fall-through
      jbs/dvs/mps/dvrs  the same donors' UPRIGHT cut sheared 10 deg, the slope fall-through
      synth  the U+2800 blank braille cell when no donor maps it

MEASURED rules (SPEC-v2 S4, 2026-09-17):
  * scale = host ink x-height / donor ink x-height, from each font's own drawn
    'x' bbox, never OS/2 (Maple's OS/2 says 550 while its 'x' tops at 560).
  * braille takes EXACTLY 2.0 on cell-ratio grounds (Maple 600/1000 = host
    1200/2000 = 0.600 em) and an optional dy: the grafted dot lattice's ink
    centre lands at 680 against the cell centre (1985-515)/2 = 735, i.e. 1.17 px
    low in a 54 px cell. dy=+55 centres it. kitty draws braille itself, so this
    affects pango/GTK/foot consumers only.
  * the oversize ceiling is max(host_max_ink, cell*1.10), per face, and it is
    measured on the UNSHEARED outline: the slope fall-through shear inflates ink
    width by tan(10)*height (up to +325 u) and would reject glyphs for being
    italic (U+019D, SemiBold Italic: 1131 accepted vs 1456 sheared). A flat 1200
    ceiling lost U+25D8-25DB (Geometric 92/96) and 237-413 glyphs per italic.
  * Maple italic cuts do not map U+2800 at all (255/256); the blank cell is
    synthesised as a contour-less glyph with advance = cell, then asserted.
  * DejaVu Sans Mono BOLD lacks U+1D670-1D6A3, U+1D7F6-1D7FF and U+038E which
    the Regular cut carries: heavy faces fall through to the Regular donor.
  * the four blocks the first prototype omitted are in TEXTISH: Latin Ext-C,
    Enclosed Alphanumerics, Supplemental Punctuation, Math Alphanumerics.
  * deliberately NOT swept: U+2500-259F (the Nerd patcher owns box/block art
    so cells connect), U+000D, U+FEFF, CJK/Hangul/Arabic/Devanagari/emoji
    (NixOS appends Noto fallbacks after defaultFonts).
"""
import argparse
import json
import math
import os
import sys

from fontTools.misc.transform import Transform
from fontTools.pens.boundsPen import BoundsPen
from fontTools.pens.recordingPen import DecomposingRecordingPen
from fontTools.pens.transformPen import TransformPen
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib import TTFont
from fontTools.ttLib.tables._c_m_a_p import CmapSubtable
from fontTools.ttLib.tables._g_l_y_f import Glyph

TEXTISH = [
    (0x0180, 0x024F), (0x02B0, 0x02FF), (0x0300, 0x036F), (0x0370, 0x03FF),
    (0x0400, 0x04FF), (0x0500, 0x052F), (0x1E00, 0x1EFF),
    (0x2000, 0x206F), (0x2070, 0x209F), (0x20A0, 0x20CF),
    (0x2100, 0x214F), (0x2150, 0x218F), (0x2190, 0x21FF),
    (0x2200, 0x22FF), (0x2300, 0x23FF), (0x2400, 0x243F),
    (0x2460, 0x24FF), (0x25A0, 0x25FF), (0x2600, 0x26FF),
    (0x2700, 0x27BF), (0x27C0, 0x27EF), (0x27F0, 0x27FF),
    (0x2900, 0x29FF), (0x2A00, 0x2AFF), (0x2B00, 0x2BFF),
    (0x2C60, 0x2C7F), (0x2E00, 0x2E7F), (0x1D400, 0x1D7FF),
]
BRAILLE = [(0x2800, 0x28FF)]
NEVER = {0x000D, 0xFEFF}
SHEAR_PIVOT = 540.0   # half the host's 1080 ink x-height (S6 uses the same pivot)
SHEAR_DEG = 10.0


def xheight(font):
    gs = font.getGlyphSet()
    n = font.getBestCmap()[ord("x")]
    bp = BoundsPen(gs)
    gs[n].draw(bp)
    return bp.bounds[3]


def ranges(spec):
    out = set()
    for a, b in spec:
        out.update(range(a, b + 1))
    return out - NEVER


def ensure_format12(font):
    have = {(t.platformID, t.platEncID) for t in font["cmap"].tables}
    base = next(t for t in font["cmap"].tables if t.isUnicode())
    for plat, enc in ((3, 10), (0, 4)):
        if (plat, enc) in have:
            continue
        sub = CmapSubtable.newSubtable(12)
        sub.platformID, sub.platEncID, sub.language = plat, enc, 0
        sub.format, sub.reserved, sub.length, sub.nGroups = 12, 0, 0, 0
        sub.cmap = dict(base.cmap)
        font["cmap"].tables.append(sub)


def donor_table(style):
    """The ordered donor list for one of the 12 styles ('Light' .. 'ExtraBoldItalic')."""
    jbm = os.environ["FONTBUILDER_DONOR_JBM"]
    dvd = os.environ["FONTBUILDER_DONOR_DEJAVU"]
    mpl = os.environ["FONTBUILDER_DONOR_MAPLE"]
    italic = style.endswith("Italic")
    base = style.replace("Italic", "").strip() or "Regular"
    heavy = base in ("SemiBold", "Bold", "ExtraBold")
    jb_it = "Italic" if base == "Regular" else base + "Italic"
    jbf = os.path.join(jbm, "JetBrainsMonoNerdFontMono-%s.ttf" % (jb_it if italic else base))
    jbu = os.path.join(jbm, "JetBrainsMonoNerdFontMono-%s.ttf" % base)
    mpf = os.path.join(mpl, "MapleMono-NF-%s.ttf" % (jb_it if italic else base))
    mpu = os.path.join(mpl, "MapleMono-NF-%s.ttf" % base)
    dv = {
        (False, False): "DejaVuSansMono.ttf", (False, True): "DejaVuSansMono-Oblique.ttf",
        (True, False): "DejaVuSansMono-Bold.ttf", (True, True): "DejaVuSansMono-BoldOblique.ttf",
    }
    dvf = os.path.join(dvd, dv[(heavy, italic)])
    dvu = os.path.join(dvd, dv[(heavy, False)])
    out = [
        dict(tag="jb", path=jbf, ranges=TEXTISH, licence="OFL-1.1"),
        dict(tag="dv", path=dvf, ranges=TEXTISH, licence="Bitstream Vera / Arev"),
        dict(tag="maple", path=mpf, ranges=BRAILLE + TEXTISH, braille_exact=2.0, licence="OFL-1.1"),
    ]
    if heavy:
        # weight fall-through: DejaVu Sans Mono Bold lacks the monospace math
        # alphanumerics (63 codepoints) that the Regular cut carries.
        out.append(dict(tag="dvr", path=os.path.join(dvd, dv[(False, italic)]), ranges=TEXTISH,
                        licence="Bitstream Vera / Arev"))
    if italic:
        # slope fall-through: whatever the italic donors lack, take the upright
        # cut and shear it by the host's own italic transform.
        out += [
            dict(tag="jbs", path=jbu, ranges=TEXTISH, shear=SHEAR_DEG, licence="OFL-1.1"),
            dict(tag="dvs", path=dvu, ranges=TEXTISH, shear=SHEAR_DEG, licence="Bitstream Vera / Arev"),
            dict(tag="mps", path=mpu, ranges=BRAILLE + TEXTISH, braille_exact=2.0, shear=SHEAR_DEG,
                 licence="OFL-1.1"),
        ]
        if heavy:
            out.append(dict(tag="dvrs", path=os.path.join(dvd, "DejaVuSansMono.ttf"), ranges=TEXTISH,
                            shear=SHEAR_DEG, licence="Bitstream Vera / Arev"))
    for d in out:
        if not os.path.isfile(d["path"]):
            sys.exit("merge: donor file missing: %s" % d["path"])
    return out


def graft(host_path, dons, out_path, report_path=None, braille_dy=0):
    host = TTFont(host_path, recalcTimestamp=False)
    ensure_format12(host)
    hglyf, hhmtx = host["glyf"], host["hmtx"]
    hcmap = host.getBestCmap()
    cell = hhmtx["space"][0]
    hx = xheight(host)
    host_max_ink = max((hglyf[n].xMax - hglyf[n].xMin)
                       for n in hglyf.keys() if hglyf[n].numberOfContours)
    ceiling = max(host_max_ink, int(cell * 1.10))
    print("merge: host x-height %d, cell %d, host max ink %d -> ceiling %d" % (hx, cell, host_max_ink, ceiling))
    log, oversize, total = [], [], 0
    for d in dons:
        dfont = TTFont(d["path"], lazy=False)
        dgs, dcm = dfont.getGlyphSet(), dfont.getBestCmap()
        dx = xheight(dfont)
        s_ink = hx / float(dx)
        added = 0
        for cp in sorted(ranges(d["ranges"])):
            if cp in hcmap:
                continue
            gn = dcm.get(cp)
            if gn is None:
                continue
            is_braille = 0x2800 <= cp <= 0x28FF
            s = d["braille_exact"] if (is_braille and d.get("braille_exact")) else s_ink
            dadv = dfont["hmtx"][gn][0]
            dx0 = (cell - dadv * s) / 2.0
            dy = braille_dy if is_braille else 0
            rec = DecomposingRecordingPen(dgs)
            dgs[gn].draw(rec)
            sh = d.get("shear")
            if sh:
                tan = math.tan(math.radians(sh))
                xf = Transform(s, 0, tan * s, s, dx0 - tan * SHEAR_PIVOT, dy)
                # measure the UNSHEARED outline (SPEC-v2 S4(2))
                mpen = TTGlyphPen(None)
                rec.replay(TransformPen(mpen, Transform(s, 0, 0, s, dx0, dy)))
                mg = mpen.glyph()
                mg.recalcBounds(hglyf)
                meas = (mg.xMax - mg.xMin) if mg.numberOfContours else 0
            else:
                xf = Transform(s, 0, 0, s, dx0, dy)
                meas = None
            pen = TTGlyphPen(None)
            rec.replay(TransformPen(pen, xf))
            g = pen.glyph()
            g.recalcBounds(hglyf)
            if meas is None:
                meas = (g.xMax - g.xMin) if g.numberOfContours else 0
            if g.numberOfContours and meas > ceiling:
                oversize.append(("U+%04X" % cp, gn, d["tag"], meas))
                continue
            newname = "%s.%s" % (gn, d["tag"])
            if newname in hglyf.glyphs:
                newname = "uni%04X.%s" % (cp, d["tag"])
            hglyf.glyphs[newname] = g
            host.glyphOrder.append(newname)
            hhmtx.metrics[newname] = (cell, g.xMin if g.numberOfContours else 0)
            hcmap[cp] = newname
            added += 1
        total += added
        log.append(dict(tag=d["tag"], file=d["path"], licence=d.get("licence"),
                        donor_xheight=dx, scale_ink=round(s_ink, 5),
                        shear=d.get("shear", 0), added=added))
        print("merge: %-5s %-44s x-h %4d scale %.5f%s added %d" % (
            d["tag"], os.path.basename(d["path"]), dx, s_ink,
            " shear" if d.get("shear") else "      ", added))
    synth = None
    if 0x2800 not in hcmap:
        g = Glyph()
        g.numberOfContours = 0
        g.xMin = g.yMin = g.xMax = g.yMax = 0
        synth = "uni2800.synth"
        hglyf.glyphs[synth] = g
        host.glyphOrder.append(synth)
        hhmtx.metrics[synth] = (cell, 0)
        hcmap[0x2800] = synth
        total += 1
        print("merge: synthesised U+2800 (blank braille cell) as %s, advance %d" % (synth, cell))
    braille = sum(1 for c in range(0x2800, 0x2900) if c in hcmap)
    assert braille == 256, "braille coverage %d/256" % braille
    host.setGlyphOrder(host.glyphOrder)
    bmp = {k: v for k, v in hcmap.items() if k <= 0xFFFF}
    subs = []
    for pid, eid in ((0, 3), (3, 1)):
        t = CmapSubtable.newSubtable(4)
        t.platformID, t.platEncID, t.language = pid, eid, 0
        t.cmap = dict(bmp)
        subs.append(t)
    for pid, eid in ((0, 4), (3, 10)):
        t = CmapSubtable.newSubtable(12)
        t.platformID, t.platEncID, t.language = pid, eid, 0
        t.format, t.reserved, t.length, t.nGroups = 12, 0, 0, 0
        t.cmap = dict(hcmap)
        subs.append(t)
    host["cmap"].tables = subs
    names = [n for n in hglyf.keys() if hglyf[n].numberOfContours]
    host["head"].yMin = min(hglyf[n].yMin for n in names)
    host["head"].yMax = max(hglyf[n].yMax for n in names)
    host["maxp"].recalc(host)
    advances = {a for a, _ in hhmtx.metrics.values()}
    assert advances == {cell}, "advance set %s != {%d}" % (sorted(advances), cell)
    host.save(out_path)
    rep = dict(host_xheight=hx, cell=cell, host_max_ink=host_max_ink, ceiling=ceiling,
               braille_dy=braille_dy, donors=log, total_added=total, braille=braille,
               synthesised_2800=synth, oversize_skipped=oversize,
               codepoints=len(hcmap), glyphs=len(host.getGlyphOrder()))
    if report_path:
        with open(report_path, "w", encoding="utf-8") as fh:
            json.dump(rep, fh, indent=1)
    print("merge: total added %d -> %d codepoints / %d glyphs, braille %d/256, oversize skipped %d"
          % (total, len(hcmap), len(host.getGlyphOrder()), braille, len(oversize)))
    return rep


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--in", dest="inp", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--style", required=True, help="Light .. ExtraBoldItalic")
    ap.add_argument("--braille-dy", type=int, default=55)
    ap.add_argument("--report")
    a = ap.parse_args()
    graft(a.inp, donor_table(a.style), a.out, a.report, a.braille_dy)
