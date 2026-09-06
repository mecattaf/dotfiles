#!/usr/bin/env bash
# Hermetic guard test for the local-models prune split (dotfiles#296).
#
# Asserts the two properties the ruling actually turns on:
#   1. the SERVICE path (local-models-sync-audit) deletes nothing, ever
#   2. `"$PRUNE_BIN" --yes` refuses unless the set it computes is exactly
#      the set a preceding `--dry-run` recorded — the dry-run diff must be 0
#
# Drives the real binaries through LOCAL_MODELS_ROOT / LOCAL_MODELS_MANIFEST /
# LOCAL_MODELS_PRUNE_STATE against a fixture tree. No network, no /var, no
# systemd, no model weights.
#
# WHICH BINARIES (dotfiles#296, U-D5). In nix the three are on PATH from the
# check's nativeBuildInputs and nothing below needs setting. Out of nix nothing
# puts them on PATH, and this suite used to report 6 pass / 13 fail with every
# failure reading "local-models-prune: command not found" — a guard nobody
# outside a nix build can run is a guard that rots. So:
#
#   LOCAL_MODELS_PRUNE_BIN         path to the `local-models-prune` VERB.
#                                  Its two siblings are looked for next to it,
#                                  which is exactly the symlinkJoin's layout:
#                                    nix build .#local-models-prune
#                                    LOCAL_MODELS_PRUNE_BIN=./result/bin/local-models-prune
#   LOCAL_MODELS_PRUNE_SET_BIN     override the ORACLE alone
#   LOCAL_MODELS_SYNC_AUDIT_BIN    override the SERVICE path alone
#
# Unset means "resolve from PATH", the in-nix behaviour, unchanged.
#
# Nothing here relaxes the guard. Pointing LOCAL_MODELS_PRUNE_BIN at a binary
# that is not the pruner (/bin/false, say) must still exit non-zero: the
# assertions are about observed behaviour, never about which path was named.
set -uo pipefail

fail=0
passes=0
total=0
check() { # $1 = description, $2 = actual, $3 = expected
  total=$((total + 1))
  if [ "$2" = "$3" ]; then
    passes=$((passes + 1))
    echo "PASS  $1"
  else
    echo "FAIL  $1"
    echo "        expected: $3"
    echo "        actual:   $2"
    fail=1
  fi
}

# Resolve one binary: an explicit override, else a sibling of the verb, else
# the bare name for PATH lookup. A bare name that PATH cannot resolve is left
# as-is deliberately — it fails the assertions that use it, with bash's own
# "command not found", rather than aborting before a single check has run.
resolve() { # $1 = override value (may be empty), $2 = basename
  if [ -n "$1" ]; then
    printf '%s\n' "$1"
    return
  fi
  if [ -n "${LOCAL_MODELS_PRUNE_BIN:-}" ]; then
    sibling="$(dirname "$LOCAL_MODELS_PRUNE_BIN")/$2"
    if [ -x "$sibling" ]; then
      printf '%s\n' "$sibling"
      return
    fi
  fi
  printf '%s\n' "$2"
}

PRUNE_BIN="${LOCAL_MODELS_PRUNE_BIN:-local-models-prune}"
PRUNE_SET_BIN="$(resolve "${LOCAL_MODELS_PRUNE_SET_BIN:-}" local-models-prune-set)"
AUDIT_BIN="$(resolve "${LOCAL_MODELS_SYNC_AUDIT_BIN:-}" local-models-sync-audit)"

echo "prune guard: verb    $PRUNE_BIN"
echo "prune guard: oracle  $PRUNE_SET_BIN"
echo "prune guard: audit   $AUDIT_BIN"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

export LOCAL_MODELS_ROOT="$work/root"
export LOCAL_MODELS_MANIFEST="$work/wanted.json"
export LOCAL_MODELS_PRUNE_STATE="$work/state/.prune-intent"

# ── fixture ────────────────────────────────────────────────────────────────
# kept-artifact: wanted, with one wanted file and one stray file
# gone-artifact: not in the manifest at all
mkdir -p "$LOCAL_MODELS_ROOT/kept-artifact" "$LOCAL_MODELS_ROOT/gone-artifact"
printf 'aaaa' >"$LOCAL_MODELS_ROOT/kept-artifact/model.gguf"   # 4 bytes, wanted
printf 'bb' >"$LOCAL_MODELS_ROOT/kept-artifact/stray.bin"      # 2 bytes, stray
printf 'cccccc' >"$LOCAL_MODELS_ROOT/gone-artifact/old.gguf"   # 6 bytes, retired

