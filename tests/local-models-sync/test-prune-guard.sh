#!/usr/bin/env bash
# Hermetic guard test for the local-models prune split (dotfiles#296).
#
# Asserts the two properties the ruling actually turns on:
#   1. the SERVICE path (local-models-sync-audit) deletes nothing, ever
#   2. `local-models-prune --yes` refuses unless the set it computes is exactly
#      the set a preceding `--dry-run` recorded — the dry-run diff must be 0
#
# Drives the real binaries through LOCAL_MODELS_ROOT / LOCAL_MODELS_MANIFEST /
# LOCAL_MODELS_PRUNE_STATE against a fixture tree. No network, no /var, no
# systemd, no model weights.
set -uo pipefail

fail=0
check() { # $1 = description, $2 = actual, $3 = expected
  if [ "$2" = "$3" ]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1"
    echo "        expected: $3"
    echo "        actual:   $2"
    fail=1
  fi
}

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
set_out="$(local-models-prune-set)"
check "prune-set names both entries" \
  "$(printf '%s\n' "$set_out" | cut -f1,3 | tr '\t' ':' | tr '\n' ';')" \
  "artifact:6;file:2;"

# ── 2. the SERVICE path audits and deletes nothing ─────────────────────────
audit_out="$(local-models-sync-audit)"
check "audit prints the summary line" \
  "$(printf '%s\n' "$audit_out" | tail -1)" \
  "local-models-sync: AUDIT prune-set 2 entries, 8 bytes"
check "audit prints one would-prune line per entry" \
  "$(printf '%s\n' "$audit_out" | grep -c 'AUDIT would prune')" \
  "2"
check "audit deleted nothing" "$(inventory)" "$before"

# ── 3. --yes with no recorded dry-run refuses ──────────────────────────────
local-models-prune --yes >"$work/out.1" 2>&1
check "--yes without a dry-run exits 3" "$?" "3"
check "refusal names the missing intent" \
  "$(grep -c 'REFUSING — no recorded dry-run intent' "$work/out.1")" "1"
check "refused --yes deleted nothing" "$(inventory)" "$before"

# ── 4. --dry-run records, then the set CHANGES, then --yes refuses ─────────
local-models-prune --dry-run >"$work/out.2" 2>&1
check "--dry-run exits 0" "$?" "0"
check "--dry-run deleted nothing" "$(inventory)" "$before"
check "--dry-run recorded an intent" "$(test -s "$LOCAL_MODELS_PRUNE_STATE" && echo yes)" "yes"

printf 'dddddddd' >"$LOCAL_MODELS_ROOT/kept-artifact/second-stray.bin"
drifted="$(inventory)"
local-models-prune --yes >"$work/out.3" 2>&1
check "--yes after the set drifted exits 4" "$?" "4"
check "drift refusal says the diff must be 0" \
  "$(grep -c 'the dry-run diff must be 0' "$work/out.3")" "1"
check "refused --yes deleted nothing after drift" "$(inventory)" "$drifted"

# ── 5. dry-run then yes on an unchanged set deletes exactly that set ───────
local-models-prune --dry-run >"$work/out.4" 2>&1
local-models-prune --yes >"$work/out.5" 2>&1
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
local-models-prune --dry-run >"$work/out.6" 2>&1
check "empty set dry-run summary" \
  "$(grep -c 'prune-set 0 entries, 0 bytes' "$work/out.6")" "1"

if [ "$fail" = 0 ]; then
  echo "local-models-sync prune guard: all checks passed"
else
  echo "local-models-sync prune guard: FAILURES above" >&2
fi
exit "$fail"
