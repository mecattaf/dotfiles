#!/usr/bin/env bash
# U-D18 DF-FILLER-TIMER — the MECHANICAL EVALUATOR's own probe (procedure 2b).
#
#   bash tools/u-d18-eval-probe.sh [<worktree>]
#
# The card's clauses and tools/u-d18-filler-timer-oracle.sh assert what the tree
# DECLARES, and clause E proves the timer RUNS — but it proves it through a
# TRANSIENT unit armed by `systemd-run --user`, and it hands that unit its argv
# and its environment with `%h` ALREADY SUBSTITUTED by the shell:
#
#     probe_cmd=${exec_start//%h/${HOME:-/home/tom}}
#     setenv+=("--setenv=${line//%h/${HOME:-/home/tom}}")
#
# So the one thing clause E cannot see is whether SYSTEMD would have expanded
# those specifiers itself. That matters twice over in this module:
#
#   * `ExecStart = ${pkgs.bash}/bin/bash %h/research-methods/tools/e1-loop.sh --all`
#     — an unexpanded `%h` is exit 127 ("no such file"), a wake that never runs;
#   * `Environment = [ "E1_LAKE=%h/mecattaf/tally-ts-sdk" ]` — an unexpanded `%h`
#     here is WORSE than a crash, because e1-loop.sh reads
#     `LAKE=${E1_LAKE:-/home/tom/mecattaf/tally-ts-sdk}` and a set-but-bogus
#     value SILENTLY DEFEATS the default the lane would otherwise have used.
#     Specifier expansion in `Environment=` is not the same systemd feature as
#     expansion in `ExecStart=`, and nothing in this repository had measured it.
#
# So this probe installs the module's RENDERED unit pair as a REAL unit file —
# not a D-Bus transient — under $XDG_RUNTIME_DIR/systemd/user (never
# ~/.config/systemd/user: Rule 9), under a name that is neither `tally-filler`
# nor the oracle's `tally-filler-probe`, lets a REAL timer start it, and reads
# back what the started process actually got.
#
#   P1  systemd expands `%h` in the module's ExecStart: the pass runs at all.
#   P2  systemd expands `%h` in the module's Environment: E1_LAKE arrives as
#       /home/tom/mecattaf/tally-ts-sdk and not as the literal `%h/...`.
#   P3  the failure mode P2 rules out is REAL, not theoretical: the lane run
#       with a literal-`%h` E1_LAKE is measured, and its rc printed beside P2's.
#   P4  the module's pinned PATH is sufficient on its own: the pass is started
#       by systemd, which grants no interactive PATH, and it exits 0.
#
# `--dry-run` is appended to the module's argv for the same reason the oracle
# appends it: the population resolves and NOTHING is dispatched, so no GPU time
# is spent proving a clock works. Nothing is switched, nothing is written to
# ~/.config, no credential is read, llama-swap is neither called nor restarted.
set -uo pipefail

repo="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$repo" || { echo "FAIL: cannot cd $repo"; exit 2; }

fail=0
pass() { printf '[P] %s\n' "$*"; }
bad()  { printf '[F] %s\n' "$*"; fail=1; }
note() { printf '[N] %s\n' "$*"; }

home='.#nixosConfigurations.coordinator.config.home-manager.users.tom'
unit=u-d18-evalprobe
: "${XDG_RUNTIME_DIR:=/run/user/$(id -u)}"
export XDG_RUNTIME_DIR
udir="$XDG_RUNTIME_DIR/systemd/user"
envout="$XDG_RUNTIME_DIR/$unit.env"

printf 'U-D18 evaluator probe — repo %s\nHEAD %s\n\n' \
  "$repo" "$(git -C "$repo" rev-parse --short HEAD 2>/dev/null || echo '<no git>')"

evapp() { nix eval --offline --raw "$1" --apply "$2" 2>/dev/null; }

exec_start=$(evapp "$home" 'h: let e = h.systemd.user.services.tally-filler.Service.ExecStart;
  in if builtins.isList e then builtins.concatStringsSep " " e else e')
env_lines=$(evapp "$home" 'h: builtins.concatStringsSep "\n" h.systemd.user.services.tally-filler.Service.Environment')
if [ -z "$exec_start" ] || [ -z "$env_lines" ]; then
  bad "the module does not render an ExecStart/Environment to probe"
  echo; echo "U-D18 evaluator probe: FAIL"; exit 1
fi
case "$exec_start$env_lines" in
  *%h*) note "the rendered unit carries systemd specifiers, which is what this probe is about: $(printf '%s' "$exec_start" | tr -s ' ')" ;;
  *)    note "the rendered unit carries NO %h at all; P1/P2 then assert only that the literal paths work" ;;
esac

cleanup() {
  systemctl --user stop "$unit.timer" "$unit.service" >/dev/null 2>&1
  systemctl --user reset-failed "$unit.timer" "$unit.service" >/dev/null 2>&1
  rm -f "$udir/$unit.service" "$udir/$unit.timer" "$envout"
  systemctl --user daemon-reload >/dev/null 2>&1
}
trap cleanup EXIT
cleanup

mkdir -p "$udir" || { bad "cannot create $udir"; exit 2; }

