{
  config,
  lib,
  pkgs,
  osConfig ? null,
  ...
}:
# Remote-access stack: wayvnc (VNC server, so any device can be viewed) + Remmina
# (VNC client, pre-loaded with a profile for every OTHER host). Only meaningful on a
# real NixOS host with a niri session — skipped on the standalone Fedora bridge.
let
  registry = import ../modules/mesh-registry.nix;
  hostName = if osConfig != null then osConfig.networking.hostName else null;

  # The headless worker captures the EDID-injected connector; everywhere else wayvnc
  # binds the single active output automatically.
  vncOutput = if hostName == "worker" then "DP-1" else null;
  outputArg = lib.optionalString (vncOutput != null) " --output ${vncOutput}";

  # A Remmina VNC profile for each host other than this one → any box reaches any box.
  others = lib.filter (h: h != hostName) (lib.attrNames registry);
  mkProfile = h: {
    name = "remmina/${h}.remmina";
    value.text = ''
      [remmina]
      name=${h} (VNC)
      protocol=VNC
      server=${builtins.head registry.${h}.aliases}:5900
      group=mesh
      colordepth=32
      quality=9
      password=
      disablepasswordstoring=1
    '';
  };
in
lib.mkIf (osConfig != null) {
  home.packages = [
    pkgs.wayvnc
    pkgs.remmina
  ];

  # Runs inside the niri graphical session. Restart-on-failure covers the brief
  # window before niri has exported its Wayland socket.
  systemd.user.services.wayvnc = {
    Unit = {
      Description = "wayvnc — VNC server for the niri session";
      After = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${pkgs.wayvnc}/bin/wayvnc --config %h/.config/wayvnc/config${outputArg}";
      Restart = "on-failure";
      RestartSec = 3;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };

  # wayvnc config + the Remmina mesh profiles. wayvnc runs with no auth — access is
  # gated at the network layer (firewalled to the tailnet + the trusted Thunderbolt
  # link; see modules/common.nix + modules/strix.nix). Remmina passwords are left
  # blank on purpose — Remmina's per-user encryption key can't be reproduced
  # declaratively, so the first connect prompts once and (if saved) stores it in
  # gnome-keyring. Launch: `remmina -c ~/.config/remmina/<host>.remmina`.
  xdg.configFile = lib.listToAttrs (map mkProfile others) // {
    "wayvnc/config".text = ''
      address=0.0.0.0
      port=5900
    '';
  };
}
