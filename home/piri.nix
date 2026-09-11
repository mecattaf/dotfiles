{
  inputs,
  lib,
  pkgs,
  osConfig,
  ...
}:
# piri — niri IPC extension daemon (github.com/Asthestarsfalll/piri). Consumed
# like ntm: a flake input pinned in flake.lock (follows nixpkgs). piri ships a
# NixOS module (services.piri) but NO home-manager module — only
# packages.default — so this file IS the module: package + user service. The
# config lives at ~/.config/niri/piri.toml, delivered RAW through the niri
# whole-dir out-of-store symlink (home/dot_config/niri/piri.toml, see
# home/home.nix configDirs) so it hot-reloads with the rest of the niri config.
#
# Not gated on a HOST NAME (unlike tally, which is coordinator-only), but gated
# all the same: piri is a general niri extension, so it belongs on every
# DISPLAY host (myDisplay.enable, modules/display.nix) and on no other. The
# older claim here — "every host in the fleet runs niri, so it runs everywhere"
# — was never true of the worker or the NAS, which run no compositor for this
# daemon's IPC to reach; it stops being true of the coordinator at the headless
# flip (R-13). Auto-started with the graphical session.
let
  piri = inputs.piri.packages.${pkgs.stdenv.hostPlatform.system}.default;
in
lib.mkIf osConfig.myDisplay.enable {
  home.packages = [ piri ]; # `piri` CLI on PATH (scratchpads/mark/... clients)

  systemd.user.services.piri = {
    Unit = {
      Description = "piri — niri IPC extension daemon";
      # Needs niri's IPC socket + Wayland session up. PartOf stops it with the
      # session.
      After = [ "graphical-session.target" ];
      Wants = [ "graphical-session.target" ];
      PartOf = [ "graphical-session.target" ];
    };
    Service = {
      ExecStart = "${lib.getExe piri} daemon";
      Restart = "on-failure";
      RestartSec = 3;
    };
    Install.WantedBy = [ "graphical-session.target" ];
  };
}
