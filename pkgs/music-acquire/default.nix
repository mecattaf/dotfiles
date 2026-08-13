{
  lib,
  stdenvNoCC,
  makeWrapper,
  python3,
  bash,
  chromaprint,
  coreutils,
  curl,
  ffmpeg,
  jq,
  nodejs,
  openssh,
  pipewire,
  yt-dlp,
}:
let
  python = python3.withPackages (ps: [ ps.websocket-client ]);
in
stdenvNoCC.mkDerivation {
  pname = "music-acquire";
  version = "2026.08.13";

  src = builtins.path {
    path = ./.;
    name = "music-acquire-src";
  };

  nativeBuildInputs = [
    makeWrapper
    python
  ];

  dontBuild = true;
  doCheck = true;

  checkPhase = ''
    runHook preCheck
    PYTHONPATH=$PWD ${python}/bin/python -m unittest discover -s tests -v
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    install -d $out/libexec/music-acquire $out/bin
    cp acquire.py $out/libexec/music-acquire/
    cp -r music_acquire $out/libexec/music-acquire/

    makeWrapper ${python}/bin/python $out/bin/acquire \
      --add-flags $out/libexec/music-acquire/acquire.py \
      --set FPCALC ${chromaprint}/bin/fpcalc \
      --prefix PATH : ${
        lib.makeBinPath [
          bash
          chromaprint
          coreutils
          curl
          ffmpeg
          jq
          nodejs
          openssh
          pipewire
          yt-dlp
        ]
      }
    runHook postInstall
  '';

  meta = {
    description = "Resumable, evidence-gated SoundCloud/YouTube/Bandcamp music acquisition";
    mainProgram = "acquire";
    platforms = lib.platforms.linux;
  };
}
