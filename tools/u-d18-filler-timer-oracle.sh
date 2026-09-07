#!/usr/bin/env bash
# U-D18 DF-FILLER-TIMER (dotfiles#321) — the DOMINANT oracle, mechanized as one
# argv, from a bare PATH.
#
#   bash tools/u-d18-filler-timer-oracle.sh
#
# The card's oracle names three things; each is run here with its MEASURED value
# printed, plus the clauses the three cannot see:
#
#   A  nix flake check --offline --no-build                      -> 0
#   B  nix eval shows tally-filler.timer DECLARED on the coordinator, with
#      OnUnitActiveSec SET, and the service calling the lane's filler verb
#      (`e1-loop.sh --all`, ~/research-methods/DECISIONS.md D-U-E1LOOP-7)
#   C  D-B10's round-robin as an equality: the filler's period IS
#      tally-drain.timer's own declared period, read from the same rendered
#      config, so neither filler can crowd the other out
#   D  the non-goals as bytes: llama-swap, :9292 and "unload" occur NOWHERE in
#      the rendered unit (ExecStart and Environment together), there is no
#      system-bus twin, the worker declares neither unit, and the installed
#      unit carries no `--dry-run`
#   E  THE RUN PROOF, before any switch: a TRANSIENT timer started with
#      `systemd-run --user --on-calendar` from this shell, running the module's
#      OWN rendered argv, named by `systemctl --user list-timers`, observed to
#      FIRE, and the launcher recorded as `launcher: shell`
#   F  nothing switched and nothing hand-installed: no
#      ~/.config/systemd/user/tally-filler.{service,timer}, the real
#      tally-filler.timer is not loaded (the declared-but-not-switched state
#      DF-U-D18-1 records), and the probe leaves no unit behind
#
# WHY E EXISTS AND WHAT IT IS NOT. Only a switch installs a declared unit, and
# this unit switches nothing (U-D19 owns the coordinator switch, D-B15). The
# card's post-switch clause — "systemctl --user list-timers names
# tally-filler.timer" — is therefore U-D19's post-condition, not this unit's
# (the orchestrator's D-B66 note; the same class as D-B33). What CAN be proven
# here without a switch is spec §2.4/§5.2's own form for a timer clause before
# TL-15: the launcher is Tom's shell, `systemd-run --user --on-calendar` arms
# the timer, and the check records `launcher: shell` and reports without
# failing.
#
# THE PROBE IS NOT THE UNIT, IN EXACTLY TWO WAYS, both deliberate and both
# printed:
#   1. its name is `tally-filler-probe`, never `tally-filler` — a transient unit
#      under the real name would shadow the unit U-D19's switch installs, and
#      Rule 9 bars a hand-installed stand-in;
#   2. its argv is the module's rendered ExecStart with `--dry-run` APPENDED, so
#      the pass resolves the population and dispatches nothing. A probe that
#      made a real model request would be this oracle spending GPU time to prove
#      a clock works, and would break the lane's own "never two concurrent model
#      requests".
# It also sets RemainAfterExit so its exit status is still readable after it
# fires. Clause D asserts the installed unit has neither difference.
#
# NOTHING IS SWITCHED, NOTHING IS INSTALLED, NOTHING IS WRITTEN outside a
# transient systemd unit that this script stops on exit. No credential is read.
# llama-swap is neither called nor restarted; the probe's `--dry-run` reaches no
# serve at all.
set -uo pipefail

repo="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$repo" || { echo "FAIL: cannot cd $repo"; exit 2; }

fail=0
pass() { printf '[P] %s\n' "$*"; }
bad()  { printf '[F] %s\n' "$*"; fail=1; }
note() { printf '[N] %s\n' "$*"; }

home='.#nixosConfigurations.coordinator.config.home-manager.users.tom'
worker='.#nixosConfigurations.worker.config.home-manager.users.tom'
sys='.#nixosConfigurations.coordinator.config'
probe=tally-filler-probe

ev()    { nix eval --offline --raw "$1" 2>/dev/null; }
evapp() { nix eval --offline --raw "$1" --apply "$2" 2>/dev/null; }

printf 'U-D18 DF-FILLER-TIMER oracle — repo %s\n' "$repo"
printf 'HEAD %s\n\n' "$(git -C "$repo" rev-parse --short HEAD 2>/dev/null || echo '<no git>')"

# --- A ---------------------------------------------------------------------
# The card's first clause, and the gate the whole suite is verified with.
if nix flake check --offline --no-build >/dev/null 2>&1; then
  pass "A nix flake check --offline --no-build -> 0"
else
  bad "A nix flake check --offline --no-build -> non-zero"
fi

