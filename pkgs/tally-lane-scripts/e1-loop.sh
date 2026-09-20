#!/usr/bin/env bash
# e1-loop — the E1 filler lane: replay the eligible rungs of cards/e1-sample.tsv,
# one item at a time, and bank one §2.3 receipt per item.
#
# This is tools/run-e1-0-worker.sh's one-rung form generalised into the lane the
# overnight handoff (c) names: "loop the E1 worker over the 24 eligible rungs in
# cards/e1-sample.tsv, one at a time, receipts in the §2.3 shape, `register
# calibrate` after every verdict". Per item (one rung x one arm x one attempt,
# TALLY-SPEC §4.4.2) the loop:
#
#   1. resolves the item with tools/e1-rungs.py — git base, archived prompt of
#      record, the frontier receipt's OWN oracle argv, §4.4.2's runtime cap, the
#      arm (local, or pi-qwencloud above the local context window per B2) — and
#      writes the per-rung kit and the per-item replay card;
#   2. locks the prior BEFORE dispatch: the kit and the card are committed, and
#      that commit's own sha replaces their placeholder (REFUTATIONS B3, in the
#      two-step form E1-0 set: ffc77b4 -> 1fa5769);
#   3. builds the frontier-blind worktree: an independent depth-one repository at
#      the base, fetched over file:// so no alternate can reach the frontier
#      object, and proves the frontier commit does not resolve in it. A REFUSED
#      earlier attempt's clone is that attempt's leftover, so it is pruned with
#      the rest of its evidence (its worker output preserved as a patch first)
#      and prepared fresh — a rung never refuses at worktree on its own
#      leftovers (D-E19, BENCH-0P);
#   4. waits for llama-swap's /running to be empty, or to hold exactly this
#      item's OWN arm in state ready (D-E16's warm start: the seat is D-E06's
#      lease, not an empty /running) — never unloading, never restarting, never
#      a second concurrent model request — and dispatches the worker through
#      tools/run-e1-worker.sh under the kit's cap;
#   5. captures the two measurement sources (the pi session, the filtered
#      llama-swap journal) plus the /running probe and the drain tenant;
#   6. acts as the EVALUATOR: the lake's mechanical evaluator reruns the frontier
#      argv in a fresh worktree of the replay commit — the worker never runs it;
#   7. composes receipts/E1/<rung>/replay.json, checks it strictly with
#      tools/check-e1.sh, appends the item's row to cards/e1-results.tsv and runs
#      the post-verdict derive step (rc 0 each): `bin/register calibrate`, then
#      `bands`, `next --pass 1` and `plot quant` — every artefact the new row
#      invalidates, regenerated and committed with the receipt (FIX-E13);
#   8. commits the evidence and keeps the replay worktree, so the receipt stays
#      re-checkable by someone who did not write it.
#
# The loop writes no verdict: `outcome_for_calibration` is computed, `outcome_ruled`
# stays Tom's, and cards/e1-sample.tsv is never touched (its seven columns are
# U-E8's oracle; results go to cards/e1-results.tsv).
#
#   bash tools/e1-loop.sh --limit 1          # the next unattempted item
#   bash tools/e1-loop.sh --all              # the whole eligible population
#   bash tools/e1-loop.sh --rung U-B1        # one named rung
#   bash tools/e1-loop.sh --all --dry-run    # the population, dispatched nothing
#
# A rung that refused twice is PARKED and never dispatched again (R-c08, the
# factory lane's rule in codex-lane/repair.py park()): the refusals already on
# disk — receipts/E1/<rung>/refusal.json and each excluded refused-<stamp>/ — are
# counted, a refusal at stage `serve` never counts (D-E06, transient), and the
# park is written beside the evidence as receipts/E1/<rung>/park.json with its
# reason and a resume condition. Nothing is deleted, no results row is written,
# the loop never acts on the resume condition, and the population walks past the
# rung to the next ready one. An operator meets the condition and removes the
# file; until then a pass that would have re-dispatched it dispatches nothing.
#
# A transient stage is not a licence to loop (FIX-E14, tally-ts-sdk#126): when the
# SAME rung refuses at the SAME transient stage with the SAME refusal text three
# times in a row, it is PARKED too, with the repeated refusal named and counted. A
# refusal is transient because the condition it names is expected to be met by the
# next pass; three identical ones measure that expectation false. And the base that
# made W-BOOT loop -- the EMPTY TREE, the one base a clone cannot sit at as a
# commit -- is now accepted at the worktree stage: a clean clone with no HEAD, or
# one whose HEAD carries the empty tree, IS at that base, and the empty tree's
# object name is computed by git and never hardcoded. A dry run MEASURES that stage
# in a throwaway clone under its own TMPDIR (dry_worktree_report).
#
# Exit status: 0 every selected item is banked (or was already banked, which is
# the idempotence the oracle asks for); 1 an item could not be measured — its
# refusal is named in receipts/E1/<rung>/refusal.json and no receipt is claimed;
# 2 a usage error.
set -u

# 2026-09-20 corrections: this script is now carried by the repository
# (pkgs/tally-lane-scripts) and runs from the nix store, so "$0/.." is no longer the
# register; E1_REGISTER_ROOT names the register tree instead. The self-relative form
# stays as the fallback so a copy run by hand from inside the register behaves exactly
# as it always did. Set before RUNGS, EMPTY_TREE and LEASE_TOOL, which all derive from
# ROOT and are computed before the argument loop parses --root.
ROOT=${E1_REGISTER_ROOT:-$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)}
LAKE=${E1_LAKE:-/home/tom/mecattaf/tally-ts-sdk}
RUNGS="$ROOT/tools/e1-rungs.py"
# The empty tree's object name is COMPUTED, never hardcoded: `git hash-object -t
# tree /dev/null` is what git itself would name the empty tree in THIS repository,
# so a register whose object format is not sha1 is named correctly instead of
# being compared against a sha1 constant it can never equal (FIX-E14).
EMPTY_TREE=$(git -C "$ROOT" hash-object -t tree /dev/null 2>/dev/null || true)
case "$EMPTY_TREE" in
	[0-9a-f][0-9a-f]*) ;;
	*) printf 'e1-loop: git would not name the empty tree in %s\n' "$ROOT" >&2; exit 2 ;;
esac
PROBE_URL=${E1_PROBE_URL:-http://localhost:9292/running}
# D-E16: the wait must be LONGER than the resident model's own idle TTL (600 s on
# this host) or a foreign model can never age out inside it, and shorter than
# llama-swap's 900 s health window. 600 s -- the TTL itself -- was the starving
# value MEASURED 16:48Z-18:25Z.
RUNNING_WAIT=${E1_RUNNING_WAIT_SECONDS:-900}
# The own-row fast path's state (tools/quant-bench.sh has the same form): the arm
# is resident and READY to answer. A model in any other state is not this item's
# seat to take.
OWN_ROW_READY_STATE=ready
ARM_MODEL=""        # the item's own arm model, resolved per item
WARM_START=false    # the arm was already resident when the serve gate opened
RESIDENT_BEFORE=none # what /running held when the serve gate opened
# The one GPU seat of this host (DECISIONS.md D-E06). The filler and the bench
# (tools/quant-bench.sh) wait on the same pid-named lease: each waits while the file
# names a live pid other than its own, takes it for one item, releases it after.
LEASE_TOOL="$ROOT/tools/gpu-lease.sh"
LEASE_WAIT=${E1_GPU_LEASE_WAIT_SECONDS:-$RUNNING_WAIT}
GPU_LEASE_HELD=0
CONSECUTIVE_CRASH_ABORT=2          # §4.4.6 abort_on.consecutive_crash ("default, unruled", H-05)

LIMIT=0 ALL=0 RUNG="" ATTEMPT=1 REATTEMPT=0 DRY=0 CALIBRATE=1 PRUNE=0 BANK=0
# The post-verdict derive step: every `bin/register` verb whose output is a
# function of cards/e1-results.tsv, in dependency order (calibrate scores the
# priors; bands counts the rows; next --pass 1 reads the bands; plot quant reads
# the results and the quant cards), and the tracked files they write. Both lists
# are one unit: what the step regenerates is exactly what the E1 commit carries,
# so a derived artefact can never lag the row that invalidated it.
DERIVE_VERBS=(calibrate bands "next --pass 1" "plot quant")
DERIVE_PATHS=(priors/calibration.tsv cards/bands.tsv cards/selection-1.tsv reports/quant)
usage() {
	cat >&2 <<'EOF'
usage: bash tools/e1-loop.sh (--limit N | --all | --rung RUNG) [options]
  --limit N          run at most N items, in the plan's order
  --all              loop the whole eligible population
  --rung RUNG        run exactly this rung of cards/e1-sample.tsv
  --bank RUNG        bank an item whose evidence is already on disk: compose,
                     row, check, control, derive, commit. It dispatches
                     nothing and requests no model.
  --attempt N        the attempt number to run (default 1)
  --reattempt        target the next attempt of rungs that already have a row
  --dry-run          resolve and print the population; dispatch nothing. It names
                     the stale replay clone it would prune and the patch it would
                     keep first. The only thing it writes is the park record of a
                     rung that already refused twice (receipts/E1/<rung>/park.json),
                     which it reads off the evidence on disk and never commits
  --no-calibrate     do not run the post-verdict derive step (register calibrate,
                     bands, next --pass 1, plot quant) after each verdict
  --prune-worktrees  remove each replay worktree after its receipt is banked
                     (the default keeps it: it is the receipt's evidence)
  --root DIR         the register checkout to work in (default: this script's parent)
environment: E1_LAKE, E1_PROBE_URL, E1_RUNNING_WAIT_SECONDS (default 900, above
             the resident model's 600s idle TTL and below llama-swap's 900s
             health window), E1_WORKTREE_ROOT
EOF
}
ORIGINAL_ARGV=$*
while [ $# -gt 0 ]; do
	case "$1" in
		--limit) LIMIT=${2:-}; shift 2 ;;
		--all) ALL=1; shift ;;
		--rung) RUNG=${2:-}; shift 2 ;;
		--bank) RUNG=${2:-}; BANK=1; ALL=0; LIMIT=0; shift 2 ;;
		--attempt) ATTEMPT=${2:-}; shift 2 ;;
		--reattempt) REATTEMPT=1; shift ;;
		--dry-run) DRY=1; shift ;;
		--no-calibrate) CALIBRATE=0; shift ;;
		--prune-worktrees) PRUNE=1; shift ;;
		--root) ROOT=$(CDPATH= cd -- "${2:-}" && pwd); shift 2 ;;
		-h|--help) usage; exit 2 ;;
		*) echo "e1-loop: unknown argument '$1'" >&2; usage; exit 2 ;;
	esac