cat >"$LOCAL_MODELS_MANIFEST" <<'JSON'
[
  {
    "id": "kept-artifact",
    "files": [ { "name": "model.gguf", "bytes": 4, "oid": "unused-here" } ]
  }
]
JSON

inventory() { find "$LOCAL_MODELS_ROOT" | LC_ALL=C sort; }
before="$(inventory)"

# ── 1. the oracle names the right set ──────────────────────────────────────
set_out="$("$PRUNE_SET_BIN")"
check "prune-set names both entries" \
  "$(printf '%s\n' "$set_out" | cut -f1,3 | tr '\t' ':' | tr '\n' ';')" \
  "artifact:6;file:2;"

# ── 2. the SERVICE path audits and deletes nothing ─────────────────────────
audit_out="$("$AUDIT_BIN")"
check "audit prints the summary line" \
  "$(printf '%s\n' "$audit_out" | tail -1)" \
  "local-models-sync: AUDIT prune-set 2 entries, 8 bytes"
check "audit prints one would-prune line per entry" \
  "$(printf '%s\n' "$audit_out" | grep -c 'AUDIT would prune')" \
  "2"
check "audit deleted nothing" "$(inventory)" "$before"

# ── 3. --yes with no recorded dry-run refuses ──────────────────────────────
"$PRUNE_BIN" --yes >"$work/out.1" 2>&1
check "--yes without a dry-run exits 3" "$?" "3"
check "refusal names the missing intent" \
  "$(grep -c 'REFUSING — no recorded dry-run intent' "$work/out.1")" "1"
check "refused --yes deleted nothing" "$(inventory)" "$before"

# ── 4. --dry-run records, then the set CHANGES, then --yes refuses ─────────
"$PRUNE_BIN" --dry-run >"$work/out.2" 2>&1
check "--dry-run exits 0" "$?" "0"
check "--dry-run deleted nothing" "$(inventory)" "$before"
check "--dry-run recorded an intent" "$(test -s "$LOCAL_MODELS_PRUNE_STATE" && echo yes)" "yes"

printf 'dddddddd' >"$LOCAL_MODELS_ROOT/kept-artifact/second-stray.bin"
drifted="$(inventory)"
"$PRUNE_BIN" --yes >"$work/out.3" 2>&1
check "--yes after the set drifted exits 4" "$?" "4"
check "drift refusal says the diff must be 0" \
  "$(grep -c 'the dry-run diff must be 0' "$work/out.3")" "1"
check "refused --yes deleted nothing after drift" "$(inventory)" "$drifted"

# ── 5. dry-run then yes on an unchanged set deletes exactly that set ───────
"$PRUNE_BIN" --dry-run >"$work/out.4" 2>&1
"$PRUNE_BIN" --yes >"$work/out.5" 2>&1
check "--yes on a matching set exits 0" "$?" "0"
check "the retired artifact is gone" \
  "$(test -e "$LOCAL_MODELS_ROOT/gone-artifact" && echo present || echo gone)" "gone"
check "both stray files are gone" \
  "$(find "$LOCAL_MODELS_ROOT" -name '*stray*' | wc -l)" "0"
check "the wanted file survived" \
  "$(cat "$LOCAL_MODELS_ROOT/kept-artifact/model.gguf")" "aaaa"
check "the intent file is consumed" \
  "$(test -e "$LOCAL_MODELS_PRUNE_STATE" && echo present || echo gone)" "gone"

# ── 6. an empty prune set is a no-op, not an error ─────────────────────────
"$PRUNE_BIN" --dry-run >"$work/out.6" 2>&1
check "empty set dry-run summary" \
  "$(grep -c 'prune-set 0 entries, 0 bytes' "$work/out.6")" "1"

# The count is part of the oracle's output, not decoration: a suite that skips
# assertions when a binary is missing would otherwise report success.
if [ "$fail" = 0 ]; then
  echo "local-models-sync prune guard: $passes/$total checks passed"
else
  echo "local-models-sync prune guard: $passes/$total checks passed, FAILURES above" >&2
fi
exit "$fail"
