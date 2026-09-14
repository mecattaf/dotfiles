{
  lib,
  stdenvNoCC,
  python3,
  makeWrapper,
  openssh,
  pipewire,
  systemd,
}:
stdenvNoCC.mkDerivation {
  pname = "qwen-speech";
  version = "0.1.0";
  src = ./.;
  nativeBuildInputs = [ makeWrapper ];
  dontBuild = true;
  installPhase = ''
    install -Dm644 speech.py "$out/lib/qwen-speech.py"
    makeWrapper ${python3}/bin/python3 "$out/bin/qwen-speech" \
      --add-flags "$out/lib/qwen-speech.py" \
      --prefix PATH : ${
        lib.makeBinPath [
          openssh
          pipewire
          systemd
        ]
      }
    makeWrapper "$out/bin/qwen-speech" "$out/bin/speak" --add-flags speak
  '';
  meta = {
    description = "Coordinator Qwen speech lifecycle and Zenbook playback";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
  };
}
