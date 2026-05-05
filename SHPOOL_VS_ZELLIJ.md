# shpool vs Zellij — the layout boundary

Context: I use `shpool` to keep SSH shells alive on `harness-desktop`, and `niri`
to tile windows locally. This note captures the *one* concept that might
pull me toward Zellij later: declarative layouts.

## What each tool actually does

- **shpool**: session-persistence daemon. Keeps a shell process alive after
  the client disconnects and replays terminal state on reattach (via its
  `shpool_vt100` fork of `doy/vt100-rust`). It does **not** split panes,
  draw tabs, or manage windows. One session = one shell.
- **Zellij**: terminal multiplexer. Persistence *plus* panes, tabs, floating
  windows, a session picker, WASM plugins — and KDL-declared layouts.

## The layout concept (the only part that tempts me)

Zellij layouts are KDL files that describe a session's structure: which
panes exist, what command runs in each, how they are arranged. Example:

```kdl
layout {
    pane split_direction="vertical" {
        pane command="nvim"
        pane split_direction="horizontal" {
            pane  // shell
            pane command="cargo" { args "watch" "-x" "test" }
        }
    }
}
```

Run `zellij --layout dev.kdl` and the whole workspace materialises. Detach,
reconnect later, it's still there. Same config language as niri — which is
the only reason this feels native rather than bolted on.

## Why shpool cannot do this (and will not)

Layouts require *owning* the terminal grid — splitting it into regions,
drawing borders, routing input to the focused pane. shpool deliberately
does none of that; it passes bytes through to the client's terminal
emulator and only intercepts enough to replay on reattach. That is its
entire design premise — "persistent sessions, nothing more."

So the boundary is clean:

|                           | shpool   | Zellij      | niri (for comparison) |
|---------------------------|----------|-------------|------------------------|
| Persist shell on disconnect | ✅      | ✅          | ❌                     |
| Multiple named sessions   | ✅ (CLI) | ✅ (picker) | n/a                    |
| Panes inside one terminal | ❌      | ✅          | ❌ (tiles *windows*)   |
| Tabs inside one terminal  | ❌      | ✅          | ❌ (uses workspaces)   |
| Declarative KDL layouts   | ❌      | ✅          | ✅ (for windows)       |

## Why I'm staying on shpool for now

My tiling already happens at the window level (niri) and the terminal
level (kitty tabs/splits). Zellij's panes/tabs duplicate that. The *one*
unique thing Zellij offers is a declarative **session** layout — "bring
back my nvim + two shells + a log tail" with one command — which niri
can't express because niri tiles windows, not processes inside a shell.

If I ever leave niri, the calculus flips: Zellij's layouts become the
only way to keep that muscle memory across window managers. Until then,
shpool + niri + kitty covers the same ground with less ceremony.

## Reference

- `shpool_vt100` is a fork of `doy/vt100-rust` with fixes shpool needs to
  replay terminal state faithfully on reattach. It is unrelated to Zellij
  — Zellij parses pty output via Alacritty's `vte` crate and its own grid
  layer. Different stacks solving different problems.
