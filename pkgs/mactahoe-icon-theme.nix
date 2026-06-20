# MacTahoe icon theme — grey variant.
#
# 100% STOCK. Investigation (2026-06-19) confirmed your grey icons are NOT
# custom: `grey` is a built-in `install.sh -t grey` variant and the grey folder
# color (#686868) comes straight from upstream colors/color-grey/*.svg. The only
# reason it wasn't already available is that MacTahoe (unlike its siblings
# whitesur-icon-theme / colloid-icon-theme) simply isn't in nixpkgs yet.
#
# `install.sh -t grey` emits all three dirs you use: MacTahoe-grey,
# MacTahoe-grey-dark, MacTahoe-grey-light (COLOR_VARIANTS=('' '-light' '-dark')).
#
# Modeled on nixpkgs' whitesur-icon-theme derivation (same upstream author /
# same install.sh). No patch — so this could even be upstreamed to nixpkgs.
{
  lib,
  stdenvNoCC,
  fetchFromGitHub,
  gtk3,
  hicolor-icon-theme,
  jdupes,
}:

stdenvNoCC.mkDerivation {
  pname = "mactahoe-icon-theme-grey";
  version = "0-unstable-2026-06-19";

  src = fetchFromGitHub {
    owner = "vinceliuice";
    repo = "MacTahoe-icon-theme";
    rev = "355f23aaed196d8de3b321e8dacd8d06888d4d96";
    hash = "sha256-YCtpagkXhRwD9NJRvgskq7yf4qr4XqUxQYUfyKD7mUs=";
  };

  nativeBuildInputs = [
    gtk3
    jdupes
  ];

  buildInputs = [ hicolor-icon-theme ];

  # the icon set is ~20k files + symlinks; skip the slow, pointless fixups
  dontPatchELF = true;
  dontRewriteSymlinks = true;
  dontDropIconThemeCache = true;

  postPatch = ''
    patchShebangs install.sh
  '';

  installPhase = ''
    runHook preInstall
    # --name is required: without it the theme dirs inherit the build-dir name.
    ./install.sh --dest $out/share/icons --name MacTahoe --theme grey
    # install.sh always also emits the default (blue) base theme; the grey
    # variants are self-contained (no symlinks into it), and your config only
    # uses MacTahoe-grey*. Drop the unused base to match the old RPM's 3 dirs.
    rm -rf $out/share/icons/MacTahoe $out/share/icons/MacTahoe-dark $out/share/icons/MacTahoe-light
    jdupes --link-soft --recurse $out/share
    runHook postInstall
  '';

  # drop dangling symlinks upstream ships (same as nixpkgs whitesur-icon-theme)
  postFixup = ''
    find $out/share/icons -xtype l -delete
  '';

  meta = {
    description = "MacTahoe grey icon theme (stock vinceliuice build)";
    homepage = "https://github.com/vinceliuice/MacTahoe-icon-theme";
    license = lib.licenses.gpl3Plus;
    platforms = lib.platforms.linux;
  };
}
