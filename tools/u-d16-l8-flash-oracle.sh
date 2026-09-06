#!/usr/bin/env bash
# tools/u-d16-l8-flash-oracle.sh — the DOMINANT oracle for U-D16 (dotfiles#319).
#
#   git merge-base --is-ancestor <l8-flash head> main after the PR merges;
#   nix flake check --offline --no-build -> 0;
#   nix build of the coordinator toplevel --dry-run succeeds;
#   the hand-written claude-transcript-mirror units are removed in the same PR
#   as the walkthrough says
#
# Run from anywhere inside a checkout:  bash tools/u-d16-l8-flash-oracle.sh
# Exit 0 iff every clause holds. One line per clause, always with the argv that
# produced it, in the shape of home/dot_local/bin/l8-flash-probe (#301): the
# output is its own receipt.
#
# set -u but deliberately NOT set -e: every clause must run even after one
# fails, so a red run says everything that is wrong, not the first thing.
set -u

ROOT="$(git rev-parse --show-toplevel)"
cd "$ROOT"

# The branch head, pinned. `git rev-parse l8-flash` is NOT used as the source of
# truth: the ref is local to this machine's clone, the evaluator's fresh
# worktree shares it only by accident of sharing a git dir, and a ref can be
# moved. The sha is what the reconciliation is about.
L8_FLASH_HEAD="e549ba911e8d8c9ff1c19b4fa9b0b6df45244f7f"
L8_FLASH_BASE="88c7c755"   # ad8a9119's first parent: where the branch forked
MANIFEST="$ROOT/tools/u-d16"

pass=0
fail=0
note=0

report() { printf '%-4s  %-52s  %s\n' "$1" "$2" "${*:3}"; }
ok() { pass=$((pass + 1)); report PASS "$@"; }
no() { fail=$((fail + 1)); report FAIL "$@"; }
info() { note=$((note + 1)); report NOTE "$@"; }

echo "u-d16-l8-flash-oracle in $ROOT"
echo "  l8-flash head $L8_FLASH_HEAD, forked at $L8_FLASH_BASE"
echo

# ── 1. ancestry: main is the ancestor-closure of the branch ─────────────────
# The reconciliation's completion condition, verbatim from the issue: the
# branch's head is reachable from main, so `main..l8-flash` is empty and the
# branch is only history. Checked against HEAD, not the local `main` ref, so it
# is true of whatever commit the evaluator is standing on.
if git cat-file -e "$L8_FLASH_HEAD^{commit}" 2>/dev/null; then
  ok "1a l8-flash head is a commit here" "git cat-file -e $L8_FLASH_HEAD^{commit}"
  if git merge-base --is-ancestor "$L8_FLASH_HEAD" HEAD; then
    ok "1b head is an ancestor of HEAD" "git merge-base --is-ancestor $L8_FLASH_HEAD HEAD"
  else
    no "1b head is an ancestor of HEAD" "git merge-base --is-ancestor $L8_FLASH_HEAD HEAD"
  fi
  behind="$(git rev-list --count "HEAD..$L8_FLASH_HEAD" 2>/dev/null || echo unknown)"
  if [ "$behind" = "0" ]; then
    ok "1c HEAD..head is empty" "git rev-list --count HEAD..$L8_FLASH_HEAD"
  else
    no "1c HEAD..head is empty (got '$behind')" "git rev-list --count HEAD..$L8_FLASH_HEAD"
  fi
  n="$(git rev-list --count "$L8_FLASH_BASE..$L8_FLASH_HEAD" 2>/dev/null || echo unknown)"
  if [ "$n" = "30" ]; then
    ok "1d the reconciliation is 30 commits" "git rev-list --count $L8_FLASH_BASE..$L8_FLASH_HEAD"
  else
    no "1d the reconciliation is 30 commits (got '$n')" "git rev-list --count $L8_FLASH_BASE..$L8_FLASH_HEAD"
  fi
  # The merge is preserved, not rebased or squashed: ad8a9119 (the herdr merge)
  # is still a merge commit reachable from HEAD, and the branch head is still a
  # single-parent commit on the first-parent line.
  if [ "$(git rev-list --parents -n1 ad8a9119 2>/dev/null | wc -w)" = "3" ] \
     && git merge-base --is-ancestor ad8a9119 HEAD 2>/dev/null; then
    ok "1e the herdr merge is preserved as a merge" "git rev-list --parents -n1 ad8a9119"
  else
    no "1e the herdr merge is preserved as a merge" "git rev-list --parents -n1 ad8a9119"
  fi
