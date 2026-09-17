#!/usr/bin/env python3
"""Pre-instance repairs on the Anthropic Mono variable sources.

Two MEASURED source defects, both italic-only:
 1. The Italic STAT names its six wght AxisValues 'Light Italic' ... so
    instancer --update-name-table appends ital=1's 'Italic' a second time
    ('Bold Italic Italic') and then fails the RIBBI test, leaving
    fsSelection without the BOLD/ITALIC bits.
 2. 37 combining-mark glyphs carry a bogus +1200 phantom-point (advance)
    delta on the wght-minimum master tuple, so their advance interpolates
    to 2400 at wght=300 and breaks the monospace grid below wght 400.
"""
import sys
from fontTools.ttLib import TTFont

def strip_italic_from_wght_axisvalues(font):
    if "STAT" not in font:
        return 0
    stat = font["STAT"].table
    axes = {a.AxisOrdering: a.AxisTag for a in stat.DesignAxisRecord.Axis}
    tag_by_index = {i: a.AxisTag for i, a in enumerate(stat.DesignAxisRecord.Axis)}
    n = 0
    av = getattr(stat, "AxisValueArray", None)
    if av is None:
        return 0
    for v in av.AxisValue:
        idx = getattr(v, "AxisIndex", None)
        if idx is None or tag_by_index.get(idx) != "wght":
            continue
        nid = v.ValueNameID
        for rec in font["name"].names:
            if rec.nameID == nid:
                s = rec.toUnicode()
                if s.endswith(" Italic"):
                    rec.string = s[: -len(" Italic")]
                    n += 1
    return n


def assert_monospace(font):
    adv = {m[0] for m in font['hmtx'].metrics.values()}
    if len(adv - {0}) != 1:
        sys.exit("repair_source: refusing to zero phantom deltas on a non-monospace font (advances=%r)" % sorted(adv))
    return sorted(adv - {0})[0]


def strip_advance_deltas(font):
    """Zero the phantom-point (advance/lsb) deltas of every gvar tuple.

    Anthropic Mono is a true monospace: no glyph's advance may vary with
    weight. The last four points of a gvar delta set are the phantom points
    (lsb, rsb-as-advance, top, bottom); zeroing them pins advance = 1200 at
    every instance without touching a single outline point.
    """
    if "gvar" not in font:
        return 0
    n = 0
    for gname, variations in font["gvar"].variations.items():
        for var in variations:
            c = var.coordinates
            if len(c) < 4:
                continue
            for i in range(len(c) - 4, len(c)):
                if c[i] not in (None, (0, 0)):
                    c[i] = (0, 0)
                    n += 1
    return n


if __name__ == "__main__":
    src, dst = sys.argv[1], sys.argv[2]
    f = TTFont(src, recalcTimestamp=False, recalcBBoxes=False)
    cell = assert_monospace(f)
    a = strip_italic_from_wght_axisvalues(f)
    b = strip_advance_deltas(f)
    print(f"repair {src}: cell={cell} STAT names fixed={a} phantom deltas zeroed={b}")
    f.save(dst)
