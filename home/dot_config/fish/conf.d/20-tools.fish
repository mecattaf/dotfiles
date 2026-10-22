# 20-tools.fish: tool inits for the interactive shell (starship prompt, zoxide,
# atuin history search on Ctrl+E).
# What it replaced: these lines lived in config.fish until 2026-10-22; moved
# verbatim. home/home.nix keeps programs.atuin.enableFishIntegration = false so
# this file stays the only atuin init (its comment still names config.fish).
# Deliberately absent: any home-manager generated fish integration.
# Interactive only, same guard as config.fish (2026-07-13 ruling): `starship init`
# and `atuin init` must not run for ssh commands or scripts.
status is-interactive || exit

set -x STARSHIP_CONFIG ~/.config/starship/starship.toml
starship init fish | source
zoxide init fish | source

# atuin last: `exit` below ends only this fragment when atuin is missing, the
# same effect it had at the bottom of the old config.fish.
type -q atuin || exit
set -gx ATUIN_NOBIND "true"
atuin init fish | source
# Bind Ctrl+E to Atuin search
bind \ce "atuin search -i"
# Restore default Fish up-arrow behavior
bind --preset \e\[A history-search-backward
# These binds now run before config.fish sets fish_key_bindings. That is safe:
# the reload handler (__fish_reload_key_bindings) is defined inside
# __fish_config_interactive, which fish runs at the first prompt, after all
# config (MEASURED 2026-10-22: `fish --no-config -c 'functions __fish_config_interactive'`
# on fish 4.8.1).

## Not verified
# The Ctrl+E bind surviving the first prompt was reasoned, not observed in a live shell.
# No second reader (Tom's light verification rule, 2026-10-20).
