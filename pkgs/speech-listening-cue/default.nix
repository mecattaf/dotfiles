{
  lib,
  stdenvNoCC,
  bash,
  coreutils,
  ffmpeg-headless,
  pipewire,
}:
stdenvNoCC.mkDerivation {
  pname = "speech-listening-cue";
  version = "2026-09-14";
  src = ./.;
  nativeBuildInputs = [ ffmpeg-headless ];
  buildPhase = ''
    runHook preBuild
    echo '51680f6e9e5632fc4a0d4a8d32b63a0c24752dc728657db685af1c8759cf9bed  assets/enter_voice_mode.mp3' | sha256sum --check
    ffmpeg -nostdin -v error -threads 1 -i assets/enter_voice_mode.mp3 \
      -map_metadata -1 -c:a pcm_s16le -threads 1 listening.wav
    ffprobe -v error -show_entries format=duration:stream=codec_name,sample_rate,channels \
      -of json listening.wav > listening-format.json
    runHook postBuild
  '';
  installPhase = ''
    runHook preInstall
    mkdir -p "$out/bin" "$out/share/speech-listening-cue/originals"
    cp assets/* "$out/share/speech-listening-cue/originals/"
    cp listening.wav listening-format.json "$out/share/speech-listening-cue/"
    substitute listening-cue.sh "$out/bin/speech-listening-cue" \
      --replace-fail '#!/usr/bin/env bash' '#!${bash}/bin/bash' \
      --replace-fail '@uname@' '${coreutils}/bin/uname' \
      --replace-fail '@pwPlay@' '${pipewire}/bin/pw-play' \
      --replace-fail '@cue@' "$out/share/speech-listening-cue/listening.wav"
    chmod +x "$out/bin/speech-listening-cue"
    runHook postInstall
  '';
  meta = {
    description = "One-shot client PipeWire playback of the preserved Claude voice-entry cue";
    license = lib.licenses.unfree;
    platforms = lib.platforms.linux;
    mainProgram = "speech-listening-cue";
  };
}
