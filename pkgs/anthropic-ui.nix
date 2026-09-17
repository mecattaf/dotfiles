# Anthropic Sans / Anthropic Serif / Anthropicons — the desktop faces, pressed
# locally by pkgs/fontbuilder and stored on the fleet's NAS M.2. Never a
# download, never in git. Same scheme as ./sf-pro.nix.
#
# These stay VARIABLE. FontForge never touches them, so fvar/gvar/STAT and the
# opsz axis survive and one file serves every weight and optical size; the
# terminal statics are a separate tarball because the Nerd patcher flattens.
#
# Source is the 26.043.1 "Web" cut, chosen over the claude.ai "Variable" cut
# because their cmaps and GSUB are identical (Sans 625/625/713, Serif 633/633)
# and the Web cut uniquely carries the brand glyph NAMES at U+E11A-E11E
# (ASlash.pua/Anthropic.pua/Claude.pua/Spark.pua/Code.pua). The four defects the
# Variable cut would have avoided are repaired in the normalize stage instead:
#   1. doubled-"Web" PostScript names (AnthropicSansWebWeb-TextRegular)
#   2. missing fsSelection ITALIC bit + macStyle on the VARIABLE row (the named
#      instances already report slant=100; the variable row reported 0, and that
#      is the row Chrome, GTK and every variable-axis consumer read)
#   3. Serif fvar default wght=300 / usWeightClass 300 / "Text Light" family
#   4. the STAT " Italic" doubling (5 records) that instancing would glue on
{
  stdenvNoCC,
  requireFile,
  zstd,
}:

stdenvNoCC.mkDerivation {
  pname = "anthropic-ui-fonts";
  version = "2026-09-17";

  src = requireFile {
    name = "anthropic-ui-fonts.tar.zst";
    sha256 = "070d34426a6eab50dd8dd3ae19cf847a52af86adb03d0a4f0d5d1d0de4393c77";
    message = ''
      Anthropic Sans/Serif is pinned to the fleet's NAS copy and is not downloadable.
      Add it to the store with:
        scp root@nas:/mnt/fast/fonts/anthropic/anthropic-ui-fonts.tar.zst .
        nix-store --add-fixed sha256 anthropic-ui-fonts.tar.zst
    '';
  };

  nativeBuildInputs = [ zstd ];
  sourceRoot = ".";
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/share/fonts
    cp -r truetype $out/share/fonts/
    runHook postInstall
  '';

  meta = {
    description = "Anthropic Sans, Anthropic Serif and Anthropicons, variable, name-repaired (fleet-pressed copy)";
    homepage = "https://www.anthropic.com/";
    # No license attribute on purpose — see ./anthropic-mono-nerd.nix.
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
}
