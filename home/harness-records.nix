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
    # 2026-09-20 corrections: `mountpoint`, for the NAS guard in the script.
    pkgs.util-linux
  ];

  recordPath = lib.makeBinPath [ pkgs.python3 ];
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
  # 2026-09-20 corrections: the mirror TARGET moved from ~/archives/claude-code-
  # mirror to /mnt/nas/documents/session-archive/claude-code-mirror/. ~/archives is
  # on the after-switch removal list, and the NAS root does not exist yet (MEASURED
  # 2026-09-20: /mnt/nas/documents/session-archive is absent, /mnt/nas has 1.6T
  # free), the after-switch list creates it, rsyncs the existing home mirror onto
  # it, and only then removes ~/archives. The script creates it if missing and
  # refuses outright when /mnt/nas is not mounted.
  #
  # SWITCH COLLISION — the hand-written files must be gone BEFORE the switch:
  #   systemctl --user disable --now claude-transcript-mirror.timer
  #   rm ~/.config/systemd/user/claude-transcript-mirror.{service,timer}
  # home-manager will not write over a plain file of the same name.
  #
  # Semantics are otherwise unchanged from the hand-written pair: oneshot,
  # Nice=10, Persistent=true. The CADENCE changed on 2026-09-20, see the timer.
  systemd.user.services.claude-transcript-mirror = lib.mkIf isCoordinator {
    Unit.Description = "Additive mirror of Claude Code transcripts";
    Service = {
      Type = "oneshot";
      # The mirror is bulk rsync over the seats' project trees; it must never
      # compete with an interactive session for CPU. Nice=10 carried over from
      # the hand-written unit verbatim.
      Nice = 10;
      # 2026-09-20 corrections: the script now calls `mountpoint` before it will
      # write to /mnt/nas, so util-linux joins the unit's PATH.
      Environment = [ "PATH=${mirrorPath}" ];
      ExecStart = "%h/.local/bin/claude-transcript-mirror";
    };
  };

  systemd.user.timers.claude-transcript-mirror = lib.mkIf isCoordinator {
    Unit.Description = "Nightly additive mirror of Claude Code transcripts (23:55)";
    Timer = {
      # 2026-09-20 corrections: hourly (OnBootSec=5min, OnUnitActiveSec=1h)
      # became one wall-clock run a night, at 23:55.
      #
      # WHY ONCE, AND WHY 23:55. The hourly tick was bulk rsync over every seat's
      # project tree, twenty-four times a day, for a mirror nothing reads between
      # runs. It is also no longer the only thing that mirrors: the memory drain
      # runs the mirror IN-FLOW at the 00:01 seal (D13), so the sessions of a day
      # are already carried as that day is sealed. 23:55 is five minutes ahead of
      # that seal, which puts the scheduled sweep on the correct side of the date
      # boundary: it closes the day it belongs to rather than racing the seal for
      # it.
      OnCalendar = "*-*-* 23:55:00";
      # Kept, and it matters more now than it did hourly: with one wake a night, a
      # box that was asleep at 23:55 would otherwise skip a whole day. A box that
      # was asleep through a scheduled run still mirrors on wake, the whole value
      # of the mirror is that it has no gaps.
      Persistent = true;
    };
    Install.WantedBy = [ "timers.target" ];
  };

  # ── the nightly record (mined 10: outside tally) ───────────────────────────
  #
  # One row per seat-lane per day, appended to
  # ~/.local/state/nightly-record/<date>.jsonl, read from the harnesses' own
  # transcripts. It records; it does not admit, ration, or feed tally — wiring
  # these numbers in as a pool usageMeter is dotfiles#304, after P06/EXP-002.
  #
  # The program is home/dot_local/bin/nightly-record: python3, stdlib only, so
  # the unit needs nothing but a python3 on PATH.
  systemd.user.services.nightly-record = lib.mkIf isCoordinator {
    Unit.Description = "Record yesterday's per-seat token spend from the harness transcripts";
    Service = {
      Type = "oneshot";
      # Same reason as the mirror: bulk reads over every seat's project tree.
      Nice = 10;
      Environment = [ "PATH=${recordPath}" ];
      ExecStart = "%h/.local/bin/nightly-record";
    };
  };

  systemd.user.timers.nightly-record = lib.mkIf isCoordinator {
    Unit.Description = "Daily per-seat token record";
    Timer = {
      # Default OnCalendar = daily is 00:00; the program reads the PREVIOUS
      # day, so it never races a day that is still being written.
      OnCalendar = "daily";
      # A box that was off at midnight still records that day on next boot.
      # This is the field that makes the record gapless, which is the only
      # property that makes a weekly budget row checkable against it.
      Persistent = true;
    };
    Install.WantedBy = [ "timers.target" ];
  };
}