# The module's OWN bytes: ExecStart verbatim (%h and all) with --dry-run
# appended, Environment verbatim (%h and all). The recorder runs first, in the
# same execution context, so what it prints is what the pass itself gets.
{
  printf '[Unit]\nDescription=U-D18 evaluator probe (specifier expansion in the module bytes)\n\n'
  printf '[Service]\nType=oneshot\nRemainAfterExit=yes\nNice=19\n'
  printf '%s\n' "$env_lines" | while IFS= read -r l; do
    [ -n "$l" ] && printf 'Environment=%s\n' "$l"
  done
  # NOTE, measured the hard way by an earlier draft of this probe: `%s` is
  # itself a systemd specifier (the user's SHELL), and `$` starts a systemd
  # variable reference. A recorder written with printf's `%s` came back saying
  # `E1_LAKE=/run/current-system/sw/bin/bash` — systemd had eaten the format
  # string. So the recorder uses no `%` at all and escapes every `$` as `$$`,
  # which is systemd's own escape for a literal dollar.
  printf 'ExecStart=/bin/sh -c '\''{ echo "E1_LAKE=$${E1_LAKE}"; echo "PATH=$${PATH}"; } > %s'\''\n' "$envout"
  printf 'ExecStart=%s --dry-run\n' "$exec_start"
} > "$udir/$unit.service"

{
  printf '[Unit]\nDescription=U-D18 evaluator probe timer\n\n'
  printf '[Timer]\nOnActiveSec=2s\nAccuracySec=1s\nUnit=%s.service\n' "$unit"
} > "$udir/$unit.timer"

systemctl --user daemon-reload >/dev/null 2>&1
if systemctl --user start "$unit.timer" >/dev/null 2>&1; then
  pass "a REAL unit file (not a transient) is loaded from $udir and its timer started"
else
  bad "could not start $unit.timer from $udir"
  echo; echo "U-D18 evaluator probe: FAIL"; exit 1
fi

fired=0
for _ in $(seq 1 90); do
  trigger=$(systemctl --user show "$unit.timer" --property=LastTriggerUSec --value 2>/dev/null)
  case "$trigger" in ""|"n/a"|0) sleep 1 ;; *) fired=1; break ;; esac
done
[ "$fired" = 1 ] \
  && pass "the real timer fired: LastTriggerUSec=$trigger" \
  || bad "the real timer never fired within 90s"

for _ in $(seq 1 180); do
  state=$(systemctl --user show "$unit.service" --property=ActiveState --value 2>/dev/null)
  case "$state" in activating|reloading|"") sleep 1 ;; *) break ;; esac
done
status=$(systemctl --user show "$unit.service" --property=ExecMainStatus --value 2>/dev/null)
result=$(systemctl --user show "$unit.service" --property=Result --value 2>/dev/null)
printf '[R] %s.service ActiveState=%s Result=%s ExecMainStatus=%s\n' "$unit" "${state:-<unknown>}" "${result:-<unknown>}" "${status:-<unknown>}"

# --- P1 --------------------------------------------------------------------
# 203 is EXIT_EXEC — systemd could not exec the argv. 127 is the shell's own
# "command not found". Either is what an unexpanded %h in ExecStart looks like.
case "${status:-x}" in
  203|127) bad "P1 the module's ExecStart did not exec (status $status) — an unexpanded specifier or a missing path" ;;
  0)       pass "P1 systemd expanded the module's own ExecStart and ran it: status 0" ;;
  *)       bad "P1 the module's ExecStart ran but exited ${status:-<unknown>}; first journal line: $(journalctl --user -u "$unit.service" --no-pager -n 20 -o cat 2>/dev/null | head -1)" ;;
esac

# --- P2 / P4 ---------------------------------------------------------------
if [ -r "$envout" ]; then
  got_lake=$(sed -n 's/^E1_LAKE=//p' "$envout" | head -1)
  got_path=$(sed -n 's/^PATH=//p' "$envout" | head -1)
  case "$got_lake" in
    *%h*) bad "P2 systemd did NOT expand %h in Environment=: the pass received E1_LAKE='$got_lake', which silently defeats e1-loop.sh's own default" ;;
    "")   bad "P2 the pass received no E1_LAKE at all" ;;
    *)    if [ -d "$got_lake" ]; then
            pass "P2 systemd expanded %h in Environment=: the pass received E1_LAKE='$got_lake', which is a directory"
          else
            bad "P2 the pass received E1_LAKE='$got_lake', which is not a directory on this box"
          fi ;;
  esac
  case "$got_path" in
    *%h*) bad "P4 the unit's PATH reached the pass unexpanded: $got_path" ;;
    "")   bad "P4 the pass received no PATH" ;;
    *)    pass "P4 the pass ran on the module's pinned PATH alone (no interactive PATH): $(printf '%s' "$got_path" | tr ':' '\n' | wc -l) entries" ;;
  esac
else
  bad "P2/P4 the recorder wrote nothing to $envout"
fi

# --- P3 --------------------------------------------------------------------
# The negative control for P2: is a literal-%h E1_LAKE actually harmful? Run the
# lane's own verb with one, from a bare environment, and print what it does.
lane="${HOME:-/home/tom}/research-methods/tools/e1-loop.sh"
if [ -f "$lane" ]; then
  littmp=$(mktemp)
  env -i HOME="${HOME:-/home/tom}" PATH="${got_path:-/run/current-system/sw/bin}" \
      E1_LAKE='%h/mecattaf/tally-ts-sdk' \
      bash "$lane" --all --dry-run >"$littmp" 2>&1
  lit_rc=$?
  lit=$(tail -1 "$littmp"); rm -f "$littmp"
  note "P3 negative control: the same verb with a LITERAL-%h E1_LAKE ends '$lit' (rc $lit_rc) — this is what P2 rules out"
else
  note "P3 the lane is absent on this box ($lane), so the negative control could not be run"
fi

echo
if [ "$fail" = 0 ]; then echo "U-D18 evaluator probe: PASS"; exit 0; fi
echo "U-D18 evaluator probe: FAIL"; exit 1
