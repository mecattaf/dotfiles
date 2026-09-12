{ config, lib, inputs, pkgs, ... }:
let
  cfg = config.services.fara-browser-model;
  engine = inputs.nix-strix-halo.packages.${pkgs.stdenv.hostPlatform.system}.llama-cpp-rocm;
in {
  options.services.fara-browser-model.enable = lib.mkEnableOption "on-demand FARA browser inference";
  config = lib.mkIf cfg.enable {
    systemd.user.services.fara-browser-model = {
      description = "FARA 1.5 9B for browser tasks (on demand)";
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
