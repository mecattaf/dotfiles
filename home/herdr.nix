{
  config,
  inputs,
  lib,
  pkgs,
  osConfig,
  ...
}:
# herdr — the terminal workspace manager for AI coding agents
# (github.com/herdrdev/herdr), pinned in flake.lock at 0.8.2. This file IS the
# module: herdr ships packages.<sys>.herdr and nothing else — no NixOS module,
# no home-manager module — so package + user service + config live here, the
# way home/piri.nix does the same job for piri.
#
# TOPOLOGY (ruling B5). ONE server, coordinator only. Every host with an
# interactive profile gets the BINARY, because the client is how you reach a
# server at all: on the coordinator `herdr` attaches to the local one, and off
# it `herdr --remote coordinator` attaches over the tailnet (see the `desk`
# function in home/dot_config/fish/conf.d/remote.fish). The NAS is not in this
# picture — it stops at NixOS with no home-manager, so nothing here can reach
# hosts/nas/tv.nix.
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
# CONFIG (ruling B7). ~/.config/herdr is herdr's RUNTIME directory — it holds
# the server socket, plugins.json, and the session store — so it must stay a
# real writable directory. Only config.toml is ours, delivered as a SINGLE-FILE
# out-of-store symlink into the git checkout: editable in place, reloadable
# with prefix+shift+r, no rebuild. Never a whole-dir link, and plugins.json is
# never generated from nix (ruling B9): `herdr plugin link` stays imperative.
let
  hostName = osConfig.networking.hostName;
  system = pkgs.stdenv.hostPlatform.system;
  herdr = inputs.herdr.packages.${system}.herdr;
  herdr-kitten = inputs.herdr-kitten.packages.${system}.herdr-kitten;

  repoDir = "${config.home.homeDirectory}/mecattaf/dotfiles";
  link = p: config.lib.file.mkOutOfStoreSymlink "${repoDir}/home/${p}";
in
{
  # `herdr` client + server and the `hk` CLI on PATH, every interactive host.
  # hk is not optional decoration: it IS the kitty side of herdr here — the
  # niri binds below the terminal keys, the kitty gestures, and the dictation
  # route all shell out to it.
  home.packages = [
    herdr
    herdr-kitten
  ];

  # The kitten half of herdr-kitten lives in the Nix store, but kitty resolves a
  # bare `kitten foo.py` against ~/.config/kitty — which here is a whole-dir
  # out-of-store symlink into the git tree, so no generated file can nest inside
  # it. Same shape as kitty-scrollback.nvim (home/home.nix): emit an
  # `action_alias` carrying the store path at a NEUTRAL ~/.config path, and let
  # the tracked, hot-reloadable kitty.conf spend it as `map <chord> hk <gesture>`.
  # The chords stay in kitty.conf where Tom can re-cut them without a rebuild —
  # upstream's README rules them "suggestions, not law".
  xdg.configFile."kitty-herdr-nix.conf".text = ''
    # GENERATED — Nix-store path for the herdr-kitten kitty kitten (offline-safe).
    action_alias hk kitten ${herdr-kitten}/share/hk/kitten/hk.py
  '';

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
    };
    Service = {
      ExecStart = "${lib.getExe herdr} server";
      Restart = "on-failure";
      RestartSec = 3;
    };
    # default.target, not graphical-session.target — starts with the user
    # manager under linger, before and independently of any Wayland session.
    Install.WantedBy = [ "default.target" ];
  };
}
