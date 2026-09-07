#!/usr/bin/env bash
# U-D13 (dotfiles#316) — the tally-b input and modules/tally-b.nix, end to end,
# from a bare PATH.
#
# This script IS U-D13's DOMINANT oracle, mechanized as one argv. The card's
# prose names three clauses; each is run here byte-exact with its MEASURED
# value printed, plus the clauses the three cannot see:
#
#   A0 nix flake lock --update-input tally-b           -> 0, lock UNCHANGED
#   A  nix flake check --offline --no-build            -> 0
#   B  nix eval .#nixosConfigurations.coordinator.config.systemd.services.tally-kernel.enable
#                                                      -> true
#   C  nix build .#nixosConfigurations.coordinator.config.system.build.toplevel --dry-run
#                                                      -> 0
#   D  the pin: flake.nix and flake.lock agree on ONE pushed rev of
#      github.com/mecattaf/tally, and that rev is an ancestor-or-equal of the
#      remote's main (read from the local clone's remote-tracking ref; no
#      network, no credential — `git ls-remote` is NOT called here)
#   E  the unit's shape: ExecStart is the store-built tally-kernel binary with
#      `serve`, the state root carries the tally-rewrite component, the socket
#      is kernel.sock BESIDE that root, and the rows file names exactly the
#      three kernel-owned rows of the rewrite's docs/rows.md
#   F  coexistence: the live user-bus tally-daemon declaration still evaluates
#      on the coordinator, no SYSTEM-bus tally-daemon unit exists, and neither
#      the worker nor the NAS imports the module at all
#
# Why A/B/C alone are not the acceptance: they are green on a tree whose lock
# pins a rev that was never pushed, and on a unit whose --state points at the
# live estate's root (the kernel would refuse it at boot, not at eval). D and E
# are where those two faults go red. F is the card's non-goal as bytes — "the
# live tally-daemon.service stays" — asserted in both directions.
#
# No network is required (A0 falls back to --offline), no build (--no-build /
# --dry-run), nothing switched, nothing written: the lock is restored if A0
# moves it, AND again on exit — under a mutation `nix flake check` rewrites
# flake.lock a second time (MEASURED on U-D15), and a mutated run must not
# leave a change nobody authorized. Every clause reads the mutated tree before
# the exit restore, so no red is masked.
set -uo pipefail

repo="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
cd "$repo" || { echo "FAIL: cannot cd $repo"; exit 2; }

fail=0
pass() { printf '[P] %s\n' "$*"; }
bad()  { printf '[F] %s\n' "$*"; fail=1; }

# --- A0 --------------------------------------------------------------------
# "the lock updated with nix flake lock --update-input tally-b" — run it, and
# require it to be a no-op at the pin, which is also the card's "re-applying
# the same card reports zero changes".
lock_before=$(mktemp) || exit 2
trap 'cmp -s "$lock_before" flake.lock || cp "$lock_before" flake.lock; rm -f "$lock_before"' EXIT
cp flake.lock "$lock_before"
if timeout 600 nix flake lock --update-input tally-b >/dev/null 2>&1 \
  || timeout 600 nix flake lock --update-input tally-b --offline >/dev/null 2>&1; then
  if cmp -s "$lock_before" flake.lock; then
    pass "A0 nix flake lock --update-input tally-b -> 0, lock unchanged"
  else
    cp "$lock_before" flake.lock
    bad "A0 nix flake lock --update-input tally-b MOVED the lock (restored)"
  fi
else
  bad "A0 nix flake lock --update-input tally-b -> non-zero"
fi

# --- A ---------------------------------------------------------------------
if timeout 1800 nix flake check --offline --no-build >/dev/null 2>&1; then
  pass "A nix flake check --offline --no-build -> 0"
else
  bad  "A nix flake check --offline --no-build -> non-zero"
fi

