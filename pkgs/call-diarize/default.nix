{
  lib,
  stdenvNoCC,
  makeWrapper,
  bash,
  coreutils,
  ffmpeg,
  python313,
  python313Packages,
  uv,
  torchRocm,
}:
let
  version = "1.0.0";
  python = torchRocm.pythonModule;
  purePythonPath = python313Packages.makePythonPath [
    python313Packages.accelerate
    python313Packages.transformers
  ];
  runtimePythonPath = "${torchRocm}/lib/python3.13/site-packages:${purePythonPath}";
  lockId = builtins.hashFile "sha256" ./uv.lock;
in
stdenvNoCC.mkDerivation {
  pname = "call-diarize";
  inherit version;
  src = ./.;

  nativeBuildInputs = [ makeWrapper ];
  nativeCheckInputs = [ python313 ];
  doCheck = true;

  checkPhase = ''
    runHook preCheck
    PYTHONPATH=$PWD ${python313}/bin/python -m unittest discover -s tests -v
    ${python313}/bin/python -m compileall -q call_diarize
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin $out/libexec/call-diarize
    cp -R call_diarize model-support tests $out/libexec/call-diarize/
    cp launcher.sh pyproject.toml uv.lock $out/libexec/call-diarize/
    makeWrapper ${bash}/bin/bash $out/bin/call-diarize \
      --add-flags "$out/libexec/call-diarize/launcher.sh" \
      --prefix PATH : ${
        lib.makeBinPath [
          coreutils
          ffmpeg
          uv
        ]
      } \
      --set CALL_DIARIZE_LOCK_ID ${lib.escapeShellArg lockId} \
      --set CALL_DIARIZE_MODEL_SUPPORT "$out/libexec/call-diarize/model-support" \
      --set CALL_DIARIZE_PROJECT "$out/libexec/call-diarize" \
      --set CALL_DIARIZE_PYTHON ${lib.escapeShellArg "${python}/bin/python3"} \
      --set CALL_DIARIZE_PYTHONPATH "$out/libexec/call-diarize:${runtimePythonPath}" \
      --set CALL_DIARIZE_TORCH_ROOT ${lib.escapeShellArg (toString torchRocm)}
    runHook postInstall
  '';

  meta = {
    description = "GPU-backed VibeVoice fusion transcription for split call recordings";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "call-diarize";
  };
}
