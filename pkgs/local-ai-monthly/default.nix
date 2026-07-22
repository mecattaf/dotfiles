{
  lib,
  stdenvNoCC,
  symlinkJoin,
  writeShellApplication,
  bash,
  coreutils,
  curl,
  diffutils,
  findutils,
  gawk,
  gh,
  git,
  gnugrep,
  gnused,
  jq,
  nix,
  tinyxxd,
  llm-agents,
  pi-llama-swap-extension,
}:
let
  shellRuntime = [
    bash
    coreutils
    diffutils
    findutils
    gawk
    git
    gnugrep
    gnused
    jq
    tinyxxd
  ];

  pureStage = writeShellApplication {
    name = "local-ai-monthly-pure-stage";
    runtimeInputs = shellRuntime;
    # Markdown code spans are intentionally single-quoted printf literals.
    excludeShellChecks = [ "SC2016" ];
    text = builtins.readFile ./lib/pure-stage.sh;
  };

  capture = writeShellApplication {
    name = "local-ai-monthly-capture";
    runtimeInputs = shellRuntime;
    text = builtins.readFile ./lib/capture.sh;
  };

  hfCapture = writeShellApplication {
    name = "local-ai-monthly-hf-capture";
    runtimeInputs = [
      coreutils
      curl
      jq
    ];
    text = builtins.readFile ./lib/hf-capture.sh;
  };

  judge = writeShellApplication {
    name = "local-ai-monthly-judge";
    runtimeInputs = [
      coreutils
      llm-agents.pi
    ];
    text = ''
      export LOCAL_AI_PI=${lib.escapeShellArg "${llm-agents.pi}/bin/pi"}
      export LOCAL_AI_PI_PROVIDER_EXTENSION=${pi-llama-swap-extension}
      exec ${bash}/bin/bash ${./lib/judge.sh} "$@"
    '';
  };

  supervisor = writeShellApplication {
    name = "local-ai-monthly";
    runtimeInputs = [
      coreutils
      curl
      gh
      git
      jq
      nix
    ];
    text = ''
      export LOCAL_AI_CAPTURE=${lib.escapeShellArg "${capture}/bin/local-ai-monthly-capture"}
      export LOCAL_AI_HF_CAPTURE=${lib.escapeShellArg "${hfCapture}/bin/local-ai-monthly-hf-capture"}
      export LOCAL_AI_JUDGE=${lib.escapeShellArg "${judge}/bin/local-ai-monthly-judge"}
      export LOCAL_AI_PROMPT=${./prompt/review.md}
      export LOCAL_AI_PURE_STAGE=${pureStage}
      export LOCAL_AI_STAGES=${./stages.nix}
      export LOCAL_AI_STAGE_BASH=${bash}
      export LOCAL_AI_STAGE_SYSTEM=${lib.escapeShellArg stdenvNoCC.hostPlatform.system}
      exec ${bash}/bin/bash ${./supervisor.sh} "$@"
    '';
  };

  tallyEntry = writeShellApplication {
    name = "local-ai-monthly-tally";
    runtimeInputs = [ supervisor ];
    text = ''
      exec local-ai-monthly --publish "$@"
    '';
  };

  tests = writeShellApplication {
    name = "local-ai-monthly-tests";
    runtimeInputs = shellRuntime;
    text = ''
      export LOCAL_AI_CAPTURE=${lib.escapeShellArg "${capture}/bin/local-ai-monthly-capture"}
      export LOCAL_AI_PURE_STAGE=${lib.escapeShellArg "${pureStage}/bin/local-ai-monthly-pure-stage"}
      export LOCAL_AI_SUPERVISOR_SOURCE=${./supervisor.sh}
      export LOCAL_AI_CAPTURE_SOURCE=${./lib/capture.sh}
      export LOCAL_AI_HF_CAPTURE_SOURCE=${./lib/hf-capture.sh}
      export LOCAL_AI_JUDGE_SOURCE=${./lib/judge.sh}
      export LOCAL_AI_PURE_STAGE_SOURCE=${./lib/pure-stage.sh}
      exec ${bash}/bin/bash ${./tests/test-workflow.sh}
    '';
  };
in
symlinkJoin {
  name = "local-ai-monthly-2.0.0";
  paths = [
    supervisor
    tallyEntry
  ];
  postBuild = ''
    ${tests}/bin/local-ai-monthly-tests
  '';

  meta = {
    description = "Evidence-first monthly local-AI update bot scheduled by Tally";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "local-ai-monthly";
  };
}
