# Restricted native PTY holder

The current source-built persistent variant is `1.0.1-agency.4-vt1`, protocol
204, with stable libghostty-vt `0fa3d577`. Its authoritative recipe is
[`source-build.nix`](source-build.nix), applying
[`agency-v4-vt1.patch`](agency-v4-vt1.patch); the exact qualification is in
[`source-build-receipt-v4-vt1.json`](source-build-receipt-v4-vt1.json) and
[`GRAPHICS-v4.md`](GRAPHICS-v4.md). This source build is what dotfiles packages.
It does not use a manually copied binary or the older version-3 manifest below.
Ordinary managed direct SSH does not allocate a holder.

All variants derive from an owned MIT patch against zmx 1.0.1, commit
`a35f00a2118b15a5e9d522a43035c8d7487df9b7`. Preserve
`LICENSE.upstream`, `NOTICE`, and `licenses/` when distributing it. The notices
include the exact pinned Ghostty, Zig, musl and linked dependency copyrights.
Ghostty/libghostty-vt remains an
upstream pinned MIT dependency; the binary contains the shadow VT engine,
while Kitty remains the only attached renderer.

The following historical baseline description is specifically version 3:
[`upstream.json`](upstream.json), `agency.patch`, `build.py`'s default patch,
`build-receipt.json` and the older `package.nix` import path. Its version is
deliberately `1.0.1-agency.3`, protocol 203; these historical fields are retained
so their exact existing sessions and evidence remain identifiable. The Python
endpoint selects and checks the exact configured variant. Do not upgrade an
executable used by existing PTYs in place. Session records retain the holder
version they need. The separate
`agency-kitty/zmx-3` socket directory excludes
unrelated zmx sessions. The ordinary input and output path is compiled native
code. Optional reconnect supervision may wait in Python, but no Python process
reads or relays terminal input/output bytes.

The patch provides `ZMX_ATTACH_ONLY=1`: attach goes directly to an existing
socket without invoking the create-if-missing code. The endpoint uses this on
resume, eliminating the wrapper preflight race. First attachment of a newly
created metadata identity may create its PTY; a missing previously used PTY is
an error and cannot be silently replaced.

Terminal input has 256 KiB buffering and reads pause before filling it. At
most sixteen clients can connect; each native client emits terminal input in
4096-byte messages. The reserve includes a prior partial frame plus a 4096-byte
read for each client and additional focus reports. Oversized input messages are
disconnected. A violated input-buffer invariant is a visible failure rather
than silent paste truncation. The normal 4 MiB paste qualification deliberately
stops the application reading for 600 ms, then verifies the complete hash.

Each daemon client output queue is bounded to 4 MiB. A foreground client that
slows down backpressures the PTY so its output remains lossless. A nonreading
observer is disconnected, with an error in the holder log, while the PTY and
foreground client continue. The client applies socket backpressure at 4 MiB of local
stdout buffering; its maximum framed payload is 4 MiB, bounding that buffer to
8 MiB. The native client also pauses local input at 256 KiB of pending socket
data. Native terminal writes are nonblocking and original descriptor flags
are restored on exit.

The PTY holder's Run, Send, Write, Switch and display-output injection IPC
commands are disabled. They are unnecessary for attaching a terminal or
reading its state, and the old Write route generated shell commands in a live
PTY. Images use the explicit file capability sidechannel. Direct terminal
input still comes from the attached Kitty client; scripts receive no ambient
permission to send text into it.

The version3 baseline does not include terminal images in reconnect
snapshots. The separate [version4 candidate](GRAPHICS-v4.md) qualifies static
PNG/RGB/RGBA restoration, with explicit limits and separate pinned binaries.
For version3, terminal state is a bounded visual history,
not a semantic transcript of every TUI redraw. Native OSC/DCS protocols pass
through while attached; restoring one-time effects such as clipboard writes
and desktop notifications is intentionally not part of a snapshot.

Shadow history is limited to 10,000 lines and 64 MiB per session. This bounds
both the retained VT state and the capture budget; native Kitty can retain its
larger local scrollback independently while attached.

`build.py` acquires the official Zig 0.17 compiler and verifies the SHA-256
published in Zig's official download index. It clones the exact upstream
release, verifies the commit, applies `agency.patch`, then builds a static
Linux x86_64 musl binary with ReleaseSafe. Run the build on compute through
fleet-exec; it refuses to compile on NAS. It installs nothing and writes a
receipt with source, patch, compiler and binary hashes.

`package.nix` imports the resulting static binary into Nix using an exact
SHA-256 assertion against `build-receipt.json`, repeated in the build phase.
Use `pkgs.callPackage ./backend/zmx/package.nix { binary = /absolute/path/to/agency-zmx-v3; }`.
It preserves the reviewed bytes and carries the upstream license, patch and
receipt. Run its Nix build on compute after checking at least 25 GB remains on
the build host. No upstream fork publication or mutable download is required.

Runtime qualification must run through runtime-test on compute, with no live
sessions. `backend/qualify_transport.py` compares direct PTY echo against the
holder while idle and streaming, checks byte preservation across split OSC/DCS
sequences, reconnect of alternate-screen/Kitty keyboard state, oversized paste,
unknown identity refusal, and a nonreading observer. This is software echo,
not a physical keyboard-to-panel measurement.

The version-2 patch also drains pending daemon socket output after PTY EOF and
pending native-client stdout after socket EOF/HUP. A private normal-end message
distinguishes successful program exit from a broken stream. The regression
test pauses foreground reads for 600 ms while the program writes 4 MiB and
exits immediately, then verifies every byte and its SHA-256. The first patch
version failed that test; version 2 passes it. Protocol 202 excludes stock and
version-1 clients from the new holder namespace.

Version 3 additionally restores only application-modified palette entries,
leaving Kitty theme defaults intact. It preserves soft wrapping in VT/plain
history and reconnect output rather than inserting hard newlines into copied
text. It restores custom tab stops before content/cursor, and preserves their
overlapping columns when libghostty resizes (the library normally resets them).
The real Kitty fixture checks native selection and OSC4/10/11/KKP/cursor/tabstop
query replies at equal and changed terminal widths; OSC8 links and fragmented
combining/CJK/emoji text also survive. Protocol203 and zmx-3 isolate this revision.