done

say() { printf 'e1-loop: %s\n' "$*" >&2; }
item_say() { printf 'e1-loop[%s]: %s\n' "$ITEM" "$*" >&2; }
die() { echo "e1-loop: $*" >&2; exit 2; }

# ---------------------------------------------------------- the serve gate --
# llama-swap's /running, classified against ONE item's own arm. Four verdicts and
# nothing else:
#
#   empty       nothing is resident; the request that follows is a cold load.
#   own-row     D-E16's warm start: the resident model IS this item's arm and it
#               is ready. The seat is D-E06's pid-named lease, not an empty
#               /running, so the request that follows loads nothing, swaps
#               nothing and unloads nothing — it is answered by the model that is
#               already there. This is the form tools/quant-bench.sh has had
#               since D-U-BENCH2.
#   foreign     another tenant's model holds the row. It is waited out in full
#               (its TTL is its own) and never unloaded by this loop.
#   unreadable  /running did not answer, or did not answer JSON.
#
# The models it saw are printed after a tab, so a caller names what it saw rather
# than what it assumed.
running_verdict() { # arm-model -> "empty|own-row|foreign|unreadable\t<models>"
	local arm=$1 body rows
	if ! body=$(curl -fsS --max-time 10 "$PROBE_URL" 2>/dev/null); then
		printf 'unreadable\t%s\n' "$PROBE_URL"; return 0
	fi
	if ! rows=$(jq -r '.running[]? | "\(.model)/\(.state // "")"' <<<"$body" 2>/dev/null); then
		printf 'unreadable\t%s\n' "$PROBE_URL"; return 0
	fi
	if [ -z "$rows" ]; then
		printf 'empty\t\n'; return 0
	fi
	if [ "$rows" = "$arm/$OWN_ROW_READY_STATE" ]; then
		printf 'own-row\t%s\n' "$rows"; return 0
	fi
	printf 'foreign\t%s\n' "$(printf '%s' "$rows" | tr '\n' ',')"
}

case "$LIMIT" in ''|*[!0-9]*) [ "$LIMIT" = 0 ] || die "--limit needs a non-negative integer" ;; esac
case "$ATTEMPT" in ''|*[!0-9]*) die "--attempt needs a positive integer" ;; esac
[ "$ATTEMPT" -ge 1 ] || die "--attempt must be >= 1"
selectors=0
[ "$LIMIT" -gt 0 ] && selectors=$((selectors + 1))
[ "$ALL" = 1 ] && selectors=$((selectors + 1))
[ -n "$RUNG" ] && selectors=$((selectors + 1))
[ "$selectors" -eq 1 ] || die "name exactly one of --limit N, --all, --rung RUNG, --bank RUNG"
[ "$REATTEMPT" = 1 ] && [ -n "$RUNG" ] && die "--reattempt needs --limit or --all, not one named rung"

cd "$ROOT" || die "cannot enter $ROOT"
for tool in curl date git jq journalctl python3 sha256sum; do
	command -v "$tool" >/dev/null 2>&1 || die "required executable is absent: $tool"
done
[ -f "$RUNGS" ] || die "the resolver is absent: $RUNGS"
[ -f "$LAKE/scripts/node-env.sh" ] || die "the lake toolchain is absent: $LAKE"
[ -f "$LAKE/apps/evaluator/bin/evaluate.mjs" ] || die "the lake's mechanical evaluator is absent"
# shellcheck disable=SC1091
. "$LAKE/scripts/node-env.sh" || die "the lake's node environment would not apply"
node_env_apply || die "the lake's node environment would not apply"
command -v node >/dev/null 2>&1 || die "node is still absent after the lake's toolchain was applied"

TMP=$(mktemp -d "${TMPDIR:-/tmp}/e1-loop.XXXXXX")
release_gpu_lease() { # the seat is never held past the item it was taken for
	[ "$GPU_LEASE_HELD" = 1 ] || return 0
	GPU_LEASE_HELD=0
	bash "$LEASE_TOOL" release --pid $$ >/dev/null 2>&1 || true
}
trap 'release_gpu_lease; rm -rf "$TMP"' EXIT

# ------------------------------------------------------------- replay clones --
# The replay clone of an item is an independent depth-one repository at the item's
# base -- not a registered worktree, no remote, no alternate (build_worktree).
# These four helpers are the whole vocabulary the loop has for one: is it usable
# as it stands, what does it carry beyond base, make one, keep what it carries.
# They are defined here, above the --dry-run report, because a dry run names the
# clone it would prune before any item is resolved.

clone_is_fresh() { # worktree base -> 0 when the clone is at base with nothing uncommitted
	# The one definition of "usable as it stands", shared by the worktree stage
	# and by the prune, so the prune never removes a clone the worktree stage
	# would have reused. An empty-tree base has no commit to sit at: there the
	# fresh clone is the one with no HEAD, which is exactly what prepare_clone
	# leaves (git init, no fetch), or one whose HEAD commit carries the empty tree
	# itself -- nothing beyond base either way.
	#
	# FIX-E14, MEASURED (git 2.55.0): `git rev-parse HEAD` on an UNBORN HEAD prints
	# the literal string `HEAD` on STDOUT and exits 128, so `head` was never empty
	# and the empty-tree branch below could never be taken. W-BOOT was prepared
	# fresh and refused at stage `worktree` on the same pass, every pass, 11 times
	# in a row from 20:32Z. `rev-parse -q --verify` prints nothing when the ref does
	# not resolve, which is what this test always meant to read.
	local wt=$1 base=$2 head tree
	[ -d "$wt/.git" ] || return 1
	head=$(git -C "$wt" rev-parse -q --verify 'HEAD^{commit}' 2>/dev/null || true)
	if [ "$base" = "$EMPTY_TREE" ]; then
		if [ -n "$head" ]; then
			tree=$(git -C "$wt" rev-parse -q --verify "$head^{tree}" 2>/dev/null || true)
			[ "$tree" = "$EMPTY_TREE" ] || return 1
		fi
	else
		[ "$head" = "$base" ] || return 1
	fi
	[ -z "$(git -C "$wt" status --porcelain 2>/dev/null)" ] || return 1
	return 0
}

clone_commits_beyond_base() { # worktree base -> how many commits it carries past base
	local wt=$1 base=$2 count
	git -C "$wt" rev-parse -q --verify HEAD >/dev/null 2>&1 || { printf '0\n'; return 0; }
	if [ "$base" = "$EMPTY_TREE" ]; then
		count=$(git -C "$wt" rev-list --count HEAD 2>/dev/null)
	else
		count=$(git -C "$wt" rev-list --count "$base..HEAD" 2>/dev/null)
	fi
	printf '%s\n' "${count:-0}"
}

prepare_clone() { # worktree repository base -> 0; the independent depth-one repository
	local wt=$1 repo=$2 base=$3
	mkdir -p "$(dirname "$wt")" || return 1
	git init -q "$wt" || return 1
	git -C "$wt" config user.name "$(git_register config user.name || echo tally-e1)" || return 1
	git -C "$wt" config user.email "$(git_register config user.email || echo tally-e1@localhost)" || return 1
	git -C "$wt" config commit.gpgsign false || return 1
	if [ "$base" != "$EMPTY_TREE" ]; then
		# file:// forces a real fetch: no hardlinks and no alternates, so the
		# frontier object cannot be reached through the source repository.
		git -C "$wt" fetch -q --no-tags --depth 1 "file://$repo" "$base" || return 1
		git -C "$wt" checkout -q --detach FETCH_HEAD || return 1
	fi
	return 0
}

dry_prune_report() { # -> name the stale replay clone of every selected rung
	# Reads only: the plan the resolver already produced, the refusal on disk and
	# the clone's own git. It removes nothing and writes nothing.
	local rung wt base evidence sha count
	for rung in $POPULATION; do
		[ -n "$rung" ] || continue
		wt=$(jq -r --arg rung "$rung" '.ready[] | select(.rung == $rung) | .paths.worktree' "$plan_json")
		base=$(jq -r --arg rung "$rung" '.ready[] | select(.rung == $rung) | .base' "$plan_json")
		evidence=$(jq -r --arg rung "$rung" '.ready[] | select(.rung == $rung) | .paths.evidence' "$plan_json")
		[ -n "$wt" ] && [ "$wt" != null ] || continue
		[ -d "$wt" ] || continue
		if [ ! -f "$ROOT/$evidence/refusal.json" ]; then
			printf 'prune %s: the replay clone %s is kept — no refusal is on disk for this attempt, so it is evidence, not a leftover\n' \
				"$rung" "$wt"
			continue
		fi
		if clone_is_fresh "$wt" "$base"; then
			printf 'prune %s: the replay clone %s is already at base %s and clean — nothing would be pruned\n' \
				"$rung" "$wt" "${base:0:10}"
			continue
		fi
		count=$(clone_commits_beyond_base "$wt" "$base")
		sha=$(git -C "$wt" rev-parse --short HEAD 2>/dev/null || printf 'no-commit')
		if [ "${count:-0}" = 0 ]; then
			printf 'prune %s: would prune the stale replay clone %s (HEAD %s, no commit beyond base %s, so no worker output to keep) and prepare it fresh\n' \
				"$rung" "$wt" "$sha" "${base:0:10}"
		else
			printf 'prune %s: would prune the stale replay clone %s (HEAD %s, %s commit(s) beyond base %s) and prepare it fresh; it would keep its worker output first as %s/refused-<stamp>/worker-output-%s.patch\n' \
				"$rung" "$wt" "$sha" "$count" "${base:0:10}" "$evidence" "$sha"
		fi
	done
}

