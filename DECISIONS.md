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

(3) **D-B54 supersedes the original source-time line: the row observation is
stamped at publication, after the read.** A reader's timestamp remains source
metadata only. In particular, `stamp-receipt.py window` may return its bounded
cache during a 429; the feeder turns that into a current UNKNOWN read naming
the cached source time instead of re-labelling old numbers as fresh MEASURED. A
Codex `rate_limits` record missing any of `used_percent`, `window_minutes`, or
`resets_at` becomes a fresh UNKNOWN row. `pi-qwencloud` declares no `window`
cell at all: absent means UNKNOWN, while `kind: none` would falsely describe a
non-spendable device.

(4) **D-B54's duration term is an enforced envelope, not a nominal runtime.**
The three 12-second Claude reads run concurrently and publish independently;
the unit fails at 20 seconds. With the 30-second period and one-second timer
accuracy, the worst permitted age is `30 + 1 + 20 = 51 < 60` seconds. The
fixture advances services through that full duration and admits during runs.

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

(2) **`gh pr view 314 --json state == MERGED` is literal and cannot be
substituted by tree ancestry.** The issue says the generation-4 DOMINANT is
byte-exact. Clause 1d therefore passes only on `MERGED`; `OPEN`, `CLOSED`, an
unavailable `gh`, and a failed lookup all fail. Clauses 1a–1c remain additional
topology checks in the form U-D16 decided (ancestry against `HEAD`, never the
local `main` ref; commits pinned as shas): `34a613dc` and `981e8d01` must be
ancestors, the range must still contain exactly those two commits, and main at
the reconciliation (`ecc6a228`) must also be an ancestor. They establish the
history-preserving merge but do not stand in for GitHub's state. Because this
unit is expressly barred from merging its own PR, the implementer's required
DOMINANT run is expected to be red on clause 1d; the complete oracle can first
turn green on the evaluator's post-merge run.

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

