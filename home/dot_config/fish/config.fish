# config.fish: the last file fish reads at startup (after every conf.d/*.fish).
# What it is: session flags, the interactive guard and the keypad escape, nothing else.
# What it replaced: until 2026-10-22 (branch dryrun/shell-consolidation-2026-10-22)
# this one file also carried the aliases, the tool inits and the agent launchers.
# They moved, unchanged, to conf.d/10-aliases.fish, conf.d/20-tools.fish and
# conf.d/30-shell-verbs.fish; README.md in this folder maps every moved line.
# Deliberately absent: universal variables (fish_variables is tracked), any
# `source` of a theme or tool fragment other than the tool inits in conf.d.
# Note on order: fish reads conf.d/ BEFORE this file and for non interactive
# shells too, so every conf.d fragment that must stay interactive only carries
# its own copy of the guard below.

set -g fish_greeting
set -g fish_key_bindings fish_default_key_bindings
set -e SSH_ASKPASS

# MICRO_TRUECOLOR / ESCDELAY / EDITOR moved to environment.sessionVariables
# (modules/common.nix) — they used to live here, above the interactive
# guard below, specifically so they'd still reach non-interactive ssh
# commands. Now that tom's login shell is bash (#236), that guard never ran
# for ssh in the first place; sessionVariables reaches every PAM session
# instead, ssh included, so the values are still there without fish's help.

# Everything below is interactive-only. Non-interactive shells (ssh commands,
# scripts, command substitutions) must get stock tools and NO tty writes —
# an unconditional `printf >/dev/tty` breaks BatchMode ssh, and eza aliases
# with forced color/icons poison captured output (e.g. ANSI codes inside
# NIRI_SOCKET). Ruling: 2026-07-13, ntm deployment session.
status is-interactive || exit

printf '\033[?1h\033=' >/dev/tty

# Aliases: conf.d/10-aliases.fish. Tool inits (starship, zoxide, atuin and its
# Ctrl+E rebind): conf.d/20-tools.fish. Agent launchers (cc, cac, cc2, cac2, cx,
# cax): conf.d/30-shell-verbs.fish. `desk`: conf.d/remote.fish (name kept, see
# herdr-projector and home/herdr.nix which point at it).

## Not verified
# Startup order after the split was reasoned from fish 4.8.1 docs and the body of
# __fish_config_interactive, not observed in a live interactive shell (no fish was
# started with this config). No second reader (Tom's light verification rule, 2026-10-20).
