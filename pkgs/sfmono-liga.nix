# Liga SF Mono Nerd Font — SF Mono ligaturized + nerd-patched upstream
# (shaunsingh/SFMono-Nerd-Font-Ligaturized, prebuilt OTFs committed to git).
# Distinct from Apple's plain SF Mono, which has no programming ligatures.
#
# Since 2026-09-15 the source is the fleet's own copy, not that repo: the exact
# OTFs the old flake input installed, tarred once at
#   nas:/mnt/fast/fonts/apple/sfmono-liga-fonts.tar.zst
# and pinned here by sha256. Same scheme and rationale as ./sf-pro.nix.
{ stdenvNoCC, requireFile, zstd }:

stdenvNoCC.mkDerivation {
  pname = "sfmono-liga-nerd-font";
  version = "2026-09-15";

  src = requireFile {
    name = "sfmono-liga-fonts.tar.zst";
    sha256 = "b8df2fa00c76b4e19a88292c44cf37cf6fa098df293df1d5b16fd223d13ef3cf";
    message = ''
      Liga SFMono is pinned to the fleet's NAS copy and is not downloadable.
      Add it to the store with:
        scp root@nas:/mnt/fast/fonts/apple/sfmono-liga-fonts.tar.zst .
        nix-store --add-fixed sha256 sfmono-liga-fonts.tar.zst
    '';
  };

  nativeBuildInputs = [ zstd ];
  sourceRoot = ".";
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/share/fonts
    cp -r opentype $out/share/fonts/
    runHook postInstall
  '';

  meta = {
    description = "Apple SF Mono, ligaturized and patched with Nerd Font glyphs (fleet-archived copy)";
    homepage = "https://github.com/shaunsingh/SFMono-Nerd-Font-Ligaturized";
    # Apple-derived font binaries; Apple's font EULA applies, not a FOSS license
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
}