2026-09-06 U-D15 (dotfiles#318): the `herdr-kitten` input moves BOTH its rev and
its URL form — `git+file:///home/tom/mecattaf/herdr-kitten?rev=41a6de5` becomes
`github:mecattaf/herdr-kitten/ccc16393cc35e2cce2b8cd9a55718b3c84849a8f` — and
three lines are decided here.

(1) **The `github:` form is taken, not deferred, because the Tom line that
barred it has been TAKEN and recorded.** The first attempt at this unit
(`receipt-parked-tomline9.json`, verdict STOPPED, branch head `25bf1dc9`)
moved only the rev and deferred the URL form behind the herdr-kitten survey's
**Q-7** — *"The repo is PRIVATE by standing wall. No executor flips
visibility"* — after measuring `HTTP 404` on the `github:` URL and
`{"isPrivate":true}` on the repo. That bar is now spent by
`~/research-methods/RULINGS.md` **R-2026-09-06-22** *(Tom's line, 2026-09-06
evening: "herdr kitten goes public is fine")*: `gh repo edit
mecattaf/herdr-kitten --visibility public` was performed by the planning
session at 20:31Z on that line, and the ruling names this unit — *"U-D15
(dotfiles PR #324, the `github:` input) resumes with no Tom line left on it."*
No executor of this unit ran any visibility command. RE-MEASURED 2026-09-06T22:05Z on
the coordinator: `gh repo view mecattaf/herdr-kitten --json isPrivate,visibility`
→ `{"isPrivate":false,"visibility":"PUBLIC"}`; `gh api repos/mecattaf/herdr-kitten`
→ `updated_at 2026-09-06T20:31:56Z`, i.e. the ruling's own timestamp; and
`nix flake metadata github:mecattaf/herdr-kitten/ccc16393…` resolves, unpacks,
and reports narHash `sha256-X5b1Fi6ObCI5xHPpEXTL8k1FbWO5JZeBnqMYAfG6jVU=` —
byte-identical to what `nix flake metadata --offline
'git+file:///home/tom/mecattaf/herdr-kitten?rev=ccc16393…'` reports for the
local checkout, so the fetcher changed and the object did not. Deferring a form
whose only blocker a Tom line has already cleared would have shipped a flake
that evaluates on exactly one box while reporting itself green, so the flip is
taken and the earlier deferral withdrawn.

(2) **The card's `mutation_hint` is honoured on flake.nix, because flake.lock
cannot carry the string it counts.** "reintroduce the file:// URL → the grep
count is 1" was executed literally: `flake.nix` back to `git+file://…`, then
`nix flake lock --update-input herdr-kitten`. MEASURED: `grep -c 'git+file'
flake.nix` = 1 (the card's "1"), `grep -c 'file:///home/tom' flake.lock` = 2,
and `grep -c 'git+file' flake.lock` = **0 on both sides of the fault** — Nix
writes a local git tree in the lock as `"type": "git"` + `"url":
"file:///home/tom/…"`, never as `git+file`. So the DOMINANT's byte-exact lock
grep is kept as clause B and cannot be the clause that goes red;
`tests/herdr/test-herdr-kitten-input.sh` adds B2/B3/B4 (the same grep over
flake.nix, `file:///home/tom` over both files, and the positive form — the URL
is `github:mecattaf/herdr-kitten/<40 hex>` and the lock node agrees). Oracle rc
0 green, rc 1 under the mutation with B2/B3/B4 red.

Those greps read the whole of `flake.nix`, COMMENTS INCLUDED, and that is not a
false positive to paper over: MEASURED 2026-09-06T22:10Z, a first draft of the
new URL comment spelled the retired local URL out for contrast and the oracle
went red on B2/B3 with the pin itself correct. So `flake.nix` never names the
form it removed, not even nostalgically; the prose that does name it lives in
`docs/herdr/herdr-kitten-input.md` and in this file, neither of which the oracle
greps.

(3) **The lock update the oracle names must be a NO-OP, and that is asserted.**
Clause A0 runs `nix flake lock --update-input herdr-kitten` (falling back to
`--offline`), then requires `flake.lock` byte-unchanged and restores it if not.
That is both "after nix flake lock --update-input herdr-kitten" and the card's
"re-applying the same card reports zero changes"; a pin that drifted on every
re-run would satisfy neither. The script restores the lock a SECOND time on
exit, because under the mutation Nix rewrites it again inside clause A
(`nix flake check` fixes up a lock that no longer matches `flake.nix`,
`--no-build` or not) — MEASURED: a mutated run otherwise leaves `flake.lock`
dirty, i.e. a change nobody authorized. Every clause reads the mutated lock
before that exit restore, so no red is masked: green run rc 0 with the tree
byte-clean, mutated run rc 1 with `flake.lock` restored on the way out.

(4) **The card's byte-exact DOMINANT does not discriminate this unit, and the
mechanized form does — both MEASURED on the parent.** The first attempt's
receipt recorded this as defect D-2 and it is still true of the card's three
clauses taken byte-exactly. CONTROL, in a detached worktree at `origin/main`
`cd917822` (removed after): `nix flake lock --update-input herdr-kitten` rc 0,
`nix flake check --offline --no-build` rc 0, `grep -c 'git+file' flake.lock`
**0**, `nix eval … home.packages` **`["herdr-kitten"]`** — every clause of the
card green on a commit that still pins `41a6de5` over a local URL. Nix spells a
local git tree `"type": "git"` + a bare `file://` URL in the lock, never
`git+file`, so the card's grep cannot see the fault it names; and `hk` was
already in the coordinator's packages before this unit.
The same control under `bash tests/herdr/test-herdr-kitten-input.sh
/tmp/ud15-control-…` exits **1** — B2 = 1, B3 = 2/1, B4 red twice, and the lock
node reading `git -/- 41a6de5…`. So the discriminating acceptance for this unit
is the script's B2/B3/B4 plus the no-op A0, not clause B alone; D-2 is answered
by mechanism rather than argued away, and the card's own argv is kept verbatim
as clause B inside it.

Not decided here and deliberately untouched: the herdr TOPOLOGY. One server, on
the coordinator (ruling B5); `#309` stays Tom's. The `home-profiles` check
asserts that shape in both directions so a pin move cannot become a topology
move. The switch that puts this pin on a box is `DEFERRED.md` DF-U-D15-1.
