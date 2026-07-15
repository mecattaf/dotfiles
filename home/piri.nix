{
  inputs,
  lib,
  pkgs,
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
# NOT host-gated (unlike ntm=zenbook-only, tally=coordinator-only): piri is a
# general niri extension and every host in the fleet runs niri, so it runs
# everywhere. Auto-started with the graphical session (unlike ntm, which omits
# WantedBy while its gestures are mid-tuning).
let
  piri = inputs.piri.packages.${pkgs.stdenv.hostPlatform.system}.default;
in
{
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
