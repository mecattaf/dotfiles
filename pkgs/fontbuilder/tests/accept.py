#!/usr/bin/env python3
"""fontbuilder acceptance suite - the fontTools/fontconfig half of spec 11.

    tests/accept.py <out-dir> [--src <capture-dir>]

Covers A3 A4 A5 A6 A7 A8 A9 A10 A13 A14 A16 A21.  A1/A2 need kitty's own
resolver and live in tests/resolve.py and tests/shape.py; A12 needs the
untouched Serif source and lives in tests/a12.py.

Writes <out>/verify/accept.json, prints one `FAIL <test> <face>: ...` line per
failure, exits 1 if there is any.  Nothing is written outside <out>/verify/.

THE ISOLATION CONTRACT (spec 11 preamble, D17).  Every fc-scan / fc-match /
fc-list here runs with FONTCONFIG_FILE pointing at a config rendered from
tests/fonts.conf.in (private <cachedir> under <out>/verify) AND with
XDG_CACHE_HOME redirected under <out>/verify.  FONTCONFIG_FILE alone is not
enough - with only it set, ~/.cache/fontconfig's DIRECTORY mtime moved.
`fc-cache` is NEVER invoked.  A21 proves both by snapshotting

    find ~/.cache/fontconfig -printf '%T@ %s %p\n' | sort | sha256sum

without -type f, before and after the whole suite.

EVERY nameID ASSERTION IS SET MEMBERSHIP (A4).  The name table carries TWO
nameID16 records with different strings (`AnthropicMono Nerd Font Mono` and
`AnthropicMono NFM`); a dict keyed by nameID silently keeps only the last and
makes A4 fail on a correct font.
"""
from __future__ import annotations

import argparse
import collections
import hashlib
import json
import math
import os
import re
import subprocess
import sys
import tarfile

from fontTools.pens.boundsPen import BoundsPen
from fontTools.ttLib import TTFont

# --------------------------------------------------------------------------
# constants measured on the real faces (spec 11 A3/A5/A6/A7/A8/A9/A10)
# --------------------------------------------------------------------------
ROMAN = ["Light", "Regular", "Medium", "SemiBold", "Bold", "ExtraBold"]
ITALIC = ["LightItalic", "Italic", "MediumItalic", "SemiBoldItalic", "BoldItalic", "ExtraBoldItalic"]
STYLES = ROMAN + ITALIC
WEIGHT = {"Light": 50, "Regular": 80, "Medium": 100, "SemiBold": 180, "Bold": 200, "ExtraBold": 205}
# fc-scan's canonical style string for each face; membership, the row also
# carries the RIBBI alias (`ExtraBold,Regular`).
FC_STYLE = {
    "Light": "Light", "Regular": "Regular", "Medium": "Medium", "SemiBold": "SemiBold",
    "Bold": "Bold", "ExtraBold": "ExtraBold", "LightItalic": "Light Italic",
    "Italic": "Italic", "MediumItalic": "Medium Italic", "SemiBoldItalic": "SemiBold Italic",
    "BoldItalic": "Bold Italic", "ExtraBoldItalic": "ExtraBold Italic",
}
LONG_FAMILY = "AnthropicMono Nerd Font Mono"
SHORT_FAMILY = "AnthropicMono NFM"
CELL = 1200

# A4.  The patcher version is NOT hardcoded.  The flake's pinned nixpkgs moved
# from nerd-font-patcher 3.4.0 (what the scouts measured) to 3.5.1, so nameID5
# now reads ";Nerd Fonts 3.5.1".  The shape is asserted with a regex, and the
# EXACT version is taken from <out>/manifest.json tools["nerd-font-patcher"]
# when that key is present - which turns a vacuous shape check into an exact
# one without pinning a number in this file.
NF_STAMP_RE = re.compile(r";Nerd Fonts \d+\.\d+\.\d+")
NF_VERSION_RE = re.compile(r"v(\d+\.\d+\.\d+)")

# A4.  nameID6.  Patcher 3.5.1 added FontnameParser._remove_regular, so the
# RIBBI Regular face ships the bare `AnthropicMonoNFM` with no -Regular token,
# while the Regular-weight italic stays `AnthropicMonoNFM-Italic` and every
# other face keeps its -<Style> suffix.  That is the patcher's own convention
# and we accept it; 12 unique PostScript names still holds.
PS_NAME_RE = re.compile(r"^AnthropicMonoNFM(-[A-Za-z]+)?$")

# A7 line box, measured identical on all 12 terminal faces and the 4 variable
# desktop faces.  Anthropicons is the exception (spec S10 / D16).
LINEBOX = dict(upm=2000, hhea=(1985, -515, 0), typo=(1985, -515, 0), win=(1985, 515),
               xh=1080, cap=1440)
ICONS_LINEBOX = dict(upm=1000, xh=540, cap=720)

# A8
PRESENT = [0x276F, 0x03BB, 0x0410, 0x2718, 0x2713, 0xE0A7, 0xE0A8, 0xE0B0,
           0xF001, 0x1D538, 0xF07E5, 0x2800, 0x28FF, 0x251C, 0x258F]
BLOCKS = [("Greek", 0x370, 0x3FF, 110), ("Cyrillic", 0x400, 0x4FF, 180),
          ("Arrows", 0x2190, 0x21FF, 112), ("CtrlPics", 0x2400, 0x243F, 36),
          ("Box", 0x2500, 0x257F, 128), ("Block", 0x2580, 0x259F, 32),
          ("Geometric", 0x25A0, 0x25FF, 96)]
SPAN_CELL = [0x2500, 0x2550, 0x2588]

# A9
GSUB_NEED = {"aalt", "calt", "ccmp", "dnom", "frac", "liga", "locl", "ordn", "sinf", "subs", "sups"}
CALT_LOOKUPS = 136
PUA_S7B = range(0xE001, 0xE00B)

# A10
ALIGN_CENSUS = {"shift": 100, "anchor-veto": 35, "clamped": 1}
DY_LO, DY_HI = -70, 100          # measured -61..+93; the band the spec pins
LIG_CENTRE_TOL = 8
CROSS_TOL = 70                   # spec 5 / A10 "cross-ligature consistency"
# A10 "the patcher changed 0 of 136 lig outlines".  The defect it guards is the
# patcher UNDOING the shear horizontally - measured before the lsb fix at
# 136/136 translated by up to 120 units.  +-1 unit of coordinate rounding IS
# measured on the Roman faces (59 of 136 on Regular, dx = -1, dy = 0, lsb and
# advance unchanged) and is not that defect, so the pin is a 1-unit tolerance,
# not byte equality.  A translation is still caught loudly.
LIG_MOVE_TOL = 1
SLOPE_TOL_DEG = 0.5