# --- B ---------------------------------------------------------------------
# The card's mutation clause: "remove the service from the module -> the eval
# is false". With the service gone the attribute does not even exist, so nix
# eval dies non-zero — MEASURED; either way this clause is red under the
# mutation and only green on `true`.
enable=$(nix eval --offline --json \
  '.#nixosConfigurations.coordinator.config.systemd.services.tally-kernel.enable' 2>/dev/null)
if [ "$enable" = "true" ]; then
  pass "B nix eval ...coordinator...tally-kernel.enable -> true"
else
  bad  "B nix eval ...coordinator...tally-kernel.enable -> '${enable:-<eval failed>}' (wanted true)"
fi

# --- C ---------------------------------------------------------------------
if timeout 1800 nix build --offline --no-link --dry-run \
    '.#nixosConfigurations.coordinator.config.system.build.toplevel' >/dev/null 2>&1; then
  pass "C nix build ...coordinator...system.build.toplevel --dry-run -> 0"
else
  bad  "C nix build ...coordinator...system.build.toplevel --dry-run -> non-zero"
fi

# --- D ---------------------------------------------------------------------
# The input pinned to a PUSHED commit of mecattaf/tally: one 40-hex rev, named
# identically in flake.nix and in the lock node, and present in the local
# clone's remote-tracking history (origin/main of /home/tom/mecattaf/tally) —
# "pushed" read from what the remote last answered, not re-asked over the
# network. If the clone is absent the pushed-half degrades to a named SKIP and
# the rev-agreement half still runs.
url=$(sed -n 's|^ *url = "git+https://github.com/mecattaf/tally?rev=\([0-9a-f]\{40\}\)";$|\1|p' flake.nix)
if [ -n "$url" ]; then
  pass "D flake.nix pins git+https://github.com/mecattaf/tally?rev=$url"
else
  bad  "D flake.nix does not pin git+https://github.com/mecattaf/tally?rev=<40 hex>: $(grep -n 'mecattaf/tally' flake.nix | grep -v 'tally.nix' | head -3)"
fi
node=$(nix eval --offline --raw --impure --expr \
  "let l = builtins.fromJSON (builtins.readFile ./flake.lock); n = l.nodes.tally-b.locked; in \"\${n.type} \${n.url or \"-\"} \${n.rev or \"-\"}\"" \
  2>/dev/null)
if [ -n "$url" ] && [ "$node" = "git https://github.com/mecattaf/tally $url" ]; then
  pass "D flake.lock's tally-b node agrees: $node"
else
  bad  "D flake.lock's tally-b node is '${node:-<unreadable>}', wanted 'git https://github.com/mecattaf/tally ${url:-<no pin>}'"
fi
tally_clone=/home/tom/mecattaf/tally
if [ -n "$url" ] && [ -d "$tally_clone/.git" ]; then
  if git -C "$tally_clone" merge-base --is-ancestor "$url" refs/remotes/origin/main 2>/dev/null; then
    pass "D rev $url is on the remote's main (read from $tally_clone's origin/main; no network)"
  else
    bad  "D rev $url is NOT an ancestor of origin/main in $tally_clone — the pin is not a pushed commit"
  fi
else
  printf '[S] D pushed-half skipped (no pin or no clone at %s)\n' "$tally_clone"
fi

# --- E ---------------------------------------------------------------------
exec_start=$(nix eval --offline --raw \
  '.#nixosConfigurations.coordinator.config.systemd.services.tally-kernel.serviceConfig.ExecStart' 2>/dev/null)
case "$exec_start" in
  /nix/store/*-tally-b-kernel-*/bin/tally-kernel\ serve\ *)
    pass "E ExecStart is the store-built kernel: ${exec_start%% *} serve …" ;;
  *)
    bad  "E ExecStart is not the store-built tally-kernel serve: '${exec_start:-<eval failed>}'" ;;
esac
case "$exec_start" in
  *"--state /home/tom/.local/state/tally-rewrite "*)
    pass "E --state is the rewrite's own root (~/.local/state/tally-rewrite)" ;;
  *)
    bad  "E --state is not the rewrite's root: $exec_start" ;;
