{
  lib,
  osConfig,
  pkgs,
  ...
}:
# harness-records — what the agent harnesses leave behind, kept and counted.
#
# Two coordinator-only user timers, both OUTSIDE tally by ruling (mined 18: no
# agent-harness logic in tally, the meter is external; mined 10: the nightly
# record is outside tally). Neither reads or writes tally state; tally's own
# meters directory is declared in home/tally.nix and fed by nobody yet
# (dotfiles#304).
#
#   claude-transcript-mirror  keeps every Claude Code session past the
#                             harness's own retention (dotfiles#293)
#   nightly-record            counts what each seat spent, per lane, per day
#                             (dotfiles#298)
#
# Coordinator-gated for the same reason the tally drain is: these read seat
# state that exists on this box, and an ungated definition would ship the
# worker a timer with nothing to do.
let
  hostName = osConfig.networking.hostName;
  isCoordinator = hostName == "coordinator";

  # A systemd user unit does not inherit the interactive session PATH, and both
  # scripts are RAW dotfiles reached through the whole-dir ~/.local/bin
  # out-of-store symlink — editable without a rebuild, which is the point. So
  # the unit supplies the PATH explicitly rather than trusting the environment
  # the hand-written units happened to be started in.
  mirrorPath = lib.makeBinPath [
    pkgs.bash
    pkgs.rsync
    pkgs.coreutils
  ];
in
{
  # ── the transcript mirror (Rule 9: nothing hand-installed stays so) ─────────
  #
  # WHAT THIS REPLACES. Until 2026-09-06 this was two PLAIN FILES written by
  # hand and owned by nothing:
  #   ~/.config/systemd/user/claude-transcript-mirror.service
  #   ~/.config/systemd/user/claude-transcript-mirror.timer
  # plus an untracked ~/archives/claude-code-mirror/sync.sh. The script is now
  # home/dot_local/bin/claude-transcript-mirror, tracked.
  #
  # SWITCH COLLISION — the hand-written files must be gone BEFORE the switch:
  #   systemctl --user disable --now claude-transcript-mirror.timer
  #   rm ~/.config/systemd/user/claude-transcript-mirror.{service,timer}
  # home-manager will not write over a plain file of the same name.
  #
  # Semantics are unchanged from the hand-written pair: oneshot, Nice=10,
  # OnBootSec=5min, OnUnitActiveSec=1h, Persistent=true.
  systemd.user.services.claude-transcript-mirror = lib.mkIf isCoordinator {
    Unit.Description = "Additive mirror of Claude Code transcripts";
    Service = {
      Type = "oneshot";
      # The mirror is bulk rsync over the seats' project trees; it must never
      # compete with an interactive session for CPU. Nice=10 carried over from
      # the hand-written unit verbatim.
      Nice = 10;
      Environment = [ "PATH=${mirrorPath}" ];
      ExecStart = "%h/.local/bin/claude-transcript-mirror";
    };
  };

  systemd.user.timers.claude-transcript-mirror = lib.mkIf isCoordinator {
    Unit.Description = "Hourly additive mirror of Claude Code transcripts";
    Timer = {
      OnBootSec = "5min";
      OnUnitActiveSec = "1h";
      # A box that was asleep through a scheduled run still mirrors on wake:
      # the whole value of the mirror is that it has no gaps.
      Persistent = true;
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
