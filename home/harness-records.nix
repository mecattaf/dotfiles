{
  lib,
  osConfig,
  pkgs,
  ...
}:
# harness-records — what the agent harnesses leave behind, kept.
#
# One brain-role user service, hand-run since 2026-09-30 (no scheduled
# agent work in dotfiles). It neither reads nor writes Tally state (Tally
# itself was removed the same day).
#
#   claude-transcript-mirror  keeps every Claude Code session past the
#                             harness's own retention (dotfiles#293)
#
# Brain-gated: it reads seat state that exists on this box, and an
# ungated definition would ship the worker a unit with nothing to do.
let
  isBrain = osConfig.myFleet.has "brain";

  # A systemd user unit does not inherit the interactive session PATH, and the
  # script is a RAW dotfile reached through the whole-dir ~/.local/bin
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
  # The service is unchanged from the hand-written unit: oneshot, Nice=10.
  systemd.user.services.claude-transcript-mirror = lib.mkIf isBrain {
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

  # No timer (Tom, 2026-09-30: no scheduled agent work in dotfiles; the
  # hourly jsonl mirror is exactly the case he named out). Run it by hand:
  #   systemctl --user start claude-transcript-mirror
  # The sources stay in ~/.claude*, so nothing is lost between runs.

  # ── seat meters directory (outlives the Tally seat feeder) ────────────────
  # `seats` reads its peer cache here. The seat feeder that used to write it
  # (home/seat-feeder.nix) went with the Tally sunset on 2026-09-30; the
  # directory stays declared so the reader never meets a missing path.
  systemd.user.tmpfiles.rules = lib.mkIf isBrain [
    "d %h/.local/state/tally-rewrite/meters 0700 - - -"
  ];

  # A tool home/tally.nix used to install on the strix, kept: call
  # diarization runs by hand now (its Tally events drop has no drain).
  home.packages = lib.optionals (osConfig.myFleet.has "compute") [ pkgs.call-diarize ];
}
