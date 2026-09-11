#!/usr/bin/env bash
# U-D19 DF-SWITCH (dotfiles#322) — THE MECHANICAL EVALUATOR'S OWN PROBE.
# Procedure step 2b: the card's clauses are a FLOOR. This is what the card did
# NOT ask, written by the evaluator (thread 1f590b72-5f59-415f-ae44-37aac4897cc5),
# not by the unit's author.
#
#   bash tools/u-d19-evaluator-probe.sh
#
# READ-ONLY. Nothing is switched, started, stopped, restarted or written; the
# worker box (and the Halogen server on it) is not contacted; no credential is
# read.
#
# THREE THINGS THE CARD'S ORACLE CANNOT SEE.
#
# P1  GENERATION MEMBERSHIP, not merely "under /nix/store".
#     The card's clause D is "FragmentPath under /nix/store", and the unit's
#     oracle strengthens it to "a symlink resolving under /nix/store". Both are
#     still satisfied by a symlink LEFT BEHIND by an earlier generation: a
#     home-manager unit installed two generations ago points at a store path
#     that is under /nix/store and is a symlink, forever, whether or not THIS
#     switch installed it. So the clause can be green about an act that never
#     happened — which is precisely the thing the switch is being graded on.
#     P1 asks the stronger question: is each unit's resolved store path in the
#     CLOSURE of the generation that is current right now? For tally-kernel,
#     /run/current-system; for the three user units, the home-manager generation
#     ~/.local/state/home-manager/gcroots/current-home points at.
#
# P2  THE CHAIN IS A CHAIN, not merely a file that got longer.
#     The card's clause G is "~/.local/state/tally-rewrite/ledger.jsonl
#     growing", and the unit's oracle grades it by BYTE COUNT across a wake. A
#     ledger that gained a row with a broken prev_hash link, a duplicated seq or
#     an unparseable line would satisfy "grew" and would still be a destroyed
#     chain. P2 walks the hash linkage with the kernel's OWN `chain` verb (the
#     shipped binary the switch installed, not a re-implementation) and then
#     re-derives seq monotonicity independently in python.
#
# P3  THE SOCKET ANSWERS, not merely `is-active`.
#     The card's clause C is `systemctl is-active tally-kernel.service ->
#     active`. A `Type=simple` process that has wedged after listen() — or one
#     whose socket file was unlinked underneath it — is `active` for as long as
#     it does not exit. P3 makes a real round trip over the unix socket with a
#     read-only verb and requires a reply, and it asks the kernel for EACH row
#     of its own --rows table, so the answer to "does the door open" is
#     separated from the known cross-repo `admit` blocker on rows the kernel
#     does not own (DEFERRED.md DF-U-D19-1).
set -uo pipefail

fail=0
pass() { printf '[P] %s\n' "$*"; }
bad()  { printf '[F] %s\n' "$*"; fail=1; }
note() { printf '[N] %s\n' "$*"; }

state=/home/tom/.local/state/tally-rewrite
ledger="$state/ledger.jsonl"
sock="$state/kernel.sock"

printf 'U-D19 evaluator probe (step 2b) — host %s, run at %s\n' "$(hostname)" "$(date -u +%FT%TZ)"
printf 'system generation %s\n\n' "$(basename "$(readlink /nix/var/nix/profiles/system)")"

# ── P1. generation membership ───────────────────────────────────────────────
sysgen=$(readlink -f /run/current-system)
homegen=$(readlink -f /home/tom/.local/state/home-manager/gcroots/current-home 2>/dev/null)
[ -n "$homegen" ] || bad "P1 cannot resolve the current home-manager generation"

sysclosure=$(mktemp); homeclosure=$(mktemp)
nix-store -qR "$sysgen"  2>/dev/null | sort > "$sysclosure"
[ -n "$homegen" ] && nix-store -qR "$homegen" 2>/dev/null | sort > "$homeclosure"
note "P1 system closure $(wc -l <"$sysclosure") paths; home closure $(wc -l <"$homeclosure") paths"

