# Liga SF Mono Nerd Font — SF Mono ligaturized + nerd-patched upstream
# (shaunsingh/SFMono-Nerd-Font-Ligaturized, prebuilt OTFs committed to git).
# Was: url-fonts/SFMono-Nerd-Font-Ligaturized in the Fedora image, via the
# now-deleted mecattaf/San-Francisco-family release zip (SFMono-Liga.zip).
# Distinct from apple-fonts' sf-mono-nerd, which has no programming ligatures.
# src is the sfmono-liga flake input (flake = false) so flake.lock pins it;
# wired in flake.nix (not overlays/default.nix — that file has no inputs).
{ stdenvNoCC, src }:

stdenvNoCC.mkDerivation {
  pname = "sfmono-liga-nerd-font";
  version = "0-unstable";
  inherit src;

  dontUnpack = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -Dm444 -t $out/share/fonts/opentype $src/*.otf
    runHook postInstall
  '';

  meta = {
    description = "Apple SF Mono, ligaturized and patched with Nerd Font glyphs";
    homepage = "https://github.com/shaunsingh/SFMono-Nerd-Font-Ligaturized";
    # Apple-derived font binaries; Apple's font EULA applies, not a FOSS license
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
      "x86_64-darwin"
      "aarch64-darwin"
    ];
  };
}
