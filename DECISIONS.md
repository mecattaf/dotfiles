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
