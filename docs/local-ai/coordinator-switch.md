# The coordinator switch — P05's order, and the probes that grade it

**Unit:** U-D19 DF-SWITCH · **issue:** [dotfiles#322](https://github.com/mecattaf/dotfiles/issues/322) ·
**files:** [`tools/u-d19-switch-oracle.sh`](../../tools/u-d19-switch-oracle.sh),
[`tools/u-d19-worker-negative-control.sh`](../../tools/u-d19-worker-negative-control.sh),
[`tools/u-d19-switch-baseline.env`](../../tools/u-d19-switch-baseline.env),
the `RemainAfterExit` key in [`home/tally-uplink.nix`](../../home/tally-uplink.nix) and its
assertion in [`flake.nix`](../../flake.nix) ·
**spec:** handoff DoD F, `TALLY-SPEC-2026-09-06.md` §7 amendment 3 and 7 ·
**rulings:** `~/research-methods/DECISIONS.md` D-B15 (the coordinator switches, the worker's stays a TOM LINE),
D-B66 (U-D18's post-switch clause is this unit's post-condition),
D-B98 (`util-row.service` was already failed before this switch),
D-B99 (this unit's branch, and why it is not `main`) ·
**exemplar:** `~/research-methods/receipts/L8-FLASH/PR-BODY.md` SWITCH WALKTHROUGH.

---

## 1. What this unit is, in one sentence

It is an **act**, not a declaration: the one `sudo nixos-rebuild switch --flake
.#coordinator` that installs everything lane D declared — U-D13's
`tally-kernel.service` on the system bus, U-D14's `tally-uplink.service` and
U-D18's `tally-filler.timer` and U-D12's three seat-feeder timers on tom's —
plus the probes that make the act *evidence* rather than a claim.

Six deferrals across four earlier units all say the same sentence — *"only a
switch installs a declared unit, and this unit switches nothing"* — and name
this one as the actor: `DF-U-D12-1`, `DF-U-D13-1`, `DF-U-D14-1`, `DF-U-D15-1`,
`DF-U-D16-2`, `DF-U-D17-1`, `DF-U-D18-1`.

## 2. P05's order, and why the order is load-bearing

```
1  nix flake check                        FULL, not --offline --no-build
2  sudo nixos-rebuild switch --flake .#coordinator
3  the probes: units active, fragments in the store, timers armed,
   llama-swap untouched, the chain growing
4  the negative control: the same probes on the UNSWITCHED worker box
```

**Why the full check and not the targeted one.** Every other unit in this suite
verifies with `nix flake check --offline --no-build`, which proves the tree
*evaluates*. The full form **builds every check derivation**, and this unit is
the first in the suite to run it. A switch taken before that gate is a switch
taken on an unbuilt closure. It is also, as the P05 walkthrough says, *"the first
networked nix run"* — substitution fills the check closure.

**It found a real red on the first try**, and the red was in a *test*, not in
the estate: `checks.x86_64-linux.l8-flash-probe-util-rows` read **6/10** while
`bash tests/l8-flash-probe/test-util-timer-rows.sh` on the box read **10/10**.
The test writes a fake `systemctl` onto `PATH` and gave it the literal shebang
`#!/usr/bin/env bash`; a nix build sandbox has **no `/usr/bin/env`**, so inside
the derivation every fake-systemctl call failed and `FragmentPath` came back
empty — flipping exactly the four `-> PASS` cases, the ones that need the fake
to actually answer. The shebang is now the running bash resolved at write time.
This is the class of bug only the full gate can see, which is the whole reason
the card asks for it.

**Why the switch is taken from this worktree and that is safe.** `home/home.nix`
anchors every raw dotfile at a hardcoded `~/mecattaf/dotfiles` (issue #313), not
at the flake source a switch is taken from, so a switch from a worktree whose
tree differs from that checkout would deliver the store half and silently drop
the raw half. It does not differ: D-B99 records that this branch was cut from
`main` at launch and is byte-identical to it, and `/home/tom/mecattaf/dotfiles`
stands on the same commit. Measured before switching, and re-measurable:
`git -C /home/tom/mecattaf/dotfiles rev-parse HEAD` equals this branch's base.

## 3. `active` for a `Type=oneshot` — the one code line this unit adds

`tally-uplink.service` is a **oneshot** with `wakes = 1`: it probes the door,
pulls proposals, executes what was admitted, mirrors the chain, re-arms, and
**exits**. Under the bare oneshot systemd erases that wake's outcome the instant
it ends — a successful wake and a wake that never happened both read `inactive`.
The card grades this switch on

```
systemctl is-active tally-kernel.service tally-uplink.service → active active
```

which under the bare oneshot is unreachable **by construction**: not "not yet
true", but never true for longer than the milliseconds of one wake.

So `home/tally-uplink.nix` adds one key — `Service.RemainAfterExit = true` —
systemd's own idiom for a job whose result outlives its process. `active` now
*means* "the last wake of this box's uplink succeeded"; a failed wake stays
`failed` and names its error. That is strictly more information than the bare
oneshot, and it turns the card's clause into a measurement instead of a race.

**It is not a schedule, and `DF-U-D14-4` is untouched.** No timer, no `Install`
section, no `WantedBy`; nothing in this repository fires the unit. `flake.nix`'s
`tally-uplink-topology` now asserts the new key **immediately beside** the
standing `assert !(unit ? Install)`, so the pair reads as what it is: the
result survives the wake, and nothing wakes it. The first wake is taken by the
oracle's clause C2; every later wake is whatever spec §2.2b's wake mechanism
becomes.

## 4. Two clauses that do not match the card's letter, and why each is stronger

**`tally-seat-feeder-cc.timer` does not exist and never did.** The card was
written before U-D12 delivered. U-D12's own DOMINANT was *"nix eval of the
coordinator config shows the **three** timers declared"*, and the three are named
for the **instrument**, not the row: one Claude reader writes the `cc`, `cc2` and
`cc3` rows on one tick (this repository's `DECISIONS.md`, U-D12 line (1); D-B5
keeps `cc` and `cc2` two pools). So the oracle does not match the string. It
finds the listed `tally-seat-feeder-*.timer` whose service declares the `cc` row
in its `X-TallyRows` key and requires **that** timer to be listed — which is what
the clause means, and is stronger than a name match, because a rename that
dropped the `cc` row would still be RED. All three instruments are asserted
besides, since the issue title says *"the feeders' timers listed"*.

**`systemctl --user --failed` is not required to be empty.** D-B98: one user
unit was already failed **before** this switch — `util-row.service` (UTIL-01,
dotfiles#329), on its own closed-day idempotence guard. It is not this suite's,
it writes branch (a)'s state dir which this run never touches, and
`reset-failed` would only clear the evidence. The clause is therefore measured
as *"the switch **added** no failed unit"*, against the name recorded in
`tools/u-d19-switch-baseline.env`.

## 5. The baseline is a committed file, not a value the oracle captures

The card's clause is *"llama-swap.service still active and never restarted
(`systemctl show -p ActiveEnterTimestamp` unchanged)"*. A baseline captured at
the oracle's own start would be worthless — it would be captured *after* any
restart a previous run caused. So it is
[`tools/u-d19-switch-baseline.env`](../../tools/u-d19-switch-baseline.env),
written once before the first switch and read by clause F, which asserts **three
independent readings** rather than one: the entry instant, the `MainPID`, and
`NRestarts`. `ActiveEnterTimestamp` alone would not notice a stop-and-start
inside the same second.

MEASURED before switching, so the clause could not have been satisfied by luck:
the new generation's `etc/systemd/system/llama-swap.service` is **byte-identical**
to the running one, so `nixos-rebuild switch` has no reason to restart it. The
three units that do change are `tally-kernel.service` (new),
`home-manager-tom.service` and `systemd-tmpfiles-resetup.service`.

## 6. The negative control — the card's mutation hint

> *not a code mutation: the negative control is the probe on the worker box,
> which must report the units absent (unswitched)*

`bash tools/u-d19-worker-negative-control.sh` is that probe, and it is a
**measurement, not an edit**. If the switch's post-conditions were also true of a
box that was never switched, they would be evidence of nothing. The worker is
exactly that box by ruling: D-B15 keeps its switch a TOM LINE. The script exits
0 when every unit the coordinator's oracle finds ACTIVE is ABSENT there —
`tally-kernel.service` and `tally-uplink.service` with empty `FragmentPath`,
none of the four timers listed, no rewrite ledger — **and** when this
repository's rendered *worker* profile declares none of the four, so the absence
is by construction and not merely by a switch not yet taken.

It is **read-only over ssh** with `BatchMode`, by the card's own non-goal *"the
worker box untouched"*: nothing is started, stopped, switched, built or written
there.

## 6b. What the switch could not turn green, measured to the line

Two clauses of the card's own oracle read `[F]`, and they are one blocker twice:
`tally-uplink.service` is `failed`, and `ledger.jsonl` does not grow across a
wake.

```
uplink: replay from last_seq 0: 0 of 0 mirrored records owed
uplink: SocketError: kernel refused admit: exec_recovery_malformed
tally-uplink.service: Main process exited, code=exited, status=1/FAILURE
```

```
$ tally-kernel call --socket S --verb admit --body '{"row":"cc","request":{}}'
{"reply":"refusal","body":{"code":"exec_recovery_malformed",
 "detail":"cannot recover held lease none: its exec_started row is malformed:
           no kernel row spec for \"cc\""}}
$ … --body '{"row":"gpu-coordinator","request":{}}'  -> {"signal":"STOP","reason":"utilization_at_stop"}
$ … --body '{"row":"mechanical","request":{}}'       -> {"signal":"GO","reason":"within_headroom"}
```

- the uplink's `probe()` is an `admit` with **no `taskId`**, taken over **every**
  row of its rows file, in file order (`tally-ts-sdk src/uplink.mjs:88-103`,
  `src/socket.mjs:105-118`);
- the kernel's `admit` runs `consider()` → `stamp_row(row)`, which refuses
  `exec_recovery_malformed` for a row outside its own `--rows` table
  (`tally crates/tally-kernel/src/exec.rs:1340-1350`);
- this estate's kernel is configured — **correctly** — with only the three
  `owner: kernel` rows, because `RowWriter::stamp` *writes*
  `<meters>/<row>.json` with `"owner":"kernel"`, so giving it the seat rows
  would have it overwrite what U-D12's feeders publish and destroy D-B5's two
  pools.

`docs/rows.md`'s first row is `cc`, so the first probe of every wake throws. The
repository's only two levers are the kernel's `--rows` (must stay the owned
rows) and the uplink's `--rows` (must stay the estate's nine, asserted by
`tally-uplink-topology`), and neither is a fix. Filed as
[mecattaf/tally#50](https://github.com/mecattaf/tally/issues/50) and
[mecattaf/tally-ts-sdk#105](https://github.com/mecattaf/tally-ts-sdk/issues/105);
carried as `DF-U-D19-1` and `DF-U-D19-2`. Neither upstream `main` carries a fix
today (MEASURED 2026-09-07: `add5dddb`, `f817f86d`), so a pin bump would not help.

**They stay hard `[F]`s and the oracle exits 1.** The card asks for `active`,
the box says `failed`, and an author who converted his own red clause into a
`NOTE` would be grading his own oracle. The chain *is* being written — the file
exists carrying `admission_transition` records from probes on the rows the
kernel owns — so what is missing is the estate's own traffic, and manufacturing
rows by hand to move the number would be the oracle writing the evidence it
then reads.

## 7. The non-goals, as the oracle enforces them

| non-goal | how it is asserted |
|---|---|
| never reboot | nothing in either script reboots; the generation is switched, and clause B prints the new one beside the baseline's |
| never restart llama-swap | clause F, three readings against a committed baseline — and the unit file was measured byte-identical before the act |
| the NAS untouched | the switch attribute is `#coordinator`; no NAS host, path or ssh target appears in either script |
| the worker box untouched | clause H3 evaluates the *worker* profile and requires it to declare none of the four units; the negative control's only verbs are `is-active`, `show -p` and `list-timers` |
| branch (a)'s live estate untouched | every path is under `~/.local/state/tally-rewrite/`; clause H4 records that `tally-daemon.service` is still running; nothing writes `~/.local/state/tally/` or its `meters/` |
| no credential read or printed | the lake token is named as a path by the unit and never opened by either script |

## 8. Running it

```
bash tools/u-d19-switch-oracle.sh            # the DOMINANT act and its probes
bash tools/u-d19-worker-negative-control.sh  # the mutation hint, read-only
```

The oracle is **idempotent**: re-running it re-takes the switch (a no-op
generation), re-wakes the uplink with `restart` rather than `start` — `start` on
an already-`active` `RemainAfterExit` oneshot would be a no-op and clause G
could not move — and re-reads the same committed baseline.
