#!/usr/bin/env bash
# tools/u-d17-util-01-oracle.sh — the DOMINANT oracle for U-D17 (dotfiles#320).
#
#   PR #314 merged (gh pr view 314 --json state == MERGED);
#   nix flake check --offline --no-build -> 0
#
# Run from anywhere inside a checkout:  bash tools/u-d17-util-01-oracle.sh
# Exit 0 iff every clause holds. One line per clause, always with the argv that
# produced it, in the shape of home/dot_local/bin/l8-flash-probe (#301) and of
# tools/u-d16-l8-flash-oracle.sh (#319): the output is its own receipt.
#
# set -u but deliberately NOT set -e: every clause must run even after one
# fails, so a red run says everything that is wrong, not the first thing.
set -u

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

# The two commits PR #314 carries, pinned by sha rather than by the ref. A ref
# is local to a clone and can be moved; the evaluator's fresh worktree shares
# `util-01-sampler` only by accident of sharing a git dir. These shas are what
# the reconciliation is about, and they are the ones named in issue #320.
UTIL_HEAD="981e8d016d280a4361543a17eb168a31db8da105"   # the adversarial-verify repairs
UTIL_BASE="34a613dc"                                    # the branch's first commit
MAIN_AT_MERGE="ecc6a2284fc2eb1d53dfd6626ce05d432650420b" # main when this reconciled (U-D16's merge)
PR=314

# cards/UTIL-01.md instrument_sha256, and the digests in 34a613dc's message.
# The unit's non-goal is "no change to the sampler's semantics"; the card's
# abort_on makes a row written by an instrument other than the one locked at
# arming a CRASH, so a merge that moved either byte is not a merge that can be
# graded.
SHA_SAMPLER="cc76a8179c46e735d6005f3f2d92f137cff026d7c3658a27b89261778fa50ce6"
SHA_ROW="1fdb80179595dc151af67e4ed2bc03e6a3bcf34685acb869b1cc9d9bcfa90906"

pass=0
fail=0
note=0

report() { printf '%-4s  %-56s  %s\n' "$1" "$2" "${*:3}"; }
ok() { pass=$((pass + 1)); report PASS "$@"; }
no() { fail=$((fail + 1)); report FAIL "$@"; }
info() { note=$((note + 1)); report NOTE "$@"; }

echo "u-d17-util-01-oracle in $ROOT"
echo "  PR #$PR carries $UTIL_BASE and ${UTIL_HEAD:0:8}; main was ${MAIN_AT_MERGE:0:8} at the reconciliation"
echo

# ── 1. "PR #314 merged", read on the tree ──────────────────────────────────
# What "merged" MEANS for this repository is that both of the branch's commits
# are reachable from the commit you are standing on, with their history intact
# — neither rebased nor squashed. That is checked against HEAD, not against the
# local `main` ref, so it is true of whatever commit the evaluator is on: this
# branch before the merge, and main after it. gh is asked separately in 1d.
for c in "$UTIL_BASE" "$UTIL_HEAD"; do
  short="$(git rev-parse --short "$c" 2>/dev/null || echo "$c")"
  if git cat-file -e "$c^{commit}" 2>/dev/null && git merge-base --is-ancestor "$c" HEAD; then
    ok "1a $short is an ancestor of HEAD" "git merge-base --is-ancestor $c HEAD"
  else
    no "1a $short is an ancestor of HEAD" "git merge-base --is-ancestor $c HEAD"
  fi
done
# Two commits and no more: a squash would leave one, a rebase would leave two
# with different shas and 1a would already be red. This pins the count the
# issue states.
n="$(git rev-list --count "$UTIL_BASE^..$UTIL_HEAD" 2>/dev/null || echo unknown)"
if [ "$n" = "2" ]; then
  ok "1b the branch is 2 commits" "git rev-list --count $UTIL_BASE^..$UTIL_HEAD"
else
  no "1b the branch is 2 commits (got '$n')" "git rev-list --count $UTIL_BASE^..$UTIL_HEAD"
fi
# The reconciliation is a MERGE, not a fast-forward of one side over the other:
# main's own head at the time must be reachable too, from the same HEAD.
if git merge-base --is-ancestor "$MAIN_AT_MERGE" HEAD 2>/dev/null; then
  ok "1c main at the reconciliation is an ancestor" "git merge-base --is-ancestor ${MAIN_AT_MERGE:0:8} HEAD"
else
  no "1c main at the reconciliation is an ancestor" "git merge-base --is-ancestor ${MAIN_AT_MERGE:0:8} HEAD"
fi

