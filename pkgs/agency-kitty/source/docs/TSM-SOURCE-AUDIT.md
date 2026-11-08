# TSM: a close existing starting point, with a narrower restore contract

[adibhanna/tsm](https://github.com/adibhanna/tsm) already implements much of the
general persistent-native-terminal idea. For a request limited to persistent
shells, a picker, project/worktree sessions and native Kitty layouts, it is a
credible simpler existing solution. Its Kitty integration preserves Kitty's
renderer. It should not be described as a browser terminal or as a failed
candidate merely because this investigation discovered it late.

This audit inspected commit `f3e09816be01ba9fdf8dc1a6fd6dd2733cbee531` in
`sources/tsm`; read-only `git ls-remote origin HEAD` still returned that exact
commit on 2026-11-08 at about 04:09 UTC. The checkout remained clean. Nothing
was built, installed, benchmarked or runtime-qualified. Statements below are
source observations; interleaving and compatibility consequences are identified
as inferences. The project carries an
[MIT license](https://github.com/adibhanna/tsm/blob/f3e09816be01ba9fdf8dc1a6fd6dd2733cbee531/LICENSE).

## Engine, renderer and transport

TSM uses one background daemon and PTY per session. Its
[Go/cgo backend](https://github.com/adibhanna/tsm/blob/f3e09816be01ba9fdf8dc1a6fd6dd2733cbee531/internal/session/terminal_backend_ghostty.go#L5-L45)
includes `ghostty/vt.h` through `pkg-config`; it does not import Ghostty's Zig
internals. The
[Makefile](https://github.com/adibhanna/tsm/blob/f3e09816be01ba9fdf8dc1a6fd6dd2733cbee531/Makefile#L1-L19)
pins Ghostty `c9e1006213eb9234209924c91285d6863e59ce4c`. That source's
[application build metadata](https://github.com/ghostty-org/ghostty/blob/c9e1006213eb9234209924c91285d6863e59ce4c/build.zig.zon#L1-L5)
says `1.3.2-dev`, with Zig 0.15.2; this is not a libghostty-vt semantic version.
Its [C header](https://github.com/ghostty-org/ghostty/blob/c9e1006213eb9234209924c91285d6863e59ce4c/include/ghostty/vt.h#L1-L24)
explicitly marks the API unstable. TSM therefore demonstrates an existing C
binding, not existing adoption of November's stable libghostty-vt 1.0 ABI.
Its doctor also
[checks required dynamic symbols](https://github.com/adibhanna/tsm/blob/f3e09816be01ba9fdf8dc1a6fd6dd2733cbee531/internal/session/symbol_check_ghostty.go#L10-L46).

The [Kitty backend](https://github.com/adibhanna/tsm/blob/f3e09816be01ba9fdf8dc1a6fd6dd2733cbee531/internal/mux/backend/kitty/kitty.go#L1-L11)
uses `kitten @` to orchestrate OS windows, tabs and splits. Its layouts are
optional orchestration; they are not a grid renderer inserted over Kitty.
For this workflow that layer could be left unused. The setup convenience
command would append `allow_remote_control yes`; it also recognizes an existing
`socket-only` setting. Our owner-socket policy should remain explicit rather
than invoking its setup command unchanged.

The session protocol
[dials a Unix socket](https://github.com/adibhanna/tsm/blob/f3e09816be01ba9fdf8dc1a6fd6dd2733cbee531/internal/session/socket.go#L12-L27).
No SSH transport/bootstrap implementation was found in the inspected code.
Running its remote client through ordinary SSH is a plausible composition,
not an end-to-end Kitty/Tailscale integration established by this audit. Native
Kitty orchestration and NAS PTY ownership still need an explicit host boundary.

## Attached path and ordered restoration

The daemon
[broadcasts each raw PTY chunk before shadow parsing](https://github.com/adibhanna/tsm/blob/f3e09816be01ba9fdf8dc1a6fd6dd2733cbee531/internal/session/daemon.go#L309-L327).
The same goroutine then calls the parser before its next PTY read. Thus the
current chunk can reach Kitty first, while expensive parsing can delay later
output. Input uses another handler goroutine. This is not a frame timer, nor
proof that PNG parsing cannot affect subsequent echoes.

[Attach marks the client live before snapshotting](https://github.com/adibhanna/tsm/blob/f3e09816be01ba9fdf8dc1a6fd6dd2733cbee531/internal/session/daemon.go#L395-L421),
then resizes and signals SIGWINCH. Outside the alternate screen it waits 10 ms
and writes Ctrl+L into the application PTY. There is no explicit parsed-output
offset barrier. Source inference: a newly live raw chunk and a snapshot can
interleave without a guarantee that each byte is represented exactly once;
application redraw can conceal that boundary. This was not reproduced here.

[Broadcast](https://github.com/adibhanna/tsm/blob/f3e09816be01ba9fdf8dc1a6fd6dd2733cbee531/internal/session/daemon.go#L509-L526)
writes clients serially with 100 ms deadlines and ignores returned write errors.
There is no bounded per-observer output queue or explicit disconnect on that
error in this path. Slow-client losslessness and framing require qualification
before using this as the strict transport.

## What fresh attach reconstructs

The
[snapshot options](https://github.com/adibhanna/tsm/blob/f3e09816be01ba9fdf8dc1a6fd6dd2733cbee531/internal/session/terminal_backend_ghostty.go#L73-L111)
enable cursor position, SGR, hyperlinks, protection, Kitty keyboard state,
charsets, modes, margins and cwd. They disable palette and tabstop emission,
and set `unwrap=false`. The backend keeps 10,000 shadow scrollback lines.
Constructor failure falls back to mode tracking; formatter failure returns an
empty snapshot. These paths do not enforce our strict-restore refusal contract.

The exact pinned Ghostty source clarifies the limits:

- Its
  [terminal formatter](https://github.com/ghostty-org/ghostty/blob/c9e1006213eb9234209924c91285d6863e59ce4c/src/terminal/formatter.zig#L169-L198)
  emits only the active screen. Primary and alternate buffers are not both
  reconstructed. Its default content selection traverses that screen's page
  list, so the design does include retained text history, rather than only a
  screenshot. TSM separately retains a 10 MiB raw ring for preview fallback.
- With unwrapping disabled, its
  [row formatter](https://github.com/ghostty-org/ghostty/blob/c9e1006213eb9234209924c91285d6863e59ce4c/src/terminal/formatter.zig#L1111-L1117)
  inserts line breaks at soft wraps. Exact native copy/reflow semantics after
  resume need a real-Kitty check; a visually similar grid is insufficient.
- The pinned formatter emits cursor position and current SGR but has no cursor
  shape replay. Disabled palette emission does not restore application palette
  overrides. It contains no graphics-image/placement serialization.
- The pinned stream explicitly treats
  [OSC66 text sizing as an unimplemented callback](https://github.com/ghostty-org/ghostty/blob/c9e1006213eb9234209924c91285d6863e59ce4c/src/terminal/stream.zig#L2050-L2063).
  Recognizing the OSC parser command is not restoration support. No TSM strict
  refusal for that lost state was found.

Raw attached KGP/OSC66 output can still reach native Kitty through the live
path; that is distinct from replay after fresh attach. Full graphics/color/
cursor/multicell parity was not tested. Its existing full-screen integration
test checks that the attach output contains alternate-screen enable, rather
than these native-state equivalence gates.

## Typeahead, metadata and frontend authority

The
[client input loop](https://github.com/adibhanna/tsm/blob/f3e09816be01ba9fdf8dc1a6fd6dd2733cbee531/internal/session/client.go#L147-L171)
reads 4 KiB chunks and intercepts picker/detach keys before forwarding. A chunk
containing either shortcut returns without forwarding other bytes in that same
chunk; shortcut encodings split across reads also need qualification. No
explicit startup input drain was found, but the daemon's injected Ctrl+L makes
ordinary attach an input-producing action. The
[output filter](https://github.com/adibhanna/tsm/blob/f3e09816be01ba9fdf8dc1a6fd6dd2733cbee531/internal/session/switch.go#L5-L73)
also consumes its private OSC633 session-switch request. It is consequently
not an entirely opaque byte transport.

TSM has useful existing session/process/git metadata and Claude/Codex status
inspection. Its
[binary IPC tags](https://github.com/adibhanna/tsm/blob/f3e09816be01ba9fdf8dc1a6fd6dd2733cbee531/internal/session/ipc.go#L9-L37)
include info and history alongside input, resize, rename and kill on the same
owner socket. This is a local authority model, not a separately authorized
read-only frontend API. The
[listing implementation](https://github.com/adibhanna/tsm/blob/f3e09816be01ba9fdf8dc1a6fd6dd2733cbee531/internal/session/session.go#L71-L119)
also removes a socket after any failed info probe; it cannot be transplanted
unchanged as our mutation-free DSH catalogue. The ordinary named
[attach command](https://github.com/adibhanna/tsm/blob/f3e09816be01ba9fdf8dc1a6fd6dd2733cbee531/main.go#L178-L189)
requests create-if-missing, so an exact resume-only external action needs a
different explicit boundary.

TSM could reduce custom session-manager work in a narrower design. It does not
already supply the qualified image upload/drop and semantic transcript bridge,
retained local Neovim UI, exact NAS/Kitty identity, typed DSH/Imagine catalogue,
or the stricter restoration and bounded transport contract developed here.
Those are adapters and admission work, not reasons to reject an unrun product.
A future comparison can reuse our existing native fidelity, typeahead,
slow-observer and ordered-reconnect gates before choosing a holder. There is
no new latency result, adoption recommendation or change to the direct SSH
baseline from this source audit.
