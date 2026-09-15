# SF Pro — from the fleet's own durable copy on the NAS, never Apple's CDN.
#
# WHY (2026-09-15). This used to come from Lyndeno/apple-fonts.nix, which locks
# Apple's DMGs as `type = "file"` flake inputs. Apple re-releases those DMGs in
# place, so the locked narHash rots: it failed the first update-center run
# (2026-08-21) and update-center-seed on 2026-09-15 01:20 (SF-Compact.dmg — a
# family we did not even install, because `nix flake archive` fetches EVERY
# lock node). Tom: "i do not want to download the fonts again everytime i do
# an update". So the input is gone and the bytes are ours.
#
# The source is the exact OTF/TTF set that input had installed, tarred once:
#   /mnt/nas/documents/fonts/sf-pro/sf-pro-fonts.tar.zst
# `requireFile` pins it by sha256 and never downloads anything. Its store path
# depends only on name + hash, so any host that already has it (or the built
# font, substituted from the NAS attic cache) never reads the NAS either.
# home/update-center-seed.nix adds it to the coordinator store and seeds +
# GC-roots it in the NAS store nightly, so the fleet builds find it there.
{ stdenvNoCC, requireFile, zstd }:

stdenvNoCC.mkDerivation {
  pname = "sf-pro";
  version = "2026-09-15";

  src = requireFile {
    name = "sf-pro-fonts.tar.zst";
    sha256 = "39b8a61b3fe615d45ca5a3803dce5d2f0ffbecfb52cd39c3fcff14d51097b93f";
    message = ''
      SF Pro is pinned to the fleet's NAS copy and is not downloadable.
      Add it to the store with:
        nix-store --add-fixed sha256 /mnt/nas/documents/fonts/sf-pro/sf-pro-fonts.tar.zst
    '';
  };

  nativeBuildInputs = [ zstd ];
  sourceRoot = ".";
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p $out/share/fonts
    cp -r opentype truetype $out/share/fonts/
    runHook postInstall
  '';

  meta = {
    description = "Apple SF Pro (fleet-archived copy)";
    homepage = "https://developer.apple.com/fonts/";
    # Apple's font EULA applies, not a FOSS license
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
}
