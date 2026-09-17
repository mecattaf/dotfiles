# nerd-font-patcher with glyphnames.json beside the wrapped script.
#
# nixpkgs' nerd-font-patcher (3.5.1 in the flake pin; 3.4.0 earlier) ships NO glyphnames.json, and the patcher
# looks for it at os.path.dirname(sys.argv[0]). A shim directory holding a
# symlink to the patcher CANNOT work: the nixpkgs wrapper sets sys.argv[0] to
# its own store path on line 9 of .nerd-font-patcher-wrapped, before
# fetch_glyphnames() runs. So the file has to land in the package's own
# $out/bin. It MUST extend installPhase, not postInstall: the package's
# installPhase is a custom string with no `runHook postInstall`, so a
# postInstall override is silently dropped and the build LOOKS like it worked.
#
# Effect (measured): U+E0B0 `uniE0B0` -> `pl-left_hard_divider`, U+F001
# `music.1` -> `fa-music`, U+E62B -> `custom-vim`. cmap, advances, shaping and
# resolution are identical either way; it is a post-table / provenance change
# worth +35 KB per face, and PROVENANCE.tsv needs it to name the Nerd glyphs.
{ nerd-font-patcher, fetchurl }:
let
  glyphnames = fetchurl {
    url = "https://raw.githubusercontent.com/ryanoasis/nerd-fonts/v3.5.1/glyphnames.json";
    hash = "sha256-0vpmFaOOtSdGLLcf8XqkSx1kU9Q37SY6uNW0WDk2aeg=";
  };
in
nerd-font-patcher.overrideAttrs (o: {
  installPhase = o.installPhase + ''
    cp ${glyphnames} $out/bin/glyphnames.json
  '';
})
