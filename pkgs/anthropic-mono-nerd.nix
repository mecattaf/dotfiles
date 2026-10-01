# AnthropicMono Nerd Font — pressed locally by pkgs/fontbuilder, stored on
# the fleet's NAS M.2, never downloaded and never in git.
#
# Built from the anthropic.com "Web" variable cuts (26.043.1): instanced to 12
# statics with fontTools, name-normalized, completeness-merged from JetBrains
# Mono 2.304 + DejaVu Sans Mono 2.37 + Maple Mono NF 7.9, ligaturized from Fira
# Code 3.001 (rev e9943d2d), ligature-aligned, then Nerd-patched with
# nerd-font-patcher --complete --makegroups 4. NOT --mono (dropped 2026-10-01):
# the 2026-09-17 press used it and every icon was squeezed into one cell
# (U+F07B 0.600 x 0.525 em, against 0.923 x 0.808 em in JetBrainsMono NF and
# Maple Mono NF). Icons now keep the 1200 advance and overflow the cell like
# every stock Nerd Font; the family is `AnthropicMono Nerd Font` / NF.
#
# `nix run .#fontbuilder -- <capture-dir> <out-dir>` reproduces the exact bytes
# (head is pinned to SOURCE_DATE_EPOCH; --verify-repro proves it). Per-glyph
# donor provenance ships inside the tarball as PROVENANCE.tsv.
#
# Same scheme and rationale as ./sf-pro.nix: requireFile, never a download.
# home/update-center-seed.nix used to root the tarball in the NAS store
# nightly; it was deleted on 2026-09-30, so a NAS-side build needs it
# `nix store add`ed by hand first (as for ./anthropic-ui.nix and
# ./anthropic-webfonts.nix).
{
  stdenvNoCC,
  requireFile,
  zstd,
}:

stdenvNoCC.mkDerivation {
  pname = "anthropic-mono-nerd-font";
  version = "2026-10-01";

  src = requireFile {
    name = "anthropic-mono-nerd-fonts.tar.zst";
    # 2026-10-01 press (no --mono). The 2026-09-17 --mono press was
    # df043254517d186e6107caedae706436182c29d3e69aaedae031825b0a030fdc.
    sha256 = "80d9503c6bc7253cb925b208eff8c2ae1dd1c78bfe91ae0ca1ea7a820cced654";
    message = ''
      Anthropic Mono is pinned to the fleet's NAS copy and is not downloadable.
      Add it to the store with:
        scp root@nas:/mnt/fast/fonts/anthropic/anthropic-mono-nerd-fonts.tar.zst .
        nix-store --add-fixed sha256 anthropic-mono-nerd-fonts.tar.zst
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
    description = "Anthropic Mono, completeness-merged, ligaturized and Nerd-patched (fleet-pressed copy)";
    homepage = "https://www.anthropic.com/";
    # No license attribute on purpose: the vendor has published none. nameID 13
    # and 14 are absent on every Anthropic face and fsType 0x0000 governs
    # embedding, not redistribution. Same stance as pkgs/sf-pro.nix. Donor
    # outlines merged in are OFL-1.1 (JetBrains, Maple, Fira) and
    # Bitstream-Vera/Arev (DejaVu); see PROVENANCE.tsv in the tarball.
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
}
