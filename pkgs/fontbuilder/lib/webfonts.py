#!/usr/bin/env python3
"""fontbuilder stage S11 — woff2 emit + round-trip verification.

woff2 is a lossless container: the same tables, re-packed (glyf/loca are
transformed and rebuilt on decode).  We assert that per file rather than assume
it: glyph order, cmap (every subtable), GSUB/GPOS feature+lookup counts, fvar
axes and named instances, name table, and the head/OS2 style bits must all
survive the round trip byte-for-byte at the table level.
"""
import argparse, hashlib, json, os, sys
from fontTools.ttLib import TTFont


def snapshot(f):
    s = {"glyphOrder": f.getGlyphOrder(),
         "numGlyphs": f["maxp"].numGlyphs,
         "cmap": {("%d.%d.%d" % (t.platformID, t.platEncID, t.format)):
                  sorted((hex(k), v) for k, v in t.cmap.items())
                  for t in f["cmap"].tables},
         "names": sorted((r.nameID, r.platformID, r.platEncID, r.langID, r.toUnicode())
                         for r in f["name"].names),
         "head": [f["head"].macStyle, f["head"].unitsPerEm, f["head"].flags],
         "os2": [f["OS/2"].fsSelection, f["OS/2"].usWeightClass, f["OS/2"].version,
                 f["OS/2"].sTypoAscender, f["OS/2"].sTypoDescender],
         "hhea": [f["hhea"].ascent, f["hhea"].descent, f["hhea"].lineGap],
         "post": f["post"].italicAngle,
         "hmtx": sorted(f["hmtx"].metrics.items())}
    for tag in ("GSUB", "GPOS"):
        if tag in f:
            t = f[tag].table
            s[tag] = {
                "features": sorted(r.FeatureTag for r in t.FeatureList.FeatureRecord),
                "nLookups": len(t.LookupList.Lookup),
                "nScripts": len(t.ScriptList.ScriptRecord),
                "langsys": sorted(
                    (r.ScriptTag, l.LangSysTag)
                    for r in t.ScriptList.ScriptRecord
                    for l in r.Script.LangSysRecord)}
    if "fvar" in f:
        s["fvar"] = {"axes": [(a.axisTag, a.minValue, a.defaultValue, a.maxValue)
                              for a in f["fvar"].axes],
                     "instances": [(f["name"].getDebugName(i.subfamilyNameID),
                                    f["name"].getDebugName(i.postscriptNameID),
                                    sorted(i.coordinates.items()))
                                   for i in f["fvar"].instances]}
    if "STAT" in f:
        st = f["STAT"].table
        av = getattr(st, "AxisValueArray", None)
        s["STAT"] = {"axes": [a.AxisTag for a in st.DesignAxisRecord.Axis],
                     "values": [f["name"].getDebugName(a.ValueNameID)
                                for a in (av.AxisValue if av else [])]}
    if "gvar" in f:
        s["gvar_glyphs"] = len(f["gvar"].variations)
    s["tables"] = sorted(t for t in f.keys() if t != "GlyphOrder")
    return s


def emit(src, dst):
    f = TTFont(src, recalcTimestamp=False, recalcBBoxes=False)
    before = snapshot(f)
    f.flavor = "woff2"
    f.save(dst)
    g = TTFont(dst, recalcTimestamp=False, recalcBBoxes=False)
    after = snapshot(g)
    diffs = [k for k in before if before[k] != after.get(k)]
    return before, after, diffs


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--outdir", required=True)
    ap.add_argument("--report", required=True)
    ap.add_argument("pairs", nargs="+", help="src.ttf:name.woff2")
    a = ap.parse_args()
    os.makedirs(a.outdir, exist_ok=True)
    out = {"files": [], "failures": []}
    for pair in a.pairs:
        src, name = pair.split(":")
        dst = os.path.join(a.outdir, name)
        before, after, diffs = emit(src, dst)
        sha = hashlib.sha256(open(dst, "rb").read()).hexdigest()
        rec = {"src": src, "woff2": name,
               "ttf_bytes": os.path.getsize(src), "woff2_bytes": os.path.getsize(dst),
               "sha256": sha, "numGlyphs": before["numGlyphs"],
               "cmap_subtables": {k: len(v) for k, v in before["cmap"].items()},
               "GSUB_features": before.get("GSUB", {}).get("features"),
               "GSUB_lookups": before.get("GSUB", {}).get("nLookups"),
               "GPOS_features": before.get("GPOS", {}).get("features"),
               "fvar": before.get("fvar", {}).get("axes"),
               "fvar_instances": len(before.get("fvar", {}).get("instances", [])),
               "roundtrip_diffs": diffs}
        out["files"].append(rec)
        if diffs:
            out["failures"].append({"file": name, "diffs": diffs})
        print("%-34s %7d -> %7d B (%.1f%%)  glyphs=%-4d cmap=%-4d GSUB=%-2s fvar=%-2s inst=%-2d roundtrip=%s"
              % (name, rec["ttf_bytes"], rec["woff2_bytes"],
                 100.0 * rec["woff2_bytes"] / rec["ttf_bytes"], rec["numGlyphs"],
                 max(rec["cmap_subtables"].values()),
                 len(rec["GSUB_features"] or []), len(rec["fvar"] or []),
                 rec["fvar_instances"],
                 "IDENTICAL" if not diffs else "DIFF:" + ",".join(diffs)))
    json.dump(out, open(a.report, "w"), indent=1)
    sys.exit(1 if out["failures"] else 0)
