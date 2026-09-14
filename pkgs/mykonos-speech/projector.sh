#!/usr/bin/env bash
set -euo pipefail
[[ $(hostname) == client ]] || exit 2
[[ $# == 1 && $1 =~ ^[a-zA-Z0-9]+:p[0-9]+$ ]] || exit 2
# Native client window initially focused on this session through its own protocol.
# Hold-Space and clipboard support stay on the laptop. No global focus API
# and no Niri brightness/power action. Herdr owns the persistent terminal.
systemd-run --user --quiet --collect --unit="mykonos-projector-$$" -- niri msg action spawn -- kitty --class herdr-projector --title 'Tom — speech' --env "HERDR_INITIAL_PANE=$1" -e "$HOME/.local/bin/herdr-projector"
