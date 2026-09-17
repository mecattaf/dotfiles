# Anthropic webfonts — woff2 + a ready-made @font-face sheet, for local pages
# and artifacts. Same NAS-pinned scheme as ./sf-pro.nix.
#
# THIS PACKAGE IS DELIBERATELY NOT IN fonts.packages, and the hazard is real and
# ORDER-DEPENDENT. Measured 2026-09-17 with a config whose only <dir> is a
# package STORE ROOT — exactly what fonts.packages produces, via the 20 store-root
# <dir> entries in /etc/fonts/conf.d/00-nixos-cache.conf (NOT
# 10-nixos-rendering.conf, which carries zero <dir> and only hinting rules; and
# plain `grep -r` skips those symlinks, use `grep -R`): fc-list returned the 2
# TTFs AND all 7 woff2 — 68 pattern rows — from share/webfonts/ three levels
# down. With the webfonts dir scanned BEFORE share/fonts,
# `fc-match "Anthropic Sans"` returned the .woff2, beating the byte-equivalent
# TTF purely on directory order; every face the TTF lacks (:italic,
# :weight=bold:italic, "Anthropic Mono", sans-serif, Anthropicons) resolved to a
# woff2 even when the TTF won for Roman; and `pango-view --font='Anthropic Serif
# 20'` rasterised FROM the woff2. Not cosmetic.
#
# The evidence form matters: `fc-scan <file>` bypasses <selectfont> and proves
# only PARSEABILITY, not indexing. The claim above is the fc-list directory-scan
# result.
#
# So the install path is home.packages (home/home.nix), where home-manager's
# ~/.config/fontconfig/conf.d/10-hm-fonts.conf adds only <profile>/share/fonts
# and <profile>/lib/X11/fonts, and the prefix is share/webfonts. Belt and
# braces, modules/common.nix ships a glob <rejectfont> for */share/webfonts/*
# and *.woff2 *.woff as fonts.fontconfig.localConf — a fontformat-based reject
# CANNOT work, because fc-scan %{fontformat} on these files reads "TrueType"
# (FreeType decompresses transparently), so the NixOS 53-nixos-reject-type1.conf
# pattern form matches nothing.
{
  stdenvNoCC,
  requireFile,
  zstd,
}:

stdenvNoCC.mkDerivation {
  pname = "anthropic-webfonts";
  version = "2026-09-17";

  src = requireFile {
    name = "anthropic-webfonts.tar.zst";
    sha256 = "8da31eca13b2c55bce504567256462d579ccdbee6b8fe713fc33feb65ef40239";
    message = ''
      The Anthropic webfonts are pinned to the fleet's NAS copy and are not downloadable.
      Add them to the store with:
        scp root@nas:/mnt/fast/fonts/anthropic/anthropic-webfonts.tar.zst .
        nix-store --add-fixed sha256 anthropic-webfonts.tar.zst
    '';
  };

  nativeBuildInputs = [ zstd ];
  sourceRoot = ".";
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/share/webfonts
    cp -r woff2 css $out/share/webfonts/
    runHook postInstall
  '';

  meta = {
    description = "Anthropic Sans/Serif/Mono + Anthropicons as woff2 with a @font-face sheet (fleet-pressed copy)";
    homepage = "https://www.anthropic.com/";
    # No license attribute on purpose — see ./anthropic-mono-nerd.nix.
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
}
