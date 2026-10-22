# 10-aliases.fish: every plain alias of the interactive shell.
# What it replaced: these lines lived in config.fish until 2026-10-22; moved
# verbatim (README.md in this folder lists the old line numbers).
# Deliberately absent: the cx and cax agent launchers (conf.d/30-shell-verbs.fish).
# conf.d runs before config.fish and also in non interactive shells, so this
# fragment repeats the guard of the 2026-07-13 ruling (see config.fish): eza
# aliases with forced colour must never reach captured output.
status is-interactive || exit

alias vi='nvim'

# Using eza instead of ls — color/icons =auto so command substitutions and
# pipes inside an interactive session still capture plain text
alias ls='eza --color=auto --group-directories-first --icons=auto'
alias l='eza -bGF --header --git --color=auto --group-directories-first --icons=auto'
alias ll='eza -la --icons=auto --octal-permissions --group-directories-first'
alias llm='eza -lbGd --header --git --sort=modified --color=auto --group-directories-first --icons=auto'
alias la='eza --long --all --group --group-directories-first'
alias lx='eza -lbhHigUmuSa@ --time-style=long-iso --git --color-scale --color=auto --group-directories-first --icons=auto'

# Specialty views
alias lS='eza -1 --color=auto --group-directories-first --icons=auto'
alias lt='eza --tree --level=2 --color=auto --group-directories-first --icons=auto'
alias l.="eza -a | grep -E \"^\.\""

# Replace cd with zoxide
# (new 2026-10-22: z itself comes from conf.d/20-tools.fish; the alias needs it
# only at call time, so 10 loading before 20 is harmless)
alias cd='z'
# zi command

# ── Music ────────────────────────────────────────────────────────────────
# The library lives on the NAS and is served by Navidrome (hosts/nas/media.nix).
# The cliamp TUI client and its m/music/mp/mn/mb/mnow aliases were removed
# 2026-09-17 (unused).
alias mscan='navidrome-scan'                     # reindex after a beets pass (--full for tag-only edits)

## Not verified
# Not run in a live shell; checked with `fish --no-execute` only.
# No second reader (Tom's light verification rule, 2026-10-20).
