# Remote nvim — Final Decision

> How to run nvim against my home server given a disposable thin-client laptop,
> shpool-backed sessions, kitty everywhere, and Claude Code editing files in the
> background. This note records the decision and *why*, so I don't re-litigate it.

## The setup this is for

- **Thin client laptops** — old, disposable, variable battery, half the year in
  the mountains. Nothing should be "stuck" on the laptop. Throw it in a river,
  grab the next one.
- **Powerful home server** — the source of truth for files and the compute.
- **shpool + kitty over ssh** — session recovery + keeping TUI/agent harnesses
  (Claude Code, shells) alive across laptop death. This is great and stays.
- **Claude Code runs on the server** and edits files out from under me.
- I have custom Lua that live-reflects external file changes into open nvim
  buffers (directory-watcher → checktime → diff → extmark highlight + fade,
  plus a diffview left-pane refresh).
- I barely use LSP — discount it heavily as a deciding factor.

## The conundrum

nvim was born (1976, vi on a dumb terminal over serial) for exactly the
thin-client model: editor logic remote, screen dumb. So running nvim on the
server is *historically correct*, not redundant. The friction I felt was
**shpool wrapping a full-screen TUI** (double-multiplexing, terminfo/keyboard-
protocol/truecolor flattening), plus the latency axis fighting the resilience
axis.

## The decision

**Run nvim LOCALLY on the laptop against LOCAL files. The server stays the
source of truth. Sync is asymmetric and explicit.**

```
LAPTOP (disposable, local nvim)              SERVER (truth + Claude Code in shpool)
┌─────────────────────────────┐             ┌──────────────────────────────────┐
│ nvim: LOCAL real files       │             │ files at rest (source of truth)  │
│  - swap + undofile = LOCAL   │  :w → rsync │ Claude Code edits files here     │
│  - offline scroll/read works │ ──────────► │ inotifywait watches the tree     │
│  - crash recovery local      │             │         │                        │
│ glue: receive nudge → refetch│ ◄───────────│ on change: nudge laptop nvim     │
└─────────────────────────────┘   RPC/SSH    └──────────────────────────────────┘
```

### The asymmetric heuristic (the whole point)

- **Server → buffer is LIVE.** Claude Code's edits on the server are reflected
  into my open buffers automatically (it's an autonomous agent — I want to *see*
  its changes immediately).
- **Buffer → server is ON SAVE.** My own edits push back on `:w` via rsync. This
  is just nvim's "save your work as you go" reflex anyway.

### Why this and not the alternatives

| Option | Verdict |
|---|---|
| **nvim on server (ssh -t / `:detach`+`:connect` / shpool)** | Watcher Lua perfect, zero loss on laptop death — **but you cannot scroll/read open files when wifi cuts** (laptop is just a frozen screenshot). Killed by the offline-read requirement. |
| **Mutagen + local nvim** | Great local feel, watcher Lua unchanged — **but it keeps a durable local working copy ("code stuck on the laptop")**, and on a disposable laptop that dies mid-sync you get smeared truth / conflict-freezes. Inverts the whole disposability model. Killed. |
| **remote-ssh.nvim / distant.nvim** | Justified by *remote LSP*, which I discounted. Files stay conceptually remote → fights offline-scroll and forces a watcher rewrite. Not worth it. |
| **Code Storage (code.storage)** | Commit-granularity git-for-agents infra. Wrong layer (not filesystem-event), replaces a server I don't want to replace. Not relevant. |
| **→ Local nvim + rsync-on-save + reflect glue (THIS)** | Only option satisfying all three: nothing stranded on laptop, offline read/scroll works, Claude edits reflected live. |

### The one accepted risk

**Unsaved local edits if the laptop battery dies.** Accepted because:
1. It's the *same* risk any local nvim has always had.
2. It's self-recoverable via the **swap file** (`.swp`, 1990s tech) — next open
   offers `(R)ecover` — and persistent **undofile** lets me undo into pre-crash
   history. Both must be **LOCAL** (they are by default; just confirm).

This is the right failure mode for the mountains: a bad link degrades to "a bit
laggy / sync stops until reconnect," never to data corruption.