else
  no "1a l8-flash head is a commit here" "git cat-file -e $L8_FLASH_HEAD^{commit}"
fi

# ── 2. content closure: the 30 commits' effect is still in the tree ─────────
# Ancestry alone cannot see a `git revert`: a revert ADDS a commit, so 1b stays
# green while the branch's content is undone. tools/u-d16/ pins that content —
# blob identity where main has not touched the path since, line survival where
# it has, absence where the branch deleted. This is the clause the
# mutation_hint's "revert one of the 30 commits" turns red.
bad=0
while IFS=$'\t' read -r blob path; do
  [ -n "${blob:-}" ] || continue
  if [ ! -e "$path" ]; then
    bad=$((bad + 1))
    [ "$bad" -le 5 ] && echo "      missing: $path"
    continue
  fi
  got="$(git hash-object -- "$path" 2>/dev/null || echo none)"
  if [ "$got" != "$blob" ]; then
    bad=$((bad + 1))
    [ "$bad" -le 5 ] && echo "      changed: $path ($got != $blob)"
  fi
done < "$MANIFEST/closure-blobs.tsv"
rows="$(wc -l < "$MANIFEST/closure-blobs.tsv")"
if [ "$bad" -eq 0 ]; then
  ok "2a $rows pinned blobs unchanged" "git hash-object over tools/u-d16/closure-blobs.tsv"
else
  no "2a $bad of $rows pinned blobs differ" "git hash-object over tools/u-d16/closure-blobs.tsv"
fi

back=0
while IFS= read -r path; do
  [ -n "${path:-}" ] || continue
  if [ -e "$path" ]; then
    back=$((back + 1))
    [ "$back" -le 5 ] && echo "      resurrected: $path"
  fi
done < "$MANIFEST/closure-absent.txt"
rows="$(wc -l < "$MANIFEST/closure-absent.txt")"
if [ "$back" -eq 0 ]; then
  ok "2b $rows deleted paths still absent" "test ! -e over tools/u-d16/closure-absent.txt"
else
  no "2b $back of $rows deleted paths are back" "test ! -e over tools/u-d16/closure-absent.txt"
fi

lost=0
total=0
while IFS=$'\t' read -r path linefile; do
  [ -n "${path:-}" ] || continue
  while IFS= read -r line; do
    total=$((total + 1))
    if ! grep -qxF -- "$line" "$path" 2>/dev/null; then
      lost=$((lost + 1))
      [ "$lost" -le 5 ] && echo "      dropped from $path: $line"
    fi
  done < "$MANIFEST/$linefile"
done < "$MANIFEST/closure-lines.tsv"
if [ "$lost" -eq 0 ]; then
  ok "2c $total pinned lines still present" "grep -qxF over tools/u-d16/lines/"
else
  no "2c $lost of $total pinned lines are gone" "grep -qxF over tools/u-d16/lines/"
fi

# Coverage: every one of the 30 commits must touch at least one manifest row,
# or the manifest would be blind to reverting exactly that commit. A merge whose
# diff against its first parent is empty is exempt — there is nothing to revert.
if git cat-file -e "$L8_FLASH_HEAD^{commit}" 2>/dev/null; then
  cut -f2 "$MANIFEST/closure-blobs.tsv" > "$MANIFEST/.paths"
  cat "$MANIFEST/closure-absent.txt" >> "$MANIFEST/.paths"
  cut -f1 "$MANIFEST/closure-lines.tsv" >> "$MANIFEST/.paths"
  blind=""
  for c in $(git rev-list "$L8_FLASH_BASE..$L8_FLASH_HEAD"); do
    touched="$(git show --pretty=format: --name-only "$c" | grep -v '^$' || true)"
    [ -n "$touched" ] || continue
    if ! printf '%s\n' "$touched" | grep -qxFf "$MANIFEST/.paths"; then
      blind="$blind $(git rev-parse --short "$c")"
    fi
  done
  rm -f "$MANIFEST/.paths"
  if [ -z "$blind" ]; then
    ok "2d all 30 commits are covered by a row" "git rev-list $L8_FLASH_BASE..$L8_FLASH_HEAD"
  else
    no "2d commits with no row:$blind" "git rev-list $L8_FLASH_BASE..$L8_FLASH_HEAD"
  fi