clone_frontier_resolves() { # worktree frontier -> 0 when the frontier commit resolves in it
	# The isolation claim is MEASURED, never asserted, and it is measured by this
	# one line so the worktree stage and the dry run cannot disagree about it.
	git -C "$1" cat-file -e "$2^{commit}" 2>/dev/null
}

dry_worktree_report() { # -> MEASURE the worktree stage of every empty-tree-base rung
	# FIX-E14: the empty tree is the one base a clone cannot sit at as a commit, and
	# the stage that reads it refused every such rung on every pass (W-BOOT, 11
	# identical refusals in a row from 20:32Z). So a dry run measures that stage
	# instead of predicting it: for each selected rung whose base is the empty tree
	# it prepares a THROWAWAY clone under this invocation's own $TMP -- `git init`
	# only, no fetch, no network, removed with $TMP on exit -- and runs the same two
	# tests build_worktree runs, clone_is_fresh and clone_frontier_resolves. No live
	# replay clone is read or touched, nothing is dispatched, and nothing outside
	# $TMP is written. A rung on any other base needs a real fetch to be measured
	# this way, so it is left to the run itself.
	local rung base frontier repo probe
	for rung in $POPULATION; do
		[ -n "$rung" ] || continue
		base=$(jq -r --arg rung "$rung" '.ready[] | select(.rung == $rung) | .base' "$plan_json")
		[ "$base" = "$EMPTY_TREE" ] || continue
		frontier=$(jq -r --arg rung "$rung" '.ready[] | select(.rung == $rung) | .frontier_commit' "$plan_json")
		repo=$(jq -r --arg rung "$rung" '.ready[] | select(.rung == $rung) | .repository' "$plan_json")
		probe="$TMP/worktree-probe-$rung"
		rm -rf "$probe"
		if ! prepare_clone "$probe" "$repo" "$base"; then
			printf 'REFUSED at worktree (dry run, %s): a clone at the empty-tree base %s could not be prepared at %s\n' \
				"$rung" "${base:0:10}" "$probe"
			continue
		fi
		printf 'prepared %s fresh at %s\n' "$probe" "${base:0:10}"
		if ! clone_is_fresh "$probe" "$base"; then
			printf 'REFUSED at worktree (dry run, %s): the freshly prepared clone at the empty-tree base %s is not at base and clean, so no pass could reach the worker\n' \
				"$rung" "${base:0:10}"
			continue
		fi
		if clone_frontier_resolves "$probe" "$frontier"; then
			printf 'REFUSED at worktree (dry run, %s): the frontier commit %s resolves in a clone at the empty-tree base\n' \
				"$rung" "${frontier:0:10}"
			continue
		fi
		printf 'worktree %s: a fresh clone at the empty-tree base %s is at base and clean and the frontier %s does not resolve in it — a real run proceeds to the worker\n' \
			"$rung" "${base:0:10}" "${frontier:0:10}"
	done
}

preserve_worker_output() { # worktree base out -> 0 when a non-empty patch is written
	# Whatever the clone carries beyond base is a worker's output that was never
	# banked (D-E19: U-D5's 93abf8d). It is written out in `git format-patch`'s
	# form -- the operator's own form in
	# receipts/E1/U-D5/stale-worktree-D-E19/worker-output-93abf8d.patch -- before
	# anything is removed.
	local wt=$1 base=$2 out=$3
	if [ "$base" = "$EMPTY_TREE" ]; then
		git -C "$wt" format-patch --root --stdout HEAD >"$out" 2>/dev/null || { rm -f "$out"; return 1; }
	else
		git -C "$wt" format-patch --stdout "$base..HEAD" >"$out" 2>/dev/null || { rm -f "$out"; return 1; }
	fi
	[ -s "$out" ] || { rm -f "$out"; return 1; }
	return 0
}

# ---------------------------------------------------------------- population --
plan_json="$TMP/plan.json"
python3 "$RUNGS" plan --json --root "$ROOT" >"$plan_json" || die "the resolver would not plan"
READY=$(jq -r '.ready | length' "$plan_json")
DEFERRED=$(jq -r '.deferred | length' "$plan_json")
PARKED=$(jq -r '.parked | length' "$plan_json")
INELIGIBLE=$(jq -r '.ineligible | length' "$plan_json")

# R-c08: the park record of every rung the evidence on disk parks. It is written
# from refusals that are already there — nothing is dispatched, nothing is
# deleted, and unchanged bytes are not rewritten — so a dry run writes it too:
# the park is a decision this loop reached, and a decision it cannot say out loud
# is worse than one it does not reach. The commit is the non-dry run's (below).
if [ "$PARKED" -gt 0 ]; then
	python3 "$RUNGS" park --root "$ROOT" >"$TMP/park.txt" 2>"$TMP/park.err" ||
		say "note: the park record could not be written: $(head -1 "$TMP/park.err")"
	while IFS= read -r line; do [ -n "$line" ] && say "park $line"; done <"$TMP/park.txt"
fi

# The plan's own order: the cheapest frontier worker output first, then the
# cheapest frontier seconds, then the rung name. Nothing here ranks a rung by
# taste; §4.4.2's item granularity makes the smallest item the smallest loss.
if [ -n "$RUNG" ]; then
	POPULATION=$(jq -r --arg rung "$RUNG" '.ready[] | select(.rung == $rung) | .rung' "$plan_json")
	[ -n "$POPULATION" ] || {
		jq -e --arg rung "$RUNG" '.deferred[] | select(.rung == $rung)' "$plan_json" >/dev/null &&
			die "$RUNG is deferred: $(jq -r --arg rung "$RUNG" '.deferred[] | select(.rung == $rung) | .reason' "$plan_json")"
		jq -e --arg rung "$RUNG" '.parked[] | select(.rung == $rung)' "$plan_json" >/dev/null &&
			die "$RUNG is parked: $(jq -r --arg rung "$RUNG" '.parked[] | select(.rung == $rung) | .reason' "$plan_json")
       resume: $(jq -r --arg rung "$RUNG" '.parked[] | select(.rung == $rung) | .park.resume_condition' "$plan_json")"
		jq -e --arg rung "$RUNG" '.ineligible[] | select(.rung == $rung)' "$plan_json" >/dev/null &&
			die "$RUNG is not eligible: $(jq -r --arg rung "$RUNG" '.ineligible[] | select(.rung == $rung) | .reason' "$plan_json")"
		die "$RUNG is not a ready row of cards/e1-sample.tsv"
	}
else
	POPULATION=$(jq -r '.ready[].rung' "$plan_json")
fi

if [ "$DRY" = 1 ]; then
	printf '%s
' "== e1-loop population (dry run: nothing dispatched; the only write is the park record)"
	# The GPU seat is a precondition of every dispatch (D-E06), so a dry run reports it:
	# a lease held by a live pid other than this loop's is what the loop would WAIT on
	# before it requested a model, and a dry run makes no request at all.
	if [ -f "$LEASE_TOOL" ] && bash "$LEASE_TOOL" status --pid $$ >/dev/null 2>&1; then
		printf 'GPU lease: waiting on the GPU lease (D-E06) — %s. A real run would wait for it before requesting a model; this dry run dispatches nothing.
' \
			"$(bash "$LEASE_TOOL" status --pid $$ 2>/dev/null | head -1)"
	else
		printf 'GPU lease: %s — no live lane holds the GPU seat
