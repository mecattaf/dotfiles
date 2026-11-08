# Native Kitty, transport and retained terminal state

Native Kitty already supplies the local VT parser, screen/history buffers,
keyboard state, graphics manager and GPU renderer. `TERM=xterm-kitty` describes
capabilities to applications; it does not load Ghostty. An SSH kitten improves
bootstrap, terminfo, shell integration and remote conveniences while retaining
OpenSSH as the carrier. Adding libghostty on the NAS adds a second, headless
terminal model. It does not replace or accelerate Kitty's local engine.
Primary sources: Kitty 0.50 [`screen.c`](https://github.com/kovidgoyal/kitty/blob/bb1aca6f279f1a5cfa3edd765a71650fe91b6472/kitty/screen.c),
[`vt-parser.c`](https://github.com/kovidgoyal/kitty/blob/bb1aca6f279f1a5cfa3edd765a71650fe91b6472/kitty/vt-parser.c),
and [SSH kitten documentation](https://sw.kovidgoyal.net/kitty/kittens/ssh/).

Three lifetimes must stay distinct. A local Kitty window owns its display. A
NAS PTY owner keeps the shell/agent alive after a client leaves. A retained VT
model reconstructs a new display after disconnected output. A PTY owner alone
can preserve the process without guaranteeing a faithful fresh-window redraw;
a VT model alone cannot preserve the process. If DSH already owns that PTY,
another holder is not required. Reuse one owner and qualify its raw carrier and
restoration contract instead of nesting holders. Native Neovim's retained RPC
server/local UI is another distinct contract: editor buffers and unsaved work
belong to Neovim, not to terminal scrollback.

## What could explain the improved typing

Removing the installed Herdr 0.9.3 presentation path removes an identified layer
of terminal repainting. Its [render gate](https://github.com/herdrdev/herdr/blob/7b116c05bfda646af39d2524c54e70c751f57ee8/src/app/runtime.rs#L74)
enforces a 16 ms interval between recent attempts. The first idle update can be
immediate; this is not a fixed delay on every key. Its ostensibly direct
[`terminal attach`](https://github.com/herdrdev/herdr/blob/7b116c05bfda646af39d2524c54e70c751f57ee8/src/server/client_shell.rs#L512)
also goes through virtual rendering/frame data. A helper calling that route
“raw” did not make it byte passthrough.

That is a plausible mechanism, not proof of the user's complete physical
keypress-to-letter sensation. Input dispatch, OpenSSH policy, network RTT,
application behavior, Kitty parsing/render scheduling, compositor and panel
all remain in the chain. There is no measured universal 10 ms, 16 ms or 18 ms floor
for this laptop. Preserve the exact direct-SSH route as the reference; compare
finished alternatives against it without changing policy and software at the
same time. Current Herdr Core is a separate design and cannot inherit old
Herdr's repaint attribution.

## Stable libghostty 1.0 is not a stable Zig API

The qualified stable holder and actor pin Ghostty
[`0fa3d577a5614150ff8e2c152de5fb9d5c6d2dec`](https://github.com/ghostty-org/ghostty/releases/tag/vt-1.0.0),
the signed `vt-1.0.0` tag. They import its Zig module directly. That module's
[`src/lib_vt.zig`](https://github.com/ghostty-org/ghostty/blob/0fa3d577a5614150ff8e2c152de5fb9d5c6d2dec/src/lib_vt.zig)
explicitly withholds an API-stability guarantee. Its C surface has a different
contract: [1.x ABI compatibility](https://github.com/ghostty-org/ghostty/blob/0fa3d577a5614150ff8e2c152de5fb9d5c6d2dec/dist/doxygen/pages/stability.md)
permits additive changes while preserving existing calls/layouts. The library's
binary snapshot format is separately versioned and explicitly outside that
ABI promise. Adopting stable 1.0 is useful maintenance work; it does not make a
Zig embedder source-compatible with every future release.

The November6 [announcement](https://mitchellh.com/writing/libghostty-1-0),
retrieved separately after the browsing tool failed, explicitly scopes its
performance claims to parsing throughput and memory use in footnote5. Those
claims do not measure physical keypress-to-letter latency. It describes the
stable C ABI, signed source and dependency tarballs for offline distribution
builds, permissive licensing and a libc-only runtime dependency. The library
creates no threads itself; an embedder chooses its scheduling and allocator.
These are useful packaging and implementation properties, not evidence that
adding a shadow improves an already running Kitty. The pinned
[render-state guide](https://github.com/ghostty-org/ghostty/blob/0fa3d577a5614150ff8e2c152de5fb9d5c6d2dec/dist/doxygen/pages/guides/rendering.md)
likewise distinguishes copying terminal state from drawing it.

## Existing native-terminal projects

- **zmx 1.0.1, MIT**, commit
  [`a35f00a2`](https://github.com/neurosnap/zmx/tree/a35f00a2118b15a5e9d522a43035c8d7487df9b7),
  keeps a PTY/socket per session and omits layout management. Attached output
  is a byte stream, with prompt-control rewriting, rather than periodic screen
  repainting. Upstream feeds libghostty synchronously before broadcasting.
  Its stock queue/input/reconnect shortcomings were reproduced; it is a
  reference, not the accepted production holder. The bounded Agency variant
  fixes those measured cases, restores tested static graphics, preserves native
  palette/wrapping/KKP state and refuses known unsupported reconnect state.
- **shpool 0.11.6, Apache-2.0**, inspected at
  [`0433875f`](https://github.com/shell-pool/shpool/tree/0433875f17a318e7b9334b1c37a2de3f7eaea152),
  keeps PTYs in a shared daemon and forwards attached bytes. Its default
  [`shpool_vt100`](https://github.com/shell-pool/shpool_vt100/tree/5539bf03da82b035e570d71edf2fb433243a8328)
  and optional [`shpool-vterm`](https://github.com/shell-pool/shpool-vterm/tree/b6a53b48cddd61e11380ba102888f391a9054014)
  are retained-state implementations, not Ghostty renderers. The latter is
  Rust built on `vte`, not Neovim's historical C libvterm. Both tested engines
  passed attached bytes and bulk input/output but omitted KKP 31 restoration;
  vterm retained the tested alternate-screen state. June's shpool preference
  remains credible history, not proof of today's full reconnect parity.
- **hauntty, MIT**, commit
  [`ddcef3d7`](https://github.com/seruman/hauntty/tree/ddcef3d714011aa2f725901911138af05b5c1388),
  uses Go and translated Ghostty WebAssembly without a browser UI. It has a
  separate shadow worker and server-enforced read-only viewers. Its shared VT
  runtime mutex and output batching are concrete design choices, not reasons
  to dismiss Go/WASM categorically. A separately labelled Linux peer-UID fix
  enabled qualification without changing its transport. Its client discards
  stdin for 50 ms after presenting a snapshot; the immediate-key loss was
  reproduced. It needs an admission fix before this workflow can adopt it.
- **zmosh 0.5.2, MIT**, commit
  [`71eba234`](https://github.com/mmonad/zmosh/tree/71eba23416bfb443df755ad89d6d06e665ebcd95),
  is a genuine SSH-bootstrapped encrypted UDP project. Its Ghostty/Zig substrate
  differs from current zmx; it is not a transparent library upgrade. Output
  gaps recover terminal state rather than every original one-shot byte, and
  its reliable-input receiver delivered authenticated inputs out of order in
  the isolated fault test (`AB` became `BA`). Released bulk-paste and final-exit
  output gates also failed. Roaming support does not waive these losses.
- **Current Herdr Core, Apache-2.0**, has separate PTY holders, a state daemon
  and native framed viewers. Audited HEAD is
  [`cd12ddd8`](https://github.com/herdrdev/herdr-core/tree/cd12ddd88bc11490228343291dc1096c9ed3bf77);
  the admitted published 0.1.18 binary corresponds to release
  [`3965a46c`](https://github.com/herdrdev/herdr-core/tree/3965a46caae095a3ead01de237fa13955e52b8c6).
  The relevant viewer/relay design is unchanged between those pins. It uses
  Rust over libghostty's C API, with its own Ghostty submodule at
  [`1e5cdb86`](https://github.com/ghostty-org/ghostty/tree/1e5cdb865807abc990181efb8ebfa9122955cce2),
  not the Agency holder's stable 1.0 pin. It forwards live output with answered
  queries filtered and can repaint slow viewers from state. It passed
  attached control bytes, same-PID resume, 4 MiB delayed-reader input and 4 MiB
  final output. Those admissions do not prove complete graphics/OSC66 replay
  or any particular typing latency. See [the exact release proof](CURRENT-HERDR-CORE.md).

These are terminal owners/carriers/state engines. None requires replacing
Kitty's local renderer or adopting a workspace/multiplexing UI. Their sockets
and client roles have different input, resize and takeover powers; a terminal
attachment socket is not automatically a read-only web API.

A bounded follow-up of the announcement's
[project list](https://github.com/Uzaaft/awesome-libghostty/tree/04593560fb1f10ea0cd329e8f9c6d24cbc9125a4)
found further source leads, not qualified replacements. **TSM, MIT**,
[`f3e09816`](https://github.com/adibhanna/tsm/tree/f3e09816be01ba9fdf8dc1a6fd6dd2733cbee531)
documents one PTY/socket daemon per session, Ghostty restoration and optional
native Kitty split orchestration; its backend also supports socket-only control.
Its [source](https://github.com/adibhanna/tsm/blob/f3e09816be01ba9fdf8dc1a6fd6dd2733cbee531/internal/session/daemon.go)
broadcasts before synchronous shadow feed, but injects Ctrl+L on a normal-screen
attach. Snapshot ordering and no-input restoration need separate admission.
**Vanish** keeps server/client
VT state and renders client viewports; **headless-terminal** and **termscope**
target programmatic TUI driving and snapshots. Their repositories are useful
[starting points](https://github.com/psyclyx/vanish),
[automation references](https://github.com/montanaflynn/headless-terminal)
and [testing references](https://github.com/mwunsch/termscope), with no new
runtime admissions claimed here. Neovim's approved
[PR39773](https://github.com/neovim/neovim/pull/39773) remained open at review;
it changes `:terminal`'s internal VT, independently of retained Nvim RPC/local UI.

## Why the separate actor exists

Version 4 retains synchronous shadow parsing. Optional version 5-actor moves
only VT feed/PNG decoding to an exclusive worker with 8192 bounded queued
chunks. The owner keeps input/raw output serviceable; an exact parsed-offset
barrier precedes snapshots, focus and resize. No lock spans PNG decoding.
Actual stopped-worker and blocked-PNG tests prove that independence causally;
real Kitty/Codex/4K reconnect gates prove the tested state survives. They do not
supply a latency number. Serialization/explicit Info barriers, allocator and
scheduler costs remain. Queue saturation backpressures PTY output, and teardown
joins the current decoder. See [design and receipts](../backend/zmx/ACTOR.md).

Stable libghostty still [drops OSC66 text-sizing state](https://github.com/ghostty-org/ghostty/blob/0fa3d577a5614150ff8e2c152de5fb9d5c6d2dec/src/terminal/stream.zig#L3097).
Attached Kitty can display those bytes while a shadow cannot reconstruct them.
The candidate therefore refuses strict reconnect after that known gap and
provides explicit text-only recovery. Static image tests likewise do not prove
all animation, virtual placement, image-number and history cases. “Whole Kitty
protocol end to end” is not an established property of any tested shadow.

## Could the NAS use Kitty's own VT instead?

Yes, as research: the exact activated Kitty C `Screen` ran headlessly without
a GPU/window and retained tested native Unicode, truecolor, KKP, OSC66 and
exact decoded PNG state. It is the same native engine, not libghostty inside
Kitty. However, this probe uses private/internal APIs, including test helpers,
and a separate GPLv3 dependency. A maintained backend still needs complete
state/history/graphics/mode serialization, flow control and version/lifecycle
contracts. `as_ansi()` alone did not restore graphics and all input state. It
is an alternative worth pursuing, not an admitted new persistence backend.
See [the native probe and limitations](NATIVE-VT.md).

For this workflow, native selection, image/file capabilities, clean native
notifications, transcript history and DSH chat/workspace metadata can remain
separate from the byte carrier. OSC7 reports the working directory; OSC99 is
[Kitty's desktop-notification protocol](https://sw.kovidgoyal.net/kitty/desktop-notifications/);
OSC7501 describes program status. They have different purposes. Copied overlays,
agent-completion sounds and hold-to-record audio are local/desktop capabilities,
not a reason to repaint every terminal frame. Semantic Claude/Codex history comes from their
saved transcripts and exact harness identity, not a screenshot of every TUI
frame. A future frontend can inspect typed, bounded metadata/capture without
receiving generic terminal-input authority. Domicile/Imagine owns workspaces;
Kitty owns terminal display/splits; DSH owns chat identity; exactly one owner
keeps each retained PTY. Kitty 0.50's native session/restore features are useful
local conveniences, but a saved launch description or scrollback is not proof
that the original NAS process survived. The [native session documentation](https://sw.kovidgoyal.net/kitty/sessions/)
makes its relaunch/restore behavior explicit.

Further source audits distinguish the
[supported C ABI migration surface](LIBGHOSTTY-C-ABI.md),
[native Kitty model export](KITTY-NATIVE-BACKEND-AUDIT.md), and
[surviving-client missing-byte continuation](SAME-CLIENT-CONTINUITY.md).
The last can avoid snapshot serialization while the same client/frontend
survives, but is not implemented by this project's fresh-attachment supervisor.
