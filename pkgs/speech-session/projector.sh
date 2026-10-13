#!/usr/bin/env bash
set -euo pipefail
[[ $(hostname) == client || $(hostname) == strix ]] || exit 2
[[ $# == 1 && $1 =~ ^[a-zA-Z0-9]+:p[0-9]+$ ]] || exit 2
# Native client window initially focused on this session through its own protocol.
# Hold-Space and clipboard support stay on the laptop. No global focus API
# and no compositor brightness/power action. Herdr owns the persistent terminal.
# The window is spawned THROUGH the compositor so it gets the session's
# environment: Sway (`swaymsg exec`; the physical session imports SWAYSOCK into
# the user manager, modules/sway.nix) or niri (the rollback).
# $1 is validated above to [a-zA-Z0-9:p], so it is safe inside the quoted exec.
# A SWAYSOCK left in the manager by an unclean Sway exit must not send a
# later niri session's projector to swaymsg: require a live socket.
swaysock=$(systemctl --user show-environment | grep -m1 '^SWAYSOCK=' || true)
swaysock=${swaysock#SWAYSOCK=}
if [[ -n $swaysock && -S $swaysock ]]; then
  systemd-run --user --quiet --collect --unit="speech-projector-$$" -- \
    swaymsg -s "$swaysock" "exec env HERDR_INITIAL_PANE=$1 kitty --class herdr-projector --title 'Tom — speech' -e \"\$HOME/.local/bin/herdr-projector\""
else
  systemd-run --user --quiet --collect --unit="speech-projector-$$" -- niri msg action spawn -- env "HERDR_INITIAL_PANE=$1" kitty --class herdr-projector --title 'Tom — speech' -e "$HOME/.local/bin/herdr-projector"
fi
