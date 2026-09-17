#!/usr/bin/env python3
"""fontbuilder stage S9 — normalize a VARIABLE Anthropic face.

Differs from the static normalize (S3) in one load-bearing way, measured
2026-09-17: on every Anthropic variable source the `fvar` named instances and
the `STAT` AxisValues REFERENCE the canonical name IDs 2/6/17 and share private
name records with each other.  Rewriting or deleting 1/2/3/4/6/16/17/25 in place
therefore silently renames the named instances (e.g. the Sans Italic instance
'Text Regular Italic' -> 'Italic', PostScript 'AnthropicSans-Italic') and the
STAT ' Italic' strip renames 10 of the 12 fvar instances.

So: UNSHARE first (clone every referenced record to a fresh private name ID and
re-point fvar/STAT at the clone), then rewrite the canonical block.
"""
import argparse, json, re, sys
from fontTools.ttLib import TTFont
from fontTools.varLib import instancer

WIN, MAC = (3, 1, 0x409), (1, 0, 0)
CANON = {1, 2, 3, 4, 6, 16, 17, 18, 20, 21, 25}


# ---------------------------------------------------------------- name helpers
def _strings(name, nid):
    return [(r.platformID, r.platEncID, r.langID, r.toUnicode())
            for r in name.names if r.nameID == nid]


def _alloc(name, state, value):
    """Allocate a fresh private nameID carrying `value` on both platforms."""
    nid = state["next"]
    state["next"] += 1
    name.setName(value, nid, *WIN)
    name.setName(value, nid, *MAC)
    return nid


def _clone(name, state, nid):
    """Clone every record of `nid` to a fresh private ID, preserving platforms."""
    fresh = state["next"]
    state["next"] += 1
    for plat, enc, lang, val in _strings(name, nid):
        name.setName(val, fresh, plat, enc, lang)
    return fresh


def unshare(font, report):
    """Re-point fvar/STAT references away from canonical name IDs, and give
    every STAT AxisValue a private record of its own."""
    name = font["name"]
    state = {"next": max([256] + [r.nameID for r in name.names]) + 1}
    remap = {}

    def canon_ref(nid):
        if nid not in CANON:
            return nid
        if nid not in remap:
            remap[nid] = _clone(name, state, nid)
            report["unshared_canonical"].append({"from": nid, "to": remap[nid],
                                                 "value": font["name"].getDebugName(nid)})
        return remap[nid]

    if "fvar" in font:
        for ax in font["fvar"].axes:
            ax.axisNameID = canon_ref(ax.axisNameID)
        for inst in font["fvar"].instances:
            inst.subfamilyNameID = canon_ref(inst.subfamilyNameID)
            if getattr(inst, "postscriptNameID", 0xFFFF) != 0xFFFF:
                inst.postscriptNameID = canon_ref(inst.postscriptNameID)

    if "STAT" in font:
        st = font["STAT"].table
        for ax in st.DesignAxisRecord.Axis:
            ax.AxisNameID = canon_ref(ax.AxisNameID)
        st.ElidedFallbackNameID = canon_ref(st.ElidedFallbackNameID)
        avs = getattr(st, "AxisValueArray", None)
        if avs:
            # every AxisValue gets its OWN record so the ' Italic' strip cannot
            # reach an fvar instance name (10 of 12 are shared on Sans/Serif).
            for av in avs.AxisValue:
                private = _clone(name, state, av.ValueNameID)
                report["privatised_stat"].append(
                    {"from": av.ValueNameID, "to": private,
                     "value": name.getDebugName(private)})
                av.ValueNameID = private
    return state


