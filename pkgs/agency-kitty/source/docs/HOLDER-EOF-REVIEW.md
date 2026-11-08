# A stalled observer no longer holds foreground completion

The final read-only review found a concrete lifecycle defect in both the
stable v4 holder and optional actor: after PTY EOF, the daemon waited for every
client's output queue and restore acknowledgement before sending any client
`StreamEnd`. A small observer withholding `RestoreReady` could therefore keep
a healthy foreground terminal open after its application had exited. Its
small queue never overflowed, so slow-observer eviction did not resolve this.

The isolated regression reproduced that behavior on both previously qualified
immutable Nix binaries. The foreground received its final marker, remained
open while the observer withheld its acknowledgement, and exited0 after the
observer closed. Those baseline receipts are preserved under
[evidence/holder-eof-observer](evidence/holder-eof-observer/SHA256.json).

The fix completes clients independently. After PTY EOF, each client queues the
existing `StreamEnd` behind its own complete text/graphics snapshot and final
output. The actor also waits for that client's deferred VT operation. A full
queue retries after draining; no bytes are removed. Existing
`close_after_flush` prevents duplicate end notices and closes that client's
socket only after its ordered bytes reach the socket. The acknowledgement
still gates application input during restoration; it no longer gates delivery
of an already completed stream. Wire tags, versions and socket namespaces are
unchanged. Running old holders are not replaced or restarted.

The source change is confined to the EOF block in the complete patches
`backend/zmx/agency-v4-vt1.patch` and `agency-actor.patch`.
`backend/qualify_eof_observer.py` is a private-PTY regression fixture. An
independent source review checked ordering, exact header-room admission,
snapshot completion and close-after-flush behavior before handoff.

Both candidates were rebuilt directly on strix-coordinator with pinned Zig
0.17, ReleaseSafe and `x86_64-linux-musl`, using isolated source trees and the
already fetched dependencies. All runtime gates used `runtime-test` and
private sockets/config/state/cache. The `HOME` value was unchanged. No Nix
build, live session change or latency measurement occurred in this pass.

- Both fixed binaries pass the new regression: the foreground exits0 before
  the observer closes, and that observer receives final bytes, `StreamEnd`,
  then socket EOF despite withholding `RestoreReady`. Owned child cleanup is
  checked explicitly.
- Both pass all nine existing functional gates, including exact4MiB paste,
  exact4MiB final output, slow-observer eviction, immediate input after
  reconnect, strict unsupported-state recovery, fullscreen/KKP and unknown-ID
  refusal.
- The actor also passes the existing stopped-worker gate: raw output and input
  remain usable, a snapshot waits for the exact parsed prefix, and later
  output follows the barrier. Its worker/parser ownership was not changed.

The directly rebuilt stable binary SHA256 is
`ef206dd5bf09e20f71f895c46818e7f53e54bcb29632d79e8052ee87872d82b9`;
the actor is
`6d3df52b9b6451cdee819934d7d4ab74027d15214c8357d07ca6cfc6ec9c929e`.
The [build/binary receipts](evidence/holder-eof-observer/binaries.json) identify
the source archives and artifacts. These are direct compiler outputs, not a
claim about a subsequent Nix output's whole-file hash.

Previous native GUI/graphics proofs and frozen timing cohorts retain their
original binary identities; they were not relabelled as runs of these new
artifacts. This pass qualifies the changed EOF path and existing functional
contracts. The root integration owns the final source recipe rebuild and
final package receipt. The actor remains optional and unpromoted.

At that EOF-only review checkpoint, no additional attached-path blocker was
identified:
actor model access remains worker-owned or protected by a completed pause,
the fixed-node queue counts the in-flight decoder chunk, and worker join
precedes terminal destruction. Existing limits remain explicit: a stalled
foreground applies backpressure, unsupported restoration is refused, snapshot
formatting consumes owner CPU, and an in-flight decode has no hard join
deadline. This EOF fix does not broaden the supported graphics/protocol set
or provide a latency guarantee.

A subsequent exact Nix admission at source/export `90b005e`/`5abc06f5`
passed the same EOF regression and nine functional gates on stable
`3cnv7p…` (SHA256 `bb7a0906…`) and actor `s2rnlr…` (`09946ecd…`).
The actor also passed stopped-worker ordering. The [exact-artifact receipt](evidence/holder-eof-observer/nix-qualification-5abc06f5.json)
retains immutable paths/hashes before and after, fixture identities and zero
latency samples. This later checkpoint does not rewrite the direct-compiler
identities above. A further concurrent-restore review is a separate correctness
change with its own source and artifact receipts.
