{ config, lib, pkgs, osConfig, ... }:
let
  cfg = config.programs.agencyKitty;
  isSeat = osConfig.myFleet.has "seat";
  assets = "${cfg.package}/share/agency-kitty/kitty";
in
{
  options.programs.agencyKitty = {
    enable = lib.mkEnableOption "native Kitty transport and DSH/Imagine workflow extensions";
    package = lib.mkOption {
      type = lib.types.package;
      description = "The reviewed agency-kitty package, built from its dedicated repository.";
    };
    kittyPackage = lib.mkOption {
      type = lib.types.package;
      default = pkgs.kitty;
      description = "The separately qualified native Kitty package; changing it affects newly opened terminals.";
    };
    editorKitten = lib.mkOption {
      type = lib.types.str;
      default = "${assets}/agency_editor.py";
      description = "Absolute path to the independently qualified native Neovim sidebar helper.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      { assertion = lib.hasPrefix "/" cfg.editorKitten;
        message = "Agency editor kitten must be installed at an absolute path."; }
      { assertion = !(cfg.package ? kittyPackage) || cfg.package.kittyPackage.outPath == cfg.kittyPackage.outPath;
        message = "Build agency-kitty against the same Kitty package selected for the native desktop."; }
    ];
    home.packages = [ cfg.package ] ++ lib.optionals isSeat [ (lib.hiPrio cfg.kittyPackage) ];
    home.sessionVariables = {
      AGENCY_KITTY_EDITOR_KITTEN = cfg.editorKitten;
      AGENCY_KITTY_COMMAND = "${cfg.package}/bin/agency-kitty";
    };
    xdg.desktopEntries = lib.mkIf isSeat {
      agency-native-terminal = {
        name = "NAS terminal";
        exec = "${cfg.package}/bin/agency-kitty desktop terminal";
        icon = "utilities-terminal";
        categories = [ "System" "TerminalEmulator" ];
        terminal = false;
      };
      agency-durable-terminal = {
        name = "Resumable NAS terminal";
        exec = "${cfg.package}/bin/agency-kitty open";
        icon = "utilities-terminal";
        categories = [ "System" "TerminalEmulator" ];
        terminal = false;
      };
      agency-session-menu = {
        name = "NAS sessions";
        exec = "${cfg.package}/bin/agency-kitty menu";
        icon = "utilities-terminal";
        categories = [ "System" ];
        terminal = false;
      };
    };
    # Kitty's raw configuration is a whole-directory link. Keep generated store
    # paths at a neutral destination, consumed by its optional globinclude.
    xdg.configFile."agency-kitty/kitty.conf" = lib.mkIf isSeat {
      text = ''
        # Generated only after the native transport candidate is enabled.
        watcher ${assets}/agency_watch.py
        env AGENCY_KITTY_EDITOR_KITTEN=${cfg.editorKitten}
        # Only the local owner socket can invoke control actions. NAS programs
        # retain OSC52 writes and prompted reads, plus ordinary OSC99 notices.
        allow_remote_control socket-only
        clipboard_control write-clipboard write-primary read-clipboard-ask read-primary-ask
        map --when-focus-on var:agency_session ctrl+b kitten ${cfg.editorKitten} sidebar
        map --when-focus-on var:agency_editor_picker=1 ctrl+b kitten ${cfg.editorKitten} sidebar
        map --when-focus-on var:agency_session ctrl+v kitten ${assets}/agency.py image
        map --when-focus-on var:agency_session ctrl+shift+c kitten ${assets}/agency.py copy
        map --when-focus-on var:agency_session ctrl+shift+h kitten ${assets}/agency.py transcript
      '';
    };
  };
}