fi

# ── 3. nix flake check --offline --no-build ─────────────────────────────────
if nix flake check --offline --no-build >/dev/null 2>&1; then
  ok "3 flake check green" "nix flake check --offline --no-build"
else
  no "3 flake check green" "nix flake check --offline --no-build"
fi

# ── 4. the coordinator toplevel evaluates ──────────────────────────────────
# --dry-run: the merged tree must be known-evaluable before anyone rebuilds
# from it. It builds nothing, so it is safe to run here; U-D19 does the switch.
attr='.#nixosConfigurations.coordinator.config.system.build.toplevel'
if nix build --offline --dry-run "$attr" >/dev/null 2>&1; then
  ok "4 coordinator toplevel --dry-run" "nix build --offline --dry-run $attr"
else
  no "4 coordinator toplevel --dry-run" "nix build --offline --dry-run $attr"
fi

# ── 5. the hand-written claude-transcript-mirror pair ───────────────────────
# The walkthrough splits this in two and this oracle keeps the split honest.
#
# The REPO half is gated here: the declared replacement is on main, the repo
# tracks no plain unit file of either name, and l8-flash-probe carries a row
# that says out loud whether the hand-written pair is still on the box.
#
# The SHELL half — `systemctl --user disable --now` and the two `rm`s — is
# Tom's act and nobody else's (scopes/clean-dotfiles.md:171 §6), it is step 4 of
# the P05 walkthrough, and it must not happen before the switch that replaces
# it: the hand-written pair is the ONLY working mirror until then. It is
# sequenced inside U-D19 and carried as DEFERRED.md row DF-U-D16-1. Its state on
# this box is reported below as NOTE and does not gate: an oracle that went red
# on it would be demanding that this unit break the mirror.
decl="home/harness-records.nix"
if grep -q 'systemd\.user\.services\.claude-transcript-mirror' "$decl" \
   && grep -q 'systemd\.user\.timers\.claude-transcript-mirror' "$decl"; then
  ok "5a declared replacement on main" "grep systemd.user.{services,timers}.claude-transcript-mirror $decl"
else
  no "5a declared replacement on main" "grep systemd.user.{services,timers}.claude-transcript-mirror $decl"
fi
tracked="$(git ls-files | grep -E '(^|/)claude-transcript-mirror\.(service|timer)$' || true)"
if [ -z "$tracked" ]; then
  ok "5b no hand-written unit file tracked" "git ls-files | grep claude-transcript-mirror.(service|timer)"
else
  no "5b tracked hand-written unit: $tracked" "git ls-files | grep claude-transcript-mirror.(service|timer)"
fi
probe="home/dot_local/bin/l8-flash-probe"
if grep -q 'hand-written pair gone' "$probe"; then
  ok "5c probe carries the hand-written-pair row" "grep 'hand-written pair gone' $probe"
else
  no "5c probe carries the hand-written-pair row" "grep 'hand-written pair gone' $probe"
fi
if bash tests/l8-flash-probe/test-handwritten-row.sh >/dev/null 2>&1; then
  ok "5d that probe row is exercised both ways" "bash tests/l8-flash-probe/test-handwritten-row.sh"
else
  no "5d that probe row is exercised both ways" "bash tests/l8-flash-probe/test-handwritten-row.sh"
fi
left=""
for u in service timer; do
  [ -e "$HOME/.config/systemd/user/claude-transcript-mirror.$u" ] && left="$left $u"
done
if [ -z "$left" ]; then
  info "5e box: hand-written pair gone (TOM LINE done)" "ls ~/.config/systemd/user/claude-transcript-mirror.*"
else
  info "5e box: hand-written pair present ($left) — DF-U-D16-1, U-D19 step 4" "ls ~/.config/systemd/user/claude-transcript-mirror.*"
fi

echo
echo "u-d16-l8-flash-oracle: $pass passed, $fail failed, $note noted"
echo "  NOTE rows report state this unit is barred from changing; they do not gate."
[ "$fail" -eq 0 ]