def strip_stat_italic(font, report, axis_tags=("wght", "opsz")):
    """Drop a trailing ' Italic' from the STAT AxisValue names on the given
    axes.  The ital-axis AxisValue ('Italic') is deliberately untouched, and so
    is the wght=400 'Italic' record on Mono (it does not end in ' Italic')."""
    if "STAT" not in font:
        return
    st = font["STAT"].table
    avs = getattr(st, "AxisValueArray", None)
    if not avs:
        return
    tags = [a.AxisTag for a in st.DesignAxisRecord.Axis]
    name = font["name"]
    for av in avs.AxisValue:
        idxs = ([av.AxisIndex] if hasattr(av, "AxisIndex")
                else [r.AxisIndex for r in av.AxisValueRecord])
        if not all(tags[i] in axis_tags for i in idxs):
            continue
        for rec in [r for r in name.names if r.nameID == av.ValueNameID]:
            s = rec.toUnicode()
            if s.endswith(" Italic"):
                rec.string = s[: -len(" Italic")]
                report["stat_stripped"].append({"nameID": av.ValueNameID,
                                                "from": s, "to": rec.string})



def referenced_nameids(font):
    """Every private (>=256) name ID still pointed at by fvar / STAT / feature
    params.  Anything else is dead weight -- and, after the unshare + rename,
    the twelve orphaned 'AnthropicSansWebWeb-*' instance PostScript records are
    exactly that."""
    ids = set()
    if "fvar" in font:
        for ax in font["fvar"].axes:
            ids.add(ax.axisNameID)
        for inst in font["fvar"].instances:
            ids.add(inst.subfamilyNameID)
            ids.add(getattr(inst, "postscriptNameID", 0xFFFF))
    if "STAT" in font:
        st = font["STAT"].table
        ids.add(st.ElidedFallbackNameID)
        for ax in st.DesignAxisRecord.Axis:
            ids.add(ax.AxisNameID)
        avs = getattr(st, "AxisValueArray", None)
        if avs:
            for av in avs.AxisValue:
                ids.add(av.ValueNameID)
    for tag in ("GSUB", "GPOS"):
        if tag in font:
            for fr in font[tag].table.FeatureList.FeatureRecord:
                fp = getattr(fr.Feature, "FeatureParams", None)
                for attr in ("UINameID", "FeatUILabelNameID", "FeatUITooltipTextNameID",
                             "SampleTextNameID", "FirstParamUILabelNameID"):
                    v = getattr(fp, attr, None)
                    if v:
                        ids.add(v)
    return ids


def gc_names(font, report):
    keep = referenced_nameids(font)
    dead = sorted({r.nameID for r in font["name"].names
                   if r.nameID >= 256 and r.nameID not in keep})
    for nid in dead:
        font["name"].removeNames(nameID=nid)
    report["gc_nameids"] = dead
    return dead


