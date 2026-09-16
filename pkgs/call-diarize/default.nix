{
  lib,
  stdenvNoCC,
  makeWrapper,
  bash,
  coreutils,
  diffutils,
  fetchFromGitHub,
  fetchPypi,
  ffmpeg,
  findutils,
  jq,
  python313,
  python313Packages,
  uv,
  util-linux,
  torchRocm,
}:
let
  version = "2.0.0";
  callRecord = ../../home/dot_local/bin/call-record;
  python = torchRocm.pythonModule;
  pythonPackages = python313Packages;
  sitePackages = pythonPackages.python.sitePackages;

  # Microsoft's streaming ASR implementation (init_streaming_state,
  # encode_speech, streaming_generate_step) at the commit the 2026-09-14
  # audition measured. It is imported from source, not installed.
  vibevoiceSource = fetchFromGitHub {
    owner = "microsoft";
    repo = "VibeVoice";
    rev = "1541f590c7099820f10ea012f48d2399282df69f";
    hash = "sha256-ev8LxeML7anP50o4vHDtl/Ik3pHx1Oghp4CRgZkSbuo=";
  };

  # Upstream requires transformers <5 and the audition ran 4.57.6, whose
  # import-time version check in turn requires huggingface-hub <1. nixpkgs
  # carries 5.x/1.x, so both come from their pure-Python PyPI wheels.
  huggingfaceHub = pythonPackages.buildPythonPackage rec {
    pname = "huggingface-hub";
    version = "0.36.2";
    format = "wheel";
    src = fetchPypi {
      pname = "huggingface_hub";
      inherit version format;
      dist = "py3";
      python = "py3";
      hash = "sha256-SPDI6sFhRd/ONx6dLXdyhUpPWRvLVsnPVIrM9THVQnA=";
    };
    dependencies = with pythonPackages; [
      filelock
      fsspec
      hf-xet
      packaging
      pyyaml
      requests
      tqdm
      typing-extensions
    ];
    pythonImportsCheck = [ "huggingface_hub" ];
  };
  transformers = pythonPackages.buildPythonPackage rec {
    pname = "transformers";
    version = "4.57.6";
    format = "wheel";
    src = fetchPypi {
      inherit pname version format;
      dist = "py3";
      python = "py3";
      hash = "sha256-TJ6d4RMz3f5RFLyHLJ83BQkZis8Lh6gyoKuUWOK9BVA=";
    };
    # tokenizers is deliberately not propagated (see runtimePythonPath).
    dependencies = with pythonPackages; [
      filelock
      huggingfaceHub
      numpy
      packaging
      pyyaml
      regex
      requests
      safetensors
      tqdm
    ];
    dontCheckRuntimeDeps = true;
  };

  # nixpkgs' tokenizers and diffusers propagate huggingface-hub 1.x. Only
  # their own site-packages join the path, so exactly one hub is importable.
  # diffusers is imported (never used) by upstream's shared VibeVoice modules.
  unpropagated = [
    pythonPackages.tokenizers
    pythonPackages.diffusers
  ];
  runtimePythonPath = lib.concatStringsSep ":" (
    [
      "${torchRocm}/${sitePackages}"
      "${vibevoiceSource}"
      (pythonPackages.makePythonPath (
        [ transformers ]
        ++ (with pythonPackages; [
          importlib-metadata
          jinja2
          networkx
          pillow
          sympy
        ])
      ))
    ]
    ++ map (package: "${package}/${sitePackages}") unpropagated
  );
  environmentId = builtins.hashString "sha256" (
    builtins.concatStringsSep ":" [
      (builtins.hashFile "sha256" ./uv.lock)
      (builtins.hashFile "sha256" ./pyproject.toml)
      (toString python)
    ]
  );
in
stdenvNoCC.mkDerivation {
  pname = "call-diarize";
  inherit version;
  src = ./.;

  nativeBuildInputs = [ makeWrapper ];
  nativeCheckInputs = [
    bash
    coreutils
    diffutils
    ffmpeg
    findutils
    jq
    python313
    util-linux
  ];
  doCheck = true;

  checkPhase = ''
    runHook preCheck
    ${bash}/bin/bash -n \
      ${callRecord} \
      launcher.sh \
      backfill.sh \
      tests/test_backfill.sh \
      tests/test_call_record.sh
    PATH=${
      lib.makeBinPath [
        coreutils
        findutils
        jq
      ]
    }:$PATH \
      ${bash}/bin/bash tests/test_backfill.sh
    ${bash}/bin/bash tests/test_call_record.sh \
      ${callRecord} \
      ${bash}/bin/bash \
      $PWD/backfill.sh
    PYTHONPATH=$PWD ${python313}/bin/python -m unittest discover -s tests -v
    ${python313}/bin/python -m compileall -q call_diarize
    # The runtime path must import upstream's streaming classes against the
    # pinned transformers, with exactly one huggingface-hub (no GPU needed).
    PYTHONNOUSERSITE=1 PYTHONPATH=$PWD:${runtimePythonPath} HOME=$TMPDIR \
      TRANSFORMERS_OFFLINE=1 HF_HUB_OFFLINE=1 \
      ${python}/bin/python3 -c '
    import huggingface_hub, transformers
    assert transformers.__version__ == "4.57.6", transformers.__version__
    assert huggingface_hub.__version__ == "0.36.2", huggingface_hub.__version__
    from vibevoice.modular.modeling_vibevoice_asr import VibeVoiceASRForConditionalGeneration
    from vibevoice.processor.vibevoice_asr_processor import VibeVoiceASRProcessor
    assert hasattr(VibeVoiceASRForConditionalGeneration, "streaming_generate_step")
    import call_diarize.asr
    '
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/bin $out/libexec/call-diarize
    cp -R call_diarize tests $out/libexec/call-diarize/
    cp launcher.sh backfill.sh pyproject.toml uv.lock $out/libexec/call-diarize/
    makeWrapper ${bash}/bin/bash $out/bin/call-diarize \
      --add-flags "$out/libexec/call-diarize/launcher.sh" \
      --prefix PATH : ${
        lib.makeBinPath [
          coreutils
          ffmpeg
          uv
        ]
      } \
      --set CALL_DIARIZE_ENVIRONMENT_ID ${lib.escapeShellArg environmentId} \
      --set CALL_DIARIZE_PROJECT "$out/libexec/call-diarize" \
      --set CALL_DIARIZE_PYTHON ${lib.escapeShellArg "${python}/bin/python3"} \
      --set CALL_DIARIZE_PYTHONPATH "$out/libexec/call-diarize:${runtimePythonPath}" \
      --set CALL_DIARIZE_TORCH_ROOT ${lib.escapeShellArg (toString torchRocm)}
    makeWrapper ${bash}/bin/bash $out/bin/call-diarize-backfill \
      --add-flags "$out/libexec/call-diarize/backfill.sh" \
      --prefix PATH : ${
        lib.makeBinPath [
          coreutils
          findutils
          jq
        ]
      }
    runHook postInstall
  '';

  passthru = {
    inherit runtimePythonPath transformers vibevoiceSource;
  };

  meta = {
    description = "GPU-backed VibeVoice-ASR-Streaming-7B transcription for split call recordings";
    license = lib.licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "call-diarize";
  };
}