# --- B ---------------------------------------------------------------------
# "nix eval shows tally-filler.timer declared on the coordinator with
# OnUnitActiveSec set and the service calling the uplink's filler verb."
declared=$(evapp "$home" 'h: if h.systemd.user.timers ? tally-filler then "true" else "false"')
if [ "$declared" = true ]; then
  pass "B tally-filler.timer is DECLARED on the coordinator: $declared"
else
  bad "B tally-filler.timer is NOT declared on the coordinator: ${declared:-<eval failed>}"
fi

svc_declared=$(evapp "$home" 'h: if h.systemd.user.services ? tally-filler then "true" else "false"')
[ "$svc_declared" = true ] \
  && pass "B tally-filler.service is DECLARED beside it: $svc_declared" \
  || bad "B tally-filler.service is NOT declared: ${svc_declared:-<eval failed>}"

on_unit_active=$(ev "$home.systemd.user.timers.tally-filler.Timer.OnUnitActiveSec")
if [ -n "$on_unit_active" ]; then
  pass "B OnUnitActiveSec is SET: $on_unit_active"
else
  bad "B OnUnitActiveSec is not set on tally-filler.timer"
fi

timer_unit=$(ev "$home.systemd.user.timers.tally-filler.Timer.Unit")
[ "$timer_unit" = "tally-filler.service" ] \
  && pass "B the timer points at its own service: $timer_unit" \
  || bad "B the timer points at '$timer_unit', not tally-filler.service"

wanted=$(evapp "$home" 'h: builtins.concatStringsSep "," h.systemd.user.timers.tally-filler.Install.WantedBy')
case ",$wanted," in
  *,timers.target,*) pass "B the timer is armed by timers.target: $wanted" ;;
  *) bad "B the timer has no timers.target in WantedBy: ${wanted:-<none>}" ;;
esac

exec_start=$(evapp "$home" 'h: let e = h.systemd.user.services.tally-filler.Service.ExecStart;
  in if builtins.isList e then builtins.concatStringsSep " " e else e')
verb_ok=0
case "$exec_start" in
  */research-methods/tools/e1-loop.sh\ --all)
    pass "B the service calls the lane's filler verb: ${exec_start##* bash }"
    verb_ok=1 ;;
  "") bad "B the service's ExecStart would not evaluate" ;;
  *)  bad "B the service does not call e1-loop.sh --all: $exec_start" ;;
esac

x_verb=$(ev "$home.systemd.user.services.tally-filler.Unit.X-TallyVerb")
[ "$x_verb" = "e1-loop.sh --all" ] \
  && pass "B the unit NAMES its own verb (X-TallyVerb): $x_verb" \
  || bad "B X-TallyVerb is '${x_verb:-<unset>}', not 'e1-loop.sh --all'"

x_level=$(ev "$home.systemd.user.services.tally-filler.Unit.X-TallyLevel")
[ "$x_level" = filler ] \
  && pass "B the unit NAMES its level (X-TallyLevel): $x_level" \
  || bad "B X-TallyLevel is '${x_level:-<unset>}', not 'filler'"

# The verb the module names must be a script that actually exists on this box,
# and it must accept the selector. Reported, never fabricated: the register is
# LOCAL by ruling (D-B12) and is not an input of this repository, so its absence
# is a NOTE about the box and not a defect in this tree.
lane="${HOME:-/home/tom}/research-methods/tools/e1-loop.sh"
if [ -f "$lane" ]; then
  pass "B the verb resolves on this box: $lane"
  if grep -q -- '--all)' "$lane"; then
    pass "B the lane's own argument parser accepts --all"
  else
    bad "B $lane does not parse --all"
  fi
else
  note "B the register checkout is absent here, so the verb cannot be resolved on this box: $lane (D-B12 keeps the register local; this is a statement about the box, not about the tree)"
fi

# --- C ---------------------------------------------------------------------
# D-B10: "the two fillers (E1 replay, academic drain) alternate by round-robin
# on gpu-coordinator". Equality against the drain's OWN declaration, so an
# upstream cadence change is red here rather than a silent end to the alternation.
drain_period=$(ev "$home.systemd.user.timers.tally-drain.Timer.OnUnitActiveSec")
if [ -n "$drain_period" ] && [ "$drain_period" = "$on_unit_active" ]; then
  pass "C D-B10 round-robin: filler period == drain period == $on_unit_active"
else
  bad "C the two fillers' cadences differ: filler '$on_unit_active' vs tally-drain '${drain_period:-<unset>}'"
fi

x_peer=$(ev "$home.systemd.user.services.tally-filler.Unit.X-TallyPeerTimer")
[ "$x_peer" = "tally-drain.timer" ] \
  && pass "C the unit NAMES the filler it alternates with: $x_peer" \
  || bad "C X-TallyPeerTimer is '${x_peer:-<unset>}', not tally-drain.timer"

