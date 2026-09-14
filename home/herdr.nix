{
  config,
  inputs,
  lib,
  pkgs,
  osConfig,
  ...
}:
# herdr — the terminal workspace manager for AI coding agents
# (github.com/herdrdev/herdr), pinned in flake.lock at 0.9.0. This file IS the
# module: herdr ships packages.<sys>.herdr and nothing else — no NixOS module,
# no home-manager module — so package + user service + config live here, the
# way home/piri.nix does the same job for piri.
#
# TOPOLOGY (ruling B5). ONE server, coordinator only. Every host with an
# interactive profile gets the BINARY, because the client is how you reach a
# server at all: on the coordinator `herdr` attaches to the local one, and off
# it `herdr --remote coordinator` attaches over the tailnet — on the client
# as ~/.local/bin/herdr-projector, the window every herdr chord there targets
# (home/dot_config/niri/binds.kdl, #385), and `desk` in
# home/dot_config/fish/conf.d/remote.fish. herdr-kitten (`hk`) was removed
# fleet-wide on 2026-09-13: it could not cross the ssh boundary. The NAS is
# not in this picture — it stops at NixOS with no home-manager, so nothing
# here can reach hosts/nas/tv.nix.
#
# LIFECYCLE (ruling B6). Deliberately NOT PartOf=graphical-session.target. The
# whole point of the server is that the PTYs outlive the surfaces attached to
# them: restart niri, log out, close the laptop lid on another host, and the
# panes are still running when a client comes back. Binding it to the graphical
# session would kill every session on a compositor restart, which is exactly
# the failure the deleted home-grown tier had. `loginctl enable-linger tom`
# holds on the coordinator (see home/home.nix) and is what keeps it up with no
# login session open.
#
# OOM RULING (#352). The server must survive its own pane children just as B6
# says it survives the compositor. A process launched in a pane remains in the
# herdr cgroup; systemd's DefaultOOMPolicy=stop turns the kernel's targeted kill
# of one runaway child into a stop of the server and every unrelated pane.
# OOMPolicy=continue leaves the kernel's chosen victim dead and the rest of the
# workspace estate alive. No MemoryHigh/MemoryMax is set on this WHOLE cgroup:
# that would throttle or protect the runaway descendants together with the
# small server. Unattended work gets workload-specific limits at its own
# systemd action boundary instead (#357).
#
# CONFIG (ruling B7). ~/.config/herdr is herdr's RUNTIME directory — it holds
# the server socket, plugins.json, and the session store — so it must stay a
# real writable directory. Only config.toml is ours, delivered as a SINGLE-FILE
# out-of-store symlink into the git checkout: editable in place, reloadable
# with prefix+shift+r, no rebuild. Never a whole-dir link, and plugins.json is
# never generated from nix (ruling B9): `herdr plugin link` stays imperative.
#
# FOOTGUNS on the projector path (#385 seam 12), recorded, not fixed here:
#   * If this unit is STOPPED while a projector attaches, the remote side's
#     `remote-client-bridge` spawns an unmanaged server daemon, which later
#     fights the unit over herdr.sock (herdr src/remote/host_unix.rs:264-287).
#     Start the unit before reattaching anything. herdr-projector refuses
#     to (re)attach until `systemctl --user is-active herdr` answers active
#     on the target, so its reconnect loop cannot race a reboot into this.
#   * `herdr --remote` may offer, interactively, to STOP and REPLACE this
#     server — killing every pane — if it judges the server incompatible.
#     Today the policy is keep-running (endpoint generation 1 on both ends).
#     Any herdr bump must land on the coordinator before or with the client.
#   * If no generation-1 `herdr` is on the coordinator's PATH, the projector
#     offers to install a non-Nix binary into ~/.local/bin/herdr. Decline.
#   * The unit below must not change as a side effect of an edit elsewhere:
#     a changed unit restarts on the next switch and kills every pane.
let
  hostName = osConfig.networking.hostName;
  system = pkgs.stdenv.hostPlatform.system;
  herdr = import ../pkgs/herdr-speech {
    upstream = inputs.herdr.packages.${system}.herdr;
    source = inputs.herdr;
  };

  repoDir = config.rawDotfiles.repoDir; # home/raw-dotfiles-guard.nix
  link = p: config.lib.file.mkOutOfStoreSymlink "${repoDir}/home/${p}";
in
{
  # `herdr` client + server on PATH, every interactive host.
  home.packages = [ herdr ];

  # RAW single-file symlink; see CONFIG above. `onboarding = false` is the first
  # assignment in that file precisely so herdr's first run never decides to
  # write its own config over a tracked path.
  xdg.configFile."herdr/config.toml".source = link "dot_config/herdr/config.toml";

  systemd.user.services.herdr = lib.mkIf (hostName == "coordinator") {
    Unit = {
      Description = "herdr — terminal workspace manager for AI coding agents";
      # NO PartOf/After/Wants on graphical-session.target: this server must
      # survive the compositor, not follow it (ruling B6).
      Documentation = [ "https://herdr.dev" ];
      # SWITCH RULING (#354, 2026-09-13). A switch never restarts this server.
      # home-manager's startServices drives sd-switch, and sd-switch restarts
      # a changed, running unit by default. For herdr that would kill every
      # live PTY, so an unattended update-adopt switch (or Tom's own) that
      # moved the herdr package or this unit file would take down all panes.
      # `keep-old` is sd-switch's own key: VERIFIED against the pinned
      # sd-switch 0.6.4 source (src/systemd/ini.rs KEY_X_SWITCHMETHOD,
      # "keep-old" => UnitSwitchMethod::KeepOld; src/lib.rs keeps the old
      # unit running for that method) and home-manager 079a3b5's
      # modules/systemd.nix X-SwitchMethod enum. The new version therefore
      # lands only on a deliberate `systemctl --user restart herdr`, the same
      # stance DF-CLIENT-7 takes. Asserted by the herdr-oom-isolation check.
      X-SwitchMethod = "keep-old";
    };
    Service = {
      ExecStart = "${lib.getExe herdr} server";
      Restart = "on-failure";
      RestartSec = 3;
      # One pane child being selected by the kernel OOM killer must not make
      # systemd tear down the server and every other pane (#352).
      OOMPolicy = "continue";
    };
    # default.target, not graphical-session.target — starts with the user
    # manager under linger, before and independently of any Wayland session.
    Install.WantedBy = [ "default.target" ];
  };
}
