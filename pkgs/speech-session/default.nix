{
  lib,
  stdenvNoCC,
  makeWrapper,
  python3,
  openssh,
  pandoc,
  pipewire,
  qwen-speech,
  coreutils,
}:
stdenvNoCC.mkDerivation {
  pname = "speech-session";
  version = "0.1.0";
  src = ./.;
  nativeBuildInputs = [ makeWrapper ];
  dontBuild = true;
  installPhase = ''
    mkdir -p $out/lib $out/bin
    cp *.py $out/lib/
    for spec in 'queue:speech-queue' 'play:speech-play'; do
      module="''${spec%%:*}"
      command="''${spec##*:}"
      makeWrapper ${python3}/bin/python3 $out/bin/$command \
        --add-flags $out/lib/$module.py \
        --prefix PATH : ${
          lib.makeBinPath [
            openssh
            pandoc
            pipewire
            qwen-speech
            coreutils
          ]
        }
    done
    install -Dm644 ${../../lib/python/utility_storage.py} $out/lib/utility_storage.py
  '';
  meta = {
    description = "Markdown speech queue and playback";
    platforms = lib.platforms.linux;
  };
}
