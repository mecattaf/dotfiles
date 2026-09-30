#!/usr/bin/env python3
"""fontbuilder - specimen sheets.

    lib/specimen.py <out-dir> [--dpi 192]

Writes, under <out>/specimens/:

    mono-regular.png  mono-semibold.png  mono-italic.png  mono-semibold-italic.png
    four-styles.png          (imagemagick -append of the four above)
    ui-sans-11.png  ui-serif-12.png  ui-mono-11.png
    align-anchor.png  align-none.png  align-side-by-side.png
                             (only when <out>/work/aligned-none/Regular.ttf exists)

PRIMARY RASTERISER: pango-view (nixpkgs#pango, measured 1.57.1).  One command,
the real fontconfig + HarfBuzz + FreeType stack, and it honours a private
FONTCONFIG_FILE.  `hb-view` is NOT in nixpkgs' harfbuzz or harfbuzzFull, which
is why the hermetic chain below exists at all.

TWO MEASURED CAVEATS, both load-bearing:

  1. pango-view applies ONE font per invocation.  A multi-style sheet is
     therefore several invocations composited with `imagemagick -append`
     (nixpkgs#imagemagick).

  2. THE SPECIMEN TEXT MUST BE WRITTEN BY PYTHON, NEVER A SHELL HEREDOC.
     Measured: the PUA / powerline codepoints were silently stripped from a
     heredoc.  Every string in this file is a python literal written to a
     UTF-8 file, and nothing in this module shells out to `cat`, `echo` or a
     heredoc to produce it.

FALLBACK: hb-shape -> fontTools SVGPathPen -> SVG, used ONLY when pango-view
cannot be found.  It needs no fontconfig and no installed font - the face is
named by PATH - so it is also what produces a pre-install specimen at bootstrap
step 5.  hb-shape lives in nixpkgs#harfbuzz.dev; both `harfbuzzFull.bin` and a
bare `harfbuzz` attribute error.

ISOLATION: a private FONTCONFIG_FILE rendered from tests/fonts.conf.in with a
<cachedir> under <out>/verify, AND XDG_CACHE_HOME redirected there too.
fc-cache is never invoked.

THE ALIGN A/B IS TWO FONTCONFIGS, NOT TWO FAMILIES.  <out>/work/aligned/
Regular.ttf and <out>/work/aligned-none/Regular.ttf carry the SAME family name
("Anthropic Mono"), which is the point: the only difference between the two
sheets is the align mode.  Each is rendered under its own config whose single
<dir> holds only that one file, so neither can leak into the other.
"""
from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys

# --------------------------------------------------------------------------
# specimen text - PYTHON LITERALS, never a heredoc
# --------------------------------------------------------------------------
LIG_ROW_1 = "-> => != === <= >= :: |> <- ~> www <=> --> |-> /* */"
LIG_ROW_2 = "++ -- == /= =~ ?: ;; !! && || <> #{ 0xFF ->> =<< <|>"


