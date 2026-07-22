{
  system,
  bashPath,
  pureStagePath,
  phase,
  registry,
  capture,
  hfCapture ? null,
  commentary ? null,
}:
let
  # Reattach the closure context of exact outputs embedded by the packaged
  # supervisor. Treating these paths as source trees drops runtime references.
  bash = builtins.storePath bashPath;
  pureStage = builtins.storePath pureStagePath;
in
assert builtins.elem phase [
  "prepare"
  "enrich"
  "finalize"
];
assert phase != "enrich" || hfCapture != null;
assert phase != "finalize" || commentary != null;
builtins.derivation {
  name = "local-ai-monthly-${phase}";
  inherit system;
  builder = "${bash}/bin/bash";
  args = [
    "-euo"
    "pipefail"
    "-c"
    (
      if phase == "prepare" then
        ''
          exec ${pureStage}/bin/local-ai-monthly-pure-stage \
            prepare ${registry} ${capture} "$out"
        ''
      else if phase == "enrich" then
        ''
          exec ${pureStage}/bin/local-ai-monthly-pure-stage \
            enrich ${registry} ${capture} ${hfCapture} "$out"
        ''
      else
        ''
          exec ${pureStage}/bin/local-ai-monthly-pure-stage \
            finalize ${registry} ${capture} ${commentary} "$out"
        ''
    )
  ];
  preferLocalBuild = true;
  allowSubstitutes = false;
}
