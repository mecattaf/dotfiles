{
  lib,
  osConfig,
  pkgs,
  ...
}:
# harness-records — what the agent harnesses leave behind, kept.
#
# No user service lives here any more: the Claude Code transcript mirror left
# dotfiles (dotfiles#741; Tom: no scheduled work in dotfiles, ever). What is
# left is brain-gated state that seat readers expect, plus one compute tool.
let
  isBrain = osConfig.myFleet.has "brain";
in
{
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
