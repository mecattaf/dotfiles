{
  inputs,
  lib,
  pkgs,
  osConfig ? null,
  ...
}:
# ntm — niri tablet management (github.com/mecattaf/ntm): edge-initiated
# multi-finger touchscreen gestures + accelerometer rotation for the Zenbook
# Duo's dual stacked touch panels. Consumed like tally — a mecattaf flake
# input pinned in flake.lock — but ntm ships no home-manager module (only
# packages.*.ntm), so this file IS the module: package + config + user
# service, all gated to the zenbook-duo. home/home.nix imports it on every
# host, but everywhere else (Strix pair, standalone bridge) the mkIf leaves
# it inert, same shape as tally's conductor gate.
#
# Division of labor with the PR #1856 niri fork (hosts/zenbook-duo +
# niri-local.kdl): niri maps each panel's raw touches to the right output;
# ntm layers bezel-edge gestures and rotation on top of that mapping.
# Rotation reads net.hadess.SensorProxy on the SYSTEM bus — provided by
# hardware.sensor.iio.enable in hosts/zenbook-duo/default.nix (NixOS's
# spelling of iio-sensor-proxy). Raw libinput access rides on the fleet-wide
# "input" group membership (modules/common.nix).
let
  hostName = if osConfig == null then "bridge" else osConfig.networking.hostName;
  isZenbook = hostName == "zenbook-duo";
  ntm = inputs.ntm.packages.${pkgs.stdenv.hostPlatform.system}.ntm;
in
lib.mkIf isZenbook {
  home.packages = [ ntm ]; # `ntm probe` / `ntm run` on PATH for hand-tuning

  # The pinned rev's own zenbook-duo example IS the config — it encodes this
  # exact machine (ELAN9008/9009 panels → eDP-1/eDP-2, the seam gestures,
  # per-output rotation tables), so the config moves in lockstep with
  # `nix flake update ntm`. Fork into local text here only if the laptop's
  # tuning ever needs to diverge from the repo's example.
  xdg.configFile."ntm/config.toml".source = "${inputs.ntm}/examples/zenbook-duo.toml";

  # Shipped PRESENT BUT NOT AUTO-STARTED — deliberately no Install.WantedBy:
  # gestures are mid-tuning with `cargo run` on the laptop, and a second live
  # instance would double-fire every gesture. Start it by hand when wanted:
  #   systemctl --user start ntm
  # Once tuning settles, add Install.WantedBy = [ "graphical-session.target" ]
  # to auto-start with the session (then wayvnc in remote.nix is the sibling).
  systemd.user.services.ntm = {
    Unit = {
      Description = "ntm — niri touchscreen gestures + accelerometer rotation";
      # Needs niri's IPC socket + Wayland session up. PartOf stops it with the
      # session even when started manually. Rotation's other dependency —
      # iio-sensor-proxy — is a D-Bus-activated SYSTEM service (user units
      # cannot Wants= across the manager boundary), so ntm's SensorProxy
      # claim activates it on demand; nothing to order against here.
      After = [ "graphical-session.target" ];
      Wants = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${lib.getExe ntm} run";
      Restart = "on-failure";
      RestartSec = 3;
    };
  };
}
