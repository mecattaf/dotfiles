# Frozen software comparison, November 8, 2026

The paced comparison ran from 03:00:14 to 03:33:46 UTC, inside the predeclared
45-minute limit. The frozen worker’s start/echo/cleanup admission passed before the
window; stock zmx remains a speed diagnostic with known failed correctness gates. Collectors, binaries, workload and seeded schedules remained fixed.
One predeclared local repeat was used after independently observed background
browser work; it also overlapped a short background job. Both complete local
runs remain labelled shared-host. There was no third attempt or sample removal.

The full report, standalone plots, raw receipts, per-round distributions and
host activity are retained at:

`/home/tom/notes/journal/2026/11/07/kitty-consolidation/research/findings.md`

## Scope and validity

These are software echo paths. Local and DSH observers use Kitty's native C
parser to verify the actual echo cell. The network observer instead matches an
exact per-case UUID, increasing sequence and echoed-key marker emitted by its
worker; it does not run the Kitty parser. Receive timestamps precede processing
of the matching chunk. Earlier observation still affects read scheduling.
These different workloads and observers remain separate cohorts.
Results exclude physical input,
Kitty GUI presentation, compositor scheduling and display pixels. Every delta
uses one observer's monotonic clock, rather than subtracting host wall clocks.

Three seeded randomized rounds use 80 ongoing keys per case, ten warmups and
absolute 40–80 ms deadlines. Busy output is 219 bytes at most every 2 ms on a
different row. All 11,190 samples remain: network 2,550; original local 3,360;
DSH 1,920; local repeat 3,360. There are zero send deadlines over 2 ms late,
empty owned-process cleanup and no discarded outliers. Quiet network cases
have five first keys per round after 3.25-second pauses.

Local and DSH jobs use CPU 21. The passive host observer records external work
without modifying it. The DSH interval contains only owned fixture activity in
that record; both local runs contain external browser work. Three rounds do not
justify confidence intervals for independent keystrokes or a universal latency
constant. Busy/idle runs have different CPU wake/scheduling behavior as well as
different terminal output; lower busy software times do not predict every TUI.

## Local paths

Each row/workload has 240 samples in each separate run. Original/repeated
median software round trips, in milliseconds:

- Direct PTY: idle 0.1755 / 0.1800; busy 0.0421 / 0.0467.
- Stable Agency v4 holder: idle 0.3455 / 0.2808; busy 0.0620 / 0.0612.
- Published Herdr Core 0.1.18: idle 0.4770 / 0.5309; busy 0.0967 / 0.1085.
- Historical Herdr 0.9.3 UI: idle 0.8640 / 0.8907; busy 10.1828 / 10.1033.
  Busy p95 is 17.4193 / 17.4816.
- Historical Herdr terminal-attach: idle 19.2792 / 18.8556; busy 10.7328 / 10.3105.
- Optional actor: idle 0.3792 / 0.3812; busy 0.0631 / 0.0627.
- Stock zmx 1.0.1: idle 0.3401 / 0.3520; busy 0.0623 / 0.0613.

The outer grid is 120×40. Historical UI chrome reduces the application grid to
93×39, and historical attach uses 119×40. Those two rows are architectural
diagnostics rather than identical-inner-geometry rankings. The old source's
conditional 16 ms render gate is relevant; no source-backed fixed 20 ms Linux
attach timer was established. Keep the approximately 19 ms attach idle result
as measured behavior, not an invented timer explanation.

The actor shares CPU 21 with its owner in this text workload. These results do
not demonstrate a speed advantage over stable v4 or test multicore PNG decoder
isolation. Stock zmx's echo speed does not cancel its failed correctness gates.
Current Core does not inherit the old TUI's alleged universal 18 ms floor.

## Actual client-to-NAS network

Each path/workload has 240 ongoing samples and 15 quiet first keys. Idle/busy
ongoing median and p95, in milliseconds:

- Plain default: median 13.1067 / 10.3728; p95 22.7801 / 21.3788.
- Plain timing protection disabled: median 3.0673 / 2.1631; p95 4.4337 / 3.0996.
- Holder timing protection disabled: median 3.2362 / 2.3943; p95 4.9763 / 3.3601.
- Forwarding-only native client: median 3.3402 / 2.1711; p95 5.4990 / 3.3384.