> Note on wifi: it's effectively **binary** (works fine at OK speed / fully cut),
> not death-by-a-thousand-flaky-packets. So the glue needs **no** retry queues /
> out-of-order / reconnect-catch-up scaffolding — best-effort is enough. When the
> link is down, nudges just don't arrive; next edit (or a manual refetch) catches
> up. One-to-one sync is *not* required at all times.

## Tooling

- **Push-on-save:** [`vim-arsync`](https://github.com/KenN7/vim-arsync) — async,
  ssh-key, project-config, push on `BufWritePost`. Does the buffer→server half
  natively and nothing else (the minimalism I want).
- **Server → buffer live reflection:** custom glue (no plugin does this fail-soft):
  1. **Server side** (`~/bin/claude-watch.sh`, run inside shpool): `inotifywait
     -m -r -e close_write -e moved_to`, `git check-ignore` filter (mirrors old
     Lua), and on change call the laptop's nvim over a **reverse-forwarded
     socket** via `nvim --server $SOCK --remote-expr` → `require('claude_reflect').on_remote_change(rel)`.
  2. **Laptop side** (`~/.config/nvim/lua/claude_reflect.lua`): my existing
     capture/diff/extmark/fade logic, triggered by the RPC nudge instead of
     local inotify. Two guards: ignore buffers not open; **never clobber a buffer
     with unsaved edits** (`if vim.bo[bufnr].modified then return end`). On nudge:
     single-file `rsync` down → `checktime` → highlight.
  3. **Connection:** `nvim --listen /tmp/nvim-laptop.sock` on laptop; `ssh -R
     /tmp/laptop-nvim.sock:/tmp/nvim-laptop.sock you@server`; run the watcher
     with that socket path on the server.
- **Manual conflict arbiter:** `kitten diff ~/work/repo/foo ssh:server:/repo/foo`
  — fetch-once-render-local snapshot diff (kitty graphics protocol). The
  human-in-the-loop check before overwriting when both sides may have moved
  (e.g. resolving the `unpushed` state after reconnect). Not in the live loop.

## Non-default nvim settings required

```lua
vim.opt.undofile  = true
vim.opt.undodir   = vim.fn.expand('~/.local/state/nvim/undo')  -- LOCAL
vim.opt.directory = vim.fn.expand('~/.local/state/nvim/swap')  -- LOCAL swap
vim.opt.autoread  = true
vim.opt.updatetime = 300   -- swap written often → tiny loss window on crash
```

## Status-line indicator (state machine, priority-ordered)

1. **⚠ unpushed** (red) — a local `:w` happened but rsync hasn't confirmed it
   landed on the server (in-flight, or link was down at save). *Most important:
   the only state where work-at-risk lives solely on the disposable laptop.*
   Set true on save, cleared **only** on `rsync` exit 0.
2. **⬇ agent (N)** (yellow, transient) — Claude just changed this buffer; fades
   on the same `fade_ms` window as the in-buffer highlights (coherent by
   construction).
3. **● synced** (green) — link up, buffer clean and pushed.
4. **○ offline** (grey) — link down, nothing pending.

Obvious enhancement (left out for minimalism): auto-repush every `unpushed`
buffer when the connection flips offline→online.

## Division of labor (final)

- **Claude Code + shells → server + shpool.** Full persistence, survives laptop
  death. Unchanged from today.
- **nvim → local on the laptop.** Local swap/undo for crash recovery,
  rsync-on-save, reflect glue for incoming Claude edits.
- **Files at rest → server only.** Source of truth.
- **Disposability preserved:** only ephemeral open buffers + recoverable swap
  ever touch the laptop; nothing checked out long-term.

## Fallback to keep in the back pocket

For the rare stable-connectivity, server-CPU-heavy day (big refactor, not the
mountains), the two-line server-side-nvim model coexists fine:

```bash
ssh -L "${PORT}:127.0.0.1:${PORT}" "$REMOTE_HOST" "nvim --headless --listen 127.0.0.1:${PORT}" &
nvim --server "127.0.0.1:${PORT}" --remote-ui
```

(This is all `remote-ssh.nvim`/`rnvim` wrap; nvim core is folding it into native
`:detach`/`:connect`. Not the daily driver — fails offline-scroll.)
