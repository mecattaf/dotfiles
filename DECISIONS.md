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

2026-09-06 U-D12 (dotfiles#315): three implementation lines were open between
the issue's per-row wording and its DOMINANT/scope, and are fixed here.

(1) **The three declared timer+service pairs are the three named instruments,
not five independently clocked row files.** They are
`tally-seat-feeder-{claude,codex,pi-qwencloud}`. The Claude invocation writes
the `cc`, `cc2`, and `cc3` rows independently; separate JSON files and reset
clocks preserve D-B5's two-pool ruling. This follows the acceptance's exact
"three timers declared" and the scope's exact "three timer+service pairs";
`X-TallyRows` on each service makes the grouping evaluated data rather than a
comment.

(2) **The fixture's admit witness is `codex`, read by name through U-B10's real
`tally-admit`.** It is below the soft ceiling in the fixture, so removing its
timer makes the very next probe unambiguously SLOW `stale_observation`. An
UNKNOWN row is rejected by the meter decoder before a Decision carries age;
those rows' source timestamps are checked separately over the same 60 ticks.
The fixture refuses to substitute a second admission implementation.

(3) **A source timestamp remains the observation timestamp.** In particular,
`stamp-receipt.py window` may return its bounded cache during a 429; the feeder
turns that into a current UNKNOWN read naming the cached source time instead of
re-labelling old numbers as fresh MEASURED. A
Codex `rate_limits` record missing any of `used_percent`, `window_minutes`, or
`resets_at` becomes a fresh UNKNOWN row. `pi-qwencloud` declares no `window`
cell at all: absent means UNKNOWN, while `kind: none` would falsely describe a
non-spendable device.