def mono_text(label):
    """The mono specimen sheet.  Every row exists to answer one question at
    the review window (spec 10 step 5 / A22)."""
    rows = [
        ("face", label),
        ("", ""),
        ("ligatures", LIG_ROW_1),
        ("ligatures", LIG_ROW_2),
        ("", ""),
        # the alignment triad: these three strokes must sit on ONE axis
        ("hyphen  row", "- - - - - - - -    a-b  x-y  --  ---  ----"),
        ("arrow   row", "-> -> -> -> -> ->  a->b x->y  =>  ==>  <-"),
        ("equals  row", "= = = = = = = =    a=b  x=y  ==  ===  <="),
        ("", ""),
        ("prompt", "❯ cd ~/mecattaf/dotfiles && nix build .#fontbuilder"),
        ("powerline", "  main    "),
        # U+2800 must be a BLANK cell, not a box and not a fallback square
        ("braille", "⠀⠁⠃⠇⠏⠟⠿⢿⣿  "
                    "⡀⡄⡆⡇⡏  [⠀] <- U+2800 blank"),
        ("box tree", "├── src/   └── lib/   "
                     "│  ┌─┐ └─┘ ╭─╮ "
                     "═╣  █▓▒░▀▄"),
        ("box join", "┌┬┐"),
        ("", "├┼┤   (the verticals must MEET the horizontals)"),
        ("", "└┴┘"),
        ("", ""),
        # the donor seam (R1): Greek/Cyrillic/braille beside Latin
        ("donor seam", "Latin λμπΣΩαβγδε "
                       "ЖДЯфыв ⣿⢿ Latin"),
        # The last two items are written as eight-digit \U escapes on purpose.
        # A four-digit \u escape consumes EXACTLY four hex digits, so a
        # five-digit codepoint written that way silently becomes a different
        # character followed by a stray digit, and renders as tofu.  Measured
        # here on U+1D538 and U+F07E5 before the fix.
        ("math/marks", "∀∃∈∉∑∏ →←↑↓ "
                       "✓✘✗✔ \U0001D538\U0001D539 \U000F07E5"),
        ("", ""),
        ("latin", "The quick brown fox jumps over 0123456789  Il1O0  {}[]()  `'\"’"),
        ("code", "def merge(donor, host) -> dict[str, int]:  # host_cp |= donor_cp"),
    ]
    width = max(len(a) for a, _ in rows)
    return "\n".join(("%-*s  %s" % (width, a, b)).rstrip() for a, b in rows) + "\n"


UI_SANS = (
    "Anthropic Sans 11 - GTK interface font (org/gnome/desktop/interface font-name)\n"
    "The quick brown fox jumps over the lazy dog - 0123456789 (éèêç"
    "àù) - “quotes”\n"
    "Files  Edit  View  Go  Bookmarks  Help        ← → ↑ ↓\n"
    "Weight ramp: Light Regular Medium Semibold Bold Extrabold\n"
)
UI_SERIF = (
    "Anthropic Serif 12 - document font (document-font-name)\n"
    "Wave-particle duality · § 14.3 · fi fl æ œ - "
    "“the long s” – 1234567890\n"
    "The repaired fvar default means index 0 is Text Regular at weight 80, not Light.\n"
)
UI_MONO = (
    "AnthropicMono NFM 11 - terminal at UI size\n"
    "$ git log --oneline -5 | grep -E 'font|kitty'   # -> => != <= >= ::\n"
    "├── pkgs/fontbuilder/   └── tests/   "
    "⠀⠁⠃⣿  ❯\n"
)

ALIGN_TEXT = (
    "hyphen  - - - -    a-b  --  ---\n"
    "arrow   -> -> ->   a->b =>  ==>\n"
    "equals  = = = =    a=b  ==  ===\n"
    "mixed   -=- ->= =-> a-b=c->d\n"
)


# --------------------------------------------------------------------------
# tools
# --------------------------------------------------------------------------
def find_tool(binary, attr):
    """PATH first; then `nix shell nixpkgs#<attr>`.

    Measured: pango-view IS in nixpkgs#pango (pango 1.57.1, the -bin output);
    magick IS in nixpkgs#imagemagick.  Neither is on this machine's PATH."""
    p = shutil.which(binary)
    if p:
        return p
    try:
        r = subprocess.run(["nix", "shell", "nixpkgs#" + attr, "--command",
                            "sh", "-c", "command -v " + binary],
                           capture_output=True, text=True, check=False, timeout=900)
    except Exception:
        return None
    out = r.stdout.strip().splitlines()
    return out[-1] if r.returncode == 0 and out else None


def fc_env(conf, xdg):
    env = dict(os.environ)
    env["FONTCONFIG_FILE"] = conf
    env["XDG_CACHE_HOME"] = xdg
    env.pop("FONTCONFIG_PATH", None)
    return env


def render_conf(template, cachedir, fontdirs, path):
    os.makedirs(cachedir, exist_ok=True)
    body = "\n".join("  <dir>%s</dir>" % d for d in fontdirs)
    with open(path, "w") as fh:
        fh.write(template.replace("@CACHEDIR@", cachedir).replace("@FONTDIR@", body))
    return path