# A16
TARBALLS = {"anthropic-mono-nerd-fonts.tar.zst": 12,
            "anthropic-ui-fonts.tar.zst": 5,
            "anthropic-webfonts.tar.zst": 8}

DESKTOP = ["AnthropicSans-Roman", "AnthropicSans-Italic",
           "AnthropicSerif-Roman", "AnthropicSerif-Italic", "Anthropicons-Regular"]


# --------------------------------------------------------------------------
# plumbing
# --------------------------------------------------------------------------
class Report:
    def __init__(self, partial=False):
        self.fails = []
        self.notes = []
        self.data = {}
        # --allow-partial: the out-dir is a smoke build with a subset of the
        # faces, so every COUNT assertion degrades to a note.  Per-face
        # assertions still fail hard - a subset run must still be able to fail.
        self.partial = partial

    def fail(self, test, who, msg):
        self.fails.append("%s %s: %s" % (test, who, msg))

    def check(self, cond, test, who, msg):
        if not cond:
            self.fail(test, who, msg)
        return bool(cond)

    def note(self, test, msg):
        self.notes.append("%s: %s" % (test, msg))

    def count(self, cond, test, who, msg):
        """A COUNT assertion: hard under a full press, a note under
        --allow-partial."""
        if cond:
            return True
        if self.partial:
            self.note(test, "%s: %s (not a failure under --allow-partial)" % (who, msg))
        else:
            self.fail(test, who, msg)
        return False


def render_conf(template, cachedir, fontdirs, path):
    """tests/fonts.conf.in -> a private config.  Never calls fc-cache."""
    os.makedirs(cachedir, exist_ok=True)
    dirs = "\n".join("  <dir>%s</dir>" % d.replace("&", "&amp;").replace("<", "&lt;")
                     for d in fontdirs)
    text = template.replace("@CACHEDIR@", cachedir).replace("@FONTDIR@", dirs)
    with open(path, "w") as fh:
        fh.write(text)
    return path


def fc(conf, xdg, argv):
    env = dict(os.environ)
    env["FONTCONFIG_FILE"] = conf
    env["XDG_CACHE_HOME"] = xdg
    env.pop("FONTCONFIG_PATH", None)
    p = subprocess.run(argv, capture_output=True, text=True, env=env, check=False)
    return p.returncode, p.stdout, p.stderr


def cache_snapshot():
    """A21.  No -type f: a directory-entry change must be caught (D17)."""
    d = os.path.expanduser("~/.cache/fontconfig")
    p = subprocess.run(["find", d, "-printf", "%T@ %s %p\n"],
                       capture_output=True, text=True, check=False)
    return hashlib.sha256("".join(sorted(p.stdout.splitlines(True))).encode()).hexdigest()


def names_of(font, nid):
    """SET of every string carried under this nameID, over every platform."""
    out = set()
    for rec in font["name"].names:
        if rec.nameID != nid:
            continue
        try:
            out.add(rec.toUnicode())
        except Exception:
            pass
    return out


def contour_boxes(glyf, name):
    """Per-contour (x0,y0,x1,y1) straight off the glyf coordinates."""
    g = glyf[name]
    if getattr(g, "numberOfContours", 0) <= 0:
        return []
    co, out, start = g.coordinates, [], 0
    for end in g.endPtsOfContours:
        pts = co[start:end + 1]
        start = end + 1
        xs = [p[0] for p in pts]
        ys = [p[1] for p in pts]
        out.append((min(xs), min(ys), max(xs), max(ys)))
    return out


def table_snapshot(f):
    """Semantic table snapshot for the woff2 round-trip (A14).

    Lifted from lib/webfonts.py's own verification so the test asserts exactly
    what the build stage asserts: glyph order, every cmap subtable, the whole
    name table, the style bits, metrics, GSUB/GPOS shape, fvar/STAT and the
    table set."""
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
         "hmtx": sorted(f["hmtx"].metrics.items()),
         "tables": sorted(t for t in f.keys() if t != "GlyphOrder")}
    for tag in ("GSUB", "GPOS"):
        if tag in f:
            t = f[tag].table
            s[tag] = {"features": sorted(r.FeatureTag for r in t.FeatureList.FeatureRecord),
                      "nLookups": len(t.LookupList.Lookup),
                      "nScripts": len(t.ScriptList.ScriptRecord)}
    if "fvar" in f:
        s["fvar"] = {"axes": [(a.axisTag, a.minValue, a.defaultValue, a.maxValue)
                              for a in f["fvar"].axes],
                     "instances": [(f["name"].getDebugName(i.subfamilyNameID),
                                    f["name"].getDebugName(i.postscriptNameID),
                                    sorted(i.coordinates.items()))
                                   for i in f["fvar"].instances]}
    if "gvar" in f:
        s["gvar_glyphs"] = len(f["gvar"].variations)
    return s


def ycentre(gs, name):
    bp = BoundsPen(gs)
    gs[name].draw(bp)
    if bp.bounds is None:
        return None
    return (bp.bounds[1] + bp.bounds[3]) / 2.0


