# Current Herdr Core is a separate candidate

The installed old Herdr TUI0.9.3 and current Herdr Core0.1.18 have different
presentation paths. The old TUI's16ms repaint cadence must not be assigned to
the headless core. This distinction is necessary for an honest comparison.

The current source was cloned at `cd12ddd88bc11490228343291dc1096c9ed3bf77`
(November7). The published0.1.18 release tag is
`3965a46caae095a3ead01de237fa13955e52b8c6` (November4). It is Apache-2.0 and
uses a Rust wrapper over libghostty's C terminal API. The source has separate
PTY holders, a core state/event daemon and attached framed clients. It is
neither the old TUI nor a GTK renderer inside Kitty.

Its attached path forwards program output through a relay and shadow parser
to viewers, without the old UI's per-frame grid repaint. It answers some
terminal queries itself and suppresses those queries from the viewer to avoid
duplicate responses. Images take a separate reply policy because the core
does not display them. Status comes from OSC7501 rather than brand-specific
screen guessing. A slow viewer can be replaced with a fresh repaint instead
of accumulating every old paint. These choices are visible in
[`viewers.rs`](https://github.com/herdrdev/herdr-core/blob/cd12ddd88bc11490228343291dc1096c9ed3bf77/crates/herdr-core/src/viewers.rs),
[`relay.rs`](https://github.com/herdrdev/herdr-core/blob/cd12ddd88bc11490228343291dc1096c9ed3bf77/crates/herdr-core/src/relay.rs)
and [`holder.rs`](https://github.com/herdrdev/herdr-core/blob/cd12ddd88bc11490228343291dc1096c9ed3bf77/crates/herdr-core/src/holder.rs).
That is a credible architecture, not evidence of a universal18ms floor.

## Actual release admission

The official HTTPS release manifest supplied the archive SHA256
`5b2f97cb4b2a9d7a6b2cc5942628203ed9fbb7cc0c2b4b09ad8a6f5648e246b7`.
The downloaded static Linux binary is7,734,456bytes with SHA256
`baa9d208d6400556a6e379152455fe1301e0e1acdbc114ff60b79d64425179cf`.
No installer, update command or existing server was used. The release service
and HTTPS are the upstream trust contract; the manifest is not independently
signed. The archive carries its license and third-party notices.

`backend/herdr_core_admission.py` ran on compute under `runtime-test`, with an
additional real-home filesystem mask, fresh core socket/state/config and
notes disabled. The published binary passed:

- Exact attached249-byte split OSC/DCS/keyboard/graphics/paste/mouse corpus.
- Fresh attach retaining the same live application PID.
- A lossless4MiB paste while the application stopped reading for600ms.
- Complete immediate-exit4MiB output, checked byte-for-byte and by SHA256.

The receipt is `docs/evidence/herdr-core/receipt.json`. The first fixture run
passed the first three gates but its own bounded reader discarded the start
marker of a4MiB capture; the corrected fixed-length reader passed. The failed
fixture and logs remain on compute. This was not a Herdr Core data-loss bug.

These gates do not establish full native Kitty reconnect fidelity. The source
paint path uses a terminal formatter; attached graphics passing does not prove
image replay. OSC66 and advanced Kitty graphics still need explicit tests.
Nor have these admission gates measured latency. The exact binary can join
the later frozen same-worker cohort. Even a fast headless backend does not
require adopting Herdr's desktop, workspace model or web terminal.
