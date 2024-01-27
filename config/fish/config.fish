set fish_greeting
set -Ua fish_user_paths $HOME/.local/bin

export MICRO_TRUECOLOR=1
printf '\033[?1h\033=' >/dev/tty

export ESCDELAY=0

alias vi='nvim'

set -gx EDITOR 'nvim'

set -x STARSHIP_CONFIG ~/.config/starship/starship.toml
starship init fish | source
