#!/usr/bin/env python3
"""fontbuilder stage S7b - re-graft the Anthropic PUA glyphs the patcher overwrote.

MEASURED (SPEC-v2 E23, C19): `nerd-font-patcher --complete` destructively
overwrites U+E001..U+E00A with Pomicons (Edotbelowacute -> POMODORO_DONE ...)
and the displaced glyphs are gone from the font entirely. `--careful` is not
the fix (it also stops the patcher redrawing cell-filling box/block art) and
naming every icon set except --pomicons is not either (nameID16 grows to 183
chars with ERROR lines). So: after S7, take those ten glyphs from the S6
aligned face, install them as <name>.apua and point every Unicode cmap
subtable back at them. The orphaned Pomicons outlines stay, uncmapped.

Mechanics that were measured to matter: append to glyf.glyphOrder AND call
font.setGlyphOrder, assigning glyf.glyphs[name] directly; `glyf[name] = g`
alone desynchronises glyphOrder and the save dies in maxp.recalc.
"""
import argparse

from fontTools.pens.recordingPen import DecomposingRecordingPen
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.ttLib import TTFont

RANGE = range(0xE001, 0xE00B)


def regraft(aligned_path, patched_path, out_path):
    src = TTFont(aligned_path, recalcTimestamp=False)
    dst = TTFont(patched_path, recalcTimestamp=False)
    scm, sgs = src.getBestCmap(), src.getGlyphSet()
    glyf, hmtx = dst["glyf"], dst["hmtx"]
    order = list(glyf.glyphOrder)
    n = 0
    for cp in RANGE:
        g = scm.get(cp)
        if g is None:
            continue
        new = g + ".apua"
        pen = DecomposingRecordingPen(sgs)
        sgs[g].draw(pen)
        tp = TTGlyphPen(None)
        pen.replay(tp)
        glyf.glyphs[new] = tp.glyph()
        glyf.glyphs[new].recalcBounds(glyf)
        hmtx.metrics[new] = src["hmtx"][g]
        if new not in order:
            order.append(new)
        for t in dst["cmap"].tables:
            if t.isUnicode():
                t.cmap[cp] = new
        n += 1
    glyf.glyphOrder = order
    dst.setGlyphOrder(order)
    assert len(order) == len(glyf.glyphs), (len(order), len(glyf.glyphs))
    dst.save(out_path)
    print("regraft: %d PUA glyphs restored, numGlyphs %d" % (n, len(order)))
    return n


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--aligned", required=True, help="the S6 face (source of truth)")
    ap.add_argument("--patched", required=True, help="the S7 output")
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    regraft(a.aligned, a.patched, a.out)
