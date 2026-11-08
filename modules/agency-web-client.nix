{ config, lib, pkgs, ... }:
let
  cfg = config.programs.agencyWebClient;
  legacyLauncher = pkgs.writeTextFile {
    name = "agency-web-client";
    destination = "/bin/agency-web";
    executable = true;
    text = "#!${pkgs.python3}/bin/python3\n" + builtins.readFile ./agency-web/client-launcher.py;
  };
  # Freeze the Python import graph together. The old launcher remains the
  # ambient bootstrap; the ordinary Agency Web entry opens Chrome --app.
  helpers = pkgs.runCommand "agency-chat-window-helpers" {} ''
    mkdir -p "$out"
    cp ${./agency-web/chat-window}/*.py "$out/"
    cp -R ${./agency-web/chat-window/native_terminal} "$out/native_terminal"
  '';
  launcher = pkgs.writeShellScriptBin "agency-web" ''
    exec ${pkgs.python3}/bin/python3 ${helpers}/chrome_launcher.py "$@"
  '';
  composerLauncher = pkgs.writeShellScriptBin "agency-chat-window" ''
    exec ${pkgs.python3}/bin/python3 ${helpers}/chrome_launcher.py "$@"
  '';
  catalogue = pkgs.writeShellScriptBin "agency-chat-catalogue" ''
    exec ${pkgs.python3}/bin/python3 ${helpers}/catalogue_client.py "$@"
  '';
  terminal = pkgs.writeShellScriptBin "agency-chat-terminal" ''
    exec ${pkgs.python3}/bin/python3 ${helpers}/terminal_launcher.py "$@"
  '';
  layoutIdentity = pkgs.writeShellScriptBin "agency-layout-identity" ''
    exec ${pkgs.python3}/bin/python3 ${helpers}/layout_identity.py "$@"
  '';
  desktop = pkgs.makeDesktopItem {
    name = "agency-web";
    desktopName = "Agency Web";
    comment = "Open the NAS-owned Agency chat";
    exec = "${launcher}/bin/agency-web";
    icon = "internet-chat";
    categories = [ "Network" "Chat" ];
    terminal = false;
  };
  ambientBootstrap = pkgs.writeShellScriptBin "agency-chat-ambient-bootstrap" ''
    exec ${legacyLauncher}/bin/agency-web --ambient-bootstrap
  '';
in {
  options.programs.agencyWebClient = {
    enable = lib.mkEnableOption "the browser-only Agency Web launcher";
    ambient.enable = lib.mkEnableOption "the optional Imagine-owned ambient chat bootstrap";
  };
  config = lib.mkIf cfg.enable {
    home-manager.users.tom.home.file = {
      ".config/kitty-dsh/agent-windows.json".text = builtins.toJSON { launcher = "/home/tom/.local/lib/kitty-dsh/agent-windows-v1/client"; };
      ".local/lib/kitty-dsh/agent-windows-v1/client" = { source = ./agency-web/agent-windows/client; executable = true; };
      ".local/lib/kitty-dsh/agent-windows-v1/client.py".source = ./agency-web/agent-windows/client.py;
      ".local/lib/kitty-dsh/agent-windows-v1/transport.py".source = ./agency-web/agent-windows/transport.py;
      ".local/state/imagine/.keep".text = "";
    };
    environment.systemPackages = [ launcher composerLauncher catalogue terminal layoutIdentity desktop pkgs.openssh ]
      ++ lib.optional cfg.ambient.enable ambientBootstrap;
  };
}
