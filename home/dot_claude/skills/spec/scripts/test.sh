#!/bin/sh
# test.sh — run spec-check.sh against the bundled fixtures and check the
# exit code each is supposed to produce. Run from anywhere:
#   home/dot_claude/skills/spec/scripts/test.sh
set -eu

here=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
check="$here/spec-check.sh"
fail=0

run() {
	name="$1"
	spec="$2"
	want="$3"
	set +e
	out=$("$check" "$spec" 2>&1)
	rc=$?
	set -e
	if [ "$rc" -eq "$want" ]; then
		echo "ok   - $name (exit $rc)"
	else
		echo "FAIL - $name: expected exit $want, got $rc"
		echo "$out" | sed 's/^/       /'
		fail=1
	fi
}

run "valid-1 (clean spec)" "$here/fixtures/valid-1/SPEC.md" 0
run "invalid-grammar (claim-grammar violations)" "$here/fixtures/invalid-grammar/SPEC.md" 1
run "invalid-structure (structural violations)" "$here/fixtures/invalid-structure/SPEC.md" 1

if [ "$fail" -eq 0 ]; then
	echo "all fixtures passed"
else
	echo "one or more fixtures did not match their expected exit code" >&2
fi
exit "$fail"
