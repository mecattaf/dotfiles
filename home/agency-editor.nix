{
  config,
  lib,
  pkgs,
  osConfig,
  ...
}:
let
  cfg = config.programs.agencyEditor;
in
{
  options.programs.agencyEditor = {
    enable = lib.mkEnableOption "native per-directory NAS Neovim editors for Agency Kitty";
    viAlias = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Opt in to vi using the durable per-directory editor on the NAS; other hosts retain ordinary nvim.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = lib.versionAtLeast pkgs.neovim-unwrapped.version "0.12";
        message = "Agency editors require Neovim >=0.12 for the native detachable TUI.";
      }
      {
        assertion = !cfg.viAlias || osConfig.myFleet.has "brain";
        message = "Agency editor vi alias belongs on the NAS brain; use Kitty SSH from the seat.";
      }
    ];
    home.packages = [ pkgs.python3 ];
    home.sessionVariables = lib.optionalAttrs cfg.viAlias { DSH_EDITOR_VI = "1"; };
  };
}
