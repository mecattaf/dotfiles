{ lib, stdenvNoCC, makeWrapper, python3, openssh, rsync }:
stdenvNoCC.mkDerivation {
  pname = "downloads-mirror";
  version = "0.1.1";
  dontUnpack = true;
  nativeBuildInputs = [ makeWrapper ];
  installPhase = ''
    install -Dm644 ${./downloads-mirror.py} $out/lib/downloads-mirror.py
    substituteInPlace $out/lib/downloads-mirror.py \
      --replace-fail 'SSH = "ssh"' 'SSH = "${openssh}/bin/ssh"' \
      --replace-fail 'RSYNC = "rsync"' 'RSYNC = "${rsync}/bin/rsync"'
    makeWrapper ${python3}/bin/python3 $out/bin/downloads-mirror \
      --add-flags $out/lib/downloads-mirror.py
  '';
  meta = {
    description = "Resumable browser-download copies with private transfer receipts";
    platforms = lib.platforms.linux;
    mainProgram = "downloads-mirror";
  };
}