' \
			"$(bash "$LEASE_TOOL" status --pid $$ 2>/dev/null | head -1)"
	fi
	# The serve gate is the other precondition of every dispatch, and since D-E16 it
	# is not "is /running empty" but "is the row this item's own". The dry run reports
	# it as it would be MET: it reads /running with the first item's own arm and, when
	# a FOREIGN model holds the row, waits it out exactly as a real pass would, so the
	# line below is a measurement and not a prediction. It takes no lease, requests no
	# model, unloads nothing and refuses nothing — a dry run has no item to refuse.
	dry_rung=$(jq -r 'first(.ready[] | select(.already_attempted | not) | .rung) // (first(.ready[].rung) // "")' "$plan_json")
	[ -n "$RUNG" ] && dry_rung=$RUNG
	dry_arm=$(jq -r --arg rung "$dry_rung" 'first(.ready[] | select(.rung == $rung) | .arm.model) // ""' "$plan_json")
	if [ -z "$dry_arm" ]; then
		printf 'serve: no ready item resolves, so there is no arm to hold the row against\n'
	else
		dry_waited=0
		while :; do
			dry_line=$(running_verdict "$dry_arm")
			dry_verdict=${dry_line%%	*}; dry_models=${dry_line#*	}
			case "$dry_verdict" in
				own-row)
					printf 'serve: the seat is taken — llama-swap holds %s in state %s, which is %s'"'"'s OWN arm, so a real run would proceed past the serve stage on a warm start (D-E16). Dry run: nothing dispatched, nothing refused.\n' \
						"$dry_arm" "$OWN_ROW_READY_STATE" "$dry_rung"
					break ;;
				empty)
					printf 'serve: llama-swap /running is empty, so a real run would proceed past the serve stage and %s'"'"'s arm %s would be a cold load. Dry run: nothing dispatched, nothing refused.\n' \
						"$dry_rung" "$dry_arm"
					break ;;
				unreadable)
					printf 'serve: llama-swap /running is not readable at %s, so a real run would refuse at stage serve (transient, D-E06). Dry run: nothing dispatched, nothing refused.\n' \
						"$PROBE_URL"
					break ;;
			esac
			if [ "$dry_waited" -ge "$RUNNING_WAIT" ]; then
				printf 'serve: the seat is taken by a FOREIGN model (%s) and it was still there after %ss, so a real run would refuse at stage serve. This loop never unloads it. Dry run: nothing dispatched, nothing refused.\n' \
					"$dry_models" "$dry_waited"
				break
			fi
			[ "$dry_waited" = 0 ] && printf 'serve: the seat is taken by a FOREIGN model (%s), not %s'"'"'s own arm %s; waiting out its own TTL, %ss budget, never an unload and never a second concurrent request\n' \
				"$dry_models" "$dry_rung" "$dry_arm" "$RUNNING_WAIT"
			sleep 5
			dry_waited=$((dry_waited + 5))
		done
	fi
	printf 'eligible %s (ready %s, deferred %s, parked %s); not eligible %s
' \
		"$((READY + DEFERRED + PARKED))" "$READY" "$DEFERRED" "$PARKED" "$INELIGIBLE"
	jq -r '.parked[] | "parked \(.rung): \(.park.reason)"' "$plan_json"
	jq -r '.parked[] | "nothing to dispatch for \(.rung): parked after \(.park.refused_attempts) refused attempts (receipts/E1/\(.rung)/park.json); resume: \(.park.resume_condition)"' "$plan_json"
	# The stale replay clones a real run would prune, named before it prunes them:
	# a leftover clone is the condition U-D5 refused at 30 times (D-E19), and a dry
	# run that would not say which directory it is about to remove is not a dry run.
	dry_prune_report
	# The worktree stage of every empty-tree-base rung, measured in a throwaway
	# clone (FIX-E14): a dry run that cannot say whether the stage would accept the
	# one base that has no commit is not a dry run of this lane.
	dry_worktree_report
	python3 "$RUNGS" plan --root "$ROOT"
	exit 0
fi

# ------------------------------------------------------------------ one item --
BANKED=0 SKIPPED=0 REFUSALS=0 CONSECUTIVE=0
BANKED_ITEMS=()
STALE_REFUSAL=""
# The item's replay clone, as exclude_stale_evidence and the prune see it. They
# are set from the resolved item before either runs and are empty when no item is
# in flight, so nothing below can act on a previous item's clone.
CLONE_PATH="" CLONE_BASE="" CLONE_REPO="" STALE_DIR=""
run_item() { # rung attempt
	ITEM=$1 ATTEMPT_TARGET=$2
	local row item_json kit card worktree base frontier repository cap oracle_cap session_id session prompt frontier_receipt lock replay_commit
	local frontier_archive frontier_source
	local started finished handed eval_rc compose_rc check_rc mutation_rc calibrate_rc
	row=$(row_of "$ITEM")
	EVIDENCE=""
	item_say "resolving item (row $row, attempt $ATTEMPT_TARGET)"
	item_json="$TMP/item-$ITEM-$ATTEMPT_TARGET.json"
	if ! python3 "$RUNGS" item "$ITEM" --attempt "$ATTEMPT_TARGET" --json --root "$ROOT" >"$item_json" 2>"$TMP/item.err"; then
		say "$(head -1 "$TMP/item.err")"
		EVIDENCE="$ROOT/receipts/E1/$ITEM"
		refuse resolve "$(head -1 "$TMP/item.err")" 1
		return 1
	fi
	kit=$(jq -r '.kit_path' "$item_json")
	card=$(jq -r '.card.path' "$item_json")
	worktree=$(jq -r '.paths.worktree' "$item_json")
	EVIDENCE="$ROOT/$(jq -r '.paths.evidence' "$item_json")"
	base=$(jq -r '.base' "$item_json")
	frontier=$(jq -r '.frontier_commit' "$item_json")
	repository=$(jq -r '.repository' "$item_json")
	CLONE_PATH=$worktree CLONE_BASE=$base CLONE_REPO=$repository STALE_DIR=""
	cap=$(jq -r '.runtime_cap_seconds' "$item_json")
	oracle_cap=$(jq -r '.oracle_cap_seconds' "$item_json")
	session_id=$(jq -r '.session_id' "$item_json")
	prompt=$(jq -r '.prompt.path' "$item_json")
	frontier_receipt=$(jq -r '.oracle.receipt' "$item_json")
	# The ONE line of that receipt the replay stands on, and its provenance, both
	# archived by the resolver before dispatch (D-E20).
	frontier_archive=$(jq -r '.oracle.handed' "$item_json")
	frontier_source=$(jq -r '.oracle.frontier_source' "$item_json")
	LOCAL_ARM=$(jq -r 'if .arm.offline then 1 else 0 end' "$item_json")
	# The item's own arm: the model the serve gate holds /running against (D-E16).
	ARM_MODEL=$(jq -r '.arm.model' "$item_json")
	WARM_START=false
	RESIDENT_BEFORE=none
	mkdir -p "$EVIDENCE"
	# A refusal left by an earlier invocation is not this attempt's evidence, and
	# it is not thrown away either: it moves aside now and exclude_stale_evidence
	# puts it inside the refused-<stamp>/ directory it belongs to, so every
	# excluded attempt carries the stage and reason it refused at. (Deleting it
	# here, as this line used to, made the copy below a no-op: MEASURED — not one
	# refused-<stamp>/ under receipts/E1/U-D5 or U-A2 carries a refusal.json, so
	# their stage reads `unknown` when the park counts them.)
	STALE_REFUSAL=""
	if [ -f "$EVIDENCE/refusal.json" ]; then
		STALE_REFUSAL="$TMP/stale-refusal-$ITEM-$ATTEMPT_TARGET.json"
		mv "$EVIDENCE/refusal.json" "$STALE_REFUSAL"
	fi

	if row_exists "$ITEM" "$row" "$ATTEMPT_TARGET" && [ -f "$EVIDENCE/replay.json" ]; then
		item_say "already banked: $EVIDENCE/replay.json and a row of cards/e1-results.tsv — nothing replayed"
		SKIPPED=$((SKIPPED + 1))
		return 0
	fi
	if row_exists "$ITEM" "$row" "$ATTEMPT_TARGET"; then
		item_say "cards/e1-results.tsv already carries $ITEM/$row/$ATTEMPT_TARGET but its receipt is absent — refusing to replay a banked item"
		refuse idempotence "a results row exists for $ITEM/$row/$ATTEMPT_TARGET without its receipt" 1
		return 1
	fi

	# 1. the prior lock, before any dispatch (REFUTATIONS B3)
	if ! lock=$(lock_prior "$kit" "$card" "$prompt" "$frontier_archive" "$frontier_source"); then
		refuse prior-lock "the kit and card could not be committed before dispatch" 1
		return 1
	fi
	item_say "prior locked at $lock"

	# 2. the frontier-blind worktree, and the GPU idle check before dispatch
	# Evidence an earlier REFUSED attempt left here is excluded, never deleted and
	# never joined: it moves aside whole, in the form E1-0 set with its
	# attempt-0-contaminated/ directory. The move is committed as its own
	# transaction (see exclude_stale_evidence) so the working tree is clean after
	# this step — an uncommitted move lingers as deletions and stalls the lane.
	exclude_stale_evidence
	mkdir -p "$EVIDENCE/session"
	if [ "$LOCAL_ARM" = 1 ] && ! wait_for_idle_gpu; then
		refuse serve "the serve gate did not open within ${RUNNING_WAIT}s: llama-swap /running was unreadable, or held a model that is not this item's own arm $ARM_MODEL (D-E16; this loop never unloads and never restarts)" 1
		return 1
	fi
	# What the serve gate saw is what is recorded: an empty /running (a cold load) or
	# this item's OWN arm already resident (D-E16's warm start). The cell is the gate's
	# own verdict, not a second probe that could have raced it.
	local running_empty=true
	if [ "$LOCAL_ARM" = 1 ] && [ "$WARM_START" = true ]; then running_empty=false; fi
	if ! build_worktree "$worktree" "$repository" "$base" "$frontier" "$running_empty"; then
		refuse worktree "the frontier-blind worktree at $worktree could not be prepared, is not at base and clean, or the frontier commit resolves in it (an operator prunes it: rm -rf $worktree)" 1
		return 1
	fi
	item_say "worktree $worktree at ${base:0:10} (frontier ${frontier:0:10} unresolvable)"

	# 3. the worker, once, under its cap
	set +e
	bash "$ROOT/tools/run-e1-worker.sh" "$kit"
	worker_rc=$?
	set -e
	if [ "$worker_rc" = 2 ]; then
		refuse dispatch "the worker refused the dispatch (a named precondition was not met)" 2
		return 1
	fi
	item_say "worker rc=$worker_rc (cap ${cap}s)"
	if [ ! -f "$EVIDENCE/worker-window.json" ]; then
		refuse dispatch "the worker left no measured window (worker-window.json), so no second of it can be stamped" "$worker_rc"
		return 1
	fi
	[ -f "$EVIDENCE/pi-events.jsonl" ] && gzip -f "$EVIDENCE/pi-events.jsonl"
	session=$(find "$EVIDENCE/session" -name '*.jsonl' -type f | head -1)
	if [ -z "$session" ]; then
		refuse measurement "the worker left no pi session file (pi rc $worker_rc), so no token cell can be stamped" "$worker_rc"
		return 1
	fi

	# 4. the measurement sources, filtered to this window
	started=$(jq -r '.started_at' "$EVIDENCE/worker-window.json")
	finished=$(jq -r '.finished_at' "$EVIDENCE/worker-window.json")
	capture_journals "$started" "$finished"

	# 5. the worker's own output becomes the replay commit the evaluator grades
	if [ -n "$(git -C "$worktree" status --porcelain)" ]; then
		git -C "$worktree" add -A || { refuse replay-commit "the worker's output could not be staged"; return 1; }
		git -C "$worktree" commit -q -m "E1 replay $ITEM attempt $ATTEMPT_TARGET: worker output" \
			|| { refuse replay-commit "the worker's output could not be committed"; return 1; }
	fi
	if [ "$base" = "$EMPTY_TREE" ] && [ -z "$(git -C "$worktree" rev-parse --verify -q HEAD 2>/dev/null)" ]; then
		refuse replay-commit "the worker left no commit on an empty-tree base, so there is no deliverable to evaluate" 1
		return 1
	fi
	replay_commit=$(git -C "$worktree" rev-parse HEAD)
	git -C "$worktree" show -s --format='commit %H%nAuthor:     %an <%ae>%nAuthorDate: %aI%nCommit:     %cn <%ce>%nCommitDate: %cI%n%n    %s' \
		>"$EVIDENCE/replay-commit.txt"
	if [ "$base" = "$EMPTY_TREE" ]; then
		git -C "$worktree" diff --binary --unified=0 "$(git -C "$worktree" hash-object -t tree /dev/null)" "$replay_commit" \
			>"$EVIDENCE/replay.patch"
	else
		git -C "$worktree" diff --binary --unified=0 "$base" "$replay_commit" >"$EVIDENCE/replay.patch"
	fi
	item_say "replay commit ${replay_commit:0:10}; patch $(wc -c <"$EVIDENCE/replay.patch") bytes"

	# 6. the evaluator: the frontier receipt's own argv, in a fresh worktree, by
	#    the lake's mechanical evaluator. The worker never ran it.
	#
	# What is handed over is ONE JSON object, resolved and archived before dispatch
	# by `e1-rungs.py` (D-E20): a frontier `.jsonl` is a log -- the workerd rungs'
	# files carry two KEEP lines -- and `apps/evaluator` JSON.parses the single file
	# it is given. The loop selects nothing here: it copies the archived line and
	# the archived provenance into the evidence, and refuses if the bytes it is
	# about to hand over are not one JSON object.
	handed="$EVIDENCE/frontier-receipt.json"
	if [ ! -f "$ROOT/$frontier_archive" ] || [ ! -f "$ROOT/$frontier_source" ]; then
		refuse frontier "the resolver archived no frontier line for $ITEM ($frontier_archive)" 1
		return 1
	fi
	cp "$ROOT/$frontier_archive" "$handed"
	cp "$ROOT/$frontier_source" "$EVIDENCE/frontier-source.json"
	if ! python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$handed" 2>/dev/null; then
		refuse frontier "the frontier receipt to hand the evaluator is not one JSON object: $frontier_archive ($(jq -r '.selection' "$EVIDENCE/frontier-source.json") of $frontier_receipt)" 1
		return 1
	fi
	item_say "frontier receipt: $(jq -r '.selection' "$EVIDENCE/frontier-source.json") of $frontier_receipt"
	set +e
	node "$LAKE/apps/evaluator/bin/evaluate.mjs" \
		--card "$ROOT/$card" \
		--deliverable "$worktree@$replay_commit" \
		--usage-source "$session" \
		--kind replay \
		--frontier-receipt "$handed" \
		>"$EVIDENCE/evaluator-receipt.jsonl" 2>"$EVIDENCE/evaluator-stderr.log"
	eval_rc=$?
	set -e
	item_say "evaluator rc=$eval_rc (0 PASS, 1 FAIL — both are measurements)"
	if [ "$eval_rc" -gt 1 ] || ! jq -e . "$EVIDENCE/evaluator-receipt.jsonl" >/dev/null 2>&1; then
		refuse evaluate "the lake's mechanical evaluator returned rc $eval_rc: $(tail -2 "$EVIDENCE/evaluator-stderr.log" | tr '\n' ' ')" "$eval_rc"
		return 1
	fi

	# 7-10. compose, bank the row, check, control, calibrate, commit
	KIT_REL=$kit CARD_REL=$card PROMPT_REL=$prompt ROW=$row WORKTREE=$worktree
	bank_item
	return $?
}

