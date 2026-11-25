{
  config,
  lib,
  pkgs,
  osConfig,
  ...
}:
# hc (herdr-core, github.com/herdrdev/herdr-core, Apache-2.0): the terminal
# runtime that carries Tom's stations and the floor's workers on the brain host.
# One core per machine, default session, socket
# /run/user/<uid>/herdr-core/default.sock. This file installs the package
# (`hc`, `herdr-core`) on every host, from the shared llm-agents input (it moved
# here from the retired home/herdr.nix with Herdr v1), and adds, on the brain
# only, the two things a declared core needs: its config file and the unit that
# decides WHEN and WITH WHICH ENVIRONMENT the core starts.
# ../modules/herdr-core.nix adds kitty's terminfo on the same host. Runbook:
# docs/herdr-core.md.
#
# WHY A ONESHOT (S2 §14, holder-eval 21 Nov). Upstream ships no unit; hc
# supervises itself with transient user units it creates through systemd-run:
#   hc-serve-<hex>.service     the core (KillMode=process, OOMPolicy=continue)
#   hc-hold-<hex>.service      the holder: parent of every PTY; it respawns a
#                              crashed core after 3 s, from its own executable
#   hc-shutdown-<hash>.service a guard that stops the core before its holders
# Their names change at every start; nothing here references them. What hc
# cannot decide is when the first core starts and with which environment:
# every terminal inherits the core's environment, and a client's `env` can add
# but never unset. A core autostarted from inside a Claude Code session carries
# that session's CLAUDE_CODE_* variables and tokens into every terminal (the
# 0.1.21 default core on the NAS was started that way). So this unit is a
# oneshot that runs `herdr-core server start` from the user manager's
# environment, minus the per-launch names below, and then stays "active
# (exited)". `server start` against a core that already answers is a status
# call and exits 0: the unit never fights a running core.
#
# NEVER wrap `herdr-core serve` in a unit: `serve` exits 0 when another core
# holds the lock, so the unit goes inactive; and a unit core with Restart=
# fights `hc server restart` and the holder's own respawn (MEASURED C4,
# 21 Nov). Hence no Restart, no ExecStop (ending everything on purpose is
# `hc server stop`, typed by a person), no Environment with values (nothing
# here is meant for every terminal, and never a token), no memory limit on the
# shared cgroup, and no ManagedOOMPreference (hc leaves it unset on purpose:
# uresourced < 0.5.5 floods the manager). KillMode=process: stopping this unit
# must never end a program; the core and the holder live in hc's own units
# anyway, so a stop or restart of hc-core.service ends nothing.
#
# SWITCH. X-SwitchMethod=keep-old (as the retired Herdr v1 unit had): once the unit is active, a
# switch that moves the herdr-core store path never re-runs it. Read in the
# sd-switch source tonight (26 Nov; the NAS's home-manager-nas activates with
# sd-switch 0.6.3 from nixos-26.05, the unstable hosts with 0.6.4; both have
# the same rule in src/lib.rs, "units that are not currently active but are
# wanted by an active target"): a NEW unit, or an inactive one, that is wanted
# by an active target (default.target) is STARTED at switch unless its
# X-SwitchMethod is stop-only; keep-old does not prevent that first start. So
# the switch that lands this file starts hc-core.service once. With a core
# already answering on default.sock (the hand-started 0.1.21 core on the NAS
# tonight) that start is a status call, exit 0, and changes nothing; the
# cutover then stops the old cores and runs `systemctl --user restart
# hc-core.service`, which is correct either way.
#
# UPGRADE after a fleet switch that moved the package: run `hc-restart-clean`
# (home/dot_local/bin) in a person's shell outside any hc terminal. It runs the
# NEW binary's `server restart --fresh` from a clean environment; programs keep
# running, the old holder drains with its terminals, new terminals go to a
# new-build holder. A restart of this unit does not upgrade a running core.
#
# NEVER on this fleet: `hc update`, `hc machine update`, `hc machine add
# --install` (they copy a binary to ~/.local/bin and restart the core from it,
# off the Nix pin); a second core or HC_SESSION outside tests; `hc server
# start|restart` typed inside a Claude Code session against the live runtime;
# a template named like a binary under ~/.config/herdr-core/templates/ (it
# shadows that binary for every caller).
let
  link = config.lib.rawDotfiles.link; # home/raw-dotfiles-guard.nix
in
{
  # Every configured host carries the client and the binary; only the brain
  # runs a declared core.
  config = lib.mkMerge [
    { home.packages = [ pkgs.llm-agents.herdr-core ]; }
    (lib.mkIf (osConfig.myFleet.has "brain") {
    # RAW single-file symlink into the checkout, like Herdr v1's config.toml was:
    # ~/.config/herdr-core/ itself stays a real directory (templates/, and
    # hand-made files such as pulse-client.conf, live next to it).
    xdg.configFile."herdr-core/config.toml".source = link "dot_config/herdr-core/config.toml";

    systemd.user.services.hc-core = {
      Unit = {
        Description = "hc core for this machine (default session)";
        # sd-switch: once active, a switch never re-runs it (see SWITCH above).
        X-SwitchMethod = "keep-old";
      };
      Service = {
        Type = "oneshot";
        RemainAfterExit = true;
        KillMode = "process";
        OOMPolicy = "continue";
        # Becomes the transient core's WorkingDirectory, so the default cwd of
        # a terminal started through the API is ~.
        WorkingDirectory = "%h";
        # Per-launch values of whatever shell last imported its environment
        # into the user manager (a Claude Code session, a DSH tool shell), and
        # the one token the NAS login shell exports. The list modules/dshd.nix
        # carried for dshd instances, plus hc's own selectors: this unit always
        # means the default session on its default socket, and a core is never
        # a terminal's child.
        UnsetEnvironment = [
          "CLOUDFLARE_API_TOKEN"
          "CLAUDECODE"
          "CLAUDE_CODE_ENTRYPOINT"
          "CLAUDE_CODE_CHILD_SESSION"
          "CLAUDE_CODE_SESSION_ID"
          "CLAUDE_CODE_SESSION_ATTENDED"
          "CLAUDE_CODE_MESSAGING_SOCKET"
          "CLAUDE_CODE_MESSAGING_TOKEN"
          "CLAUDE_CODE_EXECPATH"
          "CLAUDE_PID"
          "CLAUDE_EFFORT"
          "CLAUDE_ENVELOPE"
          "CODEX_THREAD_ID"
          "DSH_SESSION_ID"
          "DSH_SHELL"
          "DSH_PROFILE_DIR"
          "DSH_WEB_URL"
          "HC_SESSION"
          "HC_SOCKET"
          "HC_TERMINAL_ID"
          "HC_TERMINAL_SOCKET"
        ];
        ExecStart = "${pkgs.llm-agents.herdr-core}/bin/herdr-core server start";
      };
      # default.target, not graphical-session.target: under linger the core
      # comes up at boot with no login session.
      Install.WantedBy = [ "default.target" ];
    };
    })
  ];
}
