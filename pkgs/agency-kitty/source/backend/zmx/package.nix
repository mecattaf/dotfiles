{ lib, stdenvNoCC, binary
, receiptFile ? ./build-receipt.json
, patchFile ? ./agency.patch
, noticeFile ? ./NOTICE
}:
let
  receipt = builtins.fromJSON (builtins.readFile receiptFile);
  expectedHash = receipt.binary_sha256;
in
assert lib.assertMsg (builtins.hashFile "sha256" binary == expectedHash)
  "Agency zmx binary does not match the reviewed build receipt";
stdenvNoCC.mkDerivation {
  pname = "agency-zmx";
  version = receipt.fork_version;
  src = binary;
  dontUnpack = true;
  dontConfigure = true;
  dontBuild = true;
  dontStrip = true;
  dontPatchELF = true;
  installPhase = ''
    runHook preInstall
    actualHash="$(sha256sum "$src")"
    actualHash="''${actualHash%% *}"
    test "$actualHash" = "${expectedHash}"
    install -Dm755 "$src" "$out/bin/zmx"
    install -Dm644 ${./LICENSE.upstream} "$out/share/doc/agency-zmx/LICENSE.upstream"
    install -Dm644 ${noticeFile} "$out/share/doc/agency-zmx/NOTICE"
    cp -R ${./licenses} "$out/share/doc/agency-zmx/licenses"
    install -Dm644 ${receiptFile} "$out/share/doc/agency-zmx/build-receipt.json"
    install -Dm644 ${patchFile} "$out/share/doc/agency-zmx/agency.patch"
    runHook postInstall
  '';
  passthru = {
    upstreamCommit = receipt.upstream_commit;
    binarySha256 = expectedHash;
    inherit receipt;
  };
  meta = {
    description = "Bounded native PTY holder for Kitty, pinned to a reviewed source build";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "zmx";
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
}
