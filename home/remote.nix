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

  # wayvnc binds the single active output automatically — everywhere, including the
  # headless worker. Pinning the worker to a guessed connector name (--output DP-1)
  # was a crash-loop waiting to happen; headless-display.nix now force-enables
  # several candidate connectors and whichever lights up is the one to capture.
  vncOutput = null;
  outputArg = lib.optionalString (vncOutput != null) " --output ${vncOutput}";

  # A Remmina VNC profile for each host other than this one → any box reaches any box.
  others = lib.filter (h: h != hostName) (lib.attrNames registry);
  mkProfile = h: {
    name = "remmina/${h}.remmina";
    # force: Remmina rewrites its own profiles at runtime (window geometry, keyboard
    # grab, etc.), replacing HM's store symlink with a plain file. Without force the
    # next activation aborts with "would be clobbered", failing home-manager-tom.service
    # and the whole nixos-upgrade switch. The template is authoritative here — geometry
    # is niri's job (viewmode=1/scale=1) — so overwrite Remmina's runtime scribbles.
    value.force = true;
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
      # viewmode=1 → Remmina windowed (not auto-fullscreen), so niri's maximized
      # window-rule governs geometry. scale=1 → fit the remote framebuffer to that
      # window, so a maximized session fills the column cleanly regardless of the
      # DPI/resolution mismatch between the high-DPI zenbook and the headless Strix
      # outputs (wayvnc doesn't negotiate dynamic remote resize).
      viewmode=1
      scale=1
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

  # wayvnc config. wayvnc runs with no auth — access is gated at the network layer
  # (firewalled to the tailnet + the trusted Thunderbolt link; see modules/common.nix
  # + modules/strix.nix).
  xdg.configFile."wayvnc/config".text = ''
    address=0.0.0.0
    port=5900
  '';

  # Remmina mesh profiles. These are connection *data*, not app config — Remmina scans
  # $XDG_DATA_HOME/remmina (~/.local/share/remmina) for .remmina files, while
  # ~/.config/remmina only holds remmina.pref (app preferences). Putting these under
  # xdg.configFile silently produces files Remmina's main window never lists. Remmina
  # passwords are left blank on purpose — Remmina's per-user encryption key can't be
  # reproduced declaratively, so the first connect prompts once and (if saved) stores
  # it in gnome-keyring. Launch: `remmina -c ~/.local/share/remmina/<host>.remmina`.
  xdg.dataFile = lib.listToAttrs (map mkProfile others);
}