esac
case "$exec_start" in
  *"--socket /home/tom/.local/state/tally-rewrite/kernel.sock"*)
    pass "E --socket is kernel.sock beside the chain it fronts" ;;
  *)
    bad  "E --socket is not <state>/kernel.sock: $exec_start" ;;
esac
# The state root must NEVER be the live estate's: this is the eval-time twin of
# the kernel's own Ledger::open refusal (ledger.rs:31-35).
case "$exec_start" in
  *"state/tally --rows"*|*"state/tally/"*)
    bad  "E ExecStart names the LIVE state root — the kernel would refuse to start: $exec_start" ;;
  *)
    pass "E ExecStart names no path under the live ~/.local/state/tally root" ;;
esac
# The rendered --rows content is read off the OPTION, not the store path: the
# writeText file is a build product, and this script builds nothing. The option
# is exactly what the module renders into that file, cell for cell, so the
# clause reads the same bytes one derivation earlier — and offline.
rows=$(nix eval --offline --json \
  '.#nixosConfigurations.coordinator.config.services.tally-kernel.rows' \
  --apply 'rs: map (r: r.row) rs' 2>/dev/null)
if [ "$rows" = '["gpu-coordinator","gpu-worker","mechanical"]' ]; then
  pass "E the rows are exactly the three kernel-owned rows of docs/rows.md: $rows"
else
  bad  "E the rows are ${rows:-<unreadable>}, wanted the three kernel-owned rows"
fi
# Every cell the server refuses to default must be present in every row: a
# missing grace or cap is a startup refusal by name (config.rs row_from_json),
# i.e. a unit that crash-loops — caught here at eval instead.
cells=$(nix eval --offline --json \
  '.#nixosConfigurations.coordinator.config.services.tally-kernel.rows' \
  --apply 'rs: builtins.all (r: builtins.all (c: r ? ${c}) ["row" "capacity" "context_window" "checkpoint_grace_seconds" "kill_grace_seconds" "per_attempt_token_cap" "running"]) rs' 2>/dev/null)
if [ "$cells" = "true" ]; then
  pass "E every row carries all seven cells row_from_json requires — nothing left to a server-side default"
else
  bad  "E a row is missing a required cell: ${cells:-<eval failed>}"
fi

# --- F ---------------------------------------------------------------------
# The non-goal as bytes: the live tally-daemon.service stays. It lives on the
# USER bus (the `tally` input's home-manager module, home/tally.nix) — still
# declared on the coordinator, and NOT redeclared on the system bus by this
# unit's arrival.
live=$(nix eval --offline --raw \
  '.#nixosConfigurations.coordinator.config.home-manager.users.tom.systemd.user.services.tally-daemon.Service.Type' 2>/dev/null)
if [ -n "$live" ]; then
  pass "F the live user-bus tally-daemon.service is still declared (Service.Type=$live)"
else
  bad  "F the live user-bus tally-daemon.service no longer evaluates — the non-goal was violated"
fi
sysdaemon=$(nix eval --offline --json --impure --expr \
  '(builtins.getFlake (toString ./.)).nixosConfigurations.coordinator.config.systemd.services ? tally-daemon' 2>/dev/null)
if [ "$sysdaemon" = "false" ]; then
  pass "F no SYSTEM-bus tally-daemon unit exists (the daemon stays a user unit)"
else
  bad  "F a system-bus tally-daemon appeared: ${sysdaemon:-<eval failed>}"
fi
# ONE kernel, on the coordinator (spec §2.4 Q2): neither twin nor the appliance
# imports the module, so the option itself must not exist on them.
for host in worker nas; do
  has=$(nix eval --offline --json --impure --expr \
    "(builtins.getFlake (toString ./.)).nixosConfigurations.$host.config.systemd.services ? tally-kernel" 2>/dev/null)
  if [ "$has" = "false" ]; then
    pass "F $host has no tally-kernel unit (one kernel, on the coordinator)"
  else
    bad  "F $host declares tally-kernel: ${has:-<eval failed>}"
  fi
done

exit "$fail"
