# Kitty already has a VT engine

Kitty's own terminal engine is its C `Screen`, parser, cell/history buffers,
keyboard/mode state and graphics manager. Its native renderer consumes that
state. `TERM=xterm-kitty` is a capability name for applications and terminfo;
it does not select the engine or load a Ghostty library. The stock SSH kitten
installs the matching terminfo and shell integration on the NAS. It does not
retain the NAS application's PTY after the SSH connection is gone.

An optional holder owns a different lifetime. It keeps the NAS master PTY
open, forwards attached bytes, and can keep a second, headless terminal model
for reconstructing a new frontend after a disconnect. This second model is
additional work on the server. It never replaces Kitty's local parser or
renderer. A model without a retained PTY cannot keep a shell alive; a retained
PTY without a model cannot necessarily reconstruct a full-screen TUI.

## The installed Kitty can run its own engine headlessly

`backend/kitty_native_vt.py` was run through `runtime-test` with the exact
activated Kitty0.50.0 package, without a compositor, display or GPU context.
Its private `kitty.fast_data_types.Screen` interface successfully parsed:

- Unicode combining characters, CJK and a joined emoji, plus truecolor.
- Native OSC66 text sizing/multicell state, with an ANSI text round trip.
- Kitty keyboard flags31 and a native keyboard-protocol query response.
- A PNG, decoded to the exact RGBA bytes and retained with its placement in
  the native graphics manager. A window id of zero skips the GPU upload.

The receipt is `docs/evidence/native-kitty-vt/receipt.json`. This proves that
there is no fundamental need to put Ghostty inside Kitty to understand Kitty
protocols. It does not establish a production persistence backend. The APIs
used are internal and some are named `test_*`; there is no promised standalone
terminal-library ABI. A daemon would still need complete mode/history/image
serialization, PTY/observer flow control, lifecycle handling and a maintained
version contract. Plain `as_ansi()` text extraction does not restore images or
all input state. The installed Kitty dependency is GPLv3; no Kitty engine code
was copied into this MIT repository.

Relevant source: Kitty0.50 [`Screen`](https://github.com/kovidgoyal/kitty/blob/bb1aca6f279f1a5cfa3edd765a71650fe91b6472/kitty/screen.c),
[`parser`](https://github.com/kovidgoyal/kitty/blob/bb1aca6f279f1a5cfa3edd765a71650fe91b6472/kitty/vt-parser.c),
[`headless graphics guard`](https://github.com/kovidgoyal/kitty/blob/bb1aca6f279f1a5cfa3edd765a71650fe91b6472/kitty/graphics.c#L943)
and [upstream state tests](https://github.com/kovidgoyal/kitty/blob/bb1aca6f279f1a5cfa3edd765a71650fe91b6472/kitty_tests/base.py).

## Published libghostty-vt is a different integration contract

The [libghostty1.0 announcement](https://mitchellh.com/writing/libghostty-1-0)
provides a deliberately reusable terminal-state library. This is an attractive
NAS shadow-state component; it is not a faster replacement renderer for an
already running native Kitty window. Parsing throughput does not prove
keypress-to-pixel latency or complete protocol restoration.

One concrete limit matters to the request for full parity. Stable
libghostty-vt commit `0fa3d577` recognizes OSC66 syntactically, but its terminal
stream groups the callback as unimplemented and drops it. Attached bytes can
still reach Kitty and display sized text. A fresh frontend reconstructed from
that model cannot restore the same multicell text. The qualified holder also
implements an explicit static-image subset, not every Kitty graphics feature.
Native attached passthrough, successful restoration of the tested agent image
cases, and universal protocol parity are three different claims.

The direct stock-SSH route remains available. Persistence is an explicit
feature with a separately qualified state model; it is not a reason to remove
the original fast and fully native reference path.
