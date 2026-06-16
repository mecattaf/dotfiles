# Remote terminal setup — multi-session kitty + fish + shpool

Goal: from the laptop, `Mod+Shift+Return` opens a new kitty window that
SSHs into `harness-desktop` over Tailscale and drops into a **fresh**,
persistent fish shell. Hit it again, get a second independent session.
Each session is named by a UUID, in the same style as Claude Code's
`claude --resume <uuid>`.

## The pieces

```
niri binds.kdl
  └─ Mod+Shift+Return → ~/.local/bin/new-terminal
       └─ off-host: kitty fish -ic desk
            └─ fish function `desk` (conf.d/remote.fish)
                 └─ kitten ssh harness-desktop -t shpool attach -c fish <uuid>
                      └─ shpool daemon on desktop keeps the session alive
```

## What was broken

`desk` hard-coded the session name to `"main"`, so every `Mod+Shift+Return`
reattached to the same shpool session. Two kitty windows fighting over one
shell. Looked like a shpool limitation; was a wrapper bug.

## The fix

`home/dot_config/fish/conf.d/remote.fish`:

```fish
if test (hostname) != "harness-desktop"
    function desk
        # No arg → fresh UUID, like `claude` spawning a new session.
        # Arg → reattach to that session id, like `claude --resume <uuid>`.
        set session (if test (count $argv) -gt 0; echo $argv[1]; else; cat /proc/sys/kernel/random/uuid; end)
        kitty @ set-window-title "remote"
        kitten ssh harness-desktop -t shpool attach -c fish $session
        kitty @ set-window-title
    end
end
```

Key change: default session name is now `cat /proc/sys/kernel/random/uuid`
(Linux's kernel UUID source — always available, no `uuidgen` dep, lowercase
v4 format like `f3392111-be29-441b-9e84-39c5331f4406`). `shpool attach -c
fish <name>` creates the session if it doesn't exist, attaches if it does
— so the same command handles both "new" and "resume".

## Usage

| Intent               | Command                              |
|----------------------|--------------------------------------|
| New remote shell     | `Mod+Shift+Return` (or `desk`)       |
| Resume a shell       | `desk <uuid>`                        |
| Pick a session to resume | `Mod+Ctrl+Shift+Return` (or `desk-resume`) |
| List live sessions   | `ssh harness-desktop shpool list`    |
| Kill a session       | `ssh harness-desktop shpool kill <uuid>` |

### The resume picker (`shpool-resume`)

`Mod+Ctrl+Shift+Return` runs `~/.local/bin/shpool-resume` on the desktop
through an fzf picker. It lists two groups:

- **● live shpool sessions**, each annotated with its working directory and
  the program running inside (`claude` / `nvim` / `shell`) plus an age and an
  `*` if a client is already attached — so bare-UUID names are identifiable.
  Selecting one does `shpool attach -f`.
- **○ recently-closed Claude sessions** — Claude Code conversations under
  `$CLAUDE_CONFIG_DIR` (default `~/.claude-main`) that are *not* currently live
  in any shpool session, shown with their directory and opening prompt.
  Selecting one spawns a fresh shpool session that `claude --resume`s it in the
  right directory.

The closed group exists because shpool only tracks *live* sessions: a Claude
session whose terminal was closed (or whose laptop rebooted, dropping the ssh
attach) disappears from `shpool list` even though its transcript is fully
resumable. This surfaces those so an accidental close is one keypress to
recover. Tunables: `SHPOOL_RESUME_CLOSED_DAYS` (default 3),
`SHPOOL_RESUME_CLOSED_LIMIT` (default 8).

## Supporting config (already in place before this fix)

- `home/dot_config/shpool/config.toml`
  - `forward_env = ["SSH_CONNECTION", "SSH_TTY", "SSH_CLIENT", "SSH_AUTH_SOCK"]`
    so starship can detect "I'm on the remote" via `SSH_CONNECTION` and
    render the green arrow prompt.
  - `session_restore_mode = "screen"` — uses shpool's `shpool_vt100` parser
    to replay the last screen on reattach.
  - `WAYLAND_DISPLAY = "wayland-1"` forwarded so `wl-copy` / `wl-paste`
    work inside shpool sessions.
- `home/dot_config/niri/window-rules.kdl` — matches kitty windows titled
  `remote` (set by `desk`) and applies a distinct border so I can see at
  a glance which window is the remote.
- `home/dot_config/niri/binds.kdl` — `Mod+Shift+Return` →
  `~/.local/bin/new-terminal`.
- `~/.local/bin/new-terminal` — on the laptop, delegates to
  `kitty fish -ic desk`; on the desktop, opens a local kitty in the
  focused window's cwd (inherits from a descendant nvim if one exists).

## Why this stack instead of Zellij

See `SHPOOL_VS_ZELLIJ.md`. Short version: niri already tiles at the window
level, so Zellij's panes would duplicate that. shpool covers the one
concern niri can't — keeping the shell alive across disconnects — and
that's all it needs to do.
