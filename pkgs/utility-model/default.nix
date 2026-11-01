{
  lib,
  writeShellApplication,
  python3,
  endpoint ? (import ../../lib/local-model.nix).endpoint,
  modelId ? (import ../../lib/local-model.nix).modelId,
  contextTokens ? 102400,
}:
writeShellApplication {
  name = "utility-model";
  runtimeInputs = [ python3 ];
  text = ''
    exec ${lib.getExe python3} ${./utility_model.py} "$@" \
      --endpoint ${lib.escapeShellArg endpoint} \
      --concrete-model ${lib.escapeShellArg modelId} \
      --context-tokens ${toString contextTokens}
  '';
}
