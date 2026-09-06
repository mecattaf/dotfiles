#!/usr/bin/env bash
# U-D15 (dotfiles#318) — the herdr-kitten input, run from a bare PATH.
#
# Runs U-D15's DOMINANT acceptance and prints every clause with its MEASURED
# value, so the state of the deferral is visible without reading a diff:
#
#   A  nix flake check --offline --no-build            -> 0
#   B  grep -c 'git+file' flake.lock                   -> 0
#   C  hk (herdr-kitten) in the coordinator's home packages
#   C2 ...and the worker's, and the generated action_alias is a store path
#      ending at the kitten's entry point (one server, two clients: ruling B5)
#
# and the two clauses the issue's evaluator adds, which are DEFERRED as
# DEFERRED.md D-1 until Q-7 (the public flip) lands and are therefore REPORTED,
# not asserted:
#
#   D  grep -c 'git+file' flake.nix                    -> 0 wanted, 1 today
#   E  grep -c 'file:///home/tom' flake.lock           -> 0 wanted, 2 today
#
# Set HERDR_KITTEN_INPUT_FETCHABLE=1 the day the URL is flipped and D/E become
# hard assertions too; then this script IS the whole DOMINANT.
#
# No network (--offline), no build (--no-build), nothing switched.
set -uo pipefail

repo="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
cd "$repo" || { echo "FAIL: cannot cd $repo"; exit 2; }

fail=0
pass() { printf '[P] %s\n' "$*"; }
bad()  { printf '[F] %s\n' "$*"; fail=1; }
info() { printf '[.] %s\n' "$*"; }

# --- A ---------------------------------------------------------------------
if nix flake check --offline --no-build >/dev/null 2>&1; then
  pass "A nix flake check --offline --no-build -> 0"
else
  bad  "A nix flake check --offline --no-build -> non-zero"
fi

# --- B ---------------------------------------------------------------------
b=$(grep -c 'git+file' flake.lock)
if [ "$b" -eq 0 ]; then pass "B grep -c 'git+file' flake.lock == 0"
else bad "B grep -c 'git+file' flake.lock == $b, wanted 0"; fi

# --- C ---------------------------------------------------------------------
names=$(nix eval --offline --json \
  '.#nixosConfigurations.coordinator.config.home-manager.users.tom.home.packages' \
  --apply 'ps: builtins.filter (n: n == "herdr-kitten") (map (p: (builtins.parseDrvName (p.name or "")).name) ps)' \
  2>/dev/null)
if [ "$names" = '["herdr-kitten"]' ]; then
  pass "C hk in the coordinator's home packages (nix eval -> $names)"
else
  bad  "C hk NOT in the coordinator's home packages (nix eval -> ${names:-<empty>})"
fi

# --- C2 --------------------------------------------------------------------
wnames=$(nix eval --offline --json \
  '.#nixosConfigurations.worker.config.home-manager.users.tom.home.packages' \
  --apply 'ps: builtins.filter (n: n == "herdr-kitten") (map (p: (builtins.parseDrvName (p.name or "")).name) ps)' \
  2>/dev/null)
if [ "$wnames" = '["herdr-kitten"]' ]; then
  pass "C2 hk in the worker's home packages too (client, no server: ruling B5)"
else
  bad  "C2 hk NOT in the worker's home packages (nix eval -> ${wnames:-<empty>})"
fi

alias_line=$(nix eval --offline --raw \
  '.#nixosConfigurations.coordinator.config.home-manager.users.tom.xdg.configFile."kitty-herdr-nix.conf".text' \
  2>/dev/null | grep '^action_alias hk kitten ')
kitten_path=${alias_line##* }
case "$kitten_path" in
  /nix/store/*/share/hk/kitten/hk.py)
    pass "C2 action_alias names a store path at the kitten entry point: $kitten_path" ;;
  *)
    bad  "C2 action_alias does not name a store kitten entry point: ${alias_line:-<absent>}" ;;
esac

# --- D / E: DEFERRED.md D-1 ------------------------------------------------
d=$(grep -c 'git+file' flake.nix)
e=$(grep -c 'file:///home/tom' flake.lock)
if [ "${HERDR_KITTEN_INPUT_FETCHABLE:-0}" = "1" ]; then
  [ "$d" -eq 0 ] && pass "D grep -c 'git+file' flake.nix == 0" \
                 || bad  "D grep -c 'git+file' flake.nix == $d, wanted 0"
  [ "$e" -eq 0 ] && pass "E grep -c 'file:///home/tom' flake.lock == 0" \
                 || bad  "E grep -c 'file:///home/tom' flake.lock == $e, wanted 0"
else
  info "D grep -c 'git+file' flake.nix == $d (wanted 0) -- DEFERRED.md D-1"
  info "E grep -c 'file:///home/tom' flake.lock == $e (wanted 0) -- DEFERRED.md D-1"
  info "    the github: URL needs mecattaf/herdr-kitten fetchable: Q-7, a TOM LINE."
  info "    docs/herdr/herdr-kitten-input.md has the two commands that finish it."
fi

exit "$fail"
