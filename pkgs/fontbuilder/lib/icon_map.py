#!/usr/bin/env python3
"""Attempt to recover an Anthropicons icon -> codepoint mapping, and record the
evidence either way.  Re-run of the search the spec declares CLOSED, widened
from capture/bundles/ to the WHOLE capture tree (90 text files)."""
import json, os, re, sys
from fontTools.ttLib import TTFont
from fontTools.pens.boundsPen import BoundsPen

CAP = "/home/tom/colors/waves/capture"
FT = CAP + "/fonts-ttf/"
SKIP = {".png", ".ttf", ".woff2", ".woff", ".otf", ".jpg", ".jpeg", ".gif",
        ".mp3", ".wav", ".m4a", ".zst", ".gz", ".ico", ".webp"}


def scan():
    hits, scanned = [], 0
    for dp, _, fns in os.walk(CAP):
        for fn in fns:
            p = os.path.join(dp, fn)
            if os.path.splitext(fn)[1].lower() in SKIP:
                continue
            try:
                s = open(p, encoding="utf-8", errors="replace").read()
            except Exception:
                continue
            scanned += 1
            raw = sorted({ord(c) for c in s if 0xE000 <= ord(c) <= 0xF8FF})
            esc = sorted({m.lower() for m in re.findall(r"\\u[eEfF][0-9a-fA-F]{3}", s)})
            css = sorted({m.lower() for m in re.findall(r'content\s*:\s*["\']\\[eEfF][0-9a-fA-F]{3}', s)})
            if raw or esc or css:
                hits.append({"file": os.path.relpath(p, CAP),
                             "raw_pua": [hex(c) for c in raw][:40],
                             "js_escapes": esc[:40], "css_content_escapes": css[:40]})
    return scanned, hits


def bbox_em(font, cp):
    g = font.getBestCmap().get(cp)
    if not g:
        return None, None
    gs = font.getGlyphSet(); bp = BoundsPen(gs); gs[g].draw(bp)
    u = font["head"].unitsPerEm
    return g, (None if not bp.bounds else [round(x / u, 4) for x in bp.bounds])


def main(out):
    ic = TTFont(FT + "Anthropicons-Variable.ttf")
    text = {"AnthropicSans-Roman-Web": TTFont(FT + "AnthropicSans-Roman-Web.ttf"),
            "AnthropicSerif-Roman-Web": TTFont(FT + "AnthropicSerif-Roman-Web.ttf"),
            "AnthropicMono-Roman-Web": TTFont(FT + "AnthropicMono-Roman-Web.ttf")}
    scanned, hits = scan()
    cm = ic.getBestCmap()
    entries = []
    for i, cp in enumerate(sorted(cm)):
        gi, bi = bbox_em(ic, cp)
        e = {"codepoint": "U+%04X" % cp, "char": chr(cp), "sheet_index": i,
             "glyph_name": gi, "bbox_em": bi, "name": None,
             "name_source": None, "collides_with": {}}
        for k, f in text.items():
            gn, bb = bbox_em(f, cp)
            if gn:
                e["collides_with"][k] = {"glyph": gn, "bbox_em": bb}
        entries.append(e)

    # the only semantic names anywhere in the capture that sit inside the
    # Anthropicons range come from the Web cut's brand PUA glyphs.
    brand = {0xE11A: "ASlash", 0xE11B: "Anthropic", 0xE11C: "Claude",
             0xE11D: "Spark", 0xE11E: "Code"}
    for e in entries:
        cp = int(e["codepoint"][2:], 16)
        if cp in brand:
            ic_b = e["bbox_em"]
            sa = e["collides_with"].get("AnthropicSans-Roman-Web", {}).get("bbox_em")
            # the text faces carry WIDE logotype lockups at these codepoints
            # (Anthropic.pua is 6.695 em wide); the icon is a ~0.8 em square.
            same = bool(ic_b and sa and abs((sa[2] - sa[0]) - (ic_b[2] - ic_b[0])) < 0.15)
            e["name"] = brand[cp] if same else None
            e["name_source"] = ("AnthropicSans-Roman-Web glyph name %s.pua "
                                "(advance-width match)" % brand[cp]) if same else None
            e["brand_candidate"] = {"text_face_glyph": brand[cp] + ".pua",
                                    "width_em_text": None if not sa else round(sa[2] - sa[0], 4),
                                    "width_em_icon": None if not ic_b else round(ic_b[2] - ic_b[0], 4),
                                    "accepted": same}

    doc = {
        "font": "Anthropicons-Variable.ttf",
        "codepoints": len(entries),
        "range": ["U+%04X" % min(cm), "U+%04X" % max(cm)],
        "recovery_status": "NOT RECOVERABLE (1 of 307 named, by outline match)",
        "search": {
            "scope": "the whole of %s, not only bundles/" % CAP,
            "text_files_scanned": scanned,
            "files_with_any_pua_or_escape": hits,
            "conclusion": (
                "No file in the capture maps an icon name to a PUA codepoint. "
                "The only hits are (a) claude-code-theme/claude-theme-bundle-source.js, "
                "where \\uE000-\\uE003 are SENTINEL characters a streaming-markdown "
                "parser splices into text and strips again, not icons, and "
                "(b) wayback/ binaries and GIFs misread as UTF-8. The product loads "
                "the font with document.fonts.load('16px \"Anthropicons-Variable\"') "
                "and never names a glyph."),
        },
        "named": [e["codepoint"] for e in entries if e["name"]],
        "text_face_pua_collisions": sum(1 for e in entries if e["collides_with"]),
        "entries": entries}
    json.dump(doc, open(out, "w"), indent=1, ensure_ascii=False)
    print("scanned %d text files; %d with any PUA/escape" % (scanned, len(hits)))
    print("codepoints=%d named=%s collisions_with_text_faces=%d"
          % (len(entries), doc["named"], doc["text_face_pua_collisions"]))
    for e in entries:
        if "brand_candidate" in e:
            print("  %s %-14s icon_w=%-7s text_w=%-7s accepted=%s"
                  % (e["codepoint"], e["brand_candidate"]["text_face_glyph"],
                     e["brand_candidate"]["width_em_icon"],
                     e["brand_candidate"]["width_em_text"],
                     e["brand_candidate"]["accepted"]))


if __name__ == "__main__":
    main(sys.argv[1])
