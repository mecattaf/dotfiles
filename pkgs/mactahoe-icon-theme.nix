# MacTahoe icon theme — stock default (blue folders).
#
# 100% STOCK, zero flags beyond --name. Previously this built the `-t grey`
# variant (grey #686868 folders, itself also stock upstream); reverted to the
# default blue folder color 2026-07-04. The only reason this derivation exists
# at all is that MacTahoe (unlike its siblings whitesur-icon-theme /
# colloid-icon-theme) isn't in nixpkgs yet — re-check occasionally and drop
# this file when it lands.
#
# The default build emits all three dirs (COLOR_VARIANTS=('' '-light' '-dark')):
# MacTahoe, MacTahoe-light, MacTahoe-dark.
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
  pname = "mactahoe-icon-theme";
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
    # No --theme flag: default = blue folders.
    ./install.sh --dest $out/share/icons --name MacTahoe
    jdupes --link-soft --recurse $out/share
    runHook postInstall
  '';

  # drop dangling symlinks upstream ships (same as nixpkgs whitesur-icon-theme)
  postFixup = ''
    find $out/share/icons -xtype l -delete
  '';

  meta = {
    description = "MacTahoe icon theme (stock vinceliuice build, default blue folders)";
    homepage = "https://github.com/vinceliuice/MacTahoe-icon-theme";
    license = lib.licenses.gpl3Plus;
    platforms = lib.platforms.linux;
  };
}
