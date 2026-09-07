#!/usr/bin/env bash
# U-D14 (dotfiles#317) — the tally-lake input and home/tally-uplink.nix, end to
# end, from a bare PATH.
#
# This script IS U-D14's DOMINANT oracle, mechanized as one argv. The card's
# prose names three clauses; each is run here byte-exact with its MEASURED
# value printed, plus the clauses the three cannot see:
#
#   A0 nix flake lock --update-input tally-lake        -> 0, lock UNCHANGED
#   A  nix flake check --offline --no-build            -> 0
#   B  nix eval of the coordinator home config shows tally-uplink.service
#      DECLARED                                        -> true
#   C  the lake repo exports homeManagerModules.tally-uplink — the module is
#      there, apps/uplink is packaged, and the flake's recorded node is the
#      one scripts/node-env.sh records (the flake refuses to evaluate if the
#      two disagree, so C proves the "with the recorded node" half too)
#   D  the pin: flake.nix and flake.lock agree on ONE pushed rev of
#      github.com/mecattaf/tally-ts-sdk, and that rev is an ancestor-or-equal
#      of the remote's main (read from the local clone's remote-tracking ref;
#      no network, no credential — `git ls-remote` is NOT called here)
#   E  the unit's shape: ExecStart is the store node against the store copy of
#      apps/uplink, every path it runs against is under the rewrite's own
#      state root, the rows file is the PINNED kernel's docs/rows.md out of
#      the store, and the unit carries no Install section
#   G  the token is a PATH and never a value: outside the store, created by
#      nobody here, and no Environment= on the unit carries a secret
#   H  the rows file the unit points at PARSES with the very code that will
#      parse it — the store node from the rendered argv, run against the store
#      copy of the uplink with --parse-only. No socket, no network.
#   F  the non-goals: no switch is performed here, no SYSTEM-bus twin of the
#      uplink exists, the live user-bus tally-daemon declaration still
#      evaluates, and the worker declares no uplink of its own
#
# Why A/B/C alone are not the acceptance: they are green on a tree whose lock
# pins a rev that was never pushed (D), on a unit whose --rows points at a live
# checkout a `git checkout` could move underneath it (E/H), and on one that
# baked the bearer into the store (G). F is the card's non-goal as bytes — "no
# switch here" — asserted in every direction this repository can assert it.
#
# No network is required (A0 falls back to --offline), no build (--no-build),
# nothing switched, nothing written: the lock is restored if A0 moves it, AND
# again on exit — under a mutation `nix flake check` can rewrite flake.lock a
# second time, and a mutated run must not leave a change nobody authorized.
# Every clause reads the mutated tree before the exit restore, so no red is
# masked. NOTHING here reads the lake token: G asserts the path and never
# opens the file.
set -uo pipefail

repo="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
cd "$repo" || { echo "FAIL: cannot cd $repo"; exit 2; }

fail=0
pass() { printf '[P] %s\n' "$*"; }
bad()  { printf '[F] %s\n' "$*"; fail=1; }
note() { printf '[N] %s\n' "$*"; }
skip() { printf '[S] %s\n' "$*"; }

home='.#nixosConfigurations.coordinator.config.home-manager.users.tom'
state=/home/tom/.local/state/tally-rewrite

# --- A0 --------------------------------------------------------------------
# The one network act this unit ever performs, required to be a NO-OP at the
# pin — which is also the card's "re-applying the same card reports zero
# changes through its hidden marker".
lock_before=$(mktemp) || exit 2
trap 'cmp -s "$lock_before" flake.lock || cp "$lock_before" flake.lock; rm -f "$lock_before"' EXIT
cp flake.lock "$lock_before"
if timeout 600 nix flake lock --update-input tally-lake >/dev/null 2>&1 \
  || timeout 600 nix flake lock --update-input tally-lake --offline >/dev/null 2>&1; then
  if cmp -s "$lock_before" flake.lock; then
    pass "A0 nix flake lock --update-input tally-lake -> 0, lock unchanged"
  else
    cp "$lock_before" flake.lock
    bad "A0 nix flake lock --update-input tally-lake MOVED the lock (restored)"
  fi
else
  bad "A0 nix flake lock --update-input tally-lake -> non-zero"
fi

# --- A ---------------------------------------------------------------------
if timeout 3000 nix flake check --offline --no-build >/dev/null 2>&1; then
  pass "A nix flake check --offline --no-build -> 0"
else
  bad  "A nix flake check --offline --no-build -> non-zero"
