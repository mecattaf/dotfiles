# nerd-font-patcher with glyphnames.json beside the wrapped script.
#
# nixpkgs' nerd-font-patcher ships NO glyphnames.json, and the patcher
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
#
# THE PATCHER VERSION IS PINNED HERE, NOT BY THE NIXPKGS PIN. Measured
# 2026-10-01: the flake's effective nixpkgs (e2587ca, unchanged since before
# the 2026-09-17 press) ships nerd-font-patcher 3.4.0, while the installed
# faces carry "Nerd Fonts 3.5.1" in nameID5 and 214 more icons (10623 against
# 10409 mapped icon codepoints on Regular), and 3.5.1's FontnameParser strips
# `Regular` from the RIBBI PostScript name, which tests/resolve.py and the docs
# expect. A press on 3.4.0 therefore produced a DIFFERENT font. version and src
# are overridden to the 3.5.1 release so the press no longer depends on where
# nixos-unstable happens to sit; bump this file deliberately, never by a lock
# update. 3.5.1 also ships bin/scripts/braille, which installPhase must copy.
{
  nerd-font-patcher,
  fetchurl,
  fetchzip,
}:
let
  version = "3.5.1";
  glyphnames = fetchurl {
    url = "https://raw.githubusercontent.com/ryanoasis/nerd-fonts/v${version}/glyphnames.json";
    hash = "sha256-0vpmFaOOtSdGLLcf8XqkSx1kU9Q37SY6uNW0WDk2aeg=";
  };
in
nerd-font-patcher.overrideAttrs (o: {
  inherit version;
  # nixpkgs' use-nix-paths.patch is version-specific (3.5.1 adds the braille
  # sys.path line and moved hunks); this is the 3.5.1 nixpkgs copy, vendored
  # verbatim from nixpkgs f45c6f04 pkgs/by-name/ne/nerd-font-patcher.
  patches = [ ./nerd-font-patcher-use-nix-paths-3.5.1.patch ];
  src = fetchzip {
    url = "https://github.com/ryanoasis/nerd-fonts/releases/download/v${version}/FontPatcher.zip";
    hash = "sha256-gZ41oZPnsVLcchA58eJ1Vl28ccqePpOZd/ZCEKYywX4=";
    stripRoot = false;
  };
  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin $out/share $out/lib
    install -Dm755 font-patcher $out/bin/nerd-font-patcher
    cp -ra src/glyphs $out/share/
    cp -ra bin/scripts/{braille,name_parser} $out/lib/
    cp ${glyphnames} $out/bin/glyphnames.json
    runHook postInstall
  '';
})
