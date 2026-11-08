# Frozen local relay comparison

`backend/frozen_local_compare.py` compares the same Python worker and seeded
input schedule through direct PTY, zmx variants, Herdr UI, Herdr terminal attach
and Herdr Core. It creates private servers and performs no production action.
The functional-only admission collects zero echo latency samples.

Run it through `runtime-test` on compute, using the admitted Kitty 0.50 binary:

```sh
kitty +runpy 'import runpy,sys;sys.argv=["backend/frozen_local_compare.py","--manifest","/ABS/manifest.json","--output","/ABS/NEW-PROOF","--worker-python","/ABS/PYTHON","--functional-only"];runpy.run_path(sys.argv[0],run_name="__main__")'
```

The manifest contains one `direct` candidate and named candidates with `kind`,
absolute `binary` and its exact SHA-256. Supported kinds are `direct`, `zmx`,
`herdr-ui`, `herdr-attach` and `herdr-core`. Names are unique bounded path-safe
labels. Worker Python is explicit because Kitty's embedded `sys.executable` is
the Kitty executable, not a standalone Python interpreter.

## Observation and workload

- The admitted Kitty C parser incrementally consumes every output chunk. It
  locates the actual visible `READY` cells, including wide-character prefixes,
  then observes that same cell change between `Q` and `X`. An ANSI `CSI X`
  control, title/hyperlink payload or unrelated cell cannot satisfy an echo.
- Capability, DA1, cursor-position and color replies use the native parser and
  Kitty's own query helpers during startup/warmup. Once measurement starts,
  an unexpected reply causes an explicit case failure; it is never injected
  into the measured input stream.
- Stop time is captured immediately after the read containing the echo and
  before parsing that matching chunk. The observer's work on earlier chunks
  still affects read scheduling. This is local byte-arrival observation with
  a common native parser, not a Kitty GUI or display-latency measurement.
- Ten warmup keys precede each measured case. Send targets use deterministic
  absolute 40–80 ms intervals. The driver drains output while waiting, avoiding
  PTY backpressure caused by a sleeping reader. It records every actual input
  interval and send lateness; samples over the declared 2 ms scheduling
  tolerance remain in the result and are counted, never discarded.
- The single worker writes 219 bytes at most every 2 ms on row 20 during busy
  cases. It writes the echo on row 10. Busy generation shares the worker's
  thread and is identical across candidates.
- Outer geometry is fixed at 120×40 cells. Actual inner worker geometry is
  recorded separately. Admission found Herdr UI uses 93×39 cells because of
  its chrome; other admitted paths use 120×40. Herdr UI is therefore an
  architectural reference, not an equal-inner-geometry terminal ranking.

## Isolation, bounds and evidence

The driver requires the private runtime/PID namespace, then masks the real home
through a mount namespace without assigning a different `HOME`. It exposes only
its source, output and the reviewed executable directories beneath that home.
Every case gets private XDG roots, socket paths and an inherited case token.
Cleanup stops only that case's clients/server and checks exact process start
identities before any fallback signal. Remaining processes and cleanup errors
fail the case. Zmx daemon cleanup currently needs a recorded SIGTERM after its
ordinary session-kill command; it leaves no live owned process for the next case.

All waits, worker input, RPC handshakes and candidate commands respect the
cohort deadline. Cleanup has independent bounded attempts so one timeout cannot
skip a later stop. Output is bounded at 16 MiB per case and preserved in
`terminal-output.bin`; parser diagnostics remain in `observer.log`, and server
stdout/stderr remain in `daemon.log`. Failed cases preserve partial sample
vectors and ownership/cleanup receipts.

The receipt records candidate executable hashes, observer/worker interpreters,
all imported fixture source hashes, private-home/runtime scope, actual worker
PID/start/TTY/geometry, CPU affinity, load, temperatures and disk availability.
It does not record hardware input-to-pixel latency.

Functional baseline admission on compute:
`/home/tom/kitty-consolidation/proofs/frozen-functional-4-final/receipt.json`.
All 12 idle/busy cases across six candidate paths passed with zero latency
samples. Herdr/Core emit native-parser diagnostics for legacy private reset
modes 9, 1001 and 66 during startup. Those logs are retained; this echo gate is
not an assertion of support for those modes. Attempt 1 preserves a fixture
cleanup error from trying to inspect the preexisting bubblewrap PID's protected
environment; the corrected ownership scan excludes the original process set.

`backend/test_frozen_terminal.py` has six functional tests for split control
strings, `CSI X`, native queries, measured-phase refusal, wide-cell marker
coordinates, read deadlines, cleanup continuation after a command timeout and
the bounded post-kill wait. Percentiles use the sorted value at
`floor(p × (n − 1))`; no interpolation or tail-sample exclusion is applied.
Run it with the same Kitty `+runpy` mechanism. Full timing cohorts remain gated
by the separate bounded benchmark plan and the coordinated quiet window.
