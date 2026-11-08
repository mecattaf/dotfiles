# A supported C boundary is a realistic maintenance path

libghostty-vt 1.0 has a substantial public C API for the terminal model our
holder currently accesses through Zig. A C-only model adapter is realistic;
it would keep native Kitty as the renderer and keep the existing PTY owner.
It is not a one-call replacement for our strict Kitty restoration adapter.
The remaining work is mostly the replay contract and a few precise state
inspection gaps, rather than the absence of a usable C terminal library.

This read-only audit inspected exact release commit
[`0fa3d577a5614150ff8e2c152de5fb9d5c6d2dec`](https://github.com/ghostty-org/ghostty/tree/0fa3d577a5614150ff8e2c152de5fb9d5c6d2dec),
which the qualified holder already pins. It changed no runtime code, package,
tests or transport defaults and collected no new performance measurements.

## What the stability promise covers

The [1.x C ABI contract](https://github.com/ghostty-org/ghostty/blob/0fa3d577a5614150ff8e2c152de5fb9d5c6d2dec/dist/doxygen/pages/stability.md)
keeps existing calls, enum values and layouts usable in later 1.x releases.
Minor releases can add functions/types/enum values and append fields to sized
structs. A changed behavior uses a separately named call. Check compile-time
headers and the runtime library version; a library older than the headers is
not covered by forward compatibility.

The snapshot **functions** are part of that ABI. The snapshot **byte format**
is separately versioned and can change in any release; format version 1 is
explicitly still a work in progress. In contrast, the
[Zig module](https://github.com/ghostty-org/ghostty/blob/0fa3d577a5614150ff8e2c152de5fb9d5c6d2dec/src/lib_vt.zig#L1-L9)
does not promise source/API stability. Pinning the stable library release does
not turn our direct Zig field access into a stable integration boundary.

## Public C operations that can replace current model access

- **PTY stream and parser boundaries:**
  [`terminal.h`](https://github.com/ghostty-org/ghostty/blob/0fa3d577a5614150ff8e2c152de5fb9d5c6d2dec/include/ghostty/vt/terminal.h)
  provides create/free/reset, resize, VT writes, ground-state queries and
  continuation tracking. `ghostty_terminal_vt_write_until()` can stop at
  OSC/APC/DCS boundaries, including strings split across chunks. That offers a
  supported basis for bounded extension tracking instead of a second general
  VT parser. It still requires an embedder-owned PTY and ordering policy.
- **Text, history and soft wraps:**
  [`formatter.h`](https://github.com/ghostty-org/ghostty/blob/0fa3d577a5614150ff8e2c152de5fb9d5c6d2dec/include/ghostty/vt/formatter.h#L143-L237)
  supports VT/plain/HTML output, selections, unwrapping, whitespace policy and
  extras. Grid references cover active/viewport/screen/history coordinates.
  A C adapter can select history and visible text separately, preserving our
  replay phases. Its writer callback supports bounded streamed output; partial
  failure is not resumable and must fail the attachment explicitly.
- **Modes, keyboard, cwd and title:** terminal getters expose current mode
  values, Kitty keyboard flags, cursor position/pending wrap, active screen,
  title and cwd. Formatter extras cover modes, keyboard state, tab stops,
  margins, hyperlinks and charsets. These can replace many direct Zig reads;
  they are not an assertion that every saved-mode/keyboard stack is replayed.
- **Colors and cursor:** terminal getters expose effective/default colors and
  palettes. The
  [render-state API](https://github.com/ghostty-org/ghostty/blob/0fa3d577a5614150ff8e2c152de5fb9d5c6d2dec/include/ghostty/vt/render.h#L130-L177)
  also exposes cursor shape, visibility and blinking. Reading that state does
  not require using Ghostty's renderer. A C adapter can emit DECSCUSR itself,
  just as our current adapter does after ordinary VT formatting.
- **Static images:**
  [`kitty_graphics.h`](https://github.com/ghostty-org/ghostty/blob/0fa3d577a5614150ff8e2c152de5fb9d5c6d2dec/include/ghostty/vt/kitty_graphics.h)
  provides placement iteration, IDs, cropping, offsets, geometry and z-order,
  plus image lookup by ID and decoded pixel data. Render-state image entries
  distinguish fixed, virtual and relative placements. This is enough to build
  a useful C replay adapter for identified, supported images; graphics are not
  absent from the stable API.
- **Decoding and resource policy:**
  [`sys.h`](https://github.com/ghostty-org/ghostty/blob/0fa3d577a5614150ff8e2c152de5fb9d5c6d2dec/include/ghostty/vt/sys.h#L16-L33)
  accepts a process-global PNG decoder installed before concurrency starts.
  The decoder uses the supplied bounded allocator. A C integration still has
  to supply that decoder. Public scrollback byte/line limits, memory queries
  and compression calls are available; the
  [scrollback guide](https://github.com/ghostty-org/ghostty/blob/0fa3d577a5614150ff8e2c152de5fb9d5c6d2dec/dist/doxygen/pages/guides/scrollback.md)
  describes page-granularity limits as estimates, not an exact process RSS cap.

## Rich binary snapshots are not Kitty wire snapshots

The [snapshot guide](https://github.com/ghostty-org/ghostty/blob/0fa3d577a5614150ff8e2c152de5fb9d5c6d2dec/dist/doxygen/pages/guides/snapshots.md)
documents all-screen state, partial VT/UTF-8 input, image storage/placements,
animation pixels and history, with incremental READY/history/FINISH decoding.
Public decoder progress includes image ID, screen and animation frame. A
same-library snapshot/clone can therefore inspect some otherwise awkward
state without privately decoding the binary format; that is a supported
operation whose cost and semantics still need qualification.

Those bytes reconstruct a **Ghostty terminal**. Native Kitty does not accept
them. We still need a bounded VT/KGP replay stream, correct ordering with live
PTY bytes, and explicit treatment of one-shot side effects. A library built
without graphics may skip optional image records; that is allowed decoding
behavior, not acceptable image parity for this workflow. Persisted snapshots
also need their own format/version policy despite stable function signatures.

## Exact gaps in a drop-in strict replacement

**Application color identity:** the C API returns current and default palette
arrays, but not the internal per-index OSC-override mask our adapter reads.
An override equal to the old default is indistinguishable by comparing those
arrays, yet matters when a new Kitty has a different theme. `GhosttyColorPaletteMask`
exists as a utility type; it is not an override-mask getter. Default setters
[preserve program overrides](https://github.com/ghostty-org/ghostty/blob/0fa3d577a5614150ff8e2c152de5fb9d5c6d2dec/dist/doxygen/pages/guides/colors.md#L17-L57),
so bounded original-OSC tracking or a separately qualified clone/probe is
possible. A direct override getter would be a cleaner upstream API addition.
Enabling formatter palette output wholesale would overwrite client defaults.

**All cached images and strict eligibility:** the live graphics surface has a
placement iterator and lookup by known image ID, not a direct iterator over
all stored images, including unplaced ones. Its getters do not expose every
loading/animation/transient/implicit-ID property used by our strict subset
validator. The storage placement getter returns a numeric ID without the
internal/external-ID tag; visible render entries do normalize anonymous IDs to
zero. Repainting today's visible rectangles does not preserve an unplaced
image for a later application placement command. Snapshot progress can reveal
image IDs/frames, but it is not a one-for-one replacement for all those checks.

**Resize and unsupported protocols:** tab stops can be formatted, but there is
no direct C tabstop table getter/setter matching our overlapping-column resize
fix. A tracker or targeted public addition is needed for that behavior.
The exact library still groups
[OSC66 text sizing as unimplemented](https://github.com/ghostty-org/ghostty/blob/0fa3d577a5614150ff8e2c152de5fb9d5c6d2dec/src/terminal/stream.zig#L3090-L3102).
Changing the language boundary does not fix that model gap. Its unknown-OSC
callback only reports unrecognized numbers, so it is not a blanket observer of
recognized but unsupported OSC. The public boundary-write API can support a
more precise bounded guard; it has not been substituted or qualified here.

Borrowed pixels/placements expire on terminal mutation. Formatter/snapshot
writers are synchronous and cannot reenter the same terminal. A C adapter must
retain exclusive ownership, snapshot barriers, bounded queues and explicit
error handling. C ABI stability supplies no worker thread, async PNG decoder,
backpressure scheme or reconnect lifetime automatically.

## How the alternatives compare

[TSM](TSM-SOURCE-AUDIT.md) proves that a Go/cgo terminal manager can already use
the C boundary. Its older `c9e1006` pin predates stable 1.0 and uses a different
formatter construction API. Updating it is feasible work to qualify, not a
claim that today's TSM already supplies these newer capabilities or our strict
replay contract.

The [native Kitty headless probe](NATIVE-VT.md) has the strongest immediate
protocol alignment: the same Kitty 0.50 parser handles OSC66 and its graphics
manager retains exact decoded images. It uses private Python/C interfaces,
including `test_*` methods, with no public standalone-library ABI. ANSI text
export alone loses images and input state. It remains a credible research path
requiring a complete bounded serializer, version contract and qualification;
the installed engine is GPLv3 and none of its implementation was copied here.
It would still add a NAS shadow, rather than remove Kitty's local parser.

A sensible C migration keeps the current direct-SSH baseline and existing
transport/actor contracts, replaces terminal operations through public calls,
then resolves the enumerated metadata gaps through a bounded tracker or small
upstream additions. Reuse the native color/wrap/KKP/image/unsupported-state,
typeahead, slow-observer and exact-reconnect gates before changing a default.
There is no source-backed reason to declare a C implementation impossible,
and no basis here for a migration estimate or universal full-protocol claim.

The [1.0 announcement](https://mitchellh.com/writing/libghostty-1-0) scopes its
performance claims to parsing throughput and memory. Our frozen comparisons
measure separate software echo paths, not C-versus-Zig FFI overhead or physical
keypress-to-pixel latency. The parser and PNG work do not vanish when called
through C. Choosing a stable interface is a maintenance decision; responsiveness
still depends on actual transport, ordering, scheduling and workload.
