# FARA 1.5 9B, the browser computer-use appliance.
#
# Retired 2026-09-16 with the rest of the unused model estate; brought back
# 2026-09-19 on Tom's ruling: "FARA 9b should BE BROUGHT BACK, perhaps at fp8
# if not bf16; this has avenue to be optimized."
#
# OPERATOR-STARTED, NEVER RESIDENT. `wantedBy = [ ]` below is the whole rule,
# and flake.nix asserts it: nothing starts this at boot, `fara-browser` starts
# it for the length of one task and stops it. The coordinator is Tom's desktop
# and already carries Qwen TTS, Parakeet, the 17.6 GB streaming ASR, live
# agent sessions and, when an operator runs `halogen-switch`, a Halogen engine
# that wants most of the 128 GB. Do not start FARA while a coordinator Halogen
# unit is up, and do not add a wantedBy. Same doctrine as
# services.halogen.autoStart = false in modules/strix.nix.
#
# Precision: this serves the Q8_0 GGUF (8.89 GiB) with the BF16 vision
# projector (879 MiB) through llama.cpp ROCm, the exact shape that ran until
# 2026-09-16. Tom's fp8/bf16 question is open and is NOT answered here; see
# docs/local-ai/fara-restore-2026-09-19.md for the trade and what a higher
# precision row would cost. Never silently substitute a quantization.
{ config, lib, inputs, pkgs, ... }:
let
  cfg = config.services.fara-browser-model;
  engine = inputs.nix-strix-halo.packages.${pkgs.stdenv.hostPlatform.system}.llama-cpp-rocm;
in {
  options.services.fara-browser-model.enable = lib.mkEnableOption "on-demand FARA browser inference";
  config = lib.mkIf cfg.enable {
    systemd.user.services.fara-browser-model = {
      description = "FARA 1.5 9B for browser tasks (on demand)";
      # Operator-started only. No target wants this; flake.nix asserts it.
      wantedBy = [ ];
      unitConfig = {
        ConditionUser = "tom";
        ConditionPathExists = [
          "/var/lib/local-models/fara15-9b-q8-0/Fara1.5-9B-Q8_0.gguf"
          "/var/lib/local-models/fara15-9b-mmproj-bf16/mmproj-Fara1.5-9B-bf16.gguf"
        ];
      };
      serviceConfig = {
        ExecStart = lib.escapeShellArgs [
          "${engine}/bin/llama-server"
          "--model" "/var/lib/local-models/fara15-9b-q8-0/Fara1.5-9B-Q8_0.gguf"
          "--mmproj" "/var/lib/local-models/fara15-9b-mmproj-bf16/mmproj-Fara1.5-9B-bf16.gguf"
          "--host" "127.0.0.1" "--port" "8732" "--alias" "Fara1.5-9B"
          "--ctx-size" "16384" "--parallel" "1" "--gpu-layers" "all"
          "--image-min-tokens" "1024" "--jinja"
        ];
        TimeoutStopSec = 20;
      };
    };
  };
}
