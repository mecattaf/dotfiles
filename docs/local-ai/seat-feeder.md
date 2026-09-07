# The rewrite seat feeders

`home/seat-feeder.nix` declares three coordinator-only systemd user
timer+service pairs. Each fires every 30 seconds—half the 60-second policy
staleness bound—and invokes `~/.local/bin/tally-seat-feeder`; Home Manager also
creates `~/.local/state/tally-rewrite/meters/` at mode 0700.

This is a freshness mechanism, not a scheduler. A feeder reads an allowance and
atomically replaces its row file. It never launches work on a seat, holds no
lease, and spends nothing. U-D19 owns the switch that will make the declaration
live; this unit does not call `systemctl` or `nixos-rebuild`.

## Declared clocks and rows

| timer | instrument | row files | owner / state |
|---|---|---|---|
| `tally-seat-feeder-claude.timer` | `bin/stamp-receipt.py window --seat …` | `cc.json`, `cc2.json`, `cc3.json` | Tom; MEASURED when the reader answers, STALE-MEASURED with its age when it does not, fresh UNKNOWN only when nothing was retained |
| `tally-seat-feeder-codex.timer` | newest `rate_limits` record below `~/.codex/sessions/**/*.jsonl` | `codex.json` | `third-party`, by D-B6; readable by name and never proposed onto |
| `tally-seat-feeder-pi-qwencloud.timer` | the provider's own quota refusal, recorded in `pi-hold.json` (window only) | `pi-qwencloud.json` | Tom; utilization UNKNOWN with D-B17/TL-17 named in the row, window from the stated reset |

There are three pairs because the issue's DOMINANT acceptance and scope require
three. The Claude service is one sanctioned credential-reader invocation per
seat within one clock. It still publishes three independent rows: `cc` and
`cc2` retain distinct primary reset clocks and are never summed. The exact row
grouping is carried by each service's `X-TallyRows` field and asserted in the
flake check.

All services use `OnUnitActiveSec=30s`, `AccuracySec=1s`, a hard
`TimeoutStartSec=20s`, and `WantedBy=timers.target`. D-B54's enforced
worst-case arithmetic is `30 + 1 + 20 = 51 < 60` seconds: period plus timer
accuracy plus the whole service duration remains inside the kernel's
staleness bound. A service still active at 20 seconds is terminated and its
unit fails; it cannot silently publish outside that envelope. The worker
configuration evaluates with no feeder unit.

The Claude service runs its three readers concurrently. Each reader retains
its 12-second timeout, leaving eight seconds inside the service cap for row
shaping and publication. As each read returns, that seat is shaped and written
immediately; a slow seat cannot hold completed seats in a batch.

## Source boundaries

The Claude path is the reader authorized by D-B5. The feeder invokes it and
consumes only its JSON result; it never opens a credential file itself and
drops the reader's stderr. When that reader returns its bounded cache, the row
carries the cached numbers together with their age — see "Every row states its
window" below, which supersedes this section's original rule that a cached
reading is written as a current UNKNOWN.

Every row's `observed_at` (and an UNKNOWN row's `updated_at` / `taken_at`) is
sampled inside the atomic write path, after its read returned. A reader's own
timestamp is retained only as `source.source_observed_at`; it never becomes
the row-age clock. This makes a newly landed row age from publication rather
than from service start.

The Codex reader recursively opens only `.jsonl` files below
`~/.codex/sessions`. It takes `used_percent`, `window_minutes`, and `resets_at`
from the newest usable `rate_limits.primary` record. Missing any of the three
produces UNKNOWN. It skips symlinked files and directories, so a rollout-shaped
link cannot escape the sessions tree. It never names or opens
`~/.codex/auth.json`; the fixture places valid-looking rate-limit data behind
such a symlink and requires the result to stay UNKNOWN.

The Qwen Cloud writer has no source for a UTILIZATION because TL-17 remains
unset. Its row carries `capacity.grade: UNKNOWN` and a reason naming TL-17 and
D-B17. Its WINDOW is a separate question with a separate source: see below.

