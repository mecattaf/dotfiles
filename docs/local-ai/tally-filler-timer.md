# The filler lane's clock — `tally-filler.timer` on the coordinator

**Unit:** U-D18 DF-FILLER-TIMER · **issue:** [dotfiles#321](https://github.com/mecattaf/dotfiles/issues/321) ·
**files:** [`home/tally-filler.nix`](../../home/tally-filler.nix),
the `tally-filler-topology` check in [`flake.nix`](../../flake.nix),
[`tools/u-d18-filler-timer-oracle.sh`](../../tools/u-d18-filler-timer-oracle.sh) ·
**spec:** `TALLY-SPEC-2026-09-06.md` §4.4 (the filler-lane contract), §5.3 item 4, handoff DoD F ·
**rulings:** `~/research-methods/DECISIONS.md` D-B10 (the two fillers alternate), D-B12 (the register stays local), D-B15 (the switch), D-U-E1LOOP-7 (`--all` is what this timer calls), D-B66 (the post-switch clause is U-D19's).

---

## 1. What it is, in one sentence

One systemd **user** timer on the coordinator that wakes **one E1 replay pass** every
five minutes. It is a clock and nothing else: the pass proposes, and the kernel's
admission on `gpu-coordinator` decides. The card's own sentence — *"the timer only
wakes the uplink's filler pass, the kernel admits"* — is the whole division of labour.

```
tally-filler.timer  ──OnUnitActiveSec=5min──▶  tally-filler.service  (Type=oneshot, Nice=19)
                                                    │
                                                    └─ bash %h/research-methods/tools/e1-loop.sh --all
```

## 2. What the "filler verb" is, and why it is not a verb of `apps/uplink`

The card says *"the service calling the uplink's filler verb"*. The lake's uplink, at
the rev this repository pins (`tally-lake` = `tally-ts-sdk` `a233c30`), has **no such
verb**: its CLI offers `--parse-only`, `--replay-only`, `--drain-only` and the default
wake, and the string `filler` does not occur anywhere in that input (MEASURED
2026-09-07, `grep -rl filler <store path>` → no hit).

The lane's verb is named instead by a captured ruling, `~/research-methods/DECISIONS.md`
**D-U-E1LOOP-7**:

> `--all` is the lane's verb over the whole eligible population and **is what U-D18's timer calls**.

So `ExecStart` is `bash %h/research-methods/tools/e1-loop.sh --all`. That script is the
one that walks `cards/e1-sample.tsv`'s eligible rungs one item at a time, locks the
prior before dispatch, builds the frontier-blind worktree, waits for the GPU, dispatches
through the kit's cap, has the lake's mechanical evaluator rerun the frontier argv, banks
a §2.3 receipt, appends the results row and runs `register calibrate`. **None of that is
re-implemented here.** MEASURED 2026-09-07: the lane's population is 21 ready rungs
(24 eligible, 15 not eligible).

## 3. Why the verb is an out-of-store path

The register (`~/research-methods`) is **local by ruling** — D-B12, *"the register stays
local"* — so it is not, and must not become, a flake input of this repository. Naming its
script through `%h` is the same seam [`home/seat-feeder.nix`](../../home/seat-feeder.nix)
already uses for the one sanctioned credential reader
(`TALLY_STAMP_RECEIPT=%h/research-methods/bin/stamp-receipt.py`): the estate points at the
register; the register is never copied into the store.

A missing script is therefore a **legible failure** — the unit exits non-zero naming the
path — and deliberately **not** a `ConditionPathExists=`, which would turn an absent lane
into a silent no-op. That is the same rule this repository already applies to a missing
state directory (dotfiles#292).

## 4. The cadence, and how the two fillers alternate (D-B10)

D-B10 rules that *"the two fillers (E1 replay, academic drain) **alternate** by
round-robin on `gpu-coordinator`"*. Two mechanisms carry that, and only one of them is a
clock:

**1. Cadence — an equality, not a number.** This timer's period is
`tally-drain.timer`'s **own** declared period, spelled in the drain's own units so the two
are the same *string*:

| unit | `OnUnitActiveSec` | source |
|---|---|---|
| `tally-drain.timer` | `5min` | upstream `tally`'s home-manager module (MEASURED in the rendered coordinator config **and** in the installed `~/.config/systemd/user/tally-drain.timer`, 2026-09-07) |
| `tally-filler.timer` | `5min` | `home/tally-filler.nix` |

`flake.nix`'s `tally-filler-topology` check asserts
`timer.Timer.OnUnitActiveSec == drain.Timer.OnUnitActiveSec`. Asserting the **equality**
rather than the literal `"5min"` is the point: if the upstream drain's cadence moves, the
check goes red and someone re-reads D-B10, instead of the round-robin quietly ending.

**2. Serialisation on the GPU — the lane's gate, not the clock.** Cadence alone cannot
keep two tenants off one device. What does is `tools/e1-loop.sh`'s own step 4: it waits
for llama-swap's `/running` to be **empty** before it dispatches an item, and never issues
a second concurrent model request (E1-LOOP's own non-goal). Whoever holds the model
finishes; the other takes the next turn. **This unit does not duplicate that gate and
could not enforce it** — which is exactly why the non-goal below is satisfiable.

### An honest note on which unit "the academic drain" is

Spec §2.4 names `tally-drain.timer` as the GPU row's unleased tenant, *"every 5 min,
`Python-urllib/3.14`, MEASURED"*. Two things measured on this box on 2026-09-07 are worth
writing down rather than smoothing over:

- `tally-drain.timer`'s cadence **is** five minutes, and its service runs
  `tally --socket /run/user/1000/tally/tally.sock daemon drain` — the tally daemon's
  producer-event drain.
- llama-swap's only `Python-urllib/3.14` callers in a 40-minute window were **per-minute**
  `GET /health` + `GET /running` probes (the util-sampler's shape), not a five-minute
  tenant.

So the unit this timer alternates against is the drain **by name and by declared
cadence** — the unit D-B10 names — and nothing here depends on resolving which process
authored §2.4's user-agent observation. What actually keeps the GPU single-tenant is
mechanism 2, not the cadence.

## 5. The non-goals, as bytes

> the timer never calls llama-swap directly; never unloads

The `tally-filler-topology` check reads `ExecStart` **and** `Environment` as one string
and asserts that `llama`, `9292` and `unload` occur in neither, so a value cannot hide in
the environment block. In particular the module deliberately does **not** set
`E1_PROBE_URL`: the lane's `/running` probe stays the lane's own default, so the endpoint
is not even a string this unit carries.

Also asserted, in both directions: no system-bus twin, nothing on the worker, no
`~/.local/state` path (the lane's whole state is the register's git tree — its receipts,
its `cards/e1-results.tsv` row, its kept replay worktree), no `--dry-run` in the installed
unit, no `RemainAfterExit` (every wake really starts the lane again), and
`home/tally-uplink.nix` **still with no `Install` section** — `DF-U-D14-4` is discharged
by a timer of the filler's own, never by installing the uplink.

## 6. Why `Nice=19`, `IOSchedulingClass=idle` and `TimeoutStartSec=infinity`

The filler is the **lowest level** (§4.4.1), so it must never compete with the work it
fills around. Niceness is *not* the preemption mechanism — preemption is the kernel
answering `NotYet {preempt}` and the holder yielding its lease within one item — but a
filler that fought a level-1 worker for the CPU would be wrong even so.

`TimeoutStartSec=infinity` is the one systemd default this unit overrides, and it is
deliberate. §4.4.2 bounds an **item** by `runtime_cap_seconds`, which the lane enforces
itself, per item. A manager-side deadline over the whole pass would `SIGTERM` the unit
mid-item and cost more than the one item a preemption is allowed to cost. What stops a
cold-load crash loop is the lane's own `abort_on.consecutive_crash: 2` (§4.4.6), not a
clock. For the same reason there is no `Restart=`: a failed pass is a gap the next wake
closes.

## 7. Running the oracle

```bash
env -i PATH=/run/current-system/sw/bin:/usr/bin:/bin HOME=/home/tom \
  XDG_RUNTIME_DIR=/run/user/1000 \
  bash tools/u-d18-filler-timer-oracle.sh
```

Six clauses, each printing its MEASURED value:

| clause | what it proves |
|---|---|
| **A** | `nix flake check --offline --no-build` → 0 |
| **B** | `nix eval` shows `tally-filler.timer` declared on the coordinator, `OnUnitActiveSec` **set**, and the service calling `e1-loop.sh --all` |
| **C** | D-B10's round-robin as an equality against `tally-drain.timer`'s own declared period |
| **D** | the non-goals as bytes, plus no system-bus twin, nothing on the worker, no uplink `Install` |
| **E** | **the run proof** (below) |
| **F** | nothing switched, nothing hand-installed (Rule 9), nothing left behind |

`jq` is *not* on the bare `/run/current-system/sw/bin` PATH (MEASURED), so the script uses
`nix eval --raw --apply` throughout and never reaches for it.

### Clause E — proving the timer RUNS before any switch

Only a switch installs a declared unit, and this unit switches nothing. The card's
post-switch clause — *"after the switch `systemctl --user list-timers` names
`tally-filler.timer`"* — belongs to **U-D19**, which is the only unit in the manifest
whose oracle runs `nixos-rebuild switch`; U-D19 `dependsOn` U-D18, so that clause could
not be true at this unit's own evaluation without inverting the graph (the orchestrator's
D-B66 note, same class as D-B33).

What *can* be proven without a switch is spec §2.4/§5.2's own form for a timer clause
before TL-15 — the form U-D12's feeders are written against: **the launcher is a shell.**
The check arms a **transient** timer with `systemd-run --user --on-calendar` running the
module's own rendered argv, watches `systemctl --user list-timers` name it, waits for
`LastTriggerUSec` to move, records `launcher: shell`, and reports without failing.

The probe differs from the unit in exactly two ways, both printed and both asserted
against the installed unit:

1. it is named **`tally-filler-probe`**, never `tally-filler` — a transient unit under the
   real name would shadow what U-D19's switch installs, and Rule 9 bars a hand-installed
   stand-in;
2. its argv is the unit's argv **with `--dry-run` appended**, so the pass resolves the
   population and dispatches nothing. A probe that made a real model request would be this
   oracle spending GPU time to prove a clock works, and would break the lane's own "never
   two concurrent model requests".

It also sets `RemainAfterExit` so the exit status is still readable after it fires, and it
stops both transient units on exit and then proves their `LoadState`.

MEASURED 2026-09-07 on the coordinator: the probe armed, `list-timers` named
`tally-filler-probe.timer`, it fired, and the pass it started exited **0** — `launcher:
shell`, `ActiveState=active Result=success ExecMainStatus=0`.

### The mutation

> remove the timer → the eval is false

Drop `./tally-filler.nix` from `home/home.nix`. MEASURED: the card's own eval
(`… .systemd.user.timers ? tally-filler`) prints exactly **`false`**, `nix flake check
--offline --no-build` fails on `tally-filler-topology`'s first assert (rc 1), and the
oracle script reports FAIL (rc 1). The membership form is deliberate — it makes the hint's
own word `false` the printed value rather than an attribute-missing error.

## 8. What is deferred

| row | what |
|---|---|
| `DF-U-D18-1` | the switch that installs `tally-filler.timer` — U-D19's, by D-B15 |
| `DF-U-D18-2` | the anti-starvation number (TL-10) and D-B10's age-based promotion — the release station's, not a clock's |
| `DF-U-D18-3` | moving the academic drain onto a lease over the socket, so the two fillers alternate under the kernel rather than beside it — U-D11/TL-15 |

See [`DEFERRED.md`](../../DEFERRED.md) for the full rows.