# --- D ---------------------------------------------------------------------
# The non-goals as bytes: "the timer never calls llama-swap directly; never
# unloads". Read over ExecStart AND Environment together, so a value cannot hide
# in the environment block.
rendered=$(evapp "$home" 'h: let s = h.systemd.user.services.tally-filler.Service;
  e = if builtins.isList s.ExecStart then builtins.concatStringsSep " " s.ExecStart else s.ExecStart;
  in e + " " + builtins.concatStringsSep " " s.Environment')
if [ -z "$rendered" ]; then
  bad "D the rendered unit would not evaluate"
else
  for forbidden in llama 9292 unload; do
    case "$rendered" in
      *"$forbidden"*) bad "D the rendered unit names '$forbidden' — the card's non-goal" ;;
      *) pass "D the rendered unit names no '$forbidden'" ;;
    esac
  done
  case "$rendered" in
    *"/.local/state/"*) bad "D the rendered unit writes under ~/.local/state — the lane's state is the register's git tree" ;;
    *) pass "D the rendered unit names no ~/.local/state path (neither branch (a)'s nor the rewrite's)" ;;
  esac
  case "$rendered" in
    *--dry-run*) bad "D the INSTALLED unit carries --dry-run: that is the probe's selector, never the unit's" ;;
    *) pass "D the installed unit carries no --dry-run" ;;
  esac
fi

sys_twin=$(evapp "$sys" 'c: if c.systemd.services ? tally-filler then "true" else "false"')
[ "$sys_twin" = false ] \
  && pass "D no SYSTEM-bus twin of the filler exists: $sys_twin" \
  || bad "D a system-bus tally-filler.service exists: ${sys_twin:-<eval failed>}"

worker_timer=$(evapp "$worker" 'h: if h.systemd.user.timers ? tally-filler then "true" else "false"')
[ "$worker_timer" = false ] \
  && pass "D the worker declares no filler timer: $worker_timer" \
  || bad "D the worker declares a filler timer: ${worker_timer:-<eval failed>}"

uplink_install=$(evapp "$home" 'h: if h.systemd.user.services.tally-uplink ? Install then "true" else "false"')
[ "$uplink_install" = false ] \
  && pass "D the uplink still carries no Install section — DF-U-D14-4 is discharged by a timer of the filler's own, never by installing the uplink" \
  || bad "D the uplink grew an Install section: ${uplink_install:-<eval failed>}"

# --- E ---------------------------------------------------------------------
# The RUN proof. `systemd-run --user --on-calendar` from this shell, the
# module's own argv, `--dry-run` appended.
: "${XDG_RUNTIME_DIR:=/run/user/$(id -u)}"
export XDG_RUNTIME_DIR

probe_started=0
cleanup() {
  [ "$probe_started" = 1 ] || return 0
  systemctl --user stop "$probe.timer" "$probe.service" >/dev/null 2>&1
  systemctl --user reset-failed "$probe.timer" "$probe.service" >/dev/null 2>&1
}
trap cleanup EXIT

if ! systemctl --user show --property=Version >/dev/null 2>&1; then
  bad "E no user systemd bus is reachable (XDG_RUNTIME_DIR=$XDG_RUNTIME_DIR), so the timer cannot be proven to run"
elif [ -z "$exec_start" ] || [ "$verb_ok" != 1 ]; then
  bad "E no rendered argv to arm a probe with (clause B did not produce one)"
else
  # Expand the unit's `%h` the way systemd would, then split the argv. No path
  # in it contains a space (store paths and $HOME here do not), so word
  # splitting is exact rather than approximate.
  probe_cmd=${exec_start//%h/${HOME:-/home/tom}}
  read -r -a probe_argv <<<"$probe_cmd"
  probe_argv+=(--dry-run)
  case "${probe_argv[*]}" in
    *" --dry-run") pass "E the probe's argv ends in --dry-run, so it dispatches nothing: ${probe_argv[*]}" ;;
    *) bad "E refusing to arm a probe whose argv is not a dry run: ${probe_argv[*]}" ;;
  esac

  setenv=()
  while IFS= read -r line; do
    [ -n "$line" ] && setenv+=("--setenv=${line//%h/${HOME:-/home/tom}}")
  done < <(evapp "$home" 'h: builtins.concatStringsSep "\n" h.systemd.user.services.tally-filler.Service.Environment')

  # A leftover from an interrupted earlier run is not this run's evidence.
  systemctl --user stop "$probe.timer" "$probe.service" >/dev/null 2>&1
  systemctl --user reset-failed "$probe.timer" "$probe.service" >/dev/null 2>&1

  if systemd-run --user --quiet \
      --unit="$probe" \
      --on-calendar='*:*:0/5' \
      --timer-property=AccuracySec=1s \
      --property=Type=oneshot \
      --property=RemainAfterExit=yes \
      --property=Nice=19 \
      "${setenv[@]}" \
      -- "${probe_argv[@]}" >/dev/null 2>&1; then
    probe_started=1
    pass "E systemd-run --user --on-calendar armed $probe.timer from this shell"
  else
    bad "E systemd-run --user --on-calendar refused to arm $probe.timer"
  fi
