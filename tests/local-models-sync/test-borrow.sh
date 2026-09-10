#!/usr/bin/env bash
# Hermetic contract for the explicit device-side model borrow transaction.
# No systemd, network, /var, or production model paths are touched.
set -euo pipefail

borrow="${LOCAL_MODELS_BORROW_BIN:-local-models-borrow}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

export LOCAL_MODELS_ROOT="$work/root"
export LOCAL_MODELS_LIBRARY="$work/library"
export LOCAL_MODELS_MANIFEST="$work/wanted.json"
export LOCAL_MODELS_BORROW_LOCK="$work/borrow.lock"
export LOCAL_MODELS_RESERVE_BYTES=0
mkdir -p "$LOCAL_MODELS_ROOT" "$LOCAL_MODELS_LIBRARY"

fail() {
  echo "FAIL  $*" >&2
  exit 1
}

expect_status() {
  expected="$1"
  output="$2"
  shift 2
  set +e
  "$@" >"$output" 2>&1
  actual="$?"
  set -e
  if [ "$actual" -ne "$expected" ]; then
    sed 's/^/      /' "$output" >&2
    fail "expected exit $expected, got $actual: $*"
  fi
}

write_manifest() {
  id="$1"
  name="$2"
  bytes="$3"
  oid="$4"
  printf '[{"id":"%s","files":[{"name":"%s","bytes":%s,"oid":"%s"}]}]\n' \
    "$id" "$name" "$bytes" "$oid" >"$LOCAL_MODELS_MANIFEST"
}

# Borrowing cannot happen accidentally: an explicit mode is mandatory.
expect_status 2 "$work/no-mode.out" "$borrow"
expect_status 2 "$work/extra-arg.out" "$borrow" --dry-run surprise
test ! -e "$LOCAL_MODELS_ROOT/alpha/model.gguf" || fail "implicit invocation copied a file"

# A dry-run calculates the complete plan but lands no bytes.
mkdir -p "$LOCAL_MODELS_LIBRARY/alpha"
printf 'model-payload' >"$LOCAL_MODELS_LIBRARY/alpha/model.gguf"
bytes="$(stat -c %s "$LOCAL_MODELS_LIBRARY/alpha/model.gguf")"
oid="$(sha256sum "$LOCAL_MODELS_LIBRARY/alpha/model.gguf" | cut -d' ' -f1)"
write_manifest alpha model.gguf "$bytes" "$oid"
expect_status 0 "$work/dry-run.out" "$borrow" --dry-run
grep -q 'PLAN 1 file(s)' "$work/dry-run.out" || fail "dry-run omitted its plan"
test ! -e "$LOCAL_MODELS_ROOT/alpha/model.gguf" || fail "dry-run copied a file"

# --yes verifies and atomically lands the requested file. An unrelated working
# copy stays exactly where it was: borrow is not a hidden prune operation.
mkdir -p "$LOCAL_MODELS_ROOT/legacy"
printf 'keep-me' >"$LOCAL_MODELS_ROOT/legacy/model.gguf"
legacy_before="$(sha256sum "$LOCAL_MODELS_ROOT/legacy/model.gguf")"
expect_status 0 "$work/apply.out" "$borrow" --yes
cmp "$LOCAL_MODELS_LIBRARY/alpha/model.gguf" "$LOCAL_MODELS_ROOT/alpha/model.gguf"
test ! -e "$LOCAL_MODELS_ROOT/alpha/model.gguf.part" || fail "successful borrow left a part file"
test "$(sha256sum "$LOCAL_MODELS_ROOT/legacy/model.gguf")" = "$legacy_before" \
  || fail "borrow changed an unrelated working copy"

# Once local bytes have landed, the NAS may disappear: a correctly sized
# working copy is left alone and remains usable.
mv "$LOCAL_MODELS_LIBRARY/alpha/model.gguf" "$work/source-offline"
expect_status 0 "$work/already-present.out" "$borrow" --yes
grep -q 'PLAN 0 file(s), 0 bytes' "$work/already-present.out" \
  || fail "existing working copy was not treated as complete"

# The whole capacity plan is refused before any copy starts. Raise the safety
# reserve above the fixture filesystem's capacity instead of allocating data.
mkdir -p "$LOCAL_MODELS_LIBRARY/oversize"
printf 'x' >"$LOCAL_MODELS_LIBRARY/oversize/model.gguf"
write_manifest oversize model.gguf 1 unused
export LOCAL_MODELS_RESERVE_BYTES=9223372036854775807
expect_status 3 "$work/no-space.out" "$borrow" --dry-run
grep -q 'REFUSING — transaction needs' "$work/no-space.out" \
  || fail "capacity refusal did not explain itself"
test ! -e "$LOCAL_MODELS_ROOT/oversize/model.gguf" || fail "capacity refusal copied a file"
export LOCAL_MODELS_RESERVE_BYTES=0

# An incomplete canonical Library also refuses before any destination write.
write_manifest missing model.gguf 7 unused
expect_status 5 "$work/missing.out" "$borrow" --yes
grep -q 'canonical NAS Library is incomplete' "$work/missing.out" \
  || fail "missing-source refusal did not explain itself"
test ! -e "$LOCAL_MODELS_ROOT/missing/model.gguf" || fail "missing-source refusal copied a file"

# A hash failure can never replace the destination or leave a partial file.
mkdir -p "$LOCAL_MODELS_LIBRARY/bad-hash"
printf 'wrong-hash' >"$LOCAL_MODELS_LIBRARY/bad-hash/model.gguf"
bytes="$(stat -c %s "$LOCAL_MODELS_LIBRARY/bad-hash/model.gguf")"
write_manifest bad-hash model.gguf "$bytes" 0000000000000000000000000000000000000000000000000000000000000000
expect_status 1 "$work/hash.out" "$borrow" --yes
test ! -e "$LOCAL_MODELS_ROOT/bad-hash/model.gguf" || fail "hash failure landed a destination"
test ! -e "$LOCAL_MODELS_ROOT/bad-hash/model.gguf.part" || fail "hash failure left a part file"

echo "local-model borrow transaction: all checks passed"
