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
| `tally-seat-feeder-claude.timer` | `bin/stamp-receipt.py window --seat …` | `cc.json`, `cc2.json`, `cc3.json` | Tom; MEASURED when the reader answers, otherwise fresh UNKNOWN with its reason |
| `tally-seat-feeder-codex.timer` | newest `rate_limits` record below `~/.codex/sessions/**/*.jsonl` | `codex.json` | `third-party`, by D-B6; readable by name and never proposed onto |
| `tally-seat-feeder-pi-qwencloud.timer` | no external read | `pi-qwencloud.json` | Tom; UNKNOWN with D-B17/TL-17 named in the row |

There are three pairs because the issue's DOMINANT acceptance and scope require
three. The Claude service is one sanctioned credential-reader invocation per
seat within one clock. It still publishes three independent rows: `cc` and
`cc2` retain distinct primary reset clocks and are never summed. The exact row
grouping is carried by each service's `X-TallyRows` field and asserted in the
flake check.

All services use `OnUnitActiveSec=30s`, `AccuracySec=1s`, and
`WantedBy=timers.target`. D-B48 makes the period at most half the kernel's
60-second staleness bound, so the worst legal timer gap is 31 seconds rather
than 61. The worker configuration evaluates with no feeder unit. The program
gives each external read at most 12 seconds, so all three Claude reads fit
inside the service's 50-second deadline; a read that cannot finish becomes
UNKNOWN instead of delaying the next tick.

## Source boundaries

The Claude path is the reader authorized by D-B5. The feeder invokes it and
consumes only its JSON result; it never opens a credential file itself and
drops the reader's stderr. When that reader returns its bounded cache, the
feeder writes a current UNKNOWN result naming the cached source timestamp.
Re-stamping old values as fresh MEASURED would manufacture headroom.

The Codex reader recursively opens only `.jsonl` files below
`~/.codex/sessions`. It takes `used_percent`, `window_minutes`, and `resets_at`
from the newest usable `rate_limits.primary` record. Missing any of the three
produces UNKNOWN. It skips symlinked files and directories, so a rollout-shaped
link cannot escape the sessions tree. It never names or opens
`~/.codex/auth.json`; the fixture places valid-looking rate-limit data behind
such a symlink and requires the result to stay UNKNOWN.

The Qwen Cloud writer has no source because TL-17 remains unset. Its row carries
`capacity.grade: UNKNOWN` and a reason naming TL-17 and D-B17. It deliberately
has no `window` cell: absence means unknown, whereas `{"kind":"none"}` would
claim that an allowance-backed seat is a non-spendable device.

Every row also carries the U-B10 fields already settled for the estate:
per-attempt output-token cap 100000, checkpoint grace 30 seconds, kill grace 10
seconds, and a context window where one is measured.

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
replays all three declared clocks for 60 policy ticks, and probes every row at
each clock's worst-case expiry (`nominal + AccuracySec`) before the feeder
writes. It also probes after every policy tick. The otherwise-GO Codex row goes
through the real kernel at every probe; UNKNOWN rows have their source age
checked directly. Both meter files and admission receipts stay below the
fixture's temporary HOME.

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
same RED. The fixture exits 1 and names the signal, reason, and age.
