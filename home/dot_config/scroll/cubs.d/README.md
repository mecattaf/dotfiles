# cubs.d — CUBS shell module fragments

`~/.config/scroll/config` includes `~/.config/scroll/cubs.d/*.conf` BEFORE
`binds.conf`, so Tom's hand-written binds win over anything here (scoping D5).
The glob is empty-safe: with no `*.conf` present scroll skips it.

This directory is empty on purpose. The CUBS shell will write one atomic
fragment per plugin here (keybindings compiled to `bindsym … nop cubs <verb>`,
`for_window` rules, `client.*` colours, `scrollnag_command`). Plugins supply
data and handlers, never pixels; a plugin that needs scroll Lua gets it only as
a reviewed permission, loaded from a fragment, never injected over IPC.

`~/.config/scroll` is an out-of-store symlink into the dotfiles checkout, so a
fragment written here lands in the checkout. `.gitignore` keeps every
generated `*.conf` out of git: anything Tom wants kept moves into `binds.conf`
or `rules.conf` by review. Whether generated fragments should instead live
outside the checkout (`$XDG_STATE_HOME/cubs/scroll.d`) is open (D5).
