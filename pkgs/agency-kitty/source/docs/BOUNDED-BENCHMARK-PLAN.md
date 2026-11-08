# Later frozen comparison

This is the protocol for the late portion of the eight-hour run. It is not a
new measurement result. The purpose is to distinguish architecture and
scheduling decisions after the prototypes pass functional gates. It is not an
open-ended tuning sweep. The original laptop's perceived10ms and the pasted
18ms figure remain unmeasured physical claims.

## Admission and freeze

Record exact executable SHA256, source revision, patch SHA256, dependency
versions, runtime namespaces, SSH effective policy, CPU/load/temperature and
available disk before running. Preserve raw samples, orders, failures and
stdout/stderr. Do not change font, Kitty timing options, monitor settings,
host power policy or the live desktop. Use the same input generator and busy
output rate within each cohort. Exclude startup from steady echo timing and
report reconnect time separately. Functional failures disqualify a candidate
regardless of its speed.

Candidates already exist: current plain OpenSSH; interactive SSH to the
reviewed v4 holder with stable libghostty-vt; the local compiled client over
an SSH Unix forward; and the existing DSH-owned carrier in stock, input-hint
and headless-immediate forms. The DSH no-shadow variant is diagnostic only.
Herdr UI/terminal-attach and the unmodified holders remain architectural
references, not proposed default window managers.

## Fixed cohorts

- Local owner/relay cohort: the same PTY echo worker through direct, Herdr,
  reviewed holder and any retained minimal-holder reference. This isolates
  local scheduling/state-engine overhead and excludes SSH/rendering.
- SSH cohort: plain SSH and interactive holder with the actual default timing
  protection, then the same routes with timing protection explicitly off.
  Forward-only SSH is labelled separately because it does not apply that
  interactive policy. An off-path TTY is not presumed to restore protection:
  the installed release also classifies direct forwarding channels as bulk.
- DSH cohort: the same existing Host/controller/carrier, frozen dependencies
  and source masks for stock, input-hint and immediate parser scheduling.
  Each variant retains its own identical direct-PTY control. Differences in
  Host startup, IPC or test workload preclude treating absolute values as a
  cross-cohort terminal ranking.

Measure typing into an otherwise idle screen and typing during a fixed output
stream. Pace keys using a deterministic randomized interval; do not use a
tight request/response loop as a substitute for human typing. Separate first
keypress after a long enough quiet period from an ongoing typing burst, since
OpenSSH sends the first packet immediately and its chaff window can last up
to about3.1seconds. Each sample has an unambiguous echo marker. Report median,
p95, p99, maximum, sample count and per-round paired differences. Retain
outliers; if host work overlaps, label the round and use the predeclared rerun
budget rather than silently deleting it.

## Time and decision bounds

Reserve at most45minutes for the frozen latency phase, with a five-minute
setup/admission allowance and no more than one repeat of a failed/noisy
cohort. Use a fixed small set of randomized round orders, not parameter search.
Stop early when a correctness failure makes the architecture decision clear.
Coordinate a quiet compute window with the other agents. Do not run compiler
jobs, model requests, full GUI qualification or library rebuilds concurrently.
No additional long soak is needed merely to spend the clock; the already
recorded20-minute identity/backpressure soaks retain their stated duration.

The decision is whether a candidate preserves the direct path closely enough
in these measured software components while providing the required tested
features. No result from a private PTY, loopback SSH or software compositor
establishes a120Hz panel's hardware-to-photon latency. That requires a separate
physical input/display measurement and cannot be inferred by adding these
software medians.
