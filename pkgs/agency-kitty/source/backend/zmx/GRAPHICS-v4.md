# Static graphics restoration candidate

Version 4 restores the measured native Codex image workflow without asking Codex
to repaint. Kitty remains the renderer. Stock OpenSSH carries bytes in the
managed default; the SSH kitten remains an explicit bootstrap option. In both,
the native holder keeps the existing PTY and a NAS-side VT shadow. Python is
absent from the ongoing byte path. This is an optional persistent transport;
the direct SSH reference remains available.

## The reproduced defect

With Codex 0.167 and a fresh native Kitty, version 3 preserved the Codex PID,
process start time and unsent composer draft but restored zero terminal
images. The original thumbnail contained 54×57 pixels. A diagnostic Ctrl+L
redraw restored exactly the same pixel hash; it was never adopted as a fix.

The current [Codex image renderer](https://github.com/openai/codex/blob/086ccc833bc9cf01024ad2dd6af7dbd421b6bf9a/codex-rs/tui/src/custom_terminal.rs)
caches image identity and placement and skips retransmission when they have
not changed. A same-size SIGWINCH therefore cannot guarantee a new upload.
Codex's [transcript image module](https://github.com/openai/codex/blob/086ccc833bc9cf01024ad2dd6af7dbd421b6bf9a/codex-rs/tui/src/transcript_image.rs)
uses direct PNG transmission over SSH, with the first image ID 0xC100.

There were two separate gaps: zmx's text formatter emitted no images, and
[libghostty's embedding default](https://github.com/ghostty-org/ghostty/blob/53e55147bbbb0157672dac0228aa7744e881f1fa/src/terminal/sys.zig)
sets its PNG decoder callback to null. The raw original image reached Kitty,
while the shadow had no decoded PNG to restore. Version 4 wires the already
linked upstream Wuffs decoder through libghostty's documented callback. Its
existing LimitedAllocator guards remain in force. No new decoding library or
renderer is introduced.

## What is retained and streamed

The existing shadow owns decoded RGB/RGBA buffers and pinned placements.
Version 4 streams those buffers as direct KGP chunks, preserving explicit
image IDs and visible concrete placement coordinates, cropping, pixel offsets,
cell dimensions and z-index. PNG inputs already retained by the shadow become
RGBA on replay. Cursor/origin state is restored afterwards. Replacing or
deleting an image changes the authoritative retained map, so reconnect does
not resurrect old images.

The leader's text snapshot has a 32 MiB writer bound. Image replay does not use
that buffer: an iterator base64-encodes at most 3072 decoded bytes into 4096
encoded bytes per chunk. It references the existing retained image data
rather than allocating another image-sized snapshot. Output still passes
through the4 MiB per-client queue; text frames are at most64 KiB and image
frames are under 8192 bytes. The client's stdout backpressure bound remains
8 MiB and its input queue256 KiB. Text formatting can temporarily retain its
fixed32 MiB backing plus the copied result and bounded prompt rewrite; this
is a per-attach cost, not an allocation per key.

Image storage defaults to320 MiB per screen, allocated on demand.
`ZMX_IMAGE_STORAGE_MIB` accepts 1..512 MiB; it never requests an unbounded cache.
This replaces libghostty's small 10 MB embedding default. Cache eviction follows
the existing bounded library policy. This is a per-screen budget, not a hard
whole-process RSS cap or an aggregate quota across all PTYs. Existing placement
metadata and other terminal structures have their own library behavior; this
candidate does not claim every allocation is covered by the image-byte limit.

A protocol 204 restore-done/ready handshake keeps local stdin unread until the
snapshot has drained to the native client's stdout. The client acknowledges
that point, then the daemon admits input and resumes PTY parsing. The OS
buffers a key typed before admission; no timer discards it. While the image
iterator holds references, terminal mutations and PTY parsing are paused.
There is no such handshake or added timer per ordinary key after admission.

An oversized observer receives `ObserverGraphicsSnapshotTooLarge` before
image formatting when the decoded-byte lower bound already exceeds its queue.
Smaller observer snapshots must also fit the existing queue. A nonreading
observer is disconnected at that bound and cannot impose foreground queue
backpressure. Observer attachment is not an authorization boundary: a normal
terminal client can provide input. Future web readers must use a separate
server-enforced read-only capability, never an ambient holder socket.

## Proven scope and limits

The admitted static subset uses explicit image IDs, direct RGB/RGBA or decoded
PNG input and concrete placements in the visible active screen. Known retained
states that this serializer cannot reproduce are explicitly refused:

- Animations, implicit IDs, numbered images and transient images.
- Virtual Unicode-placeholder placements and relative placements.
- Image placements in historical rows or another inactive screen.
- Incomplete image transmissions or pending decoded data.

[OSC66 text sizing](https://sw.kovidgoyal.net/kitty/text-sizing-protocol/) is another concrete gap: stable libghostty parses it but [the stream dispatcher](https://github.com/ghostty-org/ghostty/blob/0fa3d577a5614150ff8e2c152de5fb9d5c6d2dec/src/terminal/stream.zig#L3097) explicitly leaves its callback unimplemented. The shadow drops the payload, so it cannot restore native multicell text. Version 4 conservatively marks the PTY when an OSC66 prefix is observed and refuses strict reconnect with `KittyTextSizingRestoreUnsupported`. The marker is sticky for that PTY lifetime; guessed screen resets do not clear it. The five-byte detector handles split boundaries and C1 OSC. It is not a full string-context parser, so an enclosed raw prefix can cause a conservative false positive; explicit text-only recovery remains available. Original attached bytes remain unchanged.

These are limitations of this reconnect candidate, not restrictions imposed
on original attached bytes. Commands or formats that libghostty itself does
not understand can pass to Kitty without leaving reconstructible shadow
state. Validation of known retained state is therefore not full Kitty graphics
protocol certification. File/shared-memory transfers are disabled in the
shadow; direct transmission is the qualified remote form.

A failed restore leaves the PTY alive. Explicit `ZMX_RESTORE_TEXT_ONLY=1`
selects a distinct recovery admission that omits graphics and prints a warning;
it does not change or recreate the retained process. It is not an automatic
fallback or a claim of visual parity. Clipboard writes, desktop notifications
and other one-time effects are not replayed. Bounded VT history remains
separate from the full semantic harness transcript.

## Qualification

Both builds use zmx 1.0.1 upstream commit
`a35f00a2118b15a5e9d522a43035c8d7487df9b7`, official SHA-verified Zig 0.17.0,
ReleaseSafe and static Linux x86_64 musl. They remain separate candidates:

- `1.0.1-agency.4`: upstream-pinned libghostty 53e55147.
- `1.0.1-agency.4-vt1`: stable libghostty-vt 1.0.0 tag 0fa3d577.

Each has an exact binary/patch/source receipt. Protocol204 excludes versions1–3;
private socket namespaces also distinguish the two version 4 variants. Existing
version 3 PTYs must keep their matching binary and namespace.

The final private GUI tests use actual Kitty 0.50 (shader2026.19), Codex 0.167,
stock SSH kitten, a private sshd, the explicit official Domicile63db244 engine and a masked
home/loopback-only network. The receipt records actual descendant executable and loaded `libdomicile_engine.so` mappings/SHA after the private monitor starts, rather than assuming the CLI wrapper selected the requested engine. No credentials or live user sessions participate.
They inspect Kitty's native decoded image bytes and render placement rectangles;
a substring of an ANSI dump is not used as a proxy for visible graphics.

Both candidates pass:

- Identical native Codex thumbnail pixels and placement after a genuinely fresh
  Kitty/SSH attachment; same Codex PID/start and unsent draft, zero provider
  requests and no Ctrl+L or injected repaint input.
- A3840×2160 PNG with 33,177,600 decoded RGBA bytes, exceeding the old monolithic
  snapshot cap, across three fresh reconnects with the same application PID.
- Replacement under the same image ID restores one replacement/ref; deletion
  leaves zero images and zero native cache bytes after another fresh attach.
- Explicit large-observer refusal with the foreground image/process intact.
- First input queued before reading the snapshot preserved exactly once,
  explicit unsupported-state refusal, same-PID text-only recovery, split
  control strings,4 MiB delayed-reader input and final output, fullscreen/KKP
  restoration, exact-ID refusal, and slow-observer disconnection.
- Native color overrides with untouched client theme defaults, OSC8 hyperlinks,
  Unicode, exact soft-wrap selection, cursor, custom tabs and KKP31 at equal
  and changed column counts.

Receipts live in `backend/results/native-graphics-v4{,-vt1}-admit.json`,
`agency-functional-v4{,-vt1}.json` and `kitty-snapshot-v4{,-vt1}-final.json`.
These are functional fidelity gates. They do not measure physical key-to-pixel
latency, certify every image format/state, or replace a later consistent
comparison of finished transport prototypes.

## Reviewable packaging

`build.py --patch backend/zmx/agency-v4.patch --workdir /fresh/path` builds
version 4 from the verified upstream release. Use `agency-v4-vt1.patch` for the
stable-library variant. Compilation belongs on compute, never NAS.

The existing Nix recipe preserves all version 3 defaults and accepts explicit
candidate receipt/patch/notice paths:

```nix
pkgs.callPackage ./backend/zmx/package.nix {
  binary = /absolute/reviewed/agency-zmx-v4-vt1;
  receiptFile = ./backend/zmx/build-receipt-v4-vt1.json;
  patchFile = ./backend/zmx/agency-v4-vt1.patch;
  noticeFile = ./backend/zmx/NOTICE.v4;
}
```

It verifies the exact binary hash at evaluation and installation and packages
all existing upstream/dependency notices. No mutable binary URL, live daemon
replacement or fork publication is needed. The separate `version-selection.patch`
proposes the small explicit backend/metadata integration; it is not applied to
root's active server implementation by this research branch.

### Source-only Nix recipe

`pkgs.callPackage ./backend/zmx/source-build.nix {}` builds the stable-library
`1.0.1-agency.4-vt1` variant without an external reviewed binary. It pins the
upstream source tarball, the full local patch, the official Zig0.17 archive
checksum and a recursive fixed-output hash for all eight Zig source packages.
The dependency fetch includes exactly Highway and Wuffs beyond
`--fetch=needed`; fetching every optional Ghostty GUI dependency is unnecessary.
The final ReleaseSafe x86_64-musl compilation takes place in the normal Nix
sandbox without network access.

Zig0.17's standalone `fetch` materializes local packages only with `--save`.
The dependency derivation temporarily adds two named fetches, checks their Zig
content-hash directories, then discards those temporary manifest additions.
They do not change the reviewed source or the final program's dependency graph.
The resulting package includes all existing notices, the source patch, its
source provenance JSON and a SHA256 receipt for its actual installed binary.
Runtime gates remain separate compute-side `runtime-test` invocations; the Nix
builder does not use a live user runtime directory.

The final source-built package is3,782,168 bytes including documentation and
notices, with zero runtime store references. Compiler/dependency paths occur
only in its separate optional `debug` output. Its3,638,432-byte static binary
has SHA256 `204fe21bebcbdd3e9d2d4efa8713f669c269384c2b1b383b6705413ff9df988f`.
That exact installed binary passes the strict protocol/data/input gates, native
color/wrap/KKP selection gates, and actual current Codex plus repeated4K
graphics reconnect/replacement/deletion gates. Final Kitty and the actually
mapped official Domicile engine are attested again. See
`source-build-receipt-v4-vt1.json` and `../results/source-nix-*.json` for
artifact/source hashes, the optional debug output and the qualification scope.
