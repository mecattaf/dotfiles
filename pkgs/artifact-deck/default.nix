{ writeShellApplication
, fetchzip
}:
# artifact-deck-init <dir> — scaffolds a presentation-beta deck: nix-vendored
# reveal.js (no CDN — the original umbrella deck hot-linked cdnjs; that is the
# anti-pattern this fixes), the empty brand-kit hook, and a starter index.html
# Claude then authors directly (full layout freedom — md->slides tools like
# marp/slidev were evaluated and rejected). Output dir is a normal artifact
# snapshot: rehearse via `artifact-view <dir>`, broadcast via publish-artifact.
let
  reveal = fetchzip {
    url = "https://github.com/hakimel/reveal.js/archive/refs/tags/5.2.1.tar.gz";
    sha256 = "1b2pahm4nrxgll30rprd81d17xg0s5fmpcwfx6pmyp7qg3sk963z";
  };
in
writeShellApplication {
  name = "artifact-deck-init";
  text = ''
    out="''${1:?usage: artifact-deck-init <dir>}"

    mkdir -p "$out/assets/reveal"
    cp -r ${reveal}/dist/* "$out/assets/reveal/"
    # one tokens.css for BOTH lanes — the doc lane's copy is the canonical hook
    cp ${../artifact-render/tokens.css} "$out/assets/tokens.css"
    if [ ! -e "$out/index.html" ]; then
      cp ${./template.html} "$out/index.html"
    fi
    chmod -R u+w "$out"

    echo "deck scaffolded: $out (rehearse: artifact-view $out)"
  '';
}