fi

if [ "$probe_started" = 1 ]; then
  if systemctl --user list-timers --all --no-pager --no-legend 2>/dev/null | grep -q "$probe.timer"; then
    pass "E systemctl --user list-timers names it: $(systemctl --user list-timers --all --no-pager --no-legend 2>/dev/null | grep "$probe.timer" | tr -s ' ' | sed 's/^ *//')"
  else
    bad "E systemctl --user list-timers does not name $probe.timer"
  fi

  fired=0
  for _ in $(seq 1 60); do
    trigger=$(systemctl --user show "$probe.timer" --property=LastTriggerUSec --value 2>/dev/null)
    case "$trigger" in ""|"n/a"|0) ;; *) fired=1; break ;; esac
    sleep 1
  done
  if [ "$fired" = 1 ]; then
    pass "E the timer FIRED: LastTriggerUSec=$trigger"
  else
    bad "E the timer never fired within 60s (LastTriggerUSec still '${trigger:-<empty>}')"
  fi

  # Let the oneshot settle, then read what it did. RemainAfterExit keeps the
  # status readable after the pass exits.
  for _ in $(seq 1 60); do
    state=$(systemctl --user show "$probe.service" --property=ActiveState --value 2>/dev/null)
    case "$state" in activating|reloading|"") sleep 1 ;; *) break ;; esac
  done
  status=$(systemctl --user show "$probe.service" --property=ExecMainStatus --value 2>/dev/null)
  result=$(systemctl --user show "$probe.service" --property=Result --value 2>/dev/null)

  # THIS is spec 2.5/5.2's form for a timer clause before TL-15: the launcher is
  # a shell, and the check RECORDS that and reports without failing.
  printf '[R] launcher: shell (systemd-run --user --on-calendar; the switch that installs tally-filler.timer is U-D19, DEFERRED.md DF-U-D18-1)\n'
  printf '[R] probe unit: %s.timer -> %s.service; ActiveState=%s Result=%s ExecMainStatus=%s\n' \
    "$probe" "$probe" "${state:-<unknown>}" "${result:-<unknown>}" "${status:-<unknown>}"
  if [ "${status:-1}" = 0 ]; then
    pass "E the pass the timer started exited 0 (the population resolved; nothing dispatched)"
  else
    # Reported, never a verdict: the pass's own success depends on the register
    # and the lake checkouts, which are not this repository's deliverable. The
    # clause under test is that the TIMER started this argv, and it did.
    note "E the pass the timer started exited ${status:-<unknown>} — reported, not failed: what clause E proves is that the timer started the module's own argv from a shell launcher. First journal line: $(journalctl --user -u "$probe.service" --no-pager -n 3 -o cat 2>/dev/null | head -1)"
  fi
fi

# --- F ---------------------------------------------------------------------
# Nothing switched, nothing hand-installed, nothing left behind.
handwritten=0
for f in "${HOME:-/home/tom}/.config/systemd/user/tally-filler.service" \
         "${HOME:-/home/tom}/.config/systemd/user/tally-filler.timer"; do
  [ -e "$f" ] && { bad "F a hand-written unit exists where only a switch may put one (Rule 9): $f"; handwritten=1; }
done
[ "$handwritten" = 0 ] && pass "F no hand-written ~/.config/systemd/user/tally-filler.{service,timer} exists (Rule 9)"

real_state=$(systemctl --user show tally-filler.timer --property=LoadState --value 2>/dev/null)
case "$real_state" in
  loaded) note "F tally-filler.timer is LOADED on this box — the switch has been taken (U-D19); DF-U-D18-1 can be re-read against the box" ;;
  *)      note "F tally-filler.timer is not loaded (LoadState=${real_state:-<unknown>}) — the declared-but-not-switched state DF-U-D18-1 records, and the intended one here" ;;
esac

cleanup
probe_started=0
left=$(systemctl --user show "$probe.timer" --property=LoadState --value 2>/dev/null)
case "$left" in
  loaded) bad "F the probe timer is still loaded after cleanup: $probe.timer" ;;
  *)      pass "F the probe left no unit behind (LoadState=${left:-not-found})" ;;
esac

git_dirty=$(git -C "$repo" status --porcelain 2>/dev/null | wc -l)
printf '[R] git status --porcelain lines in the worktree after this run: %s\n' "$git_dirty"

echo
if [ "$fail" = 0 ]; then
  echo "U-D18 DF-FILLER-TIMER: PASS"
  exit 0
fi
echo "U-D18 DF-FILLER-TIMER: FAIL"
exit 1