fi

# --- B ---------------------------------------------------------------------
# The card's second clause and the mutation hint's target. Read as a
# membership test, so removing `./tally-uplink.nix` from home/home.nix — "the
# module import" — makes this print exactly `false` rather than erroring; the
# other reading of the hint (dropping the UPSTREAM import inside
# home/tally-uplink.nix) leaves `services.tally-uplink` set but undeclared and
# the eval dies non-zero. Both are red here and only `true` is green.
declared=$(nix eval --offline --json --impure --expr \
  "(builtins.getFlake (toString ./.)).nixosConfigurations.coordinator.config.home-manager.users.tom.systemd.user.services ? tally-uplink" 2>/dev/null)
if [ "$declared" = "true" ]; then
  pass "B nix eval ...coordinator home...systemd.user.services ? tally-uplink -> true"
else
  bad  "B tally-uplink.service is not declared in the coordinator home config -> '${declared:-<eval failed>}' (wanted true)"
fi
enable=$(nix eval --offline --json "$home.services.tally-uplink.enable" 2>/dev/null)
if [ "$enable" = "true" ]; then
  pass "B services.tally-uplink.enable -> true"
else
  bad  "B services.tally-uplink.enable -> '${enable:-<eval failed>}' (wanted true)"
fi

# --- C ---------------------------------------------------------------------
# "the lake repo exports homeManagerModules.tally-uplink (a flake.nix in
# tally-ts-sdk packaging apps/uplink with the recorded node)". Three halves,
# each read off the INPUT itself rather than off our own module, so a green C
# is a statement about the lake and not about us.
exports=$(nix eval --offline --json --impure --expr \
  '(builtins.getFlake (toString ./.)).inputs.tally-lake.homeManagerModules ? tally-uplink' 2>/dev/null)
if [ "$exports" = "true" ]; then
  pass "C inputs.tally-lake exports homeManagerModules.tally-uplink"
else
  bad  "C inputs.tally-lake.homeManagerModules ? tally-uplink -> '${exports:-<eval failed>}'"
fi
pkgdrv=$(nix eval --offline --raw --impure --expr \
  '(builtins.getFlake (toString ./.)).inputs.tally-lake.packages.x86_64-linux.uplink.drvPath' 2>/dev/null)
case "$pkgdrv" in
  /nix/store/*-tally-uplink-*.drv)
    pass "C the lake packages apps/uplink: ${pkgdrv##*/}" ;;
  *)
    bad  "C inputs.tally-lake.packages.x86_64-linux.uplink does not evaluate: '${pkgdrv:-<eval failed>}'" ;;
esac
# "with the recorded node": the flake's own `lib.node` is the store path
# scripts/node-env.sh records, and the flake ASSERTS that agreement before it
# yields any output at all — so reading lib.node back is reading a pin the
# lake has already checked against its shell runner.
lakenode=$(nix eval --offline --raw --impure --expr \
  '(builtins.getFlake (toString ./.)).inputs.tally-lake.lib.node' 2>/dev/null)
lakesrc=$(nix eval --offline --raw --impure --expr \
  '(builtins.getFlake (toString ./.)).inputs.tally-lake.outPath' 2>/dev/null)
if [ -n "$lakenode" ] && [ -n "$lakesrc" ] && grep -qF "$lakenode" "$lakesrc/scripts/node-env.sh" 2>/dev/null; then
  pass "C the recorded node agrees with the lake's scripts/node-env.sh: ${lakenode##*/}"
else
  bad  "C the lake's recorded node '${lakenode:-<eval failed>}' is not in its scripts/node-env.sh"
fi

# --- D ---------------------------------------------------------------------
# The input pinned to a PUSHED commit of mecattaf/tally-ts-sdk: one 40-hex
# rev, named identically in flake.nix and in the lock node, and present in the
# local clone's remote-tracking history — "pushed" read from what the remote
# last answered, not re-asked over the network.
url=$(sed -n 's|^ *url = "git+https://github.com/mecattaf/tally-ts-sdk?rev=\([0-9a-f]\{40\}\)";$|\1|p' flake.nix)
if [ -n "$url" ]; then
  pass "D flake.nix pins git+https://github.com/mecattaf/tally-ts-sdk?rev=$url"
else
  bad  "D flake.nix does not pin git+https://github.com/mecattaf/tally-ts-sdk?rev=<40 hex>: $(grep -n 'tally-ts-sdk' flake.nix | head -3)"
