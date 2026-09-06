# `util-01-sampler`, reconciled

**What this page is.** The record of how the two-commit `util-01-sampler` branch
reached `main`, what the reconciliation is checked by, and what stays red on
purpose afterwards. It is a page about git topology and two probe rows, not
about the sampler's contents — those are `home/util-sampler.nix`, the two
programs it names, and `/home/tom/research-methods/cards/UTIL-01.md`, which is
the specification this repository does not restate.

Issue: [mecattaf/dotfiles#320](https://github.com/mecattaf/dotfiles/issues/320).
PR: [#314](https://github.com/mecattaf/dotfiles/pull/314). It is the same motion
as [`l8-flash-reconcile.md`](l8-flash-reconcile.md), one lane later and one
order of magnitude smaller.

## The motion

Long-lived branches in this repository reach `main` by **merge**, not rebase and
not squash. `ad8a9119` — `herdr: merge herdr-clean-slate (11 commits) for
L8-FLASH` — is the pattern, and `l8-flash` followed it. `util-01-sampler`
follows it too, with the direction inverted: `main` is merged **into** the
branch, because PR #314 is the vehicle and its head is `util-01-sampler`. The
evaluator merges #314, and the branch's two commits reach `main` with their
history intact.

The reconciliation, pinned:

| | |
|---|---|
| forked at | `88c7c755` |
| commits | 2 — `34a613dc` (the units and the two programs), `981e8d01` (the adversarial-verify repairs) |
| `main` at the reconciliation | `ecc6a228` — `l8-flash` already reconciled (#319) |
| merge commit | `0cf536c7` |
| conflicts | none. `git merge-tree --write-tree origin/main util-01-sampler` exited 0 and named tree `55f94c3e` |

`981e8d01` is **carried, not squashed away**. It is the commit that repaired
three refutations from the adversarial verify — the frozen lease slice, the day
clipping in the box's own IANA zone, and the sampler's write guard — and the
digests the card locks are its digests, not round 1's.

## The one overlapping file

`home/home.nix`, and one line in it. Both branches add an entry to the same
`imports` list: `l8-flash` added `./harness-records.nix` and `./herdr.nix`, this
one adds `./util-sampler.nix`. No line is removed by either, so the resolution
is to keep all three in alphabetical order, which is what PR #314's own
"Overlap with the L8-FLASH branch" section said it would be and what git
produced without being asked:

```nix
  imports = [
    ./ai-memory.nix
    ./harness-records.nix
    ./herdr.nix
    ./nvim.nix
    ./paper.nix
    ./pi.nix
    ./piri.nix
    ./remote.nix
    ./ssh.nix
    ./tally.nix
    ./util-sampler.nix
    ./voxtype.nix
  ];
```

Nothing else in the branch touches a file `l8-flash` touched.

## What must not have moved

The unit's non-goal is **no change to the sampler's semantics**, and the
sharpest form of it is a pair of digests. `cards/UTIL-01.md` locks
`instrument_sha256` at arming and its `abort_on` makes a row written by an
instrument other than the locked one a CRASH — so a merge that moved either
program is not a merge whose rows can be graded at all.

| file | sha256, before and after |
|---|---|
| `home/dot_local/bin/util-sampler` | `cc76a8179c46e735d6005f3f2d92f137cff026d7c3658a27b89261778fa50ce6` |
| `home/dot_local/bin/util-row` | `1fdb80179595dc151af67e4ed2bc03e6a3bcf34685acb869b1cc9d9bcfa90906` |

Both are asserted at **evaluation** time by the flake check
`util-sampler-topology`, with `builtins.hashFile`, so they are inside the
DOMINANT gate rather than beside it. That check also pins what a badly resolved
merge would have dropped silently:

- `util-sampler.timer` and `util-row.timer` on the coordinator;
- `util-sampler.timer` on the worker and no `util-row.timer` there;
- `Persistent = false` on the sampler, `true` on the row writer. Not a style
  choice: a catch-up burst would write several samples carrying one instant,
  each a fabricated reading of a GPU nobody was watching, so a box that was off
  must show as **absent** samples. A row, by contrast, is a pure function of a
  sampler log that is already closed, so catching that up fabricates nothing;
- the `tally` derivation on the **coordinator** sampler's `PATH` and on no
  other — the worker has no tally daemon and no tally binary, and a `PATH` that
  claimed otherwise would be a lie about what that box can answer;
- the single tmpfiles rule `d %h/.local/state/tally/meters/util-sampler 0700 - - -`
  on both boxes.

## The two rows the probe gained

`home/dot_local/bin/l8-flash-probe` gains **exactly two** rows, both `[E]`
switch-evidence, both reading `FragmentPath`:

```
[E] util-sampler.timer declared (fragment in /nix/store)   both boxes
[E] util-row.timer declared (fragment in /nix/store)       coordinator only
```

A home-manager unit's fragment lives in `/nix/store` and is linked into
`~/.config/systemd/user`; a hand-written unit **is** the plain file there. So
`FragmentPath` is the one field that says which of the two won the name. Rule 9
is stricter for these two than for the mirror: neither has ever existed by hand,
there is no hand-written ancestor to lose the name to, and a fragment outside
the store can only mean somebody hand-installed one.

`is-active` is deliberately **not** checked. `OnBootSec=1min` and
`OnCalendar=*-*-* 00:05:00` make a box rebooted a minute ago and a box that has
never switched look identical through it, while `FragmentPath` separates them
the instant the unit exists.

**Both rows ship RED**, because nothing has switched yet. Pre-switch on the
coordinator the probe exits 1 with these two additional `FAIL` rows and the same
`PASS` rows it had before — which is the state issue #320 describes and the one
`tests/l8-flash-probe/test-util-timer-rows.sh` pins. A row that is red on the
day it is written is exactly the row nobody notices has stopped working, so that
test exercises them in every state, against a fake `systemctl` and a fake
`HOME`, asserting the verdict and not the wording:

| state | `util-sampler.timer` | `util-row.timer` |
|---|---|---|
| pre-switch, coordinator | FAIL | FAIL |
| declared, coordinator | PASS | PASS |
| hand-installed sampler | FAIL | PASS |
| worker, switched | PASS | SKIP |
| worker, pre-switch | FAIL | SKIP |

and it asserts the **count**: exactly two rows come from this section, so the
probe gains two FAILs and no more. It is wired into the flake as the check
`l8-flash-probe-util-rows`, beside `l8-flash-probe-row`.

## The oracle

```
bash tools/u-d17-util-01-oracle.sh
```

Twelve clauses, one line each with the argv that produced it. The design
decisions behind two of them are in [`../DECISIONS.md`](../DECISIONS.md); the
short version:

- **"PR #314 merged" is read exactly.** Clauses 1a–1c additionally read the
  topology off the *tree*: both commits are ancestors of `HEAD`, the branch is
  still two commits, and `main`'s own head at the reconciliation is an ancestor
  too — so the history was preserved by a merge. Clause 1d makes the exact `gh
  pr view 314 --json state` call the oracle names, and only `MERGED` passes.
  `OPEN`, `CLOSED`, an unavailable `gh`, or a failed lookup are all `FAIL`;
  ancestry is evidence, not a substitute for GitHub's state. Consequently the
  implementer's required self-run is red on clause 1d while the PR is open, and
  the evaluator's post-merge run is the first run that can satisfy the complete
  DOMINANT.
- **Clause 5 greps for conflict markers** because clause 4 cannot cover the
  mutation on its own. A marker in a `.nix` file is a syntax error and
  evaluation dies; a marker left in a shell program, a doc or a fixture parses
  fine and would ship. Measured: with a marker in `home/home.nix`, clauses 4 and
  5 fail; with the same marker in `l8-flash-probe`, clause 4 stays **green** and
  clauses 3b and 5 fail.

## What is still red, and why that is correct

Nothing is switched by this merge, on either box, and nothing here produces a
UTIL-01 row.

- The **two probe rows** stay FAIL until the coordinator switches (U-D19) and
  the worker switches (Tom's own act — `~/research-methods/DECISIONS.md` D-B15).
  Carried as `DEFERRED.md` DF-U-D17-1.
- The **first row** exists only after a full night of sampling on a switched
  box. The card's T1, T2 and T5 are graded then; nothing in this merge grades
  them.
- `tokens_in` / `tokens_out` are **UNKNOWN**, loudly and never `0`, because no
  serve on the estate is started with `--metrics`. That is
  [#312](https://github.com/mecattaf/dotfiles/issues/312), and it is why "how
  many tokens per week" stays a question after this merges. Carried as
  `DEFERRED.md` DF-U-D17-2.
- `worker-gpu`'s `lease_held` is **UNKNOWN, never false** until that pool
  exists ([#310](https://github.com/mecattaf/dotfiles/issues/310)), so every
  worker hour grades UNKNOWN. That is R-04's rule, not a gap in the instrument.
