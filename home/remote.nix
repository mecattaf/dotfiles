{
  config,
  lib,
  pkgs,
  osConfig,
  ...
}:
# Remote-access stack: wayvnc (VNC server, so the coordinator's session can be
# viewed) + Remmina (VNC client, pre-loaded with a profile for every host that
# SERVES). Rendered on every niri host — the coordinator and, since 2026-09-11,
# the thin client — but the SERVER half is the coordinator's alone: a thin
# client is a viewer of the coordinator, never a thing to be viewed, and
# without this gate the client would run an unauthenticated wayvnc on :5900
# (the door is firewalled to tailscale0, which the client does not join —
# still, no unit that could never be wanted). The worker has no niri at all,
# so nothing renders there.
let
  registry = import ../modules/mesh-registry.nix;
  hostName = osConfig.networking.hostName;
  isCoordinator = hostName == "coordinator";

  # Hosts that run the wayvnc unit below. The registry says who exists; this
  # list says who serves. A profile for a host that serves nothing is a dead
  # entry in Remmina's list, so the client gets `coordinator (VNC)` and the
  # coordinator gets nothing.
  servers = [ "coordinator" ];

  # wayvnc binds the single active output automatically. Avoid pinning a guessed
  # connector name; whichever active output lights up is the one to capture.
  vncOutput = null;
  outputArg = lib.optionalString (vncOutput != null) " --output ${vncOutput}";

  # A Remmina VNC profile for each SERVING host other than this one.
  others = lib.filter (h: h != hostName) servers;
  mkProfile = h: {
    name = "remmina/${h}.remmina";
    # force: Remmina rewrites its own profiles at runtime (window geometry, keyboard
    # grab, etc.), replacing HM's store symlink with a plain file. Without force the
    # next activation aborts with "would be clobbered", failing home-manager-tom.service
    # and the whole deploy-rs switch. The template is authoritative here — geometry
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
      # DPI/resolution mismatch between whatever client is viewing and the
      # headless Strix outputs (wayvnc doesn't negotiate dynamic remote resize).
      viewmode=1
      scale=1
    '';
  };
in
lib.mkIf osConfig.programs.niri.enable {
  home.packages = [ pkgs.remmina ] ++ lib.optionals isCoordinator [ pkgs.wayvnc ];

  # Runs inside the niri graphical session. Restart-on-failure covers the brief
  # window before niri has exported its Wayland socket.
  systemd.user.services.wayvnc = lib.mkIf isCoordinator {
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
  # and firewalled to the tailnet. That :5900 admission stopped being fleet-wide
  # on 2026-09-01 and is the coordinator's alone (hosts/coordinator/tailscale.nix),
  # as is this file.
  xdg.configFile."wayvnc/config" = lib.mkIf isCoordinator {
    text = ''
      address=0.0.0.0
      port=5900
    '';
  };

  # Remmina mesh profiles. These are connection *data*, not app config — Remmina scans
  # $XDG_DATA_HOME/remmina (~/.local/share/remmina) for .remmina files, while
  # ~/.config/remmina only holds remmina.pref (app preferences). Putting these under
  # xdg.configFile silently produces files Remmina's main window never lists. Remmina
  # passwords are left blank on purpose — Remmina's per-user encryption key can't be
  # reproduced declaratively, so the first connect prompts once and (if saved) stores
  # it in gnome-keyring. Launch: `remmina -c ~/.local/share/remmina/<host>.remmina`.
  xdg.dataFile = lib.listToAttrs (map mkProfile others);
}
