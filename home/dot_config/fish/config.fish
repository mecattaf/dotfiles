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

# Claude Code: two seats (2026-09-22), plain launchers (Tom, 2026-11-25: "cc and
# cc2 shortcuts must be regular fish shell shortcuts that do claude
# --dangerously-skip-permissions not cd into ~/today etc.").
#   cc  / cac   -> ~/.claude       the personal Claude Max login (gmail org)
#   cc2 / cac2  -> ~/.claude-work  the leger.run Claude Max login
# Each starts in the current directory. Chats reach the journal by hard links
# made by the chats protocol in the agency, whatever the cwd, so no launch-time
# cd is needed. CLAUDE_CONFIG_DIR isolates login, history and state per seat;
# a terminal opened inside a cc2 session already carries it, so cc clears it
# (measured 2026-09-22). Agent view stays off for both seats (2026-10-12).
function cc;   env -u CLAUDE_CONFIG_DIR CLAUDE_CODE_DISABLE_AGENT_VIEW=1 claude --dangerously-skip-permissions $argv; end
function cac;  cc --continue $argv; end
function cc2;  env CLAUDE_CONFIG_DIR=$HOME/.claude-work CLAUDE_CODE_DISABLE_AGENT_VIEW=1 claude --dangerously-skip-permissions $argv; end
function cac2; cc2 --continue $argv; end
# Codex, same shape: cx starts, cax resumes the newest session. codex 0.160.0
# auto-starts a shared app-server daemon that copies its install into
# ~/.codex/packages and needs a codex-package.json manifest the Nix build did
# not ship ("this CLI has no complete local package", 2026-10-04), so the
# launchers run the embedded server as before 0.160. The llm-agents build of
# codex 0.162.1 ships the manifest (libexec/codex/codex-package.json), so the
# flag is now a choice rather than a workaround; it stays until Tom decides on
# the shared daemon.
function __agency_codex
    if set -q AGENCY_KITTY_SESSION; and test -n "$AGENCY_KITTY_SESSION"; and set -q AGENCY_KITTY_COMMAND
        command $AGENCY_KITTY_COMMAND harness codex -- $argv
    else
        command codex $argv
    end
end
function cx; __agency_codex --disable daemon_auto_start --dangerously-bypass-approvals-and-sandbox $argv; end
function cax; __agency_codex resume --last --disable daemon_auto_start --dangerously-bypass-approvals-and-sandbox $argv; end

# Go: module cache and GOPATH under XDG, never ~/go (25 Nov 2026). Same values
# as home.sessionVariables in home.nix, for shells that do not read those.
set -gx GOPATH $HOME/.local/share/go
set -gx GOMODCACHE $HOME/.cache/go/mod

# ── Music ────────────────────────────────────────────────────────────────
# The library lives on the NAS and is served by Navidrome (hosts/nas/media.nix).
# The cliamp TUI client and its m/music/mp/mn/mb/mnow aliases were removed
# 2026-09-17 (unused).
alias mscan='navidrome-scan'                     # reindex after a beets pass (--full for tag-only edits)

type -q atuin || exit
set -gx ATUIN_NOBIND "true"
atuin init fish | source
# Bind Ctrl+E to Atuin search
bind \ce "atuin search -i"
# Restore default Fish up-arrow behavior
bind --preset \e\[A history-search-backward