# bank_item — steps 7 to 10 of one item, from evidence that is already on disk.
#
# It dispatches nothing and requests no model: it composes the receipt from the
# retained evidence, appends the results row, runs the strict check and the
# session_id mutation control, runs the post-verdict derive step after the verdict
# (D-B24: calibrate, bands, next --pass 1, plot quant) and commits. A row appended for an item that then fails its own check
# is rolled back to the byte, so cards/e1-results.tsv never carries a row whose
# receipt did not survive the check.
# Globals read: ITEM, ATTEMPT_TARGET, EVIDENCE, KIT_REL, CARD_REL, PROMPT_REL,
# ROW, WORKTREE.
bank_item() {
	local compose_rc check_rc mutation_rc calibrate_rc rows_before rows_after
	local disposition outcome oracle_rc receipt_rel
	receipt_rel=$(python3 -c 'import os,sys; print(os.path.relpath(sys.argv[1], sys.argv[2]))' "$EVIDENCE" "$ROOT")

	set +e
	node "$ROOT/tools/compose-e1-receipt.mjs" \
		--kit "$KIT_REL" --evidence "$EVIDENCE" \
		--evaluator-receipt "$EVIDENCE/evaluator-receipt.jsonl" \
		--out "$EVIDENCE/replay.json" 2>"$EVIDENCE/compose-stderr.log"
	compose_rc=$?
	set -e
	if [ "$compose_rc" != 0 ]; then
		refuse compose "$(tail -2 "$EVIDENCE/compose-stderr.log" | tr '\n' ' ')" "$compose_rc"
		return 1
	fi

	# The results row is appended before the check because the check reads it: a
	# receipt and its row are one claim, and the check asserts they agree.
	rows_before=$( [ -f "$ROOT/cards/e1-results.tsv" ] && wc -c <"$ROOT/cards/e1-results.tsv" || printf 0)
	if ! python3 "$RUNGS" record --root "$ROOT" --receipt "$EVIDENCE/replay.json" >"$EVIDENCE/results-row.txt" 2>&1; then
		refuse results "$(tail -1 "$EVIDENCE/results-row.txt")" 1
		return 1
	fi
	cat "$EVIDENCE/results-row.txt" >&2
	rollback_row() {
		truncate -s "$rows_before" "$ROOT/cards/e1-results.tsv" 2>/dev/null ||
			python3 -c 'import sys,pathlib; pathlib.Path(sys.argv[1]).write_bytes(pathlib.Path(sys.argv[1]).read_bytes()[:int(sys.argv[2])])' \
				"$ROOT/cards/e1-results.tsv" "$rows_before"
		item_say "rolled cards/e1-results.tsv back to $rows_before bytes: the row of a refused item is no row"
	}

	set +e
	bash "$ROOT/tools/check-e1.sh" "$EVIDENCE/replay.json" >"$EVIDENCE/check.log" 2>&1
	check_rc=$?
	set -e
	if [ "$check_rc" != 0 ]; then
		cat "$EVIDENCE/check.log" >&2
		rollback_row
		refuse check "the composed receipt did not survive its own strict check (rc $check_rc)" "$check_rc"
		return 1
	fi
	cat "$EVIDENCE/check.log" >&2

	# The mutation control of the receipt itself, on a copy: blank the session_id
	# join key and require the strict decode to go RED (E1-0's own control).
	set +e
	bash "$ROOT/tools/check-e1.sh" --negative-control session-id "$EVIDENCE/replay.json" \
		>"$EVIDENCE/mutation-session-id-red.log" 2>&1
	mutation_rc=$?
	set -e
	printf '%s\n' "$mutation_rc" >"$EVIDENCE/mutation-session-id-red.rc"
	if [ "$mutation_rc" != 1 ]; then
		cat "$EVIDENCE/mutation-session-id-red.log" >&2
		rollback_row
		refuse mutation-control "blanking session_id did not make the strict decode RED (rc $mutation_rc, want 1)" "$mutation_rc"
		return 1
	fi
	cat "$EVIDENCE/mutation-session-id-red.log" >&2
	item_say "session_id mutation control RED as required (rc 1)"

	# The post-verdict derive step (D-B24, extended by FIX-E13). A banked row
	# invalidates every artefact derived from cards/e1-results.tsv, not just
	# priors/calibration.tsv: the bands are counted over the results rows, pass 1
	# of the selection is read off the bands, and reports/quant/ is emitted from
	# the quant cards AND the results. Regenerating only calibration.tsv is what
	# left cards/bands.tsv at 51b358f and reports/quant/index.md at fc23c62 while
	# the results moved on to f120b95 — two register gate suites RED and a banking
	# run dirtying the tree. So all four verbs run here, in dependency order, and
	# every file they write is committed with the receipt. --no-calibrate opts out
	# of the whole step, as it always did.
	if [ "$CALIBRATE" = 1 ]; then
		for verb in "${DERIVE_VERBS[@]}"; do
			local log="$EVIDENCE/derive-$(printf '%s' "$verb" | tr ' /' '--').log"
			set +e
			# shellcheck disable=SC2086
			python3 "$ROOT/bin/register" $verb >"$log" 2>&1
			calibrate_rc=$?
			set -e
			printf '%s\n' "$calibrate_rc" >"${log%.log}.rc"
			[ "$verb" = calibrate ] && cp -f "$log" "$EVIDENCE/calibrate.log" &&
				printf '%s\n' "$calibrate_rc" >"$EVIDENCE/calibrate.rc"
			if [ "$calibrate_rc" != 0 ]; then
				tail -3 "$log" >&2
				rollback_row
				refuse derive "bin/register $verb returned rc $calibrate_rc after the verdict" "$calibrate_rc"
				return 1
			fi
			item_say "register $verb rc 0 after the verdict"
		done
	fi

	disposition=$(jq -r '.disposition' "$EVIDENCE/replay.json")
	outcome=$(jq -r '.outcome_for_calibration' "$EVIDENCE/replay.json")
	oracle_rc=$(jq -r '.oracle_rc' "$EVIDENCE/replay.json")
	local paths=("$receipt_rel" "$KIT_REL" "$CARD_REL" "$PROMPT_REL" "cards/e1-results.tsv")
	# A banked item carries no refusal: the refusal of the attempt that produced
	# this evidence is kept inside refused-<stamp>/, where the excluded evidence is.
	rm -f "$EVIDENCE/refusal.json"
	if [ "$CALIBRATE" = 1 ]; then
		paths+=("${DERIVE_PATHS[@]}")
	fi
	git_register add -- "${paths[@]}" >/dev/null 2>&1 || true
	git_register commit -q -m "E1: $ITEM attempt $ATTEMPT_TARGET on $ROW — $disposition/$outcome (oracle_rc $oracle_rc)" \
		-- "${paths[@]}" >/dev/null 2>&1 ||
		item_say "note: the evidence commit did not happen (nothing to commit, or the checkout is not writable)"
	if [ "$PRUNE" = 1 ]; then
		rm -rf "$WORKTREE" && item_say "pruned $WORKTREE (--prune-worktrees): the receipt's worktree assertions are no longer re-runnable"
	else
		item_say "kept $WORKTREE as the receipt's evidence"
	fi
	BANKED=$((BANKED + 1))
	BANKED_ITEMS+=("$ITEM/$ROW/$ATTEMPT_TARGET")
	CONSECUTIVE=0
	item_say "banked $receipt_rel/replay.json ($disposition/$outcome)"
	release_gpu_lease
	return 0
}

