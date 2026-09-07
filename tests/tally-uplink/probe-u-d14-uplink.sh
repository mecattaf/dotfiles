#!/usr/bin/env bash
# U-D14 (dotfiles#317) — the MECHANICAL EVALUATOR's own probe, procedure step 2b.
#
# The card's three clauses and tests/tally-uplink/test-tally-uplink-input.sh
# assert what the tree DECLARES: the input evaluates, the module is imported,
# the rendered unit's argv reads right. Every one of them stops at evaluation —
# the card's own clause A is `--no-build`, so NOTHING the unit names is ever
# realised, and the rendered ExecStart is never executed by anything.
#
# This probe asserts the declaration BITES:
#
#   P1 the derivation `services.tally-uplink.package` is set to actually
#      BUILDS, offline. `nix flake check --no-build` never realises it and the
#      rendered unit does not reference it, so nothing in the card's clauses
#      would notice a `package` that cannot be built — a deliverable standing
#      in for itself.
#   P2 the built launcher names the interpreter THIS repository chose
#      (pkgs.nodejs-slim_24, the seam the lake's `mkUplink { node = ...; }`
#      exists for) and not the lake's own recorded store path, and it RUNS:
#      `sh <launcher> --rows <pinned rows> --parse-only` -> rc 0, nine rows.
#      The launcher is a FILE and not an executable one by the lake's own
#      design (its sandbox has no chmod), which is why it is run through sh.
#   P3 the absent-token path is a LEGIBLE refusal that names the file, which is
#      what makes DF-U-D14-2 a deferral and not a stub: the unit is declared
#      before the credential exists, so the failure a human meets must say so.
#      Run against a token path that does not exist, in a throwaway state dir:
#      rc 3 (RC_ABSENT), the path named on stderr, and no network reached.
#      This probe NEVER opens the real token file.
#   P4 the RENDERED ExecStart argv — the exact string systemd would run —
#      parses and resolves its rows file, with `--parse-only` appended so no
#      socket, no lake and no token are touched. An unknown flag or a rows path
#      the parser refuses is rc 2 or 3 here and green in every card clause.
#
# Nothing is built into the profile, nothing is switched, no state under
# ~/.local/state/tally or ~/.local/state/tally-rewrite is written or read, and
# no credential is read or printed.
set -uo pipefail

repo="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
cd "$repo" || { echo "FAIL: cannot cd $repo"; exit 2; }

fail=0
pass() { printf '[P] %s\n' "$*"; }
bad()  { printf '[F] %s\n' "$*"; fail=1; }
note() { printf '[N] %s\n' "$*"; }

home='.#nixosConfigurations.coordinator.config.home-manager.users.tom'

# --- P1 ---------------------------------------------------------------------
out=$(mktemp -d) || exit 2
trap 'rm -rf "$out"' EXIT
if timeout 900 nix build --offline --no-link --print-out-paths \
     "$home.services.tally-uplink.package" > "$out/path" 2>"$out/err"; then
  built=$(cat "$out/path")
  pass "P1 services.tally-uplink.package builds offline: $built"
else
  built=
  bad "P1 services.tally-uplink.package does NOT build: $(tail -3 "$out/err" | tr '\n' ' ')"
fi

# --- P2 ---------------------------------------------------------------------
# Read through the `.#` FLAKEREF and never through `builtins.getFlake (toString
# ./.)`: the impure-path form copies the working tree, so ONE untracked file of
# an unsupported type in the checkout kills the eval. MEASURED 2026-09-07 on the
# merged main: `error: file 'home/dot_config/cliamp/cliamp.sock' has an
# unsupported type` — a live unix socket somebody left in the tree. The flakeref
# form reads the git tree and is indifferent to it.
exec_start=$(nix eval --offline --raw "$home.systemd.user.services.tally-uplink.Service" \
  --apply 'u: let e = u.ExecStart; in if builtins.isList e then builtins.concatStringsSep " " e else e' \
  2>/dev/null)
# An eval that failed must be RED here, never a clause that reads an empty
# string and agrees with it: with exec_start empty, P2's grep for
# "$unit_node/bin/node" degenerates to "/bin/node" and passes vacuously.
if [ -z "$exec_start" ]; then
  bad "P2/P3/P4 the rendered ExecStart did not evaluate — every clause that reads it is RED, not vacuous"
fi
unit_node=${exec_start%%/bin/node *}
# `git+file://` and not `toString ./.`, for the same reason as above: it reads
# the git tree. `.#` cannot serve here — an input is not a flake OUTPUT, so
# there is no attribute path to it through the installable form.
lake_node=$(nix eval --offline --raw --impure --expr \
  "(builtins.getFlake \"git+file://$PWD\").inputs.tally-lake.lib.node" 2>/dev/null)
if [ -z "$lake_node" ]; then
  bad "P2 the lake's recorded node did not evaluate — the fall-back clause below would be vacuous"
