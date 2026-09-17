#!/usr/bin/env python3
"""fontbuilder - the build record (manifest.json, PROVENANCE.tsv, origins.txt).

manifest.json is the durable answer to "where did this byte come from" once the
tarball is 0444 on the NAS: every source digest, every donor path + licence +
copied glyph census, every tool version, the align mode and braille dy,
SOURCE_DATE_EPOCH, and the sha256 of every artifact.

PROVENANCE.tsv is regenerated from the shipped faces' post tables: every glyph
whose name carries a donor suffix (.jb .dv .maple .dvr .jbs .dvs .mps .dvrs
.synth .apua) is listed with its codepoint and face. Nothing separate can drift.
"""
import collections
import datetime
import hashlib
import json
import os
import subprocess

TAGS = ("jb", "dv", "maple", "dvr", "jbs", "dvs", "mps", "dvrs", "synth", "apua")
LICENCES = {
    "jb": "JetBrains Mono 2.304 via nerd-fonts.jetbrains-mono (SIL OFL-1.1)",
    "jbs": "JetBrains Mono 2.304 upright cut, sheared 10 deg (SIL OFL-1.1)",
    "dv": "DejaVu Sans Mono 2.37 (Bitstream Vera + Arev, permissive)",
    "dvr": "DejaVu Sans Mono 2.37 Regular weight, weight fall-through (Bitstream Vera + Arev)",
    "dvs": "DejaVu Sans Mono 2.37 upright cut, sheared 10 deg (Bitstream Vera + Arev)",
    "dvrs": "DejaVu Sans Mono 2.37 Regular upright, sheared 10 deg (Bitstream Vera + Arev)",
    "maple": "Maple Mono NF 7.9 (SIL OFL-1.1)",
    "mps": "Maple Mono NF 7.9 upright cut, sheared 10 deg (SIL OFL-1.1)",
    "synth": "synthesised blank braille cell U+2800 (no donor maps it in Maple italics)",
    "apua": "Anthropic's own PUA glyph, re-grafted after the patcher overwrote it with Pomicons",
}


def sha(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def tool_versions():
    out = {}
    for key, argv in (("nerd-font-patcher", ["nerd-font-patcher", "--version"]),
                      ("fontforge", ["fontforge", "--version"]),
                      ("zstd", ["zstd", "--version"]),
                      ("tar", ["tar", "--version"]),
                      ("pango-view", ["pango-view", "--version"])):
        try:
            r = subprocess.run(argv, capture_output=True, text=True, timeout=60)
            out[key] = (r.stdout or r.stderr).strip().splitlines()[0]
        except Exception as exc:  # noqa: BLE001
            out[key] = "unavailable: %s" % exc
    try:
        import fontTools
        out["fonttools"] = fontTools.version
    except Exception:  # noqa: BLE001
        pass
    for key in ("FONTBUILDER_LIGATURIZER", "FONTBUILDER_FIRA", "FONTBUILDER_GLYPHNAMES",
                "FONTBUILDER_DONOR_JBM", "FONTBUILDER_DONOR_DEJAVU", "FONTBUILDER_DONOR_MAPLE"):
        out[key] = os.environ.get(key, "")
    return out


def provenance(out_dir, faces):
    from fontTools.ttLib import TTFont
    rows, census = [], {}
    for face in faces:
        f = TTFont(face, lazy=True)
        rev = {v: k for k, v in f.getBestCmap().items()}
        counts = collections.Counter()
        for gn in f.getGlyphOrder():
            tag = gn.rsplit(".", 1)[-1] if "." in gn else None
            if tag in TAGS:
                counts[tag] += 1
                cp = rev.get(gn)
                rows.append((os.path.basename(face), "U+%04X" % cp if cp is not None else "-", gn, tag))
        census[os.path.basename(face)] = dict(counts)
        f.close()
    path = os.path.join(out_dir, "PROVENANCE.tsv")
    with open(path, "w", encoding="utf-8") as fh:
        fh.write("face\tcodepoint\tglyph\tdonor\tlicence\n")
        for face, cp, gn, tag in rows:
            fh.write("%s\t%s\t%s\t%s\t%s\n" % (face, cp, gn, tag, LICENCES[tag]))
    return path, census


def origins_text(sources_sha, tools):
    lines = ["Source material: the anthropic.com/claude.ai served webfonts captured 2026-08-31 into",
             "~/colors/waves/capture (14 files pinned in pkgs/fontbuilder/data/sources.sha256):"]
    for line in open(sources_sha, encoding="utf-8"):
        line = line.strip()
        if line:
            h, _, rel = line.partition("  ")
            lines.append("  %s  %s" % (h, rel))
    lines.append("Donors (outlines grafted for completeness, ligatures, and Nerd glyphs):")
    lines.append("  JetBrains Mono NFM 2.304 (SIL OFL-1.1)  %s" % tools.get("FONTBUILDER_DONOR_JBM", ""))
    lines.append("  DejaVu Sans Mono 2.37 (Bitstream Vera + Arev) %s" % tools.get("FONTBUILDER_DONOR_DEJAVU", ""))
    lines.append("  Maple Mono NF 7.9 (SIL OFL-1.1)               %s" % tools.get("FONTBUILDER_DONOR_MAPLE", ""))
    lines.append("  Fira Code 3.001 ligature art (SIL OFL-1.1), Ligaturizer rev c4065187  %s" % tools.get("FONTBUILDER_FIRA", ""))
    lines.append("  Nerd Fonts patcher: %s" % tools.get("nerd-font-patcher", "nerd-font-patcher"))
    lines.append("Anthropic Sans/Serif/Mono/Anthropicons are Anthropic PBC brand faces (vendor BSPK LLC) with no")
    lines.append("published licence; this copy is for Tom's personal use on his own machines only.")
    return "\n".join(lines) + "\n"


def write(out_dir, src_dir, epoch, align_mode, braille_dy, stages, sources_sha, faces):
    tools = tool_versions()
    prov_path, census = provenance(out_dir, faces)
    doc = {
        "schema": 2,
        "generated": datetime.datetime.fromtimestamp(epoch, datetime.timezone.utc).isoformat(),
        "source_date_epoch": epoch,
        "capture_dir": src_dir,
        "align_mode": align_mode,
        "braille_dy": braille_dy,
        "glyphnames_override": True,
        "stages": stages,
        "tools": tools,
        "sources": [l.strip() for l in open(sources_sha, encoding="utf-8") if l.strip()],
        "donor_census": census,
        "artifacts": {},
    }
    for sub in ("nf", "desktop", "webfonts/woff2", "webfonts/css", "dist"):
        d = os.path.join(out_dir, sub)
        if os.path.isdir(d):
            doc["artifacts"][sub] = {f: sha(os.path.join(d, f)) for f in sorted(os.listdir(d))
                                     if os.path.isfile(os.path.join(d, f))}
    with open(os.path.join(out_dir, "manifest.json"), "w", encoding="utf-8") as fh:
        json.dump(doc, fh, indent=2, sort_keys=True)
        fh.write("\n")
    with open(os.path.join(out_dir, "origins.txt"), "w", encoding="utf-8") as fh:
        fh.write(origins_text(sources_sha, tools))
    return doc
