{ runCommand
, writeShellApplication
, fetchurl
, pandoc
}:
# artifact-render <doc.md> <outdir> — the md-artifact doc lane. One-shot
# markdown -> self-contained snapshot dir (index.html + assets/), servable
# untouched at every rung: file:// app window (rung 0), Caddy file_server
# (tailnet), wrangler pages deploy (public). GFM only — MDX was researched and
# NUKED per Tom 2026-07-11; do not re-add. Flag set verified hands-on in the
# md-renderer-pick workflow (wf_820c910e): raw HTML passthrough, task lists,
# tables, footnotes, GFM alerts, native MathML.
#
# Mermaid: vendored IIFE build (ESM is CORS-blocked from file://), rendered
# client-side like the GitHub md viewer, theme follows prefers-color-scheme.
# Aesthetics: house.css is neutral-structural; the brand kit hook tokens.css is
# DELIBERATELY EMPTY (Tom's ruling — design tokens land at the very end).
let
  mermaid = fetchurl {
    url = "https://cdn.jsdelivr.net/npm/mermaid@11.12.0/dist/mermaid.min.js";
    sha256 = "0jrw6hxv4cq31lk9pddkkpq0d5wvz7fpxmb5ag4cqdxkjzx7vqq7";
  };

  assets = runCommand "artifact-render-assets" { } ''
    mkdir -p $out
    cp ${./house.html} $out/house.html
    cp ${./house.css} $out/house.css
    cp ${./tokens.css} $out/tokens.css
    cp ${mermaid} $out/mermaid.min.js
  '';
in
writeShellApplication {
  name = "artifact-render";
  runtimeInputs = [ pandoc ];
  text = ''
    doc="''${1:?usage: artifact-render <doc.md> <outdir>}"
    out="''${2:?usage: artifact-render <doc.md> <outdir>}"

    mkdir -p "$out/assets"
    cp ${assets}/house.css ${assets}/tokens.css ${assets}/mermaid.min.js "$out/assets/"
    chmod u+w "$out/assets/"*

    # title = first h1, else the filename
    title=$(sed -n '/^# /{s/^# //p;q}' "$doc")
    [ -n "$title" ] || title=$(basename "$doc" .md)

    pandoc \
      -f gfm+tex_math_dollars \
      -t html5 \
      --mathml \
      --wrap=none \
      --standalone \
      --template ${assets}/house.html \
      --metadata title="$title" \
      -o "$out/index.html" \
      "$doc"

    echo "rendered: $out/index.html (view: artifact-view $out)"
  '';
}
