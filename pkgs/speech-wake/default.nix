{
  lib,
  runCommand,
  makeWrapper,
  python3,
  pipewire,
  openssh,
  speech-listening-cue,
  callPackage,
}:
let
  upstream = callPackage ../../tools/hotword/cpu/openwakeword.nix { };
  python = python3.withPackages (ps: [
    ps.numpy
    ps.onnxruntime
    ps.scipy
    ps.scikit-learn
    ps.requests
    ps.tqdm
    ps.webrtcvad
    ps.setuptools
  ]);
in
runCommand "speech-wake-0.1.0"
  {
    nativeBuildInputs = [ makeWrapper ];
    meta = {
      description = "Client Alexa wake, listening cue and bounded command transcription";
      license = lib.licenses.asl20;
      mainProgram = "speech-wake";
    };
  }
  ''
    mkdir -p check/pkgs/speech-wake check/tests/speech-wake
    cp ${./wake.py} check/pkgs/speech-wake/wake.py
    cp ${../../tests/speech-wake/test_wake.py} check/tests/speech-wake/test_wake.py
    ${python3}/bin/python3 check/tests/speech-wake/test_wake.py
    mkdir -p $out/bin $out/lib
    cp ${./playback.py} $out/lib/playback.py
    cp ${./dictate.py} $out/lib/dictate.py
    substitute ${./wake.py} $out/lib/wake.py \
      --replace-fail '@callRecordHash@' '${builtins.hashFile "sha256" ../../home/dot_local/bin/call-record}'
    makeWrapper ${python}/bin/python3 $out/bin/speech-wake \
      --set PYTHONPATH ${upstream}/lib \
      --set OPENBLAS_NUM_THREADS 1 --set OMP_NUM_THREADS 1 --set MKL_NUM_THREADS 1 \
      --prefix PATH : ${
        lib.makeBinPath [
          pipewire
          openssh
          speech-listening-cue
        ]
      } \
      --add-flags $out/lib/wake.py
    makeWrapper ${python}/bin/python3 $out/bin/speech-dictate \
      --prefix PATH : ${
        lib.makeBinPath [
          pipewire
          openssh
          speech-listening-cue
        ]
      } \
      --add-flags $out/lib/dictate.py
  ''