# ------------------------------------------------------------------- helpers --
row_of() { jq -r --arg rung "$1" '.ready[] | select(.rung == $rung) | .arm.row' "$plan_json"; }

attempt_of() { # rung row -> the next attempt of a rung that already has rows
	python3 - "$ROOT" "$1" "$2" <<'PY'
import sys
from pathlib import Path
sys.path.insert(0, str(Path(sys.argv[1]) / "tools"))
import importlib.util
spec = importlib.util.spec_from_file_location("e1_rungs", Path(sys.argv[1]) / "tools" / "e1-rungs.py")
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
rows = mod.read_results(Path(sys.argv[1]))
print(1 + sum(1 for row in rows if row.get("rung") == sys.argv[2] and row.get("arm") == sys.argv[3]))
PY
}

row_exists() { # rung row attempt -> 0 when cards/e1-results.tsv already carries it
	python3 - "$ROOT" "$1" "$2" "$3" <<'PY'
import importlib.util, sys
from pathlib import Path
spec = importlib.util.spec_from_file_location("e1_rungs", Path(sys.argv[1]) / "tools" / "e1-rungs.py")
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)
rows = mod.read_results(Path(sys.argv[1]))
key = (sys.argv[2], sys.argv[3], sys.argv[4])
sys.exit(0 if any(mod.results_key(row) == key for row in rows) else 1)
PY
}

git_register() { git -C "$ROOT" "$@"; }

# The lane's own invocation record: one JSON line per invocation that banked
# something, inside THIS checkout's git directory. It is not evidence and it is
# never committed — the evidence is the receipt, the results row and the kept
# worktree — so a fresh worktree of the same commit starts with no record and its
# first invocation dispatches an item.
lane_state_file() { printf '%s/e1-loop-invocations.jsonl' "$(git_register rev-parse --absolute-git-dir)"; }
lane_state_last() { # argv key -> the last matching record, if any
	local file; file=$(lane_state_file)
	[ -f "$file" ] || return 0
	# Slurped, not line-by-line: a record is one object, and a reader that assumes
	# one line per record reads nothing from a file an earlier version of this loop
	# wrote pretty-printed. That defect is measured in this branch's own history:
	# the guard existed, the record was written, and the guard never fired.
	jq -c -s --arg key "$1" '[.[] | select(.argv == $key)] | last // empty' "$file" 2>/dev/null
}
lane_state_record() { # argv key -> append this invocation's record
	local file; file=$(lane_state_file)
	jq -c -n --arg argv "$1" --arg at "$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)" \
		--arg root "$ROOT" --argjson banked "$(printf '%s\n' "${BANKED_ITEMS[@]}" | jq -R . | jq -sc .)" \
		--argjson refused "$REFUSALS" \
		'{at:$at, argv:$argv, root:$root, banked:$banked, refused:$refused}' >>"$file" 2>/dev/null ||
		say "note: the invocation record could not be written to $file"
}

