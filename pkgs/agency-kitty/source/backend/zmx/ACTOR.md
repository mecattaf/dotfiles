# Isolated shadow actor candidate

Version `1.0.1-agency.5-actor`, wire protocol 205 and socket namespace
`zmx-5-actor` are an experimental alternative to the frozen version 4 holder.
The production recipe, Python version allowlist and default remain unchanged.
No latency measurements or default promotion are part of this admission pass.

The native PTY owner forwards attached output bytes and handles terminal input.
One additional native thread exclusively feeds the existing libghostty VT,
including Wuffs PNG decoding. Kitty remains the attached renderer. This removes
PNG decoding from the PTY owner's call stack; it does not remove the NAS shadow,
replace Kitty, or guarantee a particular key-to-pixel delay.

`agency-actor.patch` is a complete patch against zmx commit
`a35f00a2118b15a5e9d522a43035c8d7487df9b7`, including the version 4 graphics and
OSC66 protections. It retains stable libghostty-vt 1.0 at
`0fa3d577a5614150ff8e2c152de5fb9d5c6d2dec`. The upstream terminal package's Zig
content hash still has a `ghostty-1.4.1-dev` prefix; the exact commit identifies
the stable library release and is the same pin as version 4-vt1.

The queue permits 8192 allocations of 4112 requested bytes each, including the
in-flight decoding chunk: 32 MiB of maximum raw payload, 32.125 MiB of requested
node storage, plus allocator bookkeeping. It allocates on demand. Counting
nodes prevents one-byte PTY reads from evading the bound. A full queue suspends
PTY-output reads while the owner continues polling terminal input. No output
or input bytes are dropped. An application that blocks its own input reader
while writing to a full PTY can still stop responding; bounded buffering
cannot prevent that application behavior.

A requested snapshot, resize, history capture, Info/PWD read or focus transition
freezes the enqueue offset and asynchronously waits for the worker to parse
exactly that prefix. The owner continues servicing admitted terminal input
while waiting. After a mutex-published pause, the owner may exclusively borrow
VT state. Graphics iterators retain that pause until their references are
released; the leader's restoration handshake also preserves its existing
input-admission boundary. An observer's already serialized snapshot and
withheld RestoreReady cannot retain the VT pause. Raw bytes after the barrier
are read only after the required state operation completes.

The owner and worker never hold the queue mutex across VT parsing, PNG decode,
terminal serialization or a blocking PTY write. ReleaseSafe uses the native C
allocator; Debug mode explicitly enables the debug allocator's thread safety.
The worker starts after the holder's process forks. Queue/offset publication
uses Zig's mutex and condition primitives; `Io.Threaded.init_single_threaded`
disables asynchronous task scheduling and does not disable OS-thread mutexes.
The owner accesses mutable terminal state only during a completed pause.

On teardown, the worker is signalled and joined before the terminal is freed.
An in-flight decoder completes before the join returns; there is no unsafe
thread cancellation or hard wall-clock decoding deadline. A worker panic is a
holder process failure, not permission to use partial state. Unexpected wake
pipe failures fail loudly; a full nonblocking wake pipe is already readable
and is the only accepted notification-write error.

Explicit state operations can still consume owner CPU while serializing a
bounded snapshot. An Info request also drains outstanding shadow work before
reporting PWD. The candidate therefore does not promise that all control
operations are independent of parsing or formatting, or that allocator,
logging, scheduler and kernel costs disappear. Its separate worker has an
additional thread, allocation and scheduling cost that must be measured
against the synchronous holder before choosing it.

## Functional admission

All experiments ran on strix-coordinator through runtime-test with private PTYs,
sockets, configuration and process namespaces. The graphical fixture also
masked the real home and external network and used throwaway SSH keys. It
attests activated Kitty 0.50, Codex 0.167 and the actual mapped official Domicile
63db244 library. No real desktop or live retained session was addressed.

- `backend/actor_qualification.py` seizes only the idle worker thread of its
  verified private descendant holder. While that worker is stopped, real
  native attached input and raw output continue. A requested History snapshot
  waits; later input still reaches the same application. On releasing the
  worker, the snapshot contains exactly the earlier output, followed by
  delivery of the later raw output. A small observer withholding its restore
  acknowledgement cannot pause the foreground.
- A Zig unit test blocks the real PNG callback on another OS thread. The actual
  owner input handler and native output frame builder remain usable. Filling
  all 8192 node slots closes admission without loss; releasing decode reaches
  an exact parsed/enqueued offset barrier with ordered PWD/focus/text state,
  after which resizing is safe. The shipping decoder has no artificial gate.
- The existing nine functional-only gates cover immediate retained input,
  explicit image-free recovery, strict OSC66 refusal, split control-byte
  preservation, fullscreen/KKP31 reconnect,4MiB lossless paste, exact unknown-ID
  refusal, a nonreading observer and 4 MiB lossless output at process exit.
- Real native Kitty reconstructs exact 4K RGBA pixels and placement over three
  fresh attaches, then handles image replacement and deletion. Actual Codex
  keeps the same process, unsent draft and 54×57 thumbnail over fresh SSH/Kitty
  attachment; no input or provider request is injected for restoration.
- Native palette/default-theme separation, OSC8 links, Unicode, soft-wrap
  selection, cursor, custom tabs and KKP31 survive same-width and changed-width
  restoration in the existing GUI fixture.

Receipts live under `backend/results/actor/`; `build.json` identifies the exact
artifact, patch, toolchain and dependency hash. The native fixture source is
root helper commit 01040f8 plus `actor-fixture.patch`, which changes only the
private candidate allowlist and its hardcoded observer wire identity.

## Build and limitations

`source-build-actor.nix` is a separate source recipe with the same pinned
upstream archive, official Zig 0.17 checksum and fixed-output eight-package
Zig dependency tree as the qualified version 4 recipe. The candidate was built
with that compiler/dependency tree directly on compute using ReleaseSafe and
`x86_64-linux-musl`; its candidate Nix derivation has not been built or qualified.
No executable is committed to Git. Preserve `NOTICE.actor`, `LICENSE.upstream`
and `licenses/` with any distribution.

The existing restoration limits remain: static direct RGB/RGBA/PNG graphics
only, conservative strict refusal after OSC66, explicit refusal for unsupported
placements/animation/state, bounded history and a bounded per-screen image
cache. This is not full Kitty-protocol parity. The standalone SSH baseline and
other persistence candidates remain valid choices. Choosing this actor requires
independent source review and later consistent comparisons of frozen builds.

Primary source pins: [zmx](https://github.com/neurosnap/zmx/tree/a35f00a2118b15a5e9d522a43035c8d7487df9b7),
[libghostty](https://github.com/ghostty-org/ghostty/tree/0fa3d577a5614150ff8e2c152de5fb9d5c6d2dec),
[Zig 0.17](https://ziglang.org/download/0.17.0/release-notes.html).
