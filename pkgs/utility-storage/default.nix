{ lib, stdenvNoCC, makeWrapper, python3 }:
stdenvNoCC.mkDerivation {
  pname = "utility-storage";
  version = "0.1.1";
  dontUnpack = true;
  nativeBuildInputs = [ makeWrapper ];
  installPhase = ''
    install -Dm644 ${../../lib/python/utility_storage.py} $out/lib/utility_storage.py
    install -Dm644 ${../../home/dot_local/bin/recording-transcript-stage} $out/lib/recording_transcript.py
    makeWrapper ${python3}/bin/python3 $out/bin/utility-path \
      --add-flags $out/lib/utility_storage.py
    makeWrapper ${python3}/bin/python3 $out/bin/recording-transcript-stage \
      --add-flags $out/lib/recording_transcript.py \
      --prefix PATH : $out/bin
  '';
  meta = { description = "Private host-local utility storage configuration"; platforms = lib.platforms.linux; };
}