def pango_sheet(pv, conf, xdg, font, text, out_png, dpi, textdir):
    """ONE pango-view invocation = ONE font.  Text written by python.

    The rendered text is kept under <out>/verify/specimen-text/ as evidence of
    exactly which codepoints went in - specimens/ stays PNG-only."""
    os.makedirs(textdir, exist_ok=True)
    txt = os.path.join(textdir, os.path.basename(out_png)[:-4] + ".txt")
    with open(txt, "w", encoding="utf-8") as fh:
        fh.write(text)
    argv = [pv, "--font=" + font, "--dpi=%g" % dpi, "-q", "--margin=28",
            "--background=#faf9f5", "--foreground=#191817",
            "--hinting=slight", "--antialias=gray",
            "-o", out_png, txt]
    r = subprocess.run(argv, capture_output=True, text=True, env=fc_env(conf, xdg), check=False)
    if r.returncode != 0 or not os.path.exists(out_png):
        raise RuntimeError("pango-view failed for %r: %s" % (font, (r.stderr or r.stdout).strip()))
    return out_png


# --------------------------------------------------------------------------
# hermetic fallback: hb-shape -> SVGPathPen -> SVG.  No fontconfig at all.
# --------------------------------------------------------------------------
def hermetic_svg(rows, out_svg, px=64, pad=10, label_w=260):
    """rows = [(label, font_path, text), ...].  Used ONLY when pango-view is
    unavailable; the face is named by PATH so a specimen can never silently
    render a fallback family the way an fc-match based path can."""
    import json as _json

    from fontTools.pens.svgPathPen import SVGPathPen
    from fontTools.ttLib import TTFont

    hb = find_tool("hb-shape", "harfbuzz.dev")
    if hb is None:
        raise RuntimeError("neither pango-view nor hb-shape is available")
    lines, width = [], 0
    for label, path, text in rows:
        f = TTFont(path)
        gs = f.getGlyphSet()
        order = f.getGlyphOrder()
        items = _json.loads(subprocess.run([hb, "--output-format=json", path, text],
                                           capture_output=True, text=True,
                                           check=True).stdout)
        x, segs = 0, []
        for it in items:
            gn = order[it["g"]] if isinstance(it["g"], int) else it["g"]
            pen = SVGPathPen(gs)
            gs[gn].draw(pen)
            d = pen.getCommands()
            if d:
                segs.append('<path d="%s" transform="translate(%g,0)"/>' % (d, x + it.get("dx", 0)))
            x += it["ax"]
        width = max(width, x)
        lines.append((label, segs))
    scale = px / 2000.0
    h = int((len(lines) * 1.55 + 0.6) * px)
    w = int(width * scale) + 2 * pad + label_w
    parts = ['<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d">'
             % (w, h, w, h), '<rect width="100%" height="100%" fill="#faf9f5"/>']
    y = px * 1.25
    for label, segs in lines:
        parts.append('<text x="%d" y="%d" font-family="DejaVu Sans" font-size="%d" '
                     'fill="#8a8578">%s</text>' % (pad, y - px * 0.25, int(px * 0.30), label))
        parts.append('<g transform="translate(%d,%g) scale(%g,-%g)" fill="#191817">%s</g>'
                     % (pad + label_w - 10, y, scale, scale, "".join(segs)))
        y += px * 1.55
    parts.append("</svg>")
    with open(out_svg, "w", encoding="utf-8") as fh:
        fh.write("\n".join(parts))
    return out_svg


