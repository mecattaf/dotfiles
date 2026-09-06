# DECISIONS

2026-09-06 orchestrator B: merged U-D5, U-D8 to main under the handoff's merge authority; gate ["bash", "/tmp/claude-1000/-home-tom/f9d7af0b-e4f1-476b-b2b2-5c58c365fdaa/scratchpad/gate.sh"] = nix flake check --offline --no-build + tests/local-models-sync/test-prune-guard.sh (LOCAL_MODELS_PRUNE_BIN) + claude-capacity case count vs docs/local-ai/claude-capacity.md; rc 0; receipts under /home/tom/research-methods/receipts/FACTORY-2026-09-06/.

2026-09-06 U-D16 (dotfiles#319): the manifest's DOMINANT oracle for the l8-flash
reconciliation is prose naming four clauses, so it is mechanized as ONE argv —
`bash tools/u-d16-l8-flash-oracle.sh` — and the two lines the prose left open
are decided here.

(1) **Ancestry is checked against `HEAD`, not against the local `main` ref, and
the branch head is pinned as a sha rather than resolved from the `l8-flash`
ref.** The oracle is re-run by the evaluator from a fresh worktree; a ref is
local to a clone and can be moved, and "after the PR merges" means the commit
the evaluator stands on. `e549ba911e8d8c9ff1c19b4fa9b0b6df45244f7f` is what the
reconciliation is about.

(2) **The oracle gates the repository half of "the hand-written
claude-transcript-mirror units are removed" and reports the shell half without
gating on it.** The removal is Tom's own act by `~/sept7/scopes/clean-dotfiles.md:171`
§6 and is step 4 of the P05 walkthrough, sequenced inside U-D19 (D-B15: the
coordinator switches under U-D19, the worker's switch stays a TOM LINE); until
that switch the hand-written pair is the only working mirror, so an oracle that
went red while the files existed would be demanding this unit break the mirror.
Gated: the declaration on `main`, no plain unit file tracked, and the
`l8-flash-probe` row asserted in the flake in four states. Reported as `NOTE`:
the files' state on this box. Carried as `DEFERRED.md` DF-U-D16-1.

Also decided: content closure (`tools/u-d16/`) is part of the oracle, because
ancestry alone stays green under `git revert` of any of the 30 commits, which is
one of the two readings of the unit's `mutation_hint`. Both readings measured
RED at `020b2ad1`.

2026-09-06 U-D17 (dotfiles#320): the manifest's DOMINANT oracle for the
`util-01-sampler` reconciliation is `PR #314 merged (gh pr view 314 --json state
== MERGED); nix flake check --offline --no-build → 0`. It is mechanized as ONE
argv — `bash tools/u-d17-util-01-oracle.sh` — following U-D16's entry above, and
the four lines the prose left open are decided here.

(1) **`main` is merged INTO `util-01-sampler`, not the other way round, and no
new branch is cut.** The issue's own completion condition is `gh pr view 314`
reading `MERGED`, and PR #314's head is `util-01-sampler`; a new branch off
`main` that merged the two commits would land the same content and leave #314
OPEN forever, failing the oracle it was written for. `~/sept7/scopes/clean-dotfiles.md:202`
says "a new branch off `l8-flash`" because it was written while `l8-flash` was
still unmerged; `l8-flash` reached `main` at `ecc6a228` under U-D16, so the base
it names and `main` are now the same tree. The motion is `ad8a9119`'s either
way: a branch merged into the one switch, its commit count and issues in the
message, history preserved — `981e8d01` is carried, not squashed. Merge
authority: `~/research-methods/DECISIONS.md` D-B12.

(2) **"PR #314 merged" gates on the TREE and reads `gh` beside it.** The
evaluator re-runs the DOMINANT *before* merging — merging is its own act on PASS
— so an oracle that demanded `MERGED` could never pass and no unit of this shape
could ever be graded. Clauses 1a–1c therefore gate on what "merged" means for
this repository, in the form U-D16 decided (ancestry against `HEAD`, never the
local `main` ref; the commits pinned as shas, never resolved from the
`util-01-sampler` ref): `34a613dc` and `981e8d01` are ancestors of `HEAD`, the
branch is still two commits, and `main`'s head at the reconciliation
(`ecc6a228`) is an ancestor too — so it was a merge and not a fast-forward.
Clause 1d makes the `gh` call the oracle string names: `MERGED` passes, `OPEN`
passes only while the PR still points head `util-01-sampler` at base `main`
(a retargeted or force-pushed OPEN PR is not one whose merge would land these
commits), `CLOSED` fails always, and `gh` unable to answer is `NOT VERIFIED`
that does not gate — 1a–1c are the same fact offline.

(3) **A conflict-marker grep (clause 5) is part of the oracle**, because the
flake check alone cannot see the whole mutation. MEASURED at `120812a7`: a
marker in `home/home.nix` turns clauses 4 and 5 red; the same marker in
`home/dot_local/bin/l8-flash-probe` leaves clause 4 **green** — nix never parses
that file — and turns 3b and 5 red. Two readings of the same
`mutation_hint`, both RED.

(4) **The two new `l8-flash-probe` rows check `FragmentPath` and nothing else,
and there are exactly two.** `is-active` is not checked: `OnBootSec=1min` and
`OnCalendar=*-*-* 00:05:00` make a box rebooted a minute ago indistinguishable
from a box that never switched, while `FragmentPath` separates them the instant
the unit exists. The count is the issue's own requirement — pre-switch the probe
must exit 1 with exactly these two additional FAIL rows and the same PASS rows
as before — so it is asserted in
`tests/l8-flash-probe/test-util-timer-rows.sh` rather than left to reading.
Both rows ship RED and are carried as `DEFERRED.md` DF-U-D17-1.

Also decided: the eval-time flake check `util-sampler-topology` is part of the
gate rather than beside it, because `nix flake check --offline --no-build` on
its own only proves the merged tree EVALUATES and would stay green through a
resolution that dropped `./util-sampler.nix` from `home/home.nix`'s imports. It
asserts the unit's non-goal as bytes — `builtins.hashFile` over both programs
against `cards/UTIL-01.md` `instrument_sha256` — plus the timers per box,
`Persistent` on each, `tally` on the coordinator sampler's PATH alone, and the
one tmpfiles rule.
