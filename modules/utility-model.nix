{
  config,
  lib,
  pkgs,
  ...
}:
# The `utility-model` wrapper: the stable seam /drain and /print dial under the
# model id `utility`. It forwards one chat-completions request to the fleet's
# local model server and names the concrete served model upstream
# (pkgs/utility-model/utility_model.py). It lives apart from the server module
# so the engine behind the endpoint can change (Halogen to Gufo, #525) without
# the wrapper going with it.
let
  cfg = config.services.utilityModel;
  localModel = import ../lib/local-model.nix;

  utilityRunner = pkgs.writeShellApplication {
    name = "utility-model";
    runtimeInputs = [ pkgs.python3 ];
    text = ''
      exec ${pkgs.python3}/bin/python3 ${../pkgs/utility-model/utility_model.py} "$@" \
        --endpoint ${lib.escapeShellArg cfg.endpoint} \
        --concrete-model ${lib.escapeShellArg cfg.modelId} \
        --context-tokens ${toString cfg.contextTokens}
    '';
  };
in
{
  options.services.utilityModel = {
    enable = lib.mkEnableOption "the utility-model wrapper that forwards one request to the fleet's local model server";

    endpoint = lib.mkOption {
      type = lib.types.str;
      default = localModel.endpoint;
      description = "Where the fleet's local model server answers.";
    };

    modelId = lib.mkOption {
      type = lib.types.str;
      default = localModel.modelId;
      description = "The served model id sent upstream; the server answers 404 to any other.";
    };

    contextTokens = lib.mkOption {
      type = lib.types.ints.positive;
      default = 102400;
      description = "Prompt budget the utility-model wrapper plans against.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ utilityRunner ];
  };
}