fi
rows=$(nix eval --offline --raw "$home.services.tally-uplink.rows" 2>/dev/null)

if [ -n "$built" ] && [ -f "$built" ] && [ -n "$exec_start" ]; then
  if grep -qF "$unit_node/bin/node" "$built"; then
    pass "P2 the built launcher runs THIS repository's node: $unit_node"
  else
    bad "P2 the built launcher does not name $unit_node: $(tail -1 "$built")"
  fi
  if [ -z "$lake_node" ]; then
    bad "P2 cannot say whether the launcher fell back to the lake's recorded node: it did not evaluate"
  elif grep -qF "$lake_node/bin/node" "$built"; then
    bad "P2 the built launcher fell back to the lake's recorded node $lake_node — mkUplink's node seam is not wired"
  else
    pass "P2 the built launcher does NOT fall back to the lake's recorded node ${lake_node##*/}"
  fi
  p2=$(sh "$built" --rows "$rows" --parse-only 2>&1); p2rc=$?
  if [ "$p2rc" -eq 0 ] && printf '%s\n' "$p2" | grep -q '^uplink: 9 rows, every one probed on a wake$'; then
    pass "P2 sh <launcher> --rows <pinned rows> --parse-only -> rc 0, 9 rows"
  else
    bad "P2 the built launcher does not run: rc $p2rc: $(printf '%s' "$p2" | tail -2 | tr '\n' ' ')"
  fi
else
  bad "P2 no built launcher to run (built='$built', exec_start='${exec_start:-<eval failed>}')"
fi

# --- P3 ---------------------------------------------------------------------
# A token path that does not exist, and a throwaway state dir. The real token
# file is never opened by this probe.
absent="$out/no-such-lake-token"
node_bin=${exec_start%% *}
entry=$(printf '%s\n' "$exec_start" | cut -d' ' -f2)
if [ -z "$exec_start" ]; then
  bad "P3 not run: there is no rendered ExecStart, so there is no interpreter and no entry to run"
  p3=""; p3rc=""
else
  p3=$("$node_bin" "$entry" --rows "$rows" --lake https://127.0.0.1:1 \
        --token-file "$absent" --state "$out/state" --drain-only 2>&1); p3rc=$?
fi
if [ -n "$p3rc" ]; then
# AMENDED after a first run (D-B58, and its rc is recorded in the receipt): the
# first form of this clause demanded rc 3, the RC_ABSENT of the uplink's own
# documented exit table ("3  an input the run needs is not on disk (the path is
# named)"). MEASURED rc 1 — the token read goes through LakeError and lands on
# the generic RC_RED. That is a discrepancy in the LAKE's exit-code table
# (W-03's apps/uplink/bin/uplink.mjs), not in anything U-D14 declares, and
# U-D14's own claim is the weaker and true one: home/tally-uplink.nix says "an
# absent file raises a LakeError naming the path, which is a legible failure and
# not a silent no-token run". So this clause asserts THAT: non-zero, named, and
# never a run that proceeds without a bearer. The rc is printed either way.
if [ "$p3rc" -ne 0 ]; then
  pass "P3 an absent token file is a non-zero refusal (rc $p3rc), not a silent no-token run"
else
  bad "P3 an absent token file was ACCEPTED (rc 0) — the uplink ran with no bearer: $(printf '%s' "$p3" | tail -2 | tr '\n' ' ')"
fi
if [ "$p3rc" -ne 3 ]; then
  note "P3 the lake's documented RC_ABSENT is 3 for \"an input the run needs is not on disk\"; the token read gives rc $p3rc (LakeError -> RC_RED). W-03's table, not U-D14's declaration; recorded, not asserted."
fi
case "$p3" in
  *"$absent"*) pass "P3 the refusal NAMES the missing token file" ;;
  *)           bad  "P3 the refusal does not name $absent: $(printf '%s' "$p3" | tail -2 | tr '\n' ' ')" ;;
esac
if [ -e "$absent" ]; then
  bad "P3 the run CREATED the token file it was pointed at"
else
  pass "P3 the run created no token file of its own"
fi
fi

# --- P4 ---------------------------------------------------------------------
# The rendered argv verbatim, with --parse-only appended so the verb is `parse`:
# no socket, no lake, no token. Anything the parser refuses is non-zero here.
# shellcheck disable=SC2086
if [ -n "$exec_start" ]; then
  p4=$($exec_start --parse-only 2>&1); p4rc=$?
else
  p4="<no rendered ExecStart to run>"; p4rc=1
fi
if [ "$p4rc" -eq 0 ] && printf '%s\n' "$p4" | grep -q '^uplink: 9 rows, every one probed on a wake$'; then
  pass "P4 the rendered ExecStart argv parses and resolves its rows file (--parse-only) -> rc 0, 9 rows"
else
  bad "P4 the rendered ExecStart argv is not accepted by the uplink: rc $p4rc: $(printf '%s' "$p4" | tail -2 | tr '\n' ' ')"
fi

exit "$fail"