Quiet-key medians are around 3 ms idle and 2.3 ms busy, without a consistent
policy penalty in that small sample. Existing SSH timing protection remains
enabled by default. Forwarding-only channels do not receive interactive
padding, so comparison against default interactive SSH changes two things.
The unpadded holder's matched-round median overhead is about 0.13–0.27 ms.
Unpadded forwarding does not consistently beat unpadded ordinary SSH. Padded
holder differences include pacing/batching interactions and cannot all be
assigned to standalone VT parsing.

## Post-collection pacing check

A separate analysis used all 2,370 adjacent ongoing network pairs, with a fixed
20 ms period taken from the inspected OpenSSH policy and 1/2 ms distance bands.
It did not search for a period or remove samples. During busy output, 75.1% of
padded arrival intervals fell within 2 ms of a 20 ms multiple, versus 22.1% of
unpadded arrivals; the input schedules themselves were around 22%. Every busy
padded round showed enrichment. Idle rounds varied substantially. This supports
the pacing explanation without establishing a universal exact delivery grid
or replacing a packet trace. Applying a fixed 16 ms diagnostic to the old Herdr
paths did not reveal a fixed 16 ms arrival clock; its conditional minimum render
gate should not be described as one. All original sample hashes are unchanged.
The script, complete per-round output and hash receipt are retained alongside
the report at `research/measurements/arrival-periodicity/`.

## DSH-owned paths

Each route/workload has 240 samples. Idle/busy median and p95, in milliseconds:

- Direct shaped reference: median 0.1865 / 0.0467; p95 0.2132 / 0.2050.
- Stock: median 2.9080 / 1.2870; p95 3.4602 / 2.6473.
- Input hint: median 1.2063 / 0.1972; p95 1.6420 / 1.2801.
- Immediate headless scheduling: median 1.2295 / 0.2282; p95 1.6892 / 0.5078.

Both prototypes beat the stock median in every round; immediate scheduling has
more consistent busy tails. These are private source-masked Host/parser/carrier
fixtures, not deployed DSH changes. All applications use TERM=xterm-256color.
The direct case has no Host. Do not add its absolute costs mechanically to the
separately shaped network cohort. DSH remains sole owner of its existing PTYs.

## Immutable input receipts

All are under the report's `research/measurements/` directory:

- `frozen-local-original/receipt.json`: SHA256
  `67a01d68ce93abedd3a6f9695c8284a8775d84fef231f1718883e932ba7165a8`.
- `frozen-local-repeat/receipt.json`: SHA256
  `540eb302c8d611562083bc368f2bbb9d0a61f538c27dc305b00dc09deb0592cc`.
- `frozen-real-network/receipt.json`: exact client/NAS binaries, source hashes,
  strict Tailnet connection and all quiet/ongoing sample vectors.
- `frozen-dsh/receipt.json`: exact installed Host/carrier/parser masks and all
  input acknowledgements, native-cell observations and cleanups.
- `frozen-host-monitor/activity.jsonl` and `receipt.json`: passive 5-second host
  observations, CPU affinity 0, stopped through its owned flag.

`backend/analyze_frozen.py` validates fixed counts and complete cases, retains
all samples, reports p50/p95/p99/max and round-summary differences, and generates
standalone SVG/PNG plots with matplotlib. Changing plot labels after collection
does not change a collector or the underlying measurements.

## Later correctness fixes have different artifacts

The final EOF review happened after this comparison closed. It reproduced an
unready-observer completion hang and corrected stable/actor queue completion.
The fixed Nix stable binary is SHA256
`bb7a0906728a14d9b6313ac6aeb2f2717e9d6c84eb0350f83670454d4fb3483a`;
the fixed Nix actor is
`09946ecdfccdf754ed4ac5b2b96b146c64b51de3345cf1ffd3dbdeebedd6b39e`.
Both passed their own EOF and nine functional gates; the actor also passed
worker-stop ordering. These are correctness admissions with no new timing
samples. Their earlier rows above retain the exact earlier binary identities
in the frozen receipts. See [the EOF review](HOLDER-EOF-REVIEW.md).

The pending-image invocation-generation fix likewise has separate source and
native graphical receipts. It changes event/gesture validation, outside the
ordinary key stream. That architecture is not a substitute for measuring a
changed artifact: this report does not relabel old measurements as final-binary
measurements. See [the invocation review](INVOCATION-GENERATION.md).