member() { # $1 label, $2 fragmentpath, $3 closure file, $4 generation
  local what="$1" frag="$2" cl="$3" gen="$4" real store
  if [ -z "$frag" ]; then bad "$what FragmentPath empty"; return; fi
  real=$(readlink -f "$frag" 2>/dev/null)
  store=$(printf '%s' "$real" | sed -n 's#^\(/nix/store/[^/]*\).*#\1#p')
  if [ -z "$store" ]; then bad "$what resolves to '${real:-<none>}', not a store path"; return; fi
  if grep -qxF "$store" "$cl"; then
    pass "$what $store IS in the closure of $gen"
  else
    bad "$what $store is NOT in the closure of $gen — the unit is a leftover from an older generation, which the card's '/nix/store' clause cannot tell apart from an installed one"
  fi
}
member "P1a tally-kernel.service" "$(systemctl show -p FragmentPath --value tally-kernel.service 2>/dev/null)" "$sysclosure" "$(basename "$sysgen")"
for u in tally-uplink.service tally-filler.timer tally-seat-feeder-claude.timer; do
  member "P1b $u" "$(systemctl --user show -p FragmentPath --value "$u" 2>/dev/null)" "$homeclosure" "$(basename "${homegen:-none}")"
done

# ── P2. the chain is a chain ────────────────────────────────────────────────
kbin=$(systemctl show -p ExecStart --value tally-kernel.service 2>/dev/null | sed -n 's/.*path=\([^ ;]*\).*/\1/p' | head -1)
if [ ! -f "$ledger" ]; then
  bad "P2 $ledger absent"
elif [ ! -x "$kbin" ]; then
  bad "P2 the kernel binary '$kbin' is not executable — cannot verify the chain with the shipped verb"
else
  out=$("$kbin" chain --ledger "$ledger" 2>&1); crc=$?
  [ "$crc" = 0 ] \
    && pass "P2a $kbin chain --ledger $ledger -> 0 :: $(printf '%s' "$out" | head -1)" \
    || bad  "P2a chain verb -> $crc :: $(printf '%s' "$out" | head -3 | tr '\n' ' ')"
  python3 - "$ledger" <<'PY'
import json,sys
prev=None; seq=0; ok=True
for i,l in enumerate(open(sys.argv[1]),1):
    l=l.strip()
    if not l: continue
    try: r=json.loads(l)
    except Exception as e: print(f"[F] P2b line {i} unparseable: {e}"); ok=False; continue
    s=r.get("seq")
    if s!=seq+1: print(f"[F] P2b line {i}: seq {s}, expected {seq+1}"); ok=False
    seq=s if isinstance(s,int) else seq+1
    ph=r.get("prev_hash")
    if prev is not None and ph!=prev: print(f"[F] P2b line {i}: prev_hash {ph} != previous hash {prev}"); ok=False
    prev=r.get("hash")
print(f"[{'P' if ok else 'F'}] P2b seq is 1..{seq} contiguous and every prev_hash matches its predecessor's hash ({seq} records)")
sys.exit(0 if ok else 1)
PY
  [ $? = 0 ] || fail=1
fi

# ── P3. the socket answers ──────────────────────────────────────────────────
if [ ! -S "$sock" ]; then
  bad "P3 $sock is not a socket — tally-kernel.service is 'active' with no door"
elif [ ! -x "$kbin" ]; then
  bad "P3 no kernel binary to call with"
else
  rowsfile=$(systemctl show -p ExecStart --value tally-kernel.service | sed -n 's/.*--rows \([^ ;]*\).*/\1/p' | head -1)
  answered=0; asked=0
  for r in $(python3 -c 'import json,sys;print(" ".join(x["row"] for x in json.load(open(sys.argv[1]))))' "$rowsfile" 2>/dev/null); do
    asked=$((asked+1))
    reply=$(timeout 20 "$kbin" call --socket "$sock" --verb admit --body "{\"row\":\"$r\",\"request\":{}}" 2>&1 | head -1)
    case "$reply" in
      '') bad "P3 row $r: NO REPLY within 20s — the door is open but nothing is behind it" ;;
      *)  answered=$((answered+1)); note "P3 row $r -> $(printf '%s' "$reply" | cut -c1-160)" ;;
    esac
  done
  [ "$asked" -gt 0 ] && [ "$answered" = "$asked" ] \
    && pass "P3 the kernel answered a round trip for all $asked rows of its own --rows table ($rowsfile) — 'active' is a serving process, not a wedged one" \
    || bad  "P3 $answered of $asked rows answered"
fi

printf '\n'
[ "$fail" = 0 ] && { printf 'EVALUATOR PROBE PASS\n'; exit 0; }
printf 'EVALUATOR PROBE FAIL\n'; exit 1
