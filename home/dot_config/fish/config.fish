set -g fish_greeting
set -g fish_key_bindings fish_default_key_bindings
set -e SSH_ASKPASS

export MICRO_TRUECOLOR=1
export ESCDELAY=0
set -gx EDITOR 'nvim'

# Everything below is interactive-only. Non-interactive shells (ssh commands,
# scripts, command substitutions) must get stock tools and NO tty writes —
# an unconditional `printf >/dev/tty` breaks BatchMode ssh, and eza aliases
# with forced color/icons poison captured output (e.g. ANSI codes inside
# NIRI_SOCKET). Ruling: 2026-07-13, ntm deployment session.
status is-interactive || exit

printf '\033[?1h\033=' >/dev/tty

alias vi='nvim'

set -x STARSHIP_CONFIG ~/.config/starship/starship.toml
starship init fish | source
zoxide init fish | source

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
alias cd='z'
# zi command

# Claude Code
alias cc='claude --dangerously-skip-permissions'
alias cac='claude --continue --dangerously-skip-permissions'

type -q atuin || exit
set -gx ATUIN_NOBIND "true"
atuin init fish | source
# Bind Ctrl+E to Atuin search
bind \ce "atuin search -i"
# Restore default Fish up-arrow behavior
bind --preset \e\[A history-search-backward
