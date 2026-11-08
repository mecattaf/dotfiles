# Frozen DSH-owned carrier comparison

`backend/frozen_dsh_compare.py` compares direct PTY, stock DSH, input-hint and
headless-immediate in one private cohort. DSH remains the sole owner of its
application PTYs. Source masks affect only fresh fixture Hosts; no live carrier
or Nix-store file changes. No Agent turn or real provider runs.

The worker is the exact `frozen_local_compare.py --worker` implementation:
219 bytes at most every 2 ms on row 20 when busy, with alternating Q/X echoes on
row 10. All paths use the same worker interpreter, 120×40 cells and
`TERM=xterm-256color`, matching the existing controller's child default.
The observer incrementally parses output through the admitted Kitty 0.50 C
screen and checks cell (9,0), rather than searching raw CSI/OSC payloads.
DSH also must acknowledge each exact input sequence before another sample;
acknowledgement wait is outside that sample's echo stop time.
That acknowledgement proves carrier/provider acceptance; the visible cell
proves the corresponding worker echo, without claiming an application-side
counter or native feature parity.

The fixed measured schedule has 3 randomized rounds × 80 ongoing keys per
path/idle/busy, with 10 warmup keys per case. Seeded absolute 40–80 ms deadlines
match the local cohort. The driver drains output while waiting, retains raw
latency, actual intervals and send lateness, and counts lateness over 2 ms without
discarding it. Unexpected terminal queries after warmup fail the case.
The receive clock stops after the socket/PTY read containing the echo and
before native parsing of that matching chunk. Earlier NDJSON/native parsing
still affects read scheduling.

The 540-second measurement deadline plus bounded cleanup keeps this cohort
under 10 minutes. Every DSH terminal is explicitly closed and its empty inventory
checked before Host teardown; inherited per-case tokens and process start
identities scope any fallback cleanup. Raw terminal bytes, Host/parser logs,
partial samples and failures remain in the unique proof directory.

Run functional admission through `runtime-test` on compute, then the exact Kitty
`+runpy` executable. Required arguments are `--output NEW`, `--dsh ABS`,
`--carrier ABS`, `--worker-python ABS` and `--functional-only`. It runs8 cases,
one unmeasured echo each, with zero latency samples. The carrier must match the
previously admitted SHA256 `6c750af4…bc417`.

The resulting `manifest.json` records exact DSH wrapper/package, Node, observer
and worker binaries, carrier and fixture source hashes, and every original and
qualified controller/headless source hash. A later measured run requires
`--manifest ABS` pointing to that admitted manifest, omits `--functional-only`,
and refuses any changed input. Do not start it before the coordinated 03:00 UTC
quiet window.

Functional evidence:
`/home/tom/kitty-consolidation/proofs/frozen-dsh-functional-2-final/receipt.json`.
All 8 cases pass with zero latency samples, exact geometry/cell, matching input
acknowledgements, empty owned terminal inventories and no remaining owned
processes. `backend/test_frozen_dsh.py` covers split NDJSON, control-string false
echoes, exact input sequences and partial-response EOF bounds.

These are software byte-arrival comparisons. The direct case runs without a
DSH Host, so it is an architectural reference within this cohort. Host startup
is excluded by readiness and warmups. Results exclude SSH, Kitty GUI rendering,
compositor scheduling and physical display latency; they must not be ranked
against absolute values from differently shaped cohorts.