exclude_stale_evidence() { # -> set an earlier refused attempt's leftovers aside
	# Evidence an earlier REFUSED attempt left in $EVIDENCE is excluded, never
	# deleted and never joined: it moves aside whole into refused-<stamp>/ (the
	# form E1-0 set with its attempt-0-contaminated/ directory). The move is
	# committed as its own transaction, scoped to the receipt directory it owns,
	# so `git status --short` is clean when this step returns. An uncommitted move
	# would linger in the working tree as deletions; the next item then finds the
	# tree dirty and, if its own kit/card produce no diff, cannot make progress.
	#
	# BENCH-0P / D-E19: the refused attempt's REPLAY CLONE is a leftover of the
	# same attempt, and it used not to be excluded with the rest. It survived into
	# the next attempt of the same number, which found it not at base and refused
	# at stage `worktree` naming an operator — MEASURED 2026-09-07: U-D5 x30 from
	# 11:12Z, U-A1 once at 18:45Z. It is pruned here, with the same stamp as the
	# evidence it belongs to and with whatever it carries beyond base preserved
	# as a patch first, and prepared fresh. A clone is a leftover only when a
	# refusal for this attempt is on disk; a BANKED item's clone is its receipt's
	# evidence and this function is never reached for one (run_item returns at the
	# already-banked check above).
	local has_evidence=0 clone_stale=0
	[ -n "$(find "$EVIDENCE" -mindepth 1 -maxdepth 1 ! -name 'refusal.json' ! -name 'refused-*' ! -name 'park.json' 2>/dev/null | head -1)" ] &&
		has_evidence=1
	if [ -n "$STALE_REFUSAL" ] && [ -n "$CLONE_PATH" ] && [ -d "$CLONE_PATH" ] &&
		! clone_is_fresh "$CLONE_PATH" "$CLONE_BASE"; then
		clone_stale=1
	fi
	[ "$has_evidence" = 1 ] || [ "$clone_stale" = 1 ] || return 0
	local stale_stamp; stale_stamp=$(date -u +%Y%m%dT%H%M%SZ)
	STALE_DIR="$EVIDENCE/refused-$stale_stamp"
	if [ "$has_evidence" = 1 ]; then
		mkdir -p "$STALE_DIR"
		find "$EVIDENCE" -mindepth 1 -maxdepth 1 ! -name 'refusal.json' ! -name 'refused-*' ! -name 'park.json' \
			-exec mv {} "$STALE_DIR/" \;
	fi
	if [ "$clone_stale" = 1 ]; then prune_stale_clone || true; fi
	# The excluded attempt's own refusal goes with its evidence, so the stage it
	# refused at is on disk beside it. The directory is only ever the one the two
	# steps above made: when neither made one, nothing here creates it, so what
	# counts as a refused attempt (tools/e1-rungs.py refused_attempts) is exactly
	# what it was.
	{ [ -d "$STALE_DIR" ] && [ -n "$STALE_REFUSAL" ] && [ -f "$STALE_REFUSAL" ] &&
		cp "$STALE_REFUSAL" "$STALE_DIR/refusal.json"; } || true
	local evidence_rel=${EVIDENCE#"$ROOT"/}
	git_register add -A -- "$evidence_rel" >/dev/null 2>&1 || true
	git_register commit -q -m "E1: exclude the earlier refused $ITEM attempt $ATTEMPT_TARGET leftovers into refused-$stale_stamp" \
		-- "$evidence_rel" >/dev/null 2>&1 || true
	[ "$has_evidence" = 1 ] &&
		item_say "excluded the evidence of an earlier refused attempt into refused-$stale_stamp"
	return 0
}

prune_stale_clone() { # -> keep the stale clone's worker output, remove it, prepare it fresh
	# Never a delete without the patch first (BENCH-0P's non-goal): when the clone
	# carries anything beyond base and that cannot be written out, the clone stays
	# and the worktree stage refuses on it exactly as it did before.
	local count sha patch_rel
	count=$(clone_commits_beyond_base "$CLONE_PATH" "$CLONE_BASE")
	if [ -n "$(git -C "$CLONE_PATH" status --porcelain 2>/dev/null)" ]; then
		# Uncommitted bytes are worker output too. They are committed into the
		# clone so the patch below carries them; nothing is removed unrecorded.
		git -C "$CLONE_PATH" add -A >/dev/null 2>&1 &&
			git -C "$CLONE_PATH" commit -q \
				-m "E1 replay $ITEM attempt $ATTEMPT_TARGET: uncommitted worker output, preserved before the prune" \
				>/dev/null 2>&1 || true
		count=$(clone_commits_beyond_base "$CLONE_PATH" "$CLONE_BASE")
	fi
	if [ "${count:-0}" != 0 ]; then
		sha=$(git -C "$CLONE_PATH" rev-parse --short HEAD 2>/dev/null || printf 'unknown')
		mkdir -p "$STALE_DIR"
		# MUTATION (BENCH-0P's mutation_hint): delete the next line and the stale
		# clone's worker output is never written out — tests/e1-loop/prune-probe.sh
		# then reads RED, the patch absent.
		preserve_worker_output "$CLONE_PATH" "$CLONE_BASE" "$STALE_DIR/worker-output-$sha.patch" || true
		if [ ! -f "$STALE_DIR/worker-output-$sha.patch" ]; then
			item_say "NOT pruning $CLONE_PATH: it carries $count commit(s) beyond base that could not be written out as a patch, and worker output is never deleted"
			return 1
		fi
		patch_rel=${STALE_DIR#"$ROOT"/}/worker-output-$sha.patch
		item_say "kept the stale clone's $count commit(s) beyond base as $patch_rel"
	fi
	rm -rf "$CLONE_PATH" || return 1
	item_say "pruned the stale replay clone $CLONE_PATH (a refused attempt's leftover, not at base and clean)"
	if prepare_clone "$CLONE_PATH" "$CLONE_REPO" "$CLONE_BASE"; then
		item_say "prepared $CLONE_PATH fresh at ${CLONE_BASE:0:10}"
	else
		# A half-made clone is the very leftover this function exists to remove.
		rm -rf "$CLONE_PATH"
		item_say "the fresh clone at $CLONE_PATH could not be prepared here; the worktree stage builds it"
	fi
	return 0
}

lock_prior() { # kit card prompt frontier-receipt frontier-source -> LOCK sha; the two-step B3 lock
	local kit=$1 card=$2 prompt=$3 lock
	# The frontier bytes the evaluator will be handed are pinned by the same
	# commit as the prior: they are an evaluator-only input resolved before
	# dispatch, and only the kit and the card carry the placeholder.
	local locked=("$kit" "$card" "$prompt" "$4" "$5")
	if ! grep -q PENDING-PRIOR-LOCK "$ROOT/$kit" "$ROOT/$card" 2>/dev/null; then
		# An earlier invocation already locked this item: the lock is the commit that
		# last carried the card, and the bytes on disk must still be its bytes.
		git_register diff --quiet HEAD -- "$kit" "$card" || return 1
		lock=$(git_register log -1 --format=%H -- "$card") || return 1
		[ -n "$lock" ] || return 1
		item_say "prior already locked at $lock (an earlier invocation committed it)"
		printf '%s\n' "$lock"
		return 0
	fi
	# Step 1: commit the kit, card and prompt carrying the PENDING placeholder.
	# The two-step lock is not atomic: an invocation interrupted after this commit
	# but before step 2 leaves the placeholder committed at HEAD with a clean tree.
	# A later invocation regenerates the same PENDING bytes, so there is nothing
	# new to stage and a blind `git commit` would fail on "nothing to commit" and
	# refuse the item forever. When step 1 has nothing to add, HEAD is already the
	# lock commit — resume the second step from it instead of wedging.
	git_register add -- "${locked[@]}" || return 1
	if git_register diff --cached --quiet -- "${locked[@]}"; then
		git_register diff --quiet HEAD -- "${locked[@]}" || return 1
		grep -q PENDING-PRIOR-LOCK "$ROOT/$kit" "$ROOT/$card" || return 1
		item_say "resuming an interrupted prior lock: HEAD already carries the placeholder"
	else
		git_register commit -q -m "E1: lock the prior for $ITEM attempt $ATTEMPT_TARGET before dispatch" \
			-- "${locked[@]}" || return 1
	fi
	lock=$(git_register rev-parse HEAD) || return 1
	# The lock commit's own sha is not knowable before it exists, so the
	# placeholder it was committed with is replaced and the replacement is
	# committed too: the `prior` block never moves (the lake's evaluator asserts
	# exactly that, in assertCardLockedBeforeDispatch).
	sed -i "s/PENDING-PRIOR-LOCK/$lock/g" "$ROOT/$kit" "$ROOT/$card" || return 1
	git_register add -- "$kit" "$card" || return 1
	if ! git_register diff --cached --quiet -- "$kit" "$card"; then
		git_register commit -q -m "E1: record the prior lock commit on the $ITEM attempt $ATTEMPT_TARGET kit and card" \
			-- "$kit" "$card" || return 1
	fi
	grep -q PENDING-PRIOR-LOCK "$ROOT/$kit" "$ROOT/$card" && return 1
	printf '%s\n' "$lock"
}

build_worktree() { # worktree repository base -> 0; writes isolation.json
	local wt=$1 repo=$2 base=$3 frontier=$4 running_empty=$5
	if [ -d "$wt" ]; then
		item_say "worktree already exists: $wt (reused only if it is at base and clean)"
		clone_is_fresh "$wt" "$base" || return 1
	else
		prepare_clone "$wt" "$repo" "$base" || return 1
	fi
	# The isolation claim is measured here, not asserted: the frontier commit must
	# not resolve in this object store.
	local resolved=false
	if clone_frontier_resolves "$wt" "$frontier"; then resolved=true; fi
	jq -n --arg wt "$wt" --arg base "$base" --arg frontier "$frontier" \
		--argjson resolved "$resolved" --argjson running "$running_empty" \
		--argjson warm "$WARM_START" --arg resident "$RESIDENT_BEFORE" \
		--arg created "$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)" \
		--arg transport "file://$repo" --argjson depth 1 \
		'{worktree:$wt, base:$base, frontier:$frontier, frontier_resolved:$resolved,
		  running_empty_before_dispatch:$running, warm_start:$warm,
		  resident_model_before_dispatch:$resident, created_at:$created,
		  fetch_transport:$transport, fetch_depth:$depth,
		  git_repository:"independent-depth-one"}' >"$EVIDENCE/isolation.json"
	[ "$resolved" = false ] || { item_say "the frontier commit resolves in $wt"; return 1; }
	return 0
}

wait_for_idle_gpu() { # -> 0 when the seat is ours and the row is empty or our own; never unloads, never restarts
	local waited=0 lease_rc line verdict models
	# The seat first (D-E06): while the lease names a live pid other than this loop's,
	# another lane (the quant bench, or a second filler) is mid-item on the one GPU and
	# this loop waits rather than making a second concurrent model request. The lease is
	# taken for this item and released after it; a lease whose pid is gone is stale and
	# is taken over, so a crashed lane never wedges the lane behind it.
	if [ -f "$LEASE_TOOL" ]; then
		bash "$LEASE_TOOL" acquire --pid $$ --holder "e1-loop/${ITEM:-item}" \
			--wait-seconds "$LEASE_WAIT" >"$TMP/lease.log" 2>&1
		lease_rc=$?
		while read -r line; do item_say "$line"; done <"$TMP/lease.log"
		if [ "$lease_rc" != 0 ]; then
			item_say "the GPU seat is still held by another live lane (D-E06); this loop waits on the lease, it never steals the seat and never unloads"
			return 1
		fi
		GPU_LEASE_HELD=1
	fi
	# The serve gate (D-E16). Two shapes open it and one does not:
	#   * /running EMPTY — the request that follows is a cold load, as it always was;
	#   * /running holding exactly this item's OWN arm, ready — a warm start: the
	#     request is answered by the model already there, so nothing is loaded,
	#     nothing is swapped and nothing is unloaded. The two lanes are kept apart
	#     by D-E06's lease, which this function has just taken, not by an empty
	#     /running; the old empty-only rule only starved this lane (MEASURED
	#     16:48Z-18:25Z: 600 s of waiting per pass on the loop's own arm).
	#   * a FOREIGN model — waited out in full. Its TTL is its own and this loop
	#     never unloads it; RUNNING_WAIT is set above that TTL so the wait can
	#     actually contain it.
	WARM_START=false
	RESIDENT_BEFORE=none
	while :; do
		line=$(running_verdict "$ARM_MODEL")
		IFS=$'\t' read -r verdict models <<<"$line"
		case "$verdict" in
			unreadable)
				item_say "llama-swap /running is not readable at $PROBE_URL"
				return 1 ;;
			empty)
				[ "$waited" -gt 0 ] && item_say "waited ${waited}s for the resident model's own TTL"
				return 0 ;;
			own-row)
				WARM_START=true
				RESIDENT_BEFORE=$ARM_MODEL
				item_say "warm start after ${waited}s: /running holds this item's OWN arm $ARM_MODEL in state $OWN_ROW_READY_STATE, and the seat is D-E06's lease — the serve gate opens, nothing is loaded and nothing is unloaded (D-E16)"
				return 0 ;;
		esac
		if [ "$waited" -ge "$RUNNING_WAIT" ]; then
			item_say "/running still holds a FOREIGN model after ${waited}s ($models); this loop never unloads it"
			return 1
		fi
		[ "$waited" = 0 ] && item_say "a FOREIGN model holds the row ($models), not this item's arm $ARM_MODEL; waiting out its own TTL inside a ${RUNNING_WAIT}s budget, never an unload and never a second concurrent request"
		sleep 5
		waited=$((waited + 5))
	done
}