fi
node=$(nix eval --offline --raw --impure --expr \
  "let l = builtins.fromJSON (builtins.readFile ./flake.lock); n = l.nodes.tally-lake.locked; in \"\${n.type} \${n.url or \"-\"} \${n.rev or \"-\"}\"" \
  2>/dev/null)
if [ -n "$url" ] && [ "$node" = "git https://github.com/mecattaf/tally-ts-sdk $url" ]; then
  pass "D flake.lock's tally-lake node agrees: $node"
else
  bad  "D flake.lock's tally-lake node is '${node:-<unreadable>}', wanted 'git https://github.com/mecattaf/tally-ts-sdk ${url:-<no pin>}'"
fi
lake_clone=/home/tom/mecattaf/tally-ts-sdk
if [ -n "$url" ] && [ -d "$lake_clone/.git" ]; then
  if git -C "$lake_clone" merge-base --is-ancestor "$url" refs/remotes/origin/main 2>/dev/null; then
    pass "D rev $url is on the remote's main (read from $lake_clone's origin/main; no network)"
  else
    bad  "D rev $url is NOT an ancestor of origin/main in $lake_clone — the pin is not a pushed commit"
  fi
else
  skip "D pushed-half skipped (no pin or no clone at $lake_clone)"
fi

# --- E ---------------------------------------------------------------------
# home-manager renders Service.ExecStart through a settings type that admits a
# string or a list; join whatever it produced so the clauses below read the
# argv as one string.
exec_start=$(nix eval --offline --raw --impure --expr \
  '(let e = (builtins.getFlake (toString ./.)).nixosConfigurations.coordinator.config.home-manager.users.tom.systemd.user.services.tally-uplink.Service.ExecStart;
    in if builtins.isList e then builtins.concatStringsSep " " e else e)' 2>/dev/null)
case "$exec_start" in
  /nix/store/*-nodejs-*/bin/node\ /nix/store/*/bin/uplink.mjs\ *)
    pass "E ExecStart is the store node against the store copy of apps/uplink: ${exec_start%% *}" ;;
  *)
    bad  "E ExecStart is not <store node>/bin/node <store src>/bin/uplink.mjs …: '${exec_start:-<eval failed>}'" ;;
esac
for flag in \
  "--lake https://" \
  "--token-file $state/lake-token" \
  "--socket $state/kernel.sock" \
  "--ledger $state/ledger.jsonl" \
  "--state $state/uplink" \
  "--executor coordinator" \
  "--wakes 1" ; do
  case "$exec_start" in
    *"$flag"*) pass "E ExecStart carries $flag" ;;
    *)         bad  "E ExecStart is missing '$flag': $exec_start" ;;
  esac
done
# The state root must NEVER be branch (a)'s live estate: this is the eval-time
# twin of the served kernel's own Ledger::open refusal (ledger.rs:31-35).
case "$exec_start" in
  *"state/tally/"*|*"state/tally "*)
    bad  "E ExecStart names the LIVE state root ~/.local/state/tally: $exec_start" ;;
  *)
    pass "E ExecStart names no path under the live ~/.local/state/tally root" ;;
esac
# The rows file is the PINNED kernel's docs/rows.md out of the store, so the
# rows probed and the kernel they are probed against are ONE pin. A live
# checkout path here would let a `git checkout` move the unit under nobody's
# review.
rows=$(nix eval --offline --raw "$home.services.tally-uplink.rows" 2>/dev/null)
case "$rows" in
  /nix/store/*/docs/rows.md)
    pass "E --rows is the pinned kernel's docs/rows.md out of the store: $rows" ;;
  *)
    bad  "E --rows is not a /nix/store/*/docs/rows.md path: '${rows:-<eval failed>}'" ;;
esac
tallyb=$(nix eval --offline --raw --impure --expr \
  '(builtins.getFlake (toString ./.)).inputs.tally-b.outPath' 2>/dev/null)
if [ -n "$tallyb" ] && [ "$rows" = "$tallyb/docs/rows.md" ]; then
  pass "E --rows comes from the tally-b input itself — the rows and the kernel are one pin"
else
  bad  "E --rows '$rows' is not \${inputs.tally-b}/docs/rows.md ('${tallyb:-<eval failed>}')"
