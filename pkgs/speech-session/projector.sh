#!/usr/bin/env bash
set -euo pipefail
[[ $(hostname) == client || $(hostname) == coordinator ]] || exit 2
[[ $# == 1 && $1 =~ ^[a-zA-Z0-9]+:p[0-9]+$ ]] || exit 2
# Native client window initially focused on this session through its own protocol.
# Hold-Space and clipboard support stay on the laptop. No global focus API
# and no compositor brightness/power action. Herdr owns the persistent terminal.
# The window is spawned THROUGH the compositor so it gets the session's
# environment: scroll (`scrollmsg exec`, SCROLLSOCK comes from the user manager,
# exported by /etc/scroll/config.d/10-session.conf) or niri (the rollback).
# $1 is validated above to [a-zA-Z0-9:p], so it is safe inside the quoted exec.
if systemctl --user show-environment | grep -q '^SCROLLSOCK='; then
  systemd-run --user --quiet --collect --unit="speech-projector-$$" -- \
    scrollmsg "exec env HERDR_INITIAL_PANE=$1 kitty --class herdr-projector --title 'Tom — speech' -e \"\$HOME/.local/bin/herdr-projector\""
else
  systemd-run --user --quiet --collect --unit="speech-projector-$$" -- niri msg action spawn -- env "HERDR_INITIAL_PANE=$1" kitty --class herdr-projector --title 'Tom — speech' -e "$HOME/.local/bin/herdr-projector"
fi
