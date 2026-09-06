#!/usr/bin/env bash
# U-D15 (dotfiles#318) — the herdr-kitten input, end to end, from a bare PATH.
#
# This script IS U-D15's DOMINANT oracle, mechanized as one argv. The card's
# prose names three clauses; each is run here with its MEASURED value printed,
# plus the two the third clause implies and the one the second cannot see:
#
#   A0 nix flake lock --update-input herdr-kitten     -> 0, lock UNCHANGED
#   A  nix flake check --offline --no-build           -> 0
#   B  grep -c 'git+file' flake.lock                  -> 0
#   B2 grep -c 'git+file' flake.nix                   -> 0
#   B3 grep -c 'file:///home/tom' flake.lock/.nix     -> 0 / 0
#   B4 the input is github:mecattaf/herdr-kitten/<40 hex>, and the lock node
#      agrees (type github, owner/repo/rev)
#   C  hk (herdr-kitten) in the coordinator's home packages
#   C2 ...and the worker's, and the generated action_alias is a store path
#      ending at the kitten's entry point (one server, two clients: ruling B5)
#
# Why B alone is not enough, and why B2/B3 are part of the acceptance rather
# than decoration: Nix does not spell a local git tree "git+file" IN THE LOCK.
# It writes `"type": "git"` + `"url": "file:///home/tom/mecattaf/herdr-kitten"`,
# so `grep -c 'git+file' flake.lock` reads 0 both before and after the URL form
# is fixed. The string the card's mutation hint counts lives in flake.nix. B2
# and B3 are therefore where "reintroduce the file:// URL" goes red, whichever
# of the two files it is reintroduced in.
#
# No network is required (A0 falls back to --offline), no build (--no-build),
# nothing switched, nothing written: the lock is restored if A0 moves it, AND
# again on exit. The second restore matters under the mutation, where Nix
# rewrites flake.lock a second time inside clause A (`nix flake check` fixes up
# a lock that no longer matches flake.nix, `--no-build` or not) — MEASURED
# 2026-09-06: after a mutated run the tree would otherwise be left dirty, which
# is itself a change the card does not authorize. Every clause still reads the
# mutated lock before the exit restore happens, so nothing is masked.
set -uo pipefail

repo="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
cd "$repo" || { echo "FAIL: cannot cd $repo"; exit 2; }

fail=0
pass() { printf '[P] %s\n' "$*"; }
bad()  { printf '[F] %s\n' "$*"; fail=1; }

# --- A0 --------------------------------------------------------------------
# "after nix flake lock --update-input herdr-kitten" — run it, and require it
# to be a no-op, which is also the card's "re-applying reports zero changes".
lock_before=$(mktemp) || exit 2
trap 'cmp -s "$lock_before" flake.lock || cp "$lock_before" flake.lock; rm -f "$lock_before"' EXIT
cp flake.lock "$lock_before"
if timeout 600 nix flake lock --update-input herdr-kitten >/dev/null 2>&1 \
  || timeout 600 nix flake lock --update-input herdr-kitten --offline >/dev/null 2>&1; then
  if cmp -s "$lock_before" flake.lock; then
    pass "A0 nix flake lock --update-input herdr-kitten -> 0, lock unchanged"
  else
    cp "$lock_before" flake.lock
    bad "A0 nix flake lock --update-input herdr-kitten MOVED the lock (restored)"
  fi
else
  bad "A0 nix flake lock --update-input herdr-kitten -> non-zero"
fi

# --- A ---------------------------------------------------------------------
if timeout 1800 nix flake check --offline --no-build >/dev/null 2>&1; then
  pass "A nix flake check --offline --no-build -> 0"
else
  bad  "A nix flake check --offline --no-build -> non-zero"
fi

# --- B / B2 / B3 -----------------------------------------------------------
b=$(grep -c 'git+file' flake.lock)
[ "$b" -eq 0 ] && pass "B grep -c 'git+file' flake.lock == 0" \
               || bad  "B grep -c 'git+file' flake.lock == $b, wanted 0"

b2=$(grep -c 'git+file' flake.nix)
[ "$b2" -eq 0 ] && pass "B2 grep -c 'git+file' flake.nix == 0" \
                || bad  "B2 grep -c 'git+file' flake.nix == $b2, wanted 0 (the file:// URL is back)"

b3l=$(grep -c 'file:///home/tom' flake.lock)
b3n=$(grep -c 'file:///home/tom' flake.nix)
[ "$b3l" -eq 0 ] && pass "B3 grep -c 'file:///home/tom' flake.lock == 0" \
                 || bad  "B3 grep -c 'file:///home/tom' flake.lock == $b3l, wanted 0"
[ "$b3n" -eq 0 ] && pass "B3 grep -c 'file:///home/tom' flake.nix == 0" \
                 || bad  "B3 grep -c 'file:///home/tom' flake.nix == $b3n, wanted 0"

# --- B4 --------------------------------------------------------------------
url=$(sed -n 's/^ *url = "\(github:mecattaf\/herdr-kitten\/[0-9a-f]\{40\}\)";$/\1/p' flake.nix)
if [ -n "$url" ]; then
  pass "B4 flake.nix pins the input by rev on the native fetcher: $url"
else
  bad  "B4 flake.nix does not pin github:mecattaf/herdr-kitten/<40 hex>: $(grep -n 'mecattaf/herdr-kitten' flake.nix | head -3)"
fi
rev=${url##*/}
node=$(nix eval --offline --raw --impure --expr \
  "let l = builtins.fromJSON (builtins.readFile ./flake.lock); n = l.nodes.herdr-kitten.locked; in \"\${n.type} \${n.owner or \"-\"}/\${n.repo or \"-\"} \${n.rev or \"-\"}\"" \
  2>/dev/null)
if [ "$node" = "github mecattaf/herdr-kitten $rev" ] && [ -n "$rev" ]; then
  pass "B4 flake.lock's herdr-kitten node agrees: $node"
else
  bad  "B4 flake.lock's herdr-kitten node is '${node:-<unreadable>}', wanted 'github mecattaf/herdr-kitten $rev'"
fi

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

exit "$fail"