fi
# No Install section: this unit is started by a socket event, a verdict, or a
# timer somebody else owns (DEFERRED.md DF-U-D14-4), never by a target this
# file wired it onto.
install=$(nix eval --offline --json --impure --expr \
  '(builtins.getFlake (toString ./.)).nixosConfigurations.coordinator.config.home-manager.users.tom.systemd.user.services.tally-uplink ? Install' 2>/dev/null)
if [ "$install" = "false" ]; then
  pass "E the unit carries no Install section — no schedule this file authorises"
else
  bad  "E the unit grew an Install section: ${install:-<eval failed>}"
fi
# The uplink's own outbox, declared with its mode.
tmpf=$(nix eval --offline --json "$home.systemd.user.tmpfiles.rules" \
  --apply "rs: builtins.elem \"d $state/uplink 0700 - - -\" rs" 2>/dev/null)
if [ "$tmpf" = "true" ]; then
  pass "E the outbox is declared: d $state/uplink 0700 - - -"
else
  bad  "E no tmpfiles rule declares $state/uplink 0700: ${tmpf:-<eval failed>}"
fi

# --- G ---------------------------------------------------------------------
# The token is a PATH, never a value. This clause never opens the file.
tokenfile=$(nix eval --offline --raw "$home.services.tally-uplink.tokenFile" 2>/dev/null)
if [ "$tokenfile" = "$state/lake-token" ]; then
  pass "G tokenFile names $tokenfile — a path outside the store"
else
  bad  "G tokenFile is '${tokenfile:-<eval failed>}', wanted $state/lake-token"
