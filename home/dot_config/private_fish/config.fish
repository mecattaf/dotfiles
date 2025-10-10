set fish_greeting
set -Ua fish_user_paths $HOME/.local/bin

export MICRO_TRUECOLOR=1
printf '\033[?1h\033=' >/dev/tty

export ESCDELAY=0

alias vi='nvim'

set -gx EDITOR 'nvim'

set -x STARSHIP_CONFIG ~/.config/starship/starship.toml
starship init fish | source
zoxide init fish | source

type -q atuin || exit
set -gx ATUIN_NOBIND "true"
atuin init fish | source

# Using eza instead of ls
alias ls='eza --color=always --group-directories-first --icons'
alias l='eza -bGF --header --git --color=always --group-directories-first --icons'
alias ll='eza -la --icons --octal-permissions --group-directories-first'
alias llm='eza -lbGd --header --git --sort=modified --color=always --group-directories-first --icons'
alias la='eza --long --all --group --group-directories-first'
alias lx='eza -lbhHigUmuSa@ --time-style=long-iso --git --color-scale --color=always --group-directories-first --icons'

# Specialty views
alias lS='eza -1 --color=always --group-directories-first --icons'
alias lt='eza --tree --level=2 --color=always --group-directories-first --icons'
alias l.="eza -a | grep -E \"^\.\""

# Replace cd with zoxide
alias cd='z'
# zi command 

# Bind Ctrl+E to Atuin search
bind \ce "atuin search -i"
# Restore default Fish up-arrow behavior
bind --preset \e\[A history-search-backward