capture_journals() { # started finished
	local since until
	since=$(date -d "$1 -30 seconds" '+%Y-%m-%d %H:%M:%S' 2>/dev/null) || since=$1
	until=$(date -d "$2 +30 seconds" '+%Y-%m-%d %H:%M:%S' 2>/dev/null) || until=$2
	if [ "$LOCAL_ARM" = 1 ]; then
		journalctl -u llama-swap -o short-iso-precise --no-pager \
			--since "$since" --until "$until" >"$EVIDENCE/llama-journal.log" 2>"$TMP/journal.err" ||
			item_say "journalctl -u llama-swap failed: $(head -1 "$TMP/journal.err")"
	fi
	# The five-minute drain is the coordinator's other GPU tenant (§2.4, B8): record
	# whether it fired inside the window, and what it enqueued.
	journalctl --user -u tally-drain.service -o short-iso-precise --no-pager \
		--since "$since" --until "$until" >"$EVIDENCE/drain-journal.log" 2>/dev/null ||
		: >"$EVIDENCE/drain-journal.log"
}

refuse() { # stage reason rc
	local stage=$1 reason=$2 rc=$3
	mkdir -p "$EVIDENCE"
	jq -n --arg rung "$ITEM" --argjson attempt "$ATTEMPT_TARGET" --arg stage "$stage" \
		--arg reason "$reason" --argjson rc "$rc" \
		--arg at "$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ)" \
		'{rung:$rung, attempt:$attempt, stage:$stage, reason:$reason, rc:$rc, refused_at:$at,
		  receipt:"none", results_row:"none",
		  rule:"a required cell that cannot be stamped is named, never invented (§2.3); no §2.3 receipt and no results row are written for a refused item"}' \
		>"$EVIDENCE/refusal.json"
	release_gpu_lease
	item_say "REFUSED at $stage (rc $rc): $reason"
	item_say "no receipt and no results row are claimed for $ITEM attempt $ATTEMPT_TARGET"
	REFUSALS=$((REFUSALS + 1))
	CONSECUTIVE=$((CONSECUTIVE + 1))
	git_register add -- "receipts/E1/$ITEM" >/dev/null 2>&1 || true
	git_register commit -q -m "E1: $ITEM attempt $ATTEMPT_TARGET refused at $stage — no receipt, no row" \
		-- "receipts/E1/$ITEM" >/dev/null 2>&1 || true
}

# ---------------------------------------------------------------- --bank ----- 
# The lane's resume path: an item whose worker and evaluator already ran, whose
# evidence is on disk, but whose banking did not complete. It re-derives the
# receipt from that evidence and never dispatches, so it can claim nothing the
# retained evidence does not carry.
if [ "$BANK" = 1 ]; then
	ITEM=$RUNG ATTEMPT_TARGET=$ATTEMPT
	KIT_REL="kits/local/e1/$ITEM-attempt-$ATTEMPT_TARGET.md"
	CARD_REL="fixtures/e1/cards/$ITEM-attempt-$ATTEMPT_TARGET.md"
	PROMPT_REL="fixtures/e1/$ITEM-prompt.md"
	if [ "$ATTEMPT_TARGET" = 1 ]; then EVIDENCE="$ROOT/receipts/E1/$ITEM"
	else EVIDENCE="$ROOT/receipts/E1/$ITEM/attempt-$ATTEMPT_TARGET"; fi
	ROW=$(row_of "$ITEM")
	for required in "$KIT_REL" "$CARD_REL" "$PROMPT_REL" \
		"receipts/E1/$ITEM/worker-window.json" "receipts/E1/$ITEM/evaluator-receipt.jsonl" \
		"receipts/E1/$ITEM/isolation.json"; do
		case "$required" in receipts/E1/$ITEM/*) rel=${required#receipts/E1/$ITEM/}; abs="$EVIDENCE/$rel" ;; *) abs="$ROOT/$required" ;; esac
		[ -f "$abs" ] || die "--bank $ITEM: required evidence is absent: $required"
	done
	[ -n "$(find "$EVIDENCE/session" -name '*.jsonl' -type f 2>/dev/null | head -1)" ] ||
		die "--bank $ITEM: no pi session under $EVIDENCE/session"
	grep -q PENDING-PRIOR-LOCK "$ROOT/$KIT_REL" "$ROOT/$CARD_REL" &&
		die "--bank $ITEM: the kit and card were never locked before a dispatch"
	kit_json=$(awk '/^```json$/ { inside=1; next } inside && /^```$/ { exit } inside { print }' "$ROOT/$KIT_REL")
	WORKTREE=$(jq -er '.paths.worktree' <<<"$kit_json")
	[ -d "$WORKTREE" ] || die "--bank $ITEM: the replay worktree $WORKTREE is gone, so the receipt's worktree assertions cannot be checked"
	say "--bank $ITEM attempt $ATTEMPT_TARGET: composing from the evidence on disk; dispatching nothing"
	BANKED=0 SKIPPED=0 REFUSALS=0 CONSECUTIVE=0
	BANKED_ITEMS=()
	bank_item
	bank_rc=$?
	say "banked $BANKED, refused $REFUSALS"
	exit $(( bank_rc == 0 ? 0 : 1 ))
fi

# ---------------------------------------------------------------------- loop --
if [ "$PARKED" -gt 0 ]; then
	# The park is committed beside the evidence it was read from, so the working
	# tree is clean when the first item starts (an uncommitted file lingers and
	# stalls the lane). Nothing is deleted and no results row is written.
	park_paths=$(jq -r '.parked[] | "receipts/E1/\(.rung)/park.json"' "$plan_json")
	# shellcheck disable=SC2086
	git_register add -- $park_paths >/dev/null 2>&1 || true
	# shellcheck disable=SC2086
	# Not "after two": since FIX-E14 a park is either R-c08's two counted refusals or
	# three identical transient ones, and the count is in each park.json's own reason.
	git_register commit -q -m "E1: $PARKED rung(s) parked — no dispatch, no results row, evidence kept" \
		-- $park_paths >/dev/null 2>&1 || true
	jq -r '.parked[] | "parked \(.rung) after \(.park.refused_attempts) refused attempts: \(.park.reason)"' "$plan_json" |
		while IFS= read -r line; do say "$line"; done
	say "parked rungs are not dispatched; an operator meets the resume condition in receipts/E1/<rung>/park.json and removes the file"
fi
say "population: ready $READY, deferred $DEFERRED, parked $PARKED, not eligible $INELIGIBLE; attempt target $ATTEMPT$( [ "$REATTEMPT" = 1 ] && printf ' (next)' )"
# --limit N walks the population from the top and dispatches at most N items that
# are not banked yet; a banked item is skipped and never replayed, so the lane
# resumes where cards/e1-results.tsv says it left off. --all is the lane's own
# verb — the whole eligible population, one at a time — and it is what U-D18's
# timer will call.
#
# A repeated IDENTICAL invocation of --limit/--rung dispatches nothing: the loop
# keeps its own invocation record inside this checkout's git directory (never
# committed, so a fresh worktree starts clean) and answers the repeat with the
# item the previous identical invocation banked. That is the oracle's idempotence
# clause, and it is also what a timer that fires twice must not do: two dispatches
# for one tick would be two model requests, which this lane never makes.
INVOCATION_KEY=$(printf '%s' "$ORIGINAL_ARGV")
if [ "$ALL" = 0 ] && [ "$BANK" = 0 ] && [ -n "$INVOCATION_KEY" ]; then
	previous=$(lane_state_last "$INVOCATION_KEY")
	if [ -n "$previous" ]; then
		still_banked=$(jq -r '.banked[]' <<<"$previous" 2>/dev/null | while read -r done_item; do
			[ -n "$done_item" ] || continue
			done_rung=${done_item%%/*}; done_row=$(row_of "$done_rung" 2>/dev/null || printf '')
			row_exists "$done_rung" "$done_row" "${done_item##*/}" && printf '%s\n' "$done_item"
		done)
		if [ -n "$still_banked" ]; then
			say "an identical invocation ($INVOCATION_KEY) already banked $(printf '%s ' $still_banked)at $(jq -r '.at' <<<"$previous") in this checkout"
			say "nothing new to replay for it: idempotent, exiting 0. Continue the population with --all, or name a rung with --rung."
			exit 0
		fi
	fi
fi
COUNT=0
for rung in $POPULATION; do
	[ -n "$rung" ] || continue
	row=$(row_of "$rung")
	target=$ATTEMPT
	if [ "$REATTEMPT" = 1 ]; then target=$(attempt_of "$rung" "$row"); fi
	if row_exists "$rung" "$row" "$target"; then
		say "$rung/$row/attempt $target is already a row of cards/e1-results.tsv — nothing replayed"
		SKIPPED=$((SKIPPED + 1))
		continue
	fi
	if [ "$ALL" = 0 ] && [ -z "$RUNG" ] && [ "$COUNT" -ge "$LIMIT" ]; then break; fi
	COUNT=$((COUNT + 1))
	run_item "$rung" "$target" || true
	if [ "$CONSECUTIVE" -ge "$CONSECUTIVE_CRASH_ABORT" ]; then
		say "abort: $CONSECUTIVE consecutive items could not be measured (§4.4.6 abort_on.consecutive_crash)"
		break
	fi
done

if [ "$BANKED" -gt 0 ] && [ "$ALL" = 0 ] && [ "$BANK" = 0 ]; then
	lane_state_record "$INVOCATION_KEY"
fi
say "banked $BANKED, skipped $SKIPPED, refused $REFUSALS (of $COUNT dispatched)"
if [ "$REFUSALS" -gt 0 ]; then
	say "the refusals are named in receipts/E1/<rung>/refusal.json; no receipt was claimed for them"
	exit 1
fi
if [ "$BANKED" = 0 ] && [ "$SKIPPED" = 0 ]; then
	say "the eligible population is empty: nothing to replay"
fi
exit 0
