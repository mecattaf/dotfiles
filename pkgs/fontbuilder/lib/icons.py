#!/usr/bin/env python3
"""fontbuilder stage S10 — Anthropicons.

The source ships NO usable name table (ID1 'Anthropicons RVRN', ID2 'Regular',
nothing else), fsSelection 0, sxHeight/sCapHeight 0, achVendID '????',
zero named instances, and four axes (wght opsz ANIM ANM2).

Two artifacts:
  --pin      instance {wght:400, opsz:20, ANIM:0, ANM2:0} -> static TTF for
             fonts.packages (truetype/Anthropicons-Regular.ttf)
  otherwise  keep the axes, pin only the fvar DEFAULTS to the same point and
             add a single named instance, for the webfont
             (Anthropicons-Variable.woff2, CSS font-weight 400 700)
"""
import argparse, json
from fontTools.ttLib import TTFont
from fontTools.ttLib.tables._f_v_a_r import NamedInstance
from fontTools.varLib import instancer

WIN, MAC = (3, 1, 0x409), (1, 0, 0)
PIN = {"wght": 400, "opsz": 20, "ANIM": 0, "ANM2": 0}
# 1000 upm.  The text families are sxHeight 1080 / sCapHeight 1440 at 2000 upm
# (0.540 / 0.720 em); the same ratios at 1000 upm keep an icon optically level
# with Anthropic Sans under fontconfig's and CSS's x-height matching.
# MEASURED source ink: y 47..952, median glyph top 878, every advance 1000.
SX, SCAP = 540, 720


def setname(font, nid, value):
    for plat, enc, lang in (WIN, MAC):
        font["name"].setName(value, nid, plat, enc, lang)


def build(src, dst, pin, report_path=None):
    f = TTFont(src, recalcTimestamp=False, recalcBBoxes=False)
    rep = {"src": src, "dst": dst, "mode": "static" if pin else "variable",
           "axes_before": [(a.axisTag, a.minValue, a.defaultValue, a.maxValue)
                           for a in f["fvar"].axes]}

    if pin:
        f = instancer.instantiateVariableFont(f, PIN, inplace=False,
                                              updateFontNames=False)
        sub, version_note = "Regular", "instanced wght=400 opsz=20 ANIM=0 ANM2=0"
    else:
        # keep wght/opsz variable; freeze the two animation axes so an
        # un-set ANIM/ANM2 can never render a half-way animation frame.
        f = instancer.instantiateVariableFont(f, {"ANIM": 0, "ANM2": 0},
                                              inplace=False, updateFontNames=False)
        for a in f["fvar"].axes:                      # pin the DEFAULT instance
            if a.axisTag == "opsz":
                a.defaultValue = 20.0
        sub, version_note = "Regular", "ANIM/ANM2 frozen at 0, default opsz=20"

    ver = "Version %.3f" % f["head"].fontRevision
    fam, ps = "Anthropicons", "Anthropicons-Regular"
    for nid, val in ((1, fam), (2, sub), (3, "%s %s; %s" % (fam, sub, ver)),
                     (4, "%s %s" % (fam, sub)), (5, ver), (6, ps)):
        setname(f, nid, val)
    for nid in (16, 17, 18, 20, 21, 25):
        f["name"].removeNames(nameID=nid)

    if not pin and not f["fvar"].instances:
        nid = max([256] + [r.nameID for r in f["name"].names]) + 1
        setname(f, nid, "Regular")
        inst = NamedInstance()
        inst.subfamilyNameID = nid
        inst.postscriptNameID = 6
        inst.coordinates = {a.axisTag: a.defaultValue for a in f["fvar"].axes}
        f["fvar"].instances.append(inst)
        rep["named_instance"] = inst.coordinates

    os2, head, post = f["OS/2"], f["head"], f["post"]
    if os2.version < 4:                 # USE_TYPO_METRICS is defined from v4;
        os2.version = 4                 # fontTools warns if the bit is set on v3
    os2.fsSelection = (1 << 6) | (1 << 7)      # REGULAR | USE_TYPO_METRICS
    head.macStyle = 0
    os2.usWeightClass = 400
    os2.sxHeight, os2.sCapHeight = SX, SCAP
    post.isFixedPitch = 1               # every advance is exactly 1000
    post.italicAngle = 0.0

    f.save(dst)
    rep["result"] = {
        "nameID1": f["name"].getDebugName(1), "nameID4": f["name"].getDebugName(4),
        "nameID6": f["name"].getDebugName(6), "nameID5": f["name"].getDebugName(5),
        "OS2version": os2.version, "fsSelection": bin(os2.fsSelection),
        "usWeightClass": os2.usWeightClass, "sxHeight": os2.sxHeight,
        "sCapHeight": os2.sCapHeight, "isFixedPitch": post.isFixedPitch,
        "glyphs": len(f.getGlyphOrder()), "cmap": len(f.getBestCmap()),
        "axes_after": ([(a.axisTag, a.minValue, a.defaultValue, a.maxValue)
                        for a in f["fvar"].axes] if "fvar" in f else None),
        "note": version_note}
    if report_path:
        json.dump(rep, open(report_path, "w"), indent=1)
    print("%-44s %s glyphs=%d cmap=%d fsSel=%s OS2v=%d axes=%s"
          % (dst.split("/")[-1], rep["result"]["nameID4"], rep["result"]["glyphs"],
             rep["result"]["cmap"], rep["result"]["fsSelection"],
             rep["result"]["OS2version"], rep["result"]["axes_after"]))
    return rep


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--in", dest="inp", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--pin", action="store_true")
    ap.add_argument("--report")
    a = ap.parse_args()
    build(a.inp, a.out, a.pin, a.report)