Every row also carries the U-B10 fields already settled for the estate:
per-attempt output-token cap 100000, checkpoint grace 30 seconds, kill grace 10
seconds, and a context window where one is measured.

## Every row states its window (CAP-1, dotfiles#337)

A utilization says how much of an allowance is gone. It does not say when the
allowance comes back, and routing needs both: a seat at 95% resetting in one
tick and a seat at 95% resetting in a week are the same number and a different
door. Five-hour windows are what class 7 routing spends, and R-c12's
utilization denominator is "available per seat at start and stop". Neither was
readable from these rows. MEASURED 2026-09-07 16:19Z, before this change:
`cc.json` carried `capacity.grade UNKNOWN`, a null utilization and no window at
all; `cc2.json` and `cc3.json` did not exist; `pi-qwencloud.json` carried no
window though `pi-hold.json` had known `held_until` since 01:39Z.

Every row now carries the second half of the question.

| row | window | remainder | split |
|---|---|---|---|
| `cc`, `cc2`, `cc3` | `nested`, `primary` 300 min and `secondary` 10080 min, each `{minutes, resets_at, utilization_pct}` | `100 −` the **binding** (most spent) span | `model_split {opus, sonnet, reason}` |
| `codex` | `rolling` 10080 min with the rollout's `resets_at` | `100 − used_percent` | none — not a Claude seat |
| `pi-qwencloud` | `rolling` 10080 min (R-2026-09-06-20's week) resetting at `pi-hold.json`'s `held_until` (D-B95) | `UNKNOWN` with its reason | none |

`model_split` is UNKNOWN on every Claude row because the usage endpoint answers
`null` for `seven_day_opus` and `seven_day_sonnet` (MEASURED in the reader's own
cached response). The reason is in the cell. A zero there would be invented
utilization; the cells become numbers by themselves on the day the endpoint
starts answering, and nothing else has to change.

pi-qwencloud is the case where the two questions come apart. TL-17 leaves the
utilization unreadable and the row goes on refusing on it — `capacity.grade`
stays UNKNOWN, and the contract's reader goes on answering STOP
`observation_unusable` exactly as it did before this change (MEASURED with the
merged `tally-admit`: the same signal and reason with and without the new
cells). The RESET is stated by the provider itself, in the 429 the harvest
recorded, so it is read from that record rather than derived.

### A failed read keeps the last MEASURED reading

D-B92 rules that a reading under 45 seconds old is the same measurement — the
endpoint answers in whole percents. The feeder follows that through:

* the endpoint answered now → `grade MEASURED`, `reading_age_seconds 0`;
* the reader served its own cache → `MEASURED` under 45 s,
  `STALE-MEASURED` over it, with the age in the row either way;
* the read did not land at all (a timeout, an expired token, an endpoint
  error) → the last MEASURED reading this box retained is re-published as
  `STALE-MEASURED` with `reading_age_seconds`, `reading_observed_at`,
  `reading_source` and the failure's own `stale_reason`.

Two retained sources, and the newer wins: the row this feeder last published
(already in the contract's shape) and the reader's own
`.window-cache-<seat>.json`, whose directory the reader hard-codes and which
`TALLY_WINDOW_CACHE_DIR` names so a fixture can redirect it. Ages chain off
`reading_observed_at`, the instant the numbers were MEASURED, never off
publication, so re-publishing a re-publication cannot make a reading look
younger than it is. Only when nothing at all was retained does the row fall
back to UNKNOWN — a hole that says it is a hole.

### The UNKNOWN sentinel, and the one shape never written

Where a source is silent the cell is the string `UNKNOWN` with a reason beside
it. The kernel's reader reads that as **absent** and never as a refusal
(`crates/tally-kernel/src/window.rs` `is_absent`, `meter.rs`
`is_unknown_value`), so a row may say "I do not know this cell" and stay
readable: no field it refuses, no rename.

The one shape that would break that is a **declared** window whose reset is
unknown — the row asserts a shape and does not carry it, and the reader refuses
`meter_cell_unknown` on `window.resets_at`. MEASURED as a negative control with
the merged `tally-admit`: `STOP observation_unusable`, `refusal
meter_cell_unknown`, "declared window has no reset instant". So the feeder never
writes it. When `pi-hold.json` states no current reset the row publishes
`"window": "UNKNOWN"` with `window_reason` instead, which the reader reads as an
unknown window, and `tools/seat-rows-oracle.sh` goes RED naming the row — an
incomplete row is a fact to surface, not one to paper over.

### Three seats, one whitespace

`cc2.json` and `cc3.json` were missing for a reason with nothing to do with the
reader: systemd splits an unquoted `Environment=` value on whitespace into
separate assignments, so `Environment=TALLY_CLAUDE_SEATS=cc cc2 cc3` set the
variable to `cc` and discarded the rest. The declaration now writes
`cc,cc2,cc3`; the program reads either separator; and the home-profiles check
asserts that no feeder environment entry carries whitespace at all.

### Running CAP-1's oracle

```sh
bash tools/seat-rows-oracle.sh              # one feeder pass into a scratch dir,
                                            # then the assertions, then the flake check
bash tools/seat-rows-oracle.sh <meters-dir> # a directory a caller already fed
python3 tests/seat-feeder/test-seat-rows.py # the shape cases, no network, no cargo
```

The mutation: on a scratch copy of a fed meters directory, blank
`cc2.json`'s `window.primary.resets_at`. MEASURED — `FAIL cc2
window.primary.resets_at is "", not RFC 3339`, rc 1.

## State boundary

The only publication root is:

```
~/.local/state/tally-rewrite/meters/<row>.json
```

`~/.local/state/tally/meters` belongs to the pinned live estate and is not an
alias. The feeder refuses exit code 3 when its configured target is that tree,
any descendant, or a symlink resolving into it. The fixture exercises both the
direct and symlink cases against an isolated fake HOME and verifies its
sentinel byte-for-byte.

## Oracle and mutation

The fixture builds U-B10's merged `tally-admit` offline into a temporary target;
it does not duplicate the kernel's admission ladder. It seeds all five rows,
replays all three declared clocks for 60 policy ticks, and makes every service
occupy its full declared 20 seconds. It probes at service start, halfway
through the run, at policy-probe times, and immediately before publication.
The otherwise-GO Codex row goes through the real kernel at every probe;
UNKNOWN rows have their publication age checked directly. The conservative
maximum is 51 seconds on the first run. Both meter files and admission receipts
stay below the fixture's temporary HOME.

A credential-free wall-time check drives the real feeder with equal delayed
readers to prove concurrency, then staggered delayed readers to prove `cc` and
`cc2` appear while slower reads are still running. It also compares each file
mtime with its row stamp, catching a timestamp taken before the read.

Run the DOMINANT clauses from the repository root:

```sh
nix flake check --offline --no-build
nix eval --offline --json \
  '.#nixosConfigurations.coordinator.config.home-manager.users.tom.systemd.user.timers' \
  --apply 'timers: builtins.filter (name: builtins.match "tally-seat-feeder-.*" name != null) (builtins.attrNames timers)'
bash tools/feeder-fixture.sh
```

The middle command must print exactly:

```json
["tally-seat-feeder-claude","tally-seat-feeder-codex","tally-seat-feeder-pi-qwencloud"]
```

The original mutation removes the `tally-seat-feeder-codex.timer` line from
`tests/seat-feeder/timers.tsv`. Tick 0 remains seeded; at the first policy probe
the real kernel reads age 61000ms and answers SLOW `stale_observation`. D-B48's
regression mutation raises all periods back to 60 seconds: the first maximally
delayed firing is at 61 seconds, and the pre-fire real-kernel probe gives the
same RED. D-B54's publication mutation changes `as_completed(futures)` to
`list(as_completed(futures))`, recreating batch-at-end without changing any
input; the staggered wall-time run then turns RED because all three files land
together. The fixture exits 1 and names the failed property.