fi
case "$tokenfile" in
  /nix/store/*) bad  "G the token would be read out of the NIX STORE: $tokenfile" ;;
  *)            pass "G the token path is not under /nix/store" ;;
esac
# Creating the file empty would be a stub standing in for a credential, and an
# empty bearer is a 401 that reads like a lake outage. No rule names it.
tokrule=$(nix eval --offline --json "$home.systemd.user.tmpfiles.rules" \
  --apply 'rs: builtins.any (r: builtins.isList (builtins.match ".*lake-token.*" r)) rs' 2>/dev/null)
if [ "$tokrule" = "false" ]; then
  pass "G no tmpfiles rule creates the token file (writing it is Tom's act, DF-U-D14-2)"
else
  bad  "G a tmpfiles rule names the token file: ${tokrule:-<eval failed>}"
fi
# No secret smuggled onto the unit as an environment variable either. The
# attribute always EXISTS — home-manager's unit type defaults it — so the
# clause reads its value (MEASURED: []), not its presence.
envd=$(nix eval --offline --json --impure --expr \
  '(builtins.getFlake (toString ./.)).nixosConfigurations.coordinator.config.home-manager.users.tom.systemd.user.services.tally-uplink.Service.Environment' 2>/dev/null)
if [ "$envd" = "[]" ]; then
  pass "G the unit's Service.Environment is empty — no secret on the unit"
else
  bad  "G the unit grew an Environment=: ${envd:-<eval failed>}"
fi
# And nothing in this unit's OWN files spells a bearer literal. Scoped to those
# files deliberately: flake.nix carries a pre-existing, unrelated smoke fixture
# (the claude-capacity check) whose expected Authorization header is a hard-coded
# test string, and reading that as this unit's secret would be a false red. This
# comment says so without spelling one, because the search below reads this file
# too and a literal written here would be its own red.
#
# Every path is required to EXIST before the search runs. `grep` over a missing
# file exits 2 — the same non-zero it returns for "no match" — so an absent path
# reads as "nothing found" and masks whatever the present files say. MEASURED
# 2026-09-07: that is exactly what happened while this unit's doc was unwritten,
# and it hid a match in this script's own prose. A clause that cannot search is
# now red, not green.
g_files="home/tally-uplink.nix tests/tally-uplink/test-tally-uplink-input.sh docs/local-ai/tally-uplink-input.md"
g_missing=
for f in $g_files; do [ -e "$f" ] || g_missing="$g_missing $f"; done
if [ -n "$g_missing" ]; then
  bad  "G cannot search for a bearer literal: missing$g_missing"
elif grep -REn 'Bearer[ =:]+[A-Za-z0-9_.-]{8,}' $g_files >/dev/null 2>&1; then
  bad  "G a bearer literal appears in this unit's files: $(grep -REl 'Bearer[ =:]+[A-Za-z0-9_.-]{8,}' $g_files | tr '\n' ' ')"
else
  pass "G no bearer literal in home/tally-uplink.nix, this suite, or the unit's doc"
fi

# --- H ---------------------------------------------------------------------
# The rows file the unit points at, parsed by the very code that will parse
# it: the store node named in the rendered argv, run against the store copy of
# apps/uplink with --parse-only. No PATH toolchain (node is deliberately not
# on PATH here), no socket, no network, no lake, no token.
uplink_node=${exec_start%% *}
uplink_entry=$(printf '%s\n' "$exec_start" | cut -d' ' -f2)
if [ -x "$uplink_node" ] && [ -f "$uplink_entry" ] && [ -f "$rows" ]; then
  parse=$("$uplink_node" "$uplink_entry" --rows "$rows" --parse-only 2>&1)
  prc=$?
  count=$(printf '%s\n' "$parse" | sed -n 's/^uplink: \([0-9]\{1,\}\) rows, every one probed on a wake$/\1/p')
  if [ "$prc" -eq 0 ] && [ -n "$count" ]; then
    pass "H the uplink parses its own --rows file: $count rows, every one probed on a wake"
  else
    bad  "H --parse-only over $rows -> rc $prc: $(printf '%s' "$parse" | tail -2 | tr '\n' ' ')"
  fi
  # The three kernel-owned rows the served kernel answers for must be among
  # them, or the uplink and the door are talking about different boxes.
  for r in gpu-coordinator gpu-worker mechanical; do
    if printf '%s\n' "$parse" | grep -q "^row   $r	owner=kernel	"; then
      pass "H the rows file names the kernel-owned row $r"
    else
      bad  "H the rows file does not name a kernel-owned row $r"
    fi
  done
else
  bad  "H cannot run --parse-only: node='$uplink_node' entry='$uplink_entry' rows='$rows'"
fi

# --- F ---------------------------------------------------------------------
# "no switch here". A declaration is the deliverable; nothing in this suite
# switches, and the box is expected to be in the declared-but-not-switched
# state until U-D19 (DEFERRED.md DF-U-D14-1). Recorded as a NOTE, never a
# verdict: whether the coordinator has been switched is not this unit's to
# assert either way.
if command -v systemctl >/dev/null 2>&1; then
  st=$(systemctl --user is-active tally-uplink.service 2>&1 | head -1)
  note "F systemctl --user is-active tally-uplink.service -> $st (declared-but-not-switched is the intended state; DF-U-D14-1)"
else
  note "F no systemctl on PATH; the switch state is not read"
fi
# The uplink is a USER unit. No system-bus twin appeared with it.
systwin=$(nix eval --offline --json --impure --expr \
  '(builtins.getFlake (toString ./.)).nixosConfigurations.coordinator.config.systemd.services ? tally-uplink' 2>/dev/null)
if [ "$systwin" = "false" ]; then
  pass "F no SYSTEM-bus tally-uplink unit exists (the uplink stays a user unit)"
else
  bad  "F a system-bus tally-uplink appeared: ${systwin:-<eval failed>}"
fi
# The live daemon's declaration still evaluates — this unit added a service, it
# did not replace one.
live=$(nix eval --offline --raw "$home.systemd.user.services.tally-daemon.Service.Type" 2>/dev/null)
if [ -n "$live" ]; then
  pass "F the live user-bus tally-daemon.service is still declared (Service.Type=$live)"
else
  bad  "F the live user-bus tally-daemon.service no longer evaluates"
fi
# U-D13's kernel is still declared on the system bus: the uplink talks to it
# over the socket, and this unit did not disturb it.
kern=$(nix eval --offline --json \
  '.#nixosConfigurations.coordinator.config.systemd.services.tally-kernel.enable' 2>/dev/null)
if [ "$kern" = "true" ]; then
  pass "F U-D13's system-bus tally-kernel.service is still enabled — the door the uplink knocks on"
else
  bad  "F tally-kernel.service is no longer enabled: ${kern:-<eval failed>}"
fi
# ONE uplink, on the box that serves the kernel (spec §2.4 Q2). The worker twin
# is a ROW that kernel serves, not a second uplink; the NAS has no home config
# at all, which the eval says by failing to find the attribute.
wk=$(nix eval --offline --json --impure --expr \
  '(builtins.getFlake (toString ./.)).nixosConfigurations.worker.config.home-manager.users.tom.systemd.user.services ? tally-uplink' 2>/dev/null)
if [ "$wk" = "false" ]; then
  pass "F the worker declares no tally-uplink (one uplink, on the coordinator)"
else
  bad  "F the worker declares tally-uplink: ${wk:-<eval failed>}"
fi

exit "$fail"