# --------------------------------------------------------------------- driver
def normalize(src, dst, family, italic, serif_default_repair=False,
              report_path=None):
    report = {"src": src, "dst": dst, "family": family, "italic": italic,
              "unshared_canonical": [], "privatised_stat": [],
              "stat_stripped": [], "deleted": [], "instance_ps_fixed": [], "gc_nameids": [],
              "serif_repair": None}

    font = TTFont(src, recalcTimestamp=False, recalcBBoxes=False)

    # ---- S2b: move the fvar default (Serif ships wght default 300) --------
    if serif_default_repair:
        before = [(a.axisTag, a.minValue, a.defaultValue, a.maxValue)
                  for a in font["fvar"].axes]
        font = instancer.instantiateVariableFont(
            font, {"wght": (300, 400, 800)}, inplace=False,
            updateFontNames=False, optimize=False)
        font["OS/2"].usWeightClass = 400
        report["serif_repair"] = {
            "axes_before": before,
            "axes_after": [(a.axisTag, a.minValue, a.defaultValue, a.maxValue)
                           for a in font["fvar"].axes],
            "instances_after": len(font["fvar"].instances)}

    unshare(font, report)
    if italic:
        strip_stat_italic(font, report)

    name = font["name"]
    sub = "Italic" if italic else "Regular"
    ps_family = family.replace(" ", "")
    ps = "%s-%s" % (ps_family, sub)
    rev = "%.3f" % round(font["head"].fontRevision, 3)
    uid = "%s;BSPK;%s" % (rev.rstrip("0").rstrip("."), ps)

    for nid, val in ((1, family), (2, sub), (3, uid),
                     (4, "%s %s" % (family, sub)), (6, ps)):
        name.setName(val, nid, *WIN)
        name.setName(val, nid, *MAC)
    # RIBBI face: no typographic family/subfamily, no doubled-Web variations
    # PostScript prefix (ID25 absent => the prefix derives from ID6 up to the
    # first hyphen, which is now 'AnthropicSans'/'AnthropicSerif'/'AnthropicMono')
    for nid in (16, 17, 18, 20, 21, 25):
        if name.getDebugName(nid) is not None:
            report["deleted"].append(nid)
        name.removeNames(nameID=nid)

    # E3, part 2: the doubled-'Web' PostScript names also live in the twelve
    # fvar instance postscriptNameID records, not only in nameID 6.  Rebuild
    # them from the (unshared, still correct) instance subfamily names.
    if "fvar" in font:
        state = {"next": max([256] + [r.nameID for r in name.names]) + 1}
        for inst in font["fvar"].instances:
            style = name.getDebugName(inst.subfamilyNameID)
            want = "%s-%s" % (ps_family, re.sub(r"[^A-Za-z0-9]", "", style))
            have = (name.getDebugName(inst.postscriptNameID)
                    if getattr(inst, "postscriptNameID", 0xFFFF) != 0xFFFF else None)
            if have != want:
                inst.postscriptNameID = _alloc(name, state, want)
                report["instance_ps_fixed"].append({"style": style,
                                                    "from": have, "to": want})

    # a STAT elided fallback that used to point at ID17 now points at a clone
    # of 'Text Regular Italic'; give it the RIBBI style word instead.
    if "STAT" in font:
        st = font["STAT"].table
        state = {"next": max([256] + [r.nameID for r in name.names]) + 1}
        st.ElidedFallbackNameID = _alloc(name, state, sub)

    # ---- style bits (E2: this is what moves the VARIABLE row to slant=100)
    os2, head, post = font["OS/2"], font["head"], font["post"]
    os2.fsSelection &= ~0b1100001          # clear ITALIC(0) BOLD(5) REGULAR(6)
    head.macStyle &= ~0b11
    if italic:
        os2.fsSelection |= 1 << 0
        head.macStyle |= 1 << 1
        post.italicAngle = -10.0
    else:
        os2.fsSelection |= 1 << 6
    os2.fsSelection |= 1 << 7              # USE_TYPO_METRICS, as shipped

    gc_names(font, report)
    font.save(dst)
    report["result"] = {
        "nameID1": name.getDebugName(1), "nameID2": name.getDebugName(2),
        "nameID4": name.getDebugName(4), "nameID6": name.getDebugName(6),
        "fsSelection": bin(os2.fsSelection), "macStyle": head.macStyle,
        "italicAngle": post.italicAngle, "usWeightClass": os2.usWeightClass,
        "fvar": [(a.axisTag, a.minValue, a.defaultValue, a.maxValue)
                 for a in font["fvar"].axes],
        "instances": [(name.getDebugName(i.subfamilyNameID),
                       name.getDebugName(i.postscriptNameID), i.coordinates)
                      for i in font["fvar"].instances]}
    if report_path:
        json.dump(report, open(report_path, "w"), indent=1)
    return report


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--in", dest="inp", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--family", required=True)
    ap.add_argument("--italic", action="store_true")
    ap.add_argument("--serif-default-repair", action="store_true")
    ap.add_argument("--report")
    a = ap.parse_args()
    r = normalize(a.inp, a.out, a.family, a.italic, a.serif_default_repair, a.report)
    res = r["result"]
    print("%-46s ID1=%-16s ID2=%-8s ID6=%-24s fsSel=%s macStyle=%d wc=%d unshared=%d stat_priv=%d stripped=%d"
          % (a.out.split("/")[-1], res["nameID1"], res["nameID2"], res["nameID6"],
             res["fsSelection"], res["macStyle"], res["usWeightClass"],
             len(r["unshared_canonical"]), len(r["privatised_stat"]), len(r["stat_stripped"])),
          "instPS=%d gc=%d" % (len(r["instance_ps_fixed"]), len(r["gc_nameids"])))
