{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.programs.agencyWebClient;
  launcher = pkgs.writeTextFile {
    name = "agency-web-client";
    destination = "/bin/agency-web";
    executable = true;
    text = "#!${pkgs.python3}/bin/python3\n" + builtins.readFile ./agency-web/client-launcher.py;
  };
  desktop = pkgs.makeDesktopItem {
    name = "agency-web";
    desktopName = "Agency Web";
    comment = "Open the NAS-owned Agency chat";
    exec = "${launcher}/bin/agency-web";
    icon = "internet-chat";
    categories = [
      "Network"
      "Chat"
    ];
    terminal = false;
  };
  ambientBootstrap = pkgs.writeShellScriptBin "agency-chat-ambient-bootstrap" ''
    exec ${launcher}/bin/agency-web --ambient-bootstrap
  '';
in
{
  options.programs.agencyWebClient = {
    enable = lib.mkEnableOption "the browser-only Agency Web launcher";
    ambient.enable = lib.mkEnableOption "the optional Imagine-owned ambient chat bootstrap";
  };
  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      launcher
      desktop
      pkgs.openssh
    ]
    ++ lib.optional cfg.ambient.enable ambientBootstrap;
  };
}
