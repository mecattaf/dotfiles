# Native files dropped into a NAS terminal

A real Wayland image drop reaches the exact managed Kitty window through native
Kitty input, private SSH staging and one bracketed paste. It leaves the prompt
unsubmitted. A session change during the upload prevents delivery.

This requires two coordinated source changes in addition to the Kitty
capability adapter. The patches are reviewable assets; this proof does not
activate a new Domicile or Imagine on the live laptop.

- [Domicile patch](patches/domicile-native-drag.patch): commit
  `ec4852dc`, based on upstream `75708d7638002e1bba421cf83f6927298dbc1c3a`.
- [Imagine patch](patches/imagine-native-drag.patch): commit `8affac9`, based on
  the isolated source snapshot `0d41ebc`. Preserve the repository's upstream
  MIT/reference files when applying it to the owned Imagine source.

## Why the compositor and shell participate

The engine's native `<app>` captures the DOM pointer on a client press. During
an actual native data-device drag, that capture keeps motion addressed to the
source instead of hit-testing another native window. The source then sees
negative coordinates and the destination receives no URI offer.

An official-engine negative control reproduced this with a real Wayland source
and a validated pointer serial. The positive case uses compositor-confirmed
drag lifecycle events. Smithay validates the implicit grab serial before the
compositor queues the source app ID. The existing outbound writer delivers that
typed event; the Wayland input thread does not wait for a subscriber.

The matching `domicile-native-drag-events` binary exposes a bounded JSON-line
stream through the existing public process API. Imagine remembers native app
pointer presses and releases only a matching, still-owned DOM capture after a
confirmed drag start. It stops its helper on cleanup and recreates it after
`compositorreplaced`. Readiness, malformed data, oversized messages, connection
loss and helper exit are explicit states or errors. Idle delivery has no timer.
No engine rebuild or per-key listener is involved.

## Evidence

All paths below are on `strix-coordinator` unless identified as NAS paths.

- Final positive proof:
  `/home/tom/kitty-consolidation/proofs/native-dragdrop-15-final-attested/receipt.json`.
  Actual Kitty executable is
  `/nix/store/rs4s3ggn03a65bbwj9r1ps20d4kichm1-kitty-0.50.0/bin/.kitty-wrapped`,
  SHA-256 `d630feac38d9f709fb918135301b059ad144accbbe2ef5a6fecf8fec4d3fe6df`.
- Actual compositor descendants map
  `/nix/store/9h4xmaqrb1w5hs8f5x4vasbzac7y966z-domicile-engine-63db244/libdomicile_engine.so`,
  SHA-256 `43f0dc75132f7ab3ae7042a75d7c19b88e89a9e10a4850a656a06bcda623c02f`.
  The receipt also records the matching browser executable, all three Rust
  binary hashes and the complete Imagine bundle hash.
- The complete Imagine bundle is SHA-256
  `4402d07794555cac5bbfed661868f8cc3ccf0220731951e2c84777eb30f92290`.
  The fixture imports its real `runImagine`, waits for its real helper's ready
  acknowledgment and performs trusted pointer gestures in a private desktop.
- A native source creates an actual `wl_data_source`, starts its drag with the
  real button serial and writes `text/uri-list` to the offered descriptor.
  The first drop preserves the image bytes through an actual private SSH
  server, then produces only the expected bracketed paste in the target PTY.
  There is no Enter and no worker overlay. A second actual drop pauses the SSH
  worker, changes the exact window's managed session, and verifies zero added
  terminal input after upload completes.
- Official-engine negative control:
  `/home/tom/kitty-consolidation/proofs/native-dragdrop-12-official-negative/receipt.json`.
  Without the lifecycle consumer, the native source cancels and transfers no
  URI or terminal input. Diagnostic proof 6 manually releases capture only to
  isolate the cause; it is not the production implementation.
- Read-only live-client source identity, NAS path:
  `/home/tom/.wt/kitty-consolidation/client-live-dnd-base.json`.
  All 424 filtered Rust source files of the installed client match Git
  `75708d7` with zero differences. Its actual loaded engine is the official
  `63db244` release. The older compute fixture package instead defaults to
  `965dea407`; proofs 8–10 establish only that older fixture's behavior.

## Checks and practical limits

- Rust: formatting, core all-target Clippy with warnings denied, 1,404 core
  tests, compositor all-target Clippy with warnings denied, all 942 compositor
  unit tests and fresh native binary builds pass. Receipts and complete logs:
  `/home/tom/kitty-consolidation/proofs/dnd-rust-checks-1/`.
- TypeScript: the protocol and Rust-wire-fixture suites pass 124 tests; Biome
  2.5.11 checks both modified protocol files. Imagine's declared pinned
  workspace passes all 127 tests, provenance verification and the complete
  bundle build in `.proof/pinned-20261108T000910.854483Z/` of the staged
  `imagine-dnd` checkout.
- The upstream full compositor integration fixture reassigns `HOME`; it is
  excluded under this session's isolation requirement. The actual private
  desktop proof keeps `HOME` unchanged and uses `runtime-test`. This is not a
  claim that the entire upstream `bun run check` or every compositor
  integration test ran.
- Build/package activation remains a separate integration step. These gates
  run the source-built Rust binaries under their declared full development
  environment. They do not prove a Nix release package or a physical monitor's
  input-to-pixel latency.
- The source records `drop-performed` and successful URI transfer, followed by
  the destination's cancellation/cleanup callback. No claim is made about an
  application-level drag-completion acknowledgment or touch-driven drags.
- Private desktop DBus, portal, priority and software-renderer diagnostics are
  retained. Attempt 13 also preserves a failed launch outside the declared
  development environment, where the debug compositor could not load PAM/EGL;
  the declared environment is used by successful attempts 14 and 15.