# --------------------------------------------------------------------------
def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("--dpi", type=float, default=192.0)
    a = ap.parse_args(argv[1:])
    out = os.path.abspath(a.out)
    spec = os.path.join(out, "specimens")
    verify = os.path.join(out, "verify")
    xdg = os.path.join(verify, "xdg")
    os.makedirs(spec, exist_ok=True)
    os.makedirs(xdg, exist_ok=True)

    here = os.path.dirname(os.path.abspath(__file__))
    tplpath = os.path.join(os.path.dirname(here), "tests", "fonts.conf.in")
    tpl = open(tplpath).read()

    pv = find_tool("pango-view", "pango")
    written = []

    if pv is None:
        print("specimen: pango-view not found - falling back to the hermetic "
              "hb-shape -> SVG path", file=sys.stderr)
        rows = []
        for style, label in (("Regular", "Regular"), ("SemiBold", "SemiBold"),
                             ("Italic", "Italic"), ("SemiBoldItalic", "SemiBold Italic")):
            p = os.path.join(out, "nf", "AnthropicMonoNerdFontMono-%s.ttf" % style)
            if os.path.exists(p):
                rows.append((label, p, LIG_ROW_1))
        svg = hermetic_svg(rows, os.path.join(spec, "four-styles.svg"))
        print(svg)
        return 0

    textdir = os.path.join(verify, "specimen-text")
    conf = render_conf(tpl, os.path.join(verify, "cache-specimen"),
                       [os.path.join(out, "nf"), os.path.join(out, "desktop")],
                       os.path.join(verify, "fonts-specimen.conf"))

    MONO = [("mono-regular.png", "AnthropicMono NFM 16",
             "AnthropicMono Nerd Font Mono  Regular  16 pt"),
            ("mono-semibold.png", "AnthropicMono NFM SemiBold 16",
             "AnthropicMono Nerd Font Mono  SemiBold  16 pt"),
            ("mono-italic.png", "AnthropicMono NFM Italic 16",
             "AnthropicMono Nerd Font Mono  Italic  16 pt"),
            ("mono-semibold-italic.png", "AnthropicMono NFM SemiBold Italic 16",
             "AnthropicMono Nerd Font Mono  SemiBold Italic  16 pt")]
    sheets = []
    for name, font, label in MONO:
        p = pango_sheet(pv, conf, xdg, font, mono_text(label), os.path.join(spec, name),
                        a.dpi, textdir)
        sheets.append(p)
        written.append(p)

    for name, font, text in (("ui-sans-11.png", "Anthropic Sans 11", UI_SANS),
                             ("ui-serif-12.png", "Anthropic Serif 12", UI_SERIF),
                             ("ui-mono-11.png", "AnthropicMono NFM 11", UI_MONO)):
        written.append(pango_sheet(pv, conf, xdg, font, text, os.path.join(spec, name),
                                   a.dpi, textdir))

    magick = find_tool("magick", "imagemagick")
    if magick and len(sheets) == 4:
        four = os.path.join(spec, "four-styles.png")
        r = subprocess.run([magick] + sheets + ["-background", "#faf9f5", "-append", four],
                           capture_output=True, text=True, check=False)
        if r.returncode == 0 and os.path.exists(four):
            written.append(four)
        else:
            print("specimen: imagemagick -append failed: %s" % (r.stderr or r.stdout).strip(),
                  file=sys.stderr)
    elif not magick:
        print("specimen: imagemagick not found - four-styles.png not composited", file=sys.stderr)

    # the align A/B: SAME family name, TWO configs, one <dir> each
    anchor = os.path.join(out, "work", "aligned", "Regular.ttf")
    none = os.path.join(out, "work", "aligned-none", "Regular.ttf")
    if os.path.exists(none) and os.path.exists(anchor):
        pair = []
        for tag, face in (("anchor", anchor), ("none", none)):
            d = os.path.join(verify, "align-%s-fonts" % tag)
            os.makedirs(d, exist_ok=True)
            dst = os.path.join(d, os.path.basename(face))
            shutil.copyfile(face, dst)
            c = render_conf(tpl, os.path.join(verify, "cache-align-%s" % tag), [d],
                            os.path.join(verify, "fonts-align-%s.conf" % tag))
            p = pango_sheet(pv, c, xdg, "Anthropic Mono 16",
                            "align mode: %s\n\n" % tag + ALIGN_TEXT,
                            os.path.join(spec, "align-%s.png" % tag), a.dpi, textdir)
            pair.append(p)
            written.append(p)
        if magick and len(pair) == 2:
            sbs = os.path.join(spec, "align-side-by-side.png")
            r = subprocess.run([magick] + pair + ["-background", "#faf9f5", "+append", sbs],
                               capture_output=True, text=True, check=False)
            if r.returncode == 0 and os.path.exists(sbs):
                written.append(sbs)
    else:
        print("specimen: no <out>/work/aligned-none/Regular.ttf - the align A/B "
              "(G1 decision 1) was NOT rendered", file=sys.stderr)

    print("pango-view: %s" % pv)
    for p in written:
        print(p)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