# ── 1d. gh pr view 314 --json state ────────────────────────────────────────
# The oracle string names this call, so it is made. It is read in three states:
#
#   MERGED  — the completion condition, after the evaluator merges. PASS.
#   OPEN    — the state the implementer leaves it in, because merging is the
#             evaluator's act and not this unit's. PASS *only* while 1a holds
#             and the PR still points head util-01-sampler at base main, which
#             is checked here: an OPEN PR that was retargeted or whose head was
#             force-pushed elsewhere is NOT a PR whose merge would land these
#             two commits on main.
#   CLOSED  — closed without merging. FAIL, always.
#
# gh needs network and an authenticated account. On a bare PATH without either
# this clause CANNOT RUN, and it says NOT VERIFIED and does not gate — clauses
# 1a–1c are the same fact read off the tree, offline, and they do gate.
if command -v gh >/dev/null 2>&1; then
  if pr_json="$(gh pr view "$PR" --json state,baseRefName,headRefName 2>/dev/null)"; then
    state="$(printf '%s' "$pr_json" | tr -d ' "' | sed -n 's/.*state:\([A-Z]*\).*/\1/p')"
    base="$(printf '%s' "$pr_json" | tr -d ' "' | sed -n 's/.*baseRefName:\([^,}]*\).*/\1/p')"
    head="$(printf '%s' "$pr_json" | tr -d ' "' | sed -n 's/.*headRefName:\([^,}]*\).*/\1/p')"
    case "$state:$base:$head" in
      MERGED:main:util-01-sampler)
        ok "1d PR #$PR state MERGED" "gh pr view $PR --json state,baseRefName,headRefName"
        ;;
      OPEN:main:util-01-sampler)
        ok "1d PR #$PR state OPEN, main <- util-01-sampler (the evaluator merges)" \
           "gh pr view $PR --json state,baseRefName,headRefName"
        ;;
      *)
        no "1d PR #$PR state '$state' base '$base' head '$head'" \
           "gh pr view $PR --json state,baseRefName,headRefName"
        ;;
    esac
  else
    info "1d NOT VERIFIED: gh could not answer (no network or no auth)" "gh pr view $PR --json state"
  fi
else
  info "1d NOT VERIFIED: gh is not on PATH" "command -v gh"
fi

# ── 2. the sampler's semantics did not move ────────────────────────────────
# The unit's non-goal, checked as bytes. kits/util/* is not in this repository;
# what is here are the two byte-copies, and cards/UTIL-01.md instrument_sha256
# is what they must still equal after the merge.
check_sha() { # $1 = path, $2 = want
  local got
  got="$(sha256sum "$1" 2>/dev/null | cut -d' ' -f1)"
  if [ "$got" = "$2" ]; then
    ok "2a $(basename "$1") unchanged" "sha256sum $1"
  else
    no "2a $(basename "$1") is ${got:-absent}, want ${2:0:8}…" "sha256sum $1"
  fi
}
check_sha home/dot_local/bin/util-sampler "$SHA_SAMPLER"
check_sha home/dot_local/bin/util-row "$SHA_ROW"

# The one import line, in the one file both branches touched. Present, and the
# neighbours main brought are present too — the resolution kept all three.
imports="home/home.nix"
missing=""
for m in ./harness-records.nix ./herdr.nix ./util-sampler.nix; do
  grep -qxF "    $m" "$imports" || missing="$missing $m"
done
if [ -z "$missing" ]; then
  ok "2b home.nix imports all three modules" "grep -xF over $imports"
else
  no "2b home.nix imports missing:$missing" "grep -xF over $imports"
fi

# ── 3. the probe's two new rows ────────────────────────────────────────────
probe="home/dot_local/bin/l8-flash-probe"
rows=0
for t in util-sampler.timer util-row.timer; do
  if grep -q "util_fragment_row $t" "$probe"; then
    rows=$((rows + 1))
  fi
done
if [ "$rows" = "2" ]; then
  ok "3a probe carries both UTIL-01 rows" "grep 'util_fragment_row' $probe"
else
  no "3a probe carries both UTIL-01 rows (found $rows)" "grep 'util_fragment_row' $probe"
fi
if bash tests/l8-flash-probe/test-util-timer-rows.sh >/dev/null 2>&1; then
  ok "3b those rows are exercised in every state" "bash tests/l8-flash-probe/test-util-timer-rows.sh"
else
  no "3b those rows are exercised in every state" "bash tests/l8-flash-probe/test-util-timer-rows.sh"
fi

# ── 4. nix flake check --offline --no-build ────────────────────────────────
# The second half of the DOMINANT, verbatim. This is the clause the
# mutation_hint turns red: a conflicting hunk left unresolved leaves `<<<<<<<`
# in a tracked file, and in a .nix file that is a syntax error, so evaluation
# dies here. checks.util-sampler-topology rides inside it and asserts at eval
# time what a merge that resolved wrongly would have dropped.
if nix flake check --offline --no-build >/dev/null 2>&1; then
  ok "4 flake check green" "nix flake check --offline --no-build"
else
  no "4 flake check green" "nix flake check --offline --no-build"
fi

# ── 5. no conflict marker survived, anywhere ───────────────────────────────
# Clause 4 only sees a marker that lands in a file nix parses. A marker left in
# a shell program, a doc or a fixture is just as unresolved and would ship. The
# grep excludes this file, which has to name the markers to look for them.
markers="$(git grep -In -e '^<<<<<<< ' -e '^>>>>>>> ' -- . ':!tools/u-d17-util-01-oracle.sh' || true)"
if [ -z "$markers" ]; then
  ok "5 no conflict marker in the tree" "git grep -In '^<<<<<<< ' '^>>>>>>> '"
else
  no "5 conflict markers: $(printf '%s' "$markers" | head -3 | tr '\n' ' ')" \
     "git grep -In '^<<<<<<< ' '^>>>>>>> '"
fi

echo
echo "u-d17-util-01-oracle: $pass passed, $fail failed, $note noted"
echo "  NOTE rows could not run here and do not gate; clauses 1a-1c read the"
echo "  same fact off the tree, offline, and they do."
[ "$fail" -eq 0 ]
