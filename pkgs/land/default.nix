{
  lib,
  stdenvNoCC,
  python3,
  makeWrapper,
  rsync,
  coreutils,
}:
# land (CNA-M07): copy-then-verify for preservation packets. One stdlib Python
# file, one entry point. `land copy` writes a packet (the tree plus
# preservation-<date>.json and README.md), `land verify` recomputes every hash
# and count in it, `land diff` proves a source and its copy are the same bytes
# before anybody removes a source.
#
# rsync is a SECOND OPINION, never the authority: a packet legitimately differs
# from its source in two recorded ways (the dot-git rename and the exclusions),
# so `land diff` always hashes and only adds the rsync -rn --checksum pass when
# neither applies. Suffix, not prefix, on PATH — the host's own rsync is fine,
# this one only guarantees the command exists.
stdenvNoCC.mkDerivation {
  pname = "land";
  version = "1";
  src = ./.;
  nativeBuildInputs = [ makeWrapper ];
  dontBuild = true;
  installPhase = ''
    runHook preInstall
    install -Dm0644 land.py $out/share/land/land.py
    makeWrapper ${python3.interpreter} $out/bin/land \
      --add-flags "$out/share/land/land.py" \
      --argv0 land \
      --suffix PATH : ${
        lib.makeBinPath [
          rsync
          coreutils
        ]
      }
    runHook postInstall
  '';
  meta = {
    description = "Copy-then-verify landing tool for preservation packets: manifest, README, hashes";
    mainProgram = "land";
  };
}