def slope_deg(glyf, name):
    """Top-decile vs bottom-decile x-slope of the tallest contour, in degrees.

    Catches an un-sheared ligature inside an italic face (A10)."""
    best, boxes = None, contour_boxes(glyf, name)
    if not boxes:
        return None
    g = glyf[name]
    co, start, pick = g.coordinates, 0, None
    for i, end in enumerate(g.endPtsOfContours):
        pts = list(co[start:end + 1])
        start = end + 1
        h = boxes[i][3] - boxes[i][1]
        if best is None or h > best:
            best, pick = h, pts
    if not pick or best is None or best <= 0:
        return None
    ys = sorted(p[1] for p in pick)
    lo = ys[max(0, len(ys) // 10 - 1)]
    hi = ys[min(len(ys) - 1, len(ys) - len(ys) // 10)]
    bot = [p[0] for p in pick if p[1] <= lo]
    top = [p[0] for p in pick if p[1] >= hi]
    if not bot or not top or hi == lo:
        return None
    dx = sum(top) / len(top) - sum(bot) / len(bot)
    return math.degrees(math.atan2(dx, hi - lo))


# --------------------------------------------------------------------------
# A3 - exact family strings, through fc-scan
# --------------------------------------------------------------------------
def a3(R, out, conf, xdg, faces):
    rows = {}
    for st, path in faces.items():
        rc, so, se = fc(conf, xdg, ["fc-scan", "--format",
                                    "%{family}|%{style}|%{fullname}|%{weight}|%{slant}|%{spacing}\n", path])
        if rc != 0:
            R.fail("A3", st, "fc-scan exit %d %s" % (rc, se.strip()))
            continue
        line = so.strip().splitlines()[0]
        rows[st] = line
        fam, style, full, w, slant, spacing = line.split("|")
        fams, styles = set(fam.split(",")), set(style.split(","))
        R.check(LONG_FAMILY in fams, "A3", st, "family %r lacks %r" % (fam, LONG_FAMILY))
        R.check(SHORT_FAMILY in fams, "A3", st, "family %r lacks %r" % (fam, SHORT_FAMILY))
        R.check(FC_STYLE[st] in styles, "A3", st, "style %r lacks %r" % (style, FC_STYLE[st]))
        base = st[:-6] if st.endswith("Italic") and st != "Italic" else ("Regular" if st == "Italic" else st)
        R.check(w == str(WEIGHT[base]), "A3", st, "weight %s != %d" % (w, WEIGHT[base]))
        R.check(slant == ("100" if st in ITALIC else "0"), "A3", st, "slant %s" % slant)
        R.check(spacing == "100", "A3", st, "spacing %s != 100" % spacing)
    R.data["A3_fc_scan"] = rows


# --------------------------------------------------------------------------
# A4 - name table.  Set membership everywhere.
# --------------------------------------------------------------------------
def a4(R, out, fonts, patcher_version=None):
    LIMIT = {1: 31, 2: 31, 4: 63, 6: 63, 16: 31, 17: 31}
    ps_all = []
    rows = {}
    want_stamp = ";Nerd Fonts %s" % patcher_version if patcher_version else None
    if want_stamp:
        R.data["A4_patcher_version"] = patcher_version
    else:
        R.note("A4", "no tools['nerd-font-patcher'] in <out>/manifest.json - nameID5 is "
                     "checked for SHAPE only, not for the exact version")
    for st, f in fonts.items():
        over = {}
        dirty = []
        for rec in f["name"].names:
            try:
                s = rec.toUnicode()
            except Exception:
                continue
            lim = LIMIT.get(rec.nameID)
            if lim and len(s) > lim:
                over["%d/%d,%d,%d" % (rec.nameID, rec.platformID, rec.platEncID, rec.langID)] = (s, len(s))
            if "Web" in s or "Italic Italic" in s:
                dirty.append((rec.nameID, s))
        R.check(not over, "A4", st, "nameID over its limit: %s" % over)
        R.check(not dirty, "A4", st, "Web / 'Italic Italic' in name table: %s" % dirty)

        id16, id6, id5, id1 = names_of(f, 16), names_of(f, 6), names_of(f, 5), names_of(f, 1)
        R.check(LONG_FAMILY in id16, "A4", st, "nameID16 set %s lacks %r" % (sorted(id16), LONG_FAMILY))
        R.check(SHORT_FAMILY in id1 or any(s.startswith(SHORT_FAMILY) for s in id1),
                "A4", st, "nameID1 set %s" % sorted(id1))
        for s in id6:
            R.check(PS_NAME_RE.match(s), "A4", st, "nameID6 %r does not match %s"
                    % (s, PS_NAME_RE.pattern))
            if st != "Regular":
                R.check("Regular" not in s, "A4", st, "Regular glued onto nameID6 %r" % s)
        R.check(any(NF_STAMP_RE.search(s) for s in id5), "A4", st,
                "nameID5 %s carries no ';Nerd Fonts <x.y.z>' stamp" % sorted(id5))
        if want_stamp:
            R.check(any(want_stamp in s for s in id5), "A4", st,
                    "nameID5 %s does not carry %r, which is the patcher the manifest names"
                    % (sorted(id5), want_stamp))
        ps_all.extend(id6)
        rows[st] = dict(id1=sorted(id1), id6=sorted(id6), id16=sorted(id16))
    R.count(len(set(ps_all)) == 12, "A4", "suite",
            "%d unique PostScript names, expected 12: %s" % (len(set(ps_all)), sorted(set(ps_all))))
    R.check(len(set(ps_all)) == len(fonts), "A4", "suite",
            "%d faces but %d unique PostScript names - a collision"
            % (len(fonts), len(set(ps_all))))
    R.data["A4_names"] = rows

    # the patcher log gate: zero ^ERROR / ^CRITICAL lines.  Exit code is NOT
    # the gate - measured, 3 ERROR lines with exit 0.
    logs = None
    for cand in (os.path.join(out, "logs"), os.path.join(out, "work", "logs")):
        if os.path.isdir(cand):
            logs = cand
            break
    if logs:
        bad = {}
        for n in sorted(os.listdir(logs)):
            p = os.path.join(logs, n)
            if not os.path.isfile(p):
                continue
            with open(p, errors="replace") as fh:
                hits = [ln.rstrip() for ln in fh if ln.startswith("ERROR") or ln.startswith("CRITICAL")]
            if hits:
                bad[n] = hits[:5]
        R.check(not bad, "A4", "patcher-log", "ERROR/CRITICAL lines: %s" % bad)
        R.data["A4_logs_dir"] = logs
        R.data["A4_logs_scanned"] = len(os.listdir(logs))
    else:
        R.note("A4", "no <out>/logs or <out>/work/logs - the patcher-log ERROR gate, which is "
                     "THE gate (exit code is not: measured 3 ERROR lines with exit 0), was "
                     "NOT exercised")


# --------------------------------------------------------------------------
# A5 - monospace canary, both levels, plus the negative control
# --------------------------------------------------------------------------
def a5(R, out, conf, xdg, faces, fonts, src):
    for st, f in fonts.items():
        adv = {a for a, _ in f["hmtx"].metrics.values()}
        R.check(adv == {CELL}, "A5", st, "hmtx advances %s != {1200}" % sorted(adv))
    for st, path in faces.items():
        rc, so, _ = fc(conf, xdg, ["fc-scan", "--format", "%{spacing}\n", path])
        R.check(so.strip().splitlines()[:1] == ["100"], "A5", st, "fc-scan spacing %r" % so.strip())

    if not src:
        R.note("A5", "no --src: the NEGATIVE CONTROL was not run, so A5 could go "
                     "vacuous if S1 were dropped")
        return
    from fontTools.varLib.instancer import instantiateVariableFont as inst
    p = os.path.join(src, "fonts-ttf", "AnthropicMono-Italic-Web.ttf")
    if not os.path.exists(p):
        R.fail("A5", "negative-control", "unrepaired italic source not at %s" % p)
        return
    vf = inst(TTFont(p, recalcTimestamp=False), {"wght": 300}, inplace=True, updateFontNames=False)
    census = dict(collections.Counter(a for a, _ in vf["hmtx"].metrics.values()))
    R.check(census == {1200: 662, 2400: 37}, "A5", "negative-control",
            "unrepaired wght=300 hmtx census %s, expected {1200: 662, 2400: 37}" % census)
    tmp = os.path.join(out, "verify", "negctl-italic-300.ttf")
    vf.save(tmp)
    rc, so, _ = fc(conf, xdg, ["fc-scan", "--format", "%{spacing}\n", tmp])
    R.check(so.strip() == "90", "A5", "negative-control",
            "unrepaired wght=300 fc-scan spacing %r, expected 90" % so.strip())
    R.data["A5_negative_control"] = dict(census=census, spacing=so.strip())


# --------------------------------------------------------------------------
# A6 - style bits, as PREDICATES (never a literal fsSelection integer)
# --------------------------------------------------------------------------
def a6(R, out, conf, xdg, fonts):
    RIBBI_BOLD = {"Bold", "BoldItalic"}
    for st, f in fonts.items():
        o, head, post = f["OS/2"], f["head"], f["post"]
        fs, mac = o.fsSelection, head.macStyle
        ital = st in ITALIC
        R.check(bool(fs & 1) == ital, "A6", st, "fsSelection bit0 ITALIC=%d on %s" % (fs & 1, st))
        R.check(bool(mac & 2) == ital, "A6", st, "macStyle bit1 italic=%d" % (mac & 2))
        bold = bool(fs & (1 << 5)) and bool(mac & 1)
        R.check(bold == (st in RIBBI_BOLD), "A6", st,
                "BOLD bit5+macStyle bit0 = %s, expected %s (RIBBI Bold pair only)"
                % (bold, st in RIBBI_BOLD))
        R.check(bool(fs & (1 << 6)) == (st == "Regular"), "A6", st,
                "REGULAR bit6 = %d, set only on plain Regular" % bool(fs & (1 << 6)))
        R.check(bool(fs & (1 << 7)), "A6", st, "USE_TYPO_METRICS bit7 clear")
        R.check((fs & 0x41) != 0x41, "A6", st, "fsSelection ITALIC+REGULAR both set (%s)" % bin(fs))
        want_angle = -10.0 if ital else 0.0
        R.check(post.italicAngle == want_angle, "A6", st,
                "post.italicAngle %s != %s" % (post.italicAngle, want_angle))

    # the variable desktop italics: %{slant} must be 100 on the VARIABLE row,
    # and each family's variable rows must carry slant 0 once and 100 once
    # (pre-fix it is {0, 0} - E2).
    desk = os.path.join(out, "desktop")
    for fam in ("AnthropicSans", "AnthropicSerif"):
        slants = []
        for cut in ("Roman", "Italic"):
            p = os.path.join(desk, "%s-%s.ttf" % (fam, cut))
            if not os.path.exists(p):
                R.count(False, "A6", fam, "missing %s" % p)
                continue
            rc, so, _ = fc(conf, xdg, ["fc-scan", "--format", "%{slant}|%{variable}\n", p])
            var = [ln.split("|")[0] for ln in so.strip().splitlines() if ln.endswith("|True")]
            R.check(len(var) == 1, "A6", "%s-%s" % (fam, cut),
                    "%d variable rows, expected 1" % len(var))
            if cut == "Italic":
                R.check(var[:1] == ["100"], "A6", "%s-Italic" % fam,
                        "variable row slant %s != 100 (E2: pre-fix it is 0)" % var)
            slants.extend(var)
        if slants:
            R.check(sorted(slants) == ["0", "100"], "A6", fam,
                    "variable-row slant set %s, expected one 0 and one 100" % sorted(slants))


# --------------------------------------------------------------------------
# A7 - line box
# --------------------------------------------------------------------------
def a7(R, out, fonts):
    def linebox(f):
        o, h, hd = f["OS/2"], f["hhea"], f["head"]
        return dict(upm=hd.unitsPerEm, hhea=(h.ascent, h.descent, h.lineGap),
                    typo=(o.sTypoAscender, o.sTypoDescender, o.sTypoLineGap),
                    win=(o.usWinAscent, o.usWinDescent), xh=o.sxHeight, cap=o.sCapHeight)

    for st, f in fonts.items():
        got = linebox(f)
        for k, want in LINEBOX.items():
            R.check(got[k] == want, "A7", st, "%s %s != %s" % (k, got[k], want))
    n = 0
    for name in DESKTOP:
        p = os.path.join(out, "desktop", name + ".ttf")
        if not os.path.exists(p):
            R.count(False, "A7", name, "missing %s" % p)
            continue
        n += 1
        got = linebox(TTFont(p, recalcTimestamp=False, recalcBBoxes=False))
        want = ICONS_LINEBOX if name.startswith("Anthropicons") else LINEBOX
        for k, v in want.items():
            R.check(got[k] == v, "A7", name, "%s %s != %s" % (k, got[k], v))
    R.count(len(fonts) == 12, "A7", "suite", "%d terminal faces, expected 12" % len(fonts))
    R.count(n == 5, "A7", "suite", "%d desktop faces, expected 5" % n)


# --------------------------------------------------------------------------
# A8 - coverage
# --------------------------------------------------------------------------
def a8(R, out, fonts):
    rows = {}
    for st, f in fonts.items():
        cm = f.getBestCmap()
        gs = f.getGlyphSet()
        r = dict(codepoints=len(cm), glyphs=len(f.getGlyphOrder()))
        R.check(len(cm) >= 13000, "A8", st, "getBestCmap %d < 13000" % len(cm))
        absent = ["U+%04X" % c for c in PRESENT if c not in cm]
        R.check(not absent, "A8", st, "absent codepoints %s" % absent)

        # 256 braille in EVERY UNICODE subtable, not only fmt12.  Measured 256
        # in each of (0,3), (3,1), (0,4), (3,10).  The (1,0) fmt6 Mac Roman
        # subtable is deliberately excluded: it is the 227-entry legacy table
        # A8 names as the thing that inflates an all-subtable union, and it
        # cannot carry U+2800 at all.
        per = {}
        for t in f["cmap"].tables:
            if not t.isUnicode():
                continue
            key = "(%d,%d)/fmt%d" % (t.platformID, t.platEncID, t.format)
            per[key] = sum(1 for c in range(0x2800, 0x2900) if c in t.cmap)
        R.check(len(per) >= 2, "A8", st, "fewer than two Unicode cmap subtables: %s" % per)
        r["braille_per_subtable"] = per
        bad = {k: v for k, v in per.items() if v != 256}
        R.check(not bad, "A8", st, "braille not 256 in every cmap subtable: %s" % bad)

        # U+2800 is its OWN contour-less glyph with advance 1200, never an
        # alias of space or .notdef (D12/E6)
        g2800 = cm.get(0x2800)
        if R.check(g2800 is not None, "A8", st, "U+2800 absent"):
            R.check(g2800 not in (".notdef", "space", "nbspace"), "A8", st,
                    "U+2800 aliased to %r" % g2800)
            others = [cm.get(c) for c in (0x20, 0xA0) if cm.get(c)]
            R.check(g2800 not in others, "A8", st,
                    "U+2800 shares glyph %r with space/nbspace" % g2800)
            bp = BoundsPen(gs)
            gs[g2800].draw(bp)
            R.check(bp.bounds is None, "A8", st, "U+2800 glyph %r has contours %s" % (g2800, bp.bounds))
            R.check(f["hmtx"][g2800][0] == CELL, "A8", st,
                    "U+2800 advance %d != 1200" % f["hmtx"][g2800][0])

        blocks = {}
        for name, lo, hi, floor in BLOCKS:
            n = sum(1 for c in range(lo, hi + 1) if c in cm)
            blocks[name] = n
            R.check(n >= floor, "A8", st, "%s %d < %d" % (name, n, floor))
        r["blocks"] = blocks

        subs = [(t.platformID, t.platEncID, t.format) for t in f["cmap"].tables]
        R.check(any(s[2] == 4 for s in subs) and any(s[2] == 12 for s in subs),
                "A8", st, "cmap lacks fmt4 and/or fmt12: %s" % subs)
        R.check(max(cm) >= 0xF1AF0, "A8", st, "max codepoint %s < 0xF1AF0" % hex(max(cm)))

        boxes = {}
        for c in SPAN_CELL:
            bp = BoundsPen(gs)
            gs[cm[c]].draw(bp)
            x0, _, x1, _ = bp.bounds
            boxes["U+%04X" % c] = (x0, x1)
            R.check(x0 <= 0 and x1 >= CELL, "A8", st,
                    "U+%04X does not span the cell: x %g..%g" % (c, x0, x1))
        r["box_span"] = boxes
        rows[st] = r

    # italic/Roman cmap parity - this is what caught the U+019D hole (S4(2))
    for rst, ist in zip(ROMAN, ITALIC):
        if rst not in fonts or ist not in fonts:
            continue
        missing = sorted(set(fonts[rst].getBestCmap()) - set(fonts[ist].getBestCmap()))
        R.check(not missing, "A8", "%s/%s" % (rst, ist),
                "%d codepoints in the Roman and not the italic: %s"
                % (len(missing), ["U+%04X" % c for c in missing[:12]]))
    R.data["A8"] = rows


# --------------------------------------------------------------------------
# A9 - nothing lost + S7b
# --------------------------------------------------------------------------
def a9(R, out, fonts):
    norm = os.path.join(out, "work", "norm")
    have_norm = os.path.isdir(norm)
    if not have_norm:
        R.note("A9", "no <out>/work/norm - the superset check was SKIPPED")
    aligned = os.path.join(out, "work", "aligned")

    for st, f in fonts.items():
        feats = collections.Counter()
        for fr in f["GSUB"].table.FeatureList.FeatureRecord:
            feats[fr.FeatureTag] += len(fr.Feature.LookupListIndex)
        R.check(feats.get("calt") == CALT_LOOKUPS, "A9", st,
                "calt %s lookups, expected %d" % (feats.get("calt"), CALT_LOOKUPS))
        miss = GSUB_NEED - set(feats)
        R.check(not miss, "A9", st, "GSUB features missing %s" % sorted(miss))
        R.check("GDEF" in f, "A9", st, "no GDEF")
        gpos = {fr.FeatureTag for fr in f["GPOS"].table.FeatureList.FeatureRecord} if "GPOS" in f else set()
        R.check("mark" in gpos, "A9", st, "GPOS 'mark' feature absent")

        if have_norm:
            p = os.path.join(norm, st + ".ttf")
            if not os.path.exists(p):
                R.fail("A9", st, "no normalised face at %s" % p)
            else:
                s = TTFont(p, recalcTimestamp=False, recalcBBoxes=False)
                lost = sorted(set(s.getBestCmap()) - set(f.getBestCmap()))
                R.check(not lost, "A9", st, "lost %d codepoints vs work/norm: %s"
                        % (len(lost), ["U+%04X" % c for c in lost[:12]]))
                sf = {fr.FeatureTag for fr in s["GSUB"].table.FeatureList.FeatureRecord}
                lostf = sorted(sf - set(feats))
                R.check(not lostf, "A9", st, "lost GSUB features vs work/norm: %s" % lostf)

        # S7b (E23): nerd-font-patcher --complete OVERWRITES U+E001..E00A with
        # Pomicons and the displaced Anthropic glyphs are gone from the font
        # entirely.  The re-graft must put them back as <s6 name>.apua.
        ap = os.path.join(aligned, st + ".ttf")
        cm = f.getBestCmap()
        if not os.path.exists(ap):
            R.fail("A9", st, "no S6 face at %s - S7b cannot be checked" % ap)
            continue
        s6 = TTFont(ap, recalcTimestamp=False, recalcBBoxes=False).getBestCmap()
        bad = []
        for cp in PUA_S7B:
            got, want = cm.get(cp), s6.get(cp)
            if want is None:
                continue
            if got != want + ".apua":
                bad.append(("U+%04X" % cp, got, want + ".apua"))
            elif f["hmtx"][got][0] != CELL:
                bad.append(("U+%04X" % cp, got, "advance %d != 1200" % f["hmtx"][got][0]))
        R.check(not bad, "A9", st,
                "S7b PUA re-graft missing - U+E001..E00A are (got, want): %s" % bad)


# --------------------------------------------------------------------------
# A10 - ligature alignment
# --------------------------------------------------------------------------
def a10(R, out, fonts):
    rep_dir = os.path.join(out, "align-report")
    aligned = os.path.join(out, "work", "aligned")
    rows = {}
    for st, f in fonts.items():
        gs, glyf, hmtx = f.getGlyphSet(), f["glyf"], f["hmtx"]
        ligs = [g for g in f.getGlyphOrder() if g.startswith("lig.")]
        bad = {g: hmtx[g][0] for g in ligs if hmtx[g][0] != CELL}
        R.check(not bad, "A10", st, "lig advance != 1200: %s" % dict(list(bad.items())[:5]))

        rp = os.path.join(rep_dir, st + ".json")
        if not os.path.exists(rp):
            R.fail("A10", st, "no align report at %s" % rp)
            continue
        rep = json.load(open(rp))["ligatures"]
        census = dict(collections.Counter(e["mode"] for e in rep))
        R.check(census == ALIGN_CENSUS, "A10", st,
                "align census %s != %s" % (census, ALIGN_CENSUS))
        dys = [e["dy"] for e in rep if e["mode"] == "shift"]
        lo, hi = (min(dys), max(dys)) if dys else (0, 0)
        R.check(DY_LO <= lo and hi <= DY_HI, "A10", st,
                "dy range %+d..%+d outside %d..%d" % (lo, hi, DY_LO, DY_HI))
        byname = {e["lig"]: e["glyph"] for e in rep}

        # the two alignment triad assertions
        deltas = []
        for lig, ref in (("hyphen_hyphen", "hyphen"), ("equal_equal", "equal")):
            g = byname.get(lig)
            if g and g in gs and ref in gs:
                d = ycentre(gs, g) - ycentre(gs, ref)
                deltas.append((lig, round(d, 2)))
                R.check(abs(d) <= LIG_CENTRE_TOL, "A10", st,
                        "%s vs %s y-centre delta %.2f > %d" % (lig, ref, d, LIG_CENTRE_TOL))

        # the patcher must have changed 0 of 136 lig outlines, and the lsb rule
        ap = os.path.join(aligned, st + ".ttf")
        if os.path.exists(ap):
            a = TTFont(ap, recalcTimestamp=False, recalcBBoxes=False)
            ag, ah = a["glyf"], a["hmtx"]
            moved, lsb_bad, rounded = [], [], 0
            for g in ligs:
                if g not in ag:
                    moved.append((g, "absent from the S6 face"))
                    continue
                A = list(map(tuple, ag[g].coordinates))
                B = list(map(tuple, glyf[g].coordinates))
                if len(A) != len(B):
                    moved.append((g, "point count %d -> %d" % (len(A), len(B))))
                else:
                    d = max([max(abs(p[0] - q[0]), abs(p[1] - q[1])) for p, q in zip(A, B)] + [0])
                    if d > LIG_MOVE_TOL:
                        moved.append((g, "outline translated by %d units" % d))
                    elif d:
                        rounded += 1
                if st in ITALIC:
                    gl = glyf[g]
                    if getattr(gl, "numberOfContours", 0) > 0 and hmtx[g][1] != gl.xMin:
                        lsb_bad.append((g, hmtx[g][1], gl.xMin))
                elif ah[g][1] != hmtx[g][1]:
                    lsb_bad.append((g, hmtx[g][1], ah[g][1]))
            R.check(not moved, "A10", st,
                    "the patcher TRANSLATED %d of %d lig outlines (> %d unit): %s"
                    % (len(moved), len(ligs), LIG_MOVE_TOL, moved[:5]))
            R.check(not lsb_bad, "A10", st,
                    "lsb rule broken on %d lig glyphs (%s): %s"
                    % (len(lsb_bad), "lsb==xMin for sheared italics" if st in ITALIC
                       else "lsb unchanged for Roman", lsb_bad[:5]))
        else:
            R.fail("A10", st, "no S6 face at %s - the 0-of-136 outline check was skipped" % ap)

        # italic shear: lig.11 stem slope within 0.5 deg of the host's own bar
        if st in ITALIC:
            a, b = slope_deg(glyf, byname.get("bar_bar", "lig.11")), slope_deg(glyf, "bar")
            if a is None or b is None:
                R.fail("A10", st, "could not measure stem slope (lig.11=%s bar=%s)" % (a, b))
            else:
                R.check(abs(a - b) <= SLOPE_TOL_DEG, "A10", st,
                        "lig.11 stem slope %.2f deg vs host bar %.2f deg, delta %.2f > %.1f "
                        "(an un-sheared ligature in an italic face)" % (a, b, abs(a - b), SLOPE_TOL_DEG))

        # cross-ligature consistency, TOL = 70 units (spec 5)
        cross = {}
        fams = [("bar", ["bar_bar", "braceleft_bar", "bar_braceright",
                         "bracketleft_bar", "bar_bracketright"], "vert"),
                ("equal", ["equal_equal", "numbersign_equal"], "horiz"),
                ("slash", ["slash_slash", "backslash_slash", "slash_backslash"], "bbox")]
        for label, members, kind in fams:
            cent = {}
            for m in members:
                g = byname.get(m)
                if not g or g not in glyf:
                    continue
                if kind == "vert":
                    cs = [c for c in contour_boxes(glyf, g) if (c[3] - c[1]) > 400 and (c[2] - c[0]) < 700]
                elif kind == "horiz":
                    cs = [c for c in contour_boxes(glyf, g) if (c[2] - c[0]) > 250 and (c[3] - c[1]) < 300]
                else:
                    cs = contour_boxes(glyf, g)
                if cs:
                    cent[m] = sum((c[1] + c[3]) / 2.0 for c in cs) / len(cs)
            if len(cent) >= 2:
                spread = max(cent.values()) - min(cent.values())
                cross[label] = round(spread, 2)
                R.check(spread <= CROSS_TOL, "A10", st,
                        "cross-ligature %s spread %.1f > %d units: %s"
                        % (label, spread, CROSS_TOL, {k: round(v, 1) for k, v in cent.items()}))
        rows[st] = dict(census=census, dy=(lo, hi), triad=deltas, cross=cross,
                        ligs=len(ligs), lig_rounded_1u=rounded)
    R.data["A10"] = rows


# --------------------------------------------------------------------------
# A13 - desktop matching
# --------------------------------------------------------------------------
def a13(R, out, conf, xdg):
    desk = os.path.join(out, "desktop")
    if not os.path.isdir(desk) or not [n for n in os.listdir(desk) if n.endswith(".ttf")]:
        R.count(False, "A13", "desktop", "no desktop faces in the out-dir - desktop matching "
                                         "was NOT checked")
        return

    def match(query, fmt):
        rc, so, se = fc(conf, xdg, ["fc-match", "-f", fmt, query])
        return so

    got = match("Anthropic Sans", "%{file|basename}|%{index}\n").strip()
    R.check(got == "AnthropicSans-Roman.ttf|0", "A13", "sans",
            "fc-match 'Anthropic Sans' -> %r, expected AnthropicSans-Roman.ttf|0" % got)
    got = match("Anthropic Sans:weight=bold", "%{style}\n").strip()
    R.check(got and not got.startswith("Display"), "A13", "sans-bold",
            "fc-match 'Anthropic Sans:weight=bold' -> style %r, expected a Text instance" % got)
    got = match("Anthropic Serif", "%{style}|%{weight}\n").strip()
    R.check(got.endswith("|80"), "A13", "serif",
            "fc-match 'Anthropic Serif' -> %r, expected a Text Regular at weight 80" % got)

    # the three FACE-LEVEL assertions (C16) - all three fail on the unrepaired
    # Serif and pass on the repaired one
    rc, so, _ = fc(conf, xdg, ["fc-scan", "--format", "%{index}\t%{style}\t%{weight}\n",
                               os.path.join(desk, "AnthropicSerif-Roman.ttf")])
    first = so.splitlines()[0] if so.strip() else ""
    parts = first.split("\t")
    R.check(len(parts) == 3 and parts[0] == "0" and parts[2] == "80", "A13", "serif-index0",
            "fc-scan first row %r, expected index 0 ... weight 80" % first)
    for q in ("Anthropic Serif:style=Regular", ":postscriptname=AnthropicSerif-Regular"):
        got = match(q, "%{weight}\t%{index}\n").strip()
        R.check(got == "80\t0", "A13", "serif-face-level",
                "fc-match %r -> %r, expected '80\\t0' (unrepaired gives weight 50)" % (q, got))

    # no duplicate style names on any shipped variable face
    for name in DESKTOP:
        p = os.path.join(desk, name + ".ttf")
        if not os.path.exists(p):
            continue
        rc, so, _ = fc(conf, xdg, ["fc-scan", "--format", "%{style}|%{weight}|%{variable}\n", p])
        styles = [ln.split("|")[0] for ln in so.strip().splitlines() if ln and not ln.endswith("|True")]
        dup = [s for s, n in collections.Counter(styles).items() if n > 1 and s]
        R.check(not dup, "A13", name, "duplicate style names %s" % dup)


# --------------------------------------------------------------------------
# A14 - webfonts isolation
# --------------------------------------------------------------------------
def a14(R, out, conf_tpl, verify, xdg):
    web = os.path.join(out, "webfonts")
    css = os.path.join(web, "css", "anthropic-fonts.css")
    w2 = os.path.join(web, "woff2")
    if not os.path.exists(css):
        R.count(False, "A14", "css", "no %s - webfonts isolation was NOT checked" % css)
        return
    text = open(css).read()
    urls = re.findall(r"url\(\s*['\"]?([^'\")]+)['\"]?\s*\)", text)
    referenced = set()
    for u in urls:
        base = os.path.basename(u.split("?")[0].split("#")[0])
        referenced.add(base)
        R.check(os.path.exists(os.path.join(w2, base)), "A14", "css",
                "url(%s) does not resolve under webfonts/woff2/" % u)
    on_disk = {n for n in os.listdir(w2) if n.endswith(".woff2")}
    R.check(referenced == on_disk, "A14", "css",
            "orphans: css-not-on-disk=%s on-disk-not-in-css=%s"
            % (sorted(referenced - on_disk), sorted(on_disk - referenced)))
    R.data["A14_woff2"] = sorted(on_disk)

    # every woff2 decodes table-for-table identically to its TTF.  The
    # comparison is the SEMANTIC table snapshot, not raw table bytes: woff2
    # transforms glyf/loca and fontTools recompiles on decode, so head's
    # checkSumAdjustment and the gvar/hmtx packing legitimately differ while
    # every value in them is the same.  Measured roundtrip=IDENTICAL on all 7
    # under this snapshot and DIFF on head/gvar/hhea/hmtx under a byte diff.
    # where the woff2's own TTF source may live.  The driver stages the
    # mono-web and icon-variable cuts under work/desktop/ - they are never
    # shipped as desktop faces, but they ARE what webfonts.py encoded.
    search = [os.path.join(out, "desktop"), os.path.join(out, "work", "desktop"),
              os.path.join(out, "work", "mono"), os.path.join(out, "work", "web-ttf")]
    unmatched = []
    for n in sorted(on_disk):
        stem = n[:-6]
        ttf = None
        for d in search:
            cand = os.path.join(d, stem + ".ttf")
            if os.path.exists(cand):
                ttf = cand
                break
        if not ttf:
            unmatched.append(n)
            continue
        a = table_snapshot(TTFont(os.path.join(w2, n), recalcTimestamp=False, recalcBBoxes=False))
        b = table_snapshot(TTFont(ttf, recalcTimestamp=False, recalcBBoxes=False))
        diff = [k for k in sorted(b) if a.get(k) != b[k]]
        R.check(not diff, "A14", n,
                "woff2 does not decode identically to %s: %s" % (os.path.basename(ttf), diff))
    if unmatched:
        R.note("A14", "no same-stem TTF in the out-dir for %s - the decode-identity "
                      "check did NOT run for those" % unmatched)

    # the assertion that proves the glob reject works: a config whose ONLY
    # <dir> is <out>/webfonts must yield zero woff2 rows.  The hazard demo must
    # be the DIRECTORY-SCAN form: fc-scan <file> bypasses <selectfont> and
    # proves parseability only.
    conf = render_conf(conf_tpl, os.path.join(verify, "cache-web"), [web],
                       os.path.join(verify, "fonts-webfonts.conf"))
    rc, so, _ = fc(conf, xdg, ["fc-list", "--format", "%{file}\n"])
    rows = [ln for ln in so.splitlines() if ln.strip().endswith((".woff2", ".woff"))]
    R.check(not rows, "A14", "glob-reject",
            "%d woff2 rows survived the reject block: %s" % (len(rows), rows[:3]))
    rc, so, _ = fc(conf, xdg, ["fc-list", ":", "family"])
    hits = [ln for ln in so.splitlines()
            if re.search(r"Anthropic (Sans|Serif|Mono) Web|^Anthropicons$", ln)]
    R.check(not hits, "A14", "namespace", "web families entered the font namespace: %s" % hits[:3])


# --------------------------------------------------------------------------
# A16 - archive shape
# --------------------------------------------------------------------------
def a16(R, out):
    dist = os.path.join(out, "dist")
    if not os.path.isdir(dist) or not [n for n in os.listdir(dist) if n.endswith(".tar.zst")]:
        R.note("A16", "no tarballs under <out>/dist - archive shape NOT checked")
        return
    digests = {}
    for name, min_files in TARBALLS.items():
        p = os.path.join(dist, name)
        if not os.path.exists(p):
            R.fail("A16", name, "missing %s" % p)
            continue
        stem = name.split(".")[0]
        R.check(stem and name == stem + ".tar.zst", "A16", name,
                "basename has an interior dot; requireFile's name is taken at the first dot")
        digests[name] = hashlib.sha256(open(p, "rb").read()).hexdigest()

        f = subprocess.run(["zstd", "-lv", p], capture_output=True, text=True, check=False).stdout
        R.check("Decompressed Size" not in f, "A16", name,
                "zstd -lv prints a Decompressed Size line - not the streamed form")
        m = re.search(r"Window Size:\s*([\d.]+)\s*(\w+)", f)
        R.check(m and float(m.group(1)) > 0, "A16", name,
                "zstd -lv Window Size is 0 or absent - the empty-frame trap")
        R.check(re.search(r"Frames:\s*1\b", f), "A16", name, "zstd -lv Frames != 1")

        raw = subprocess.run(["zstd", "-dc", p], capture_output=True, check=False).stdout
        import io
        tf = tarfile.open(fileobj=io.BytesIO(raw), mode="r:")
        members = tf.getmembers()
        names = [m_.name for m_ in members]
        R.check(not any(n == "./" or n.startswith("./") for n in names), "A16", name,
                "archive carries ./ entries: %s" % [n for n in names if n.startswith("./")][:3])
        owners = {(m_.uid, m_.gid) for m_ in members}
        R.check(owners == {(0, 0)}, "A16", name, "owners %s != {(0, 0)}" % sorted(owners))
        times = {m_.mtime for m_ in members}
        R.check(times == {0}, "A16", name, "entry mtimes %s, expected all 1970-01-01 (@0)" % sorted(times)[:4])
        files = [m_ for m_ in members if m_.isfile()]
        R.check(len(files) >= min_files, "A16", name,
                "%d file(s), expected >= %d" % (len(files), min_files))
        tf.close()
    vals = list(digests.values())
    R.check(len(set(vals)) == len(vals), "A16", "suite",
            "tarball digests are not pairwise distinct: %s" % digests)
    R.data["A16_digests"] = digests

    sums = os.path.join(dist, "SHA256SUMS")
    if os.path.exists(sums):
        listed = {}
        for ln in open(sums):
            parts = ln.split()
            if len(parts) == 2:
                listed[parts[1]] = parts[0]
        for name, d in digests.items():
            R.check(listed.get(name) == d, "A16", name,
                    "SHA256SUMS says %s, file hashes %s" % (listed.get(name), d))
    else:
        R.fail("A16", "dist", "no SHA256SUMS")


# --------------------------------------------------------------------------
def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("--src", default=None,
                    help="the READ-ONLY capture dir; enables A5's negative control")
    ap.add_argument("--allow-partial", action="store_true",
                    help="the out-dir holds a SUBSET of the faces (a smoke build). "
                         "Count assertions degrade to notes; every per-face assertion "
                         "still fails hard.")
    a = ap.parse_args(argv[1:])
    out = os.path.abspath(a.out)
    verify = os.path.join(out, "verify")
    xdg = os.path.join(verify, "xdg")
    os.makedirs(xdg, exist_ok=True)

    here = os.path.dirname(os.path.abspath(__file__))
    conf_tpl = open(os.path.join(here, "fonts.conf.in")).read()

    before = cache_snapshot()
    R = Report(partial=a.allow_partial)

    # the patcher version, from the manifest, never hardcoded
    patcher_version = None
    mpath = os.path.join(out, "manifest.json")
    if os.path.exists(mpath):
        try:
            tools = json.load(open(mpath)).get("tools", {})
            m = NF_VERSION_RE.search(str(tools.get("nerd-font-patcher", "")))
            if m:
                patcher_version = m.group(1)
        except Exception as e:
            R.note("A4", "could not read <out>/manifest.json: %s" % e)

    faces = {}
    for st in STYLES:
        p = os.path.join(out, "nf", "AnthropicMonoNerdFontMono-%s.ttf" % st)
        if os.path.exists(p):
            faces[st] = p
        else:
            R.count(False, "A7", st, "missing terminal face %s" % p)
    fonts = {st: TTFont(p, recalcTimestamp=False, recalcBBoxes=False) for st, p in faces.items()}

    conf_nf = render_conf(conf_tpl, os.path.join(verify, "cache-nf"),
                          [os.path.join(out, "nf")], os.path.join(verify, "fonts-nf.conf"))
    conf_desk = render_conf(conf_tpl, os.path.join(verify, "cache-desktop"),
                            [os.path.join(out, "desktop")],
                            os.path.join(verify, "fonts-desktop.conf"))

    a3(R, out, conf_nf, xdg, faces)
    a4(R, out, fonts, patcher_version)
    a5(R, out, conf_nf, xdg, faces, fonts, a.src)
    a6(R, out, conf_desk, xdg, fonts)
    a7(R, out, fonts)
    a8(R, out, fonts)
    a9(R, out, fonts)
    a10(R, out, fonts)
    a13(R, out, conf_desk, xdg)
    a14(R, out, conf_tpl, verify, xdg)
    a16(R, out)

    after = cache_snapshot()
    if before != after:
        R.fail("A21", "live-runtime", "~/.cache/fontconfig changed during the suite: %s -> %s"
               % (before[:16], after[:16]))
    R.data["A21"] = dict(before=before, after=after, identical=before == after)

    R.data["notes"] = R.notes
    R.data["failures"] = R.fails
    with open(os.path.join(verify, "accept.json"), "w") as fh:
        json.dump(R.data, fh, indent=1, sort_keys=True, default=str)

    for n in R.notes:
        print("NOTE", n)
    for f in R.fails:
        print("FAIL", f)
    print("accept: %d failure(s), %d note(s) -> %s/accept.json" % (len(R.fails), len(R.notes), verify))
    return 1 if R.fails else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
