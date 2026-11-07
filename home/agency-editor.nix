{
  config,
  lib,
  pkgs,
  osConfig,
  ...
}:
let
  cfg = config.programs.agencyEditor;
  isBrain = osConfig.myFleet.has "brain";
  isSeat = osConfig.myFleet.has "seat";
in
{
  options.programs.agencyEditor = {
    enable = lib.mkEnableOption "native per-directory NAS Neovim editors for Agency Kitty";
    viAlias = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Use a local native Neovim UI for retained NAS directory editors from both seat and managed NAS fish.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = lib.versionAtLeast pkgs.neovim-unwrapped.version "0.12";
        message = "Agency editors require Neovim >=0.12 for the native detachable TUI.";
      }
      {
        assertion = !cfg.viAlias || ((isBrain || isSeat) && config.programs.agencyKitty.enable);
        message = "Agency editor vi requires the native transport on the NAS brain or desktop seat.";
      }
    ];
    # home/home.nix already provides the fleet Python-with-packages. Adding a
    # second bare python3 would collide with that environment during activation.
    home.sessionVariables = lib.optionalAttrs cfg.viAlias {
      DSH_EDITOR_VI = "1";
      DSH_EDITOR_ROLE = if isBrain then "brain" else "seat";
    };
  };
}
