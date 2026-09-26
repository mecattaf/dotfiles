#!/usr/bin/env bash
# update-adopt gates and probes (#354). One verb per local fact; the adopt
# script runs them by argv (modules/update-adopt.nix renders the lists).
#
# GATE contract: exit 0 = clear to disturb this host, exit 1 = busy (stdout
# says why), anything else = cannot tell, which update-adopt also treats as
# "defer". PROBE contract: exit 0 = healthy, nonzero = unhealthy (stdout says
# why). Every external command resolves through PATH, so
# tests/update-adopt runs this file with fakes first.
set -u

verb="${1:-}"
shift || true

user_systemctl() {
  local user="$1"
  shift
  systemctl --user -M "$user@" "$@"
}

halogen_units_active() {
  # Prints the active podman-halogen* units, one per line.
  systemctl list-units --plain --no-legend --no-pager --state=active 'podman-halogen*' 2>/dev/null |
    awk '{print $1}'
}

case "$verb" in
  # ── gates ────────────────────────────────────────────────────────────────
  halogen-idle)
    # A live request on the worker's one inference server. /health carries
    # in_flight and queued (Halogen API 0.7.0); an established TCP session on
    # :8731 covers a stream the counters might not show. Halogen runs with
    # --network=host, so ss sees its sockets.
    port="${1:-8731}"
    if [ -z "$(halogen_units_active)" ]; then
      echo "no halogen unit is active"
      exit 0
    fi
    if ! health="$(curl -fsS -m 5 "http://127.0.0.1:$port/health")"; then
      echo "halogen is active but /health did not answer"
      exit 2
    fi
    # An unparseable answer is "cannot tell", never "idle".
    if ! busy="$(jq -r '((.in_flight // 0) + (.queued // 0)) as $n | if $n > 0 or .busy == true then "\($n)" else "" end' <<<"$health")"; then
      echo "halogen /health was not parseable"
      exit 2
    fi
    if [ -n "$busy" ]; then
      echo "halogen has $busy request(s) in flight or queued"
      exit 1
    fi
    if ! conns="$(ss -Htn state established "( sport = :$port )")"; then
      echo "ss failed"
      exit 2
    fi
    if [ -n "$conns" ]; then
      echo "halogen has $(wc -l <<<"$conns") established connection(s) on :$port"
      exit 1
    fi
    exit 0
    ;;

  units-inactive)
    # units-inactive <system|user:NAME> <unit>... — busy while any is active.
    scope="$1"
    shift
    for unit in "$@"; do
      if [ "$scope" = system ]; then
        systemctl is-active --quiet "$unit" && active=1 || active=0
      else
        user_systemctl "${scope#user:}" is-active --quiet "$unit" && active=1 || active=0
      fi
      if [ "$active" -eq 1 ]; then
        echo "$unit is active ($scope)"
        exit 1
      fi
    done
    exit 0
    ;;

  flock-free)
    # flock-free <path>... — busy while another process holds a flock(2) lock
    # on any path (e.g. lane_b_batch.py's <out>/.lane-b.lock, taken LOCK_EX |
    # LOCK_NB for a whole batch). A missing file is free, and is never created:
    # the shell opens the file read-only (no O_CREAT) and flock(1) locks that
    # descriptor, so this root gate cannot leave a root-owned file in a user's
    # tree. The probe holds the lock for the life of one flock process; a
    # LOCK_NB taker starting in that same instant is refused once.
    for path in "$@"; do
      [ -e "$path" ] || continue
      if [ ! -r "$path" ]; then
        echo "$path is not readable"
        exit 2
      fi
      rc=0
      flock -n -E 75 9 9<"$path" || rc=$?
      if [ "$rc" -eq 75 ]; then
        echo "$path is locked"
        exit 1
      fi
      if [ "$rc" -ne 0 ]; then
        echo "flock on $path failed with rc $rc"
        exit 2
      fi
    done
    exit 0
    ;;

  herdr-agents-idle)
    # herdr-agents-idle <user> — busy while any agent is not idle/done.
    # `herdr agent list` prints JSON by default (no --json flag, verified
    # 2026-09-13) with result.agents[].agent_status in working/idle/done/…;
    # an unrecognised status defers rather than guesses.
    user="$1"
    if ! user_systemctl "$user" is-active --quiet herdr.service; then
      echo "herdr is not running for $user"
      exit 0
    fi
    if ! listing="$(runuser -u "$user" -- env HOME="/home/$user" herdr agent list)"; then
      echo "herdr agent list failed"
      exit 2
    fi
    if ! busy="$(jq -er '[.result.agents[] | select(.agent_status != "idle" and .agent_status != "done") | "\(.pane_id)=\(.agent_status)"] | join(" ")' <<<"$listing")"; then
      echo "herdr agent list was not parseable"
      exit 2
    fi
    if [ -n "$busy" ]; then
      echo "herdr agents busy: $busy"
      exit 1
    fi
    exit 0
    ;;

  tally-kernel-idle)
    # tally-kernel-idle <tally-kernel binary> <socket> <row>... — busy while any
    # row has holders (the kernel's rows.read verb, docs/transport.md §1). If
    # the socket will not answer, fall back to the service cgroup: exec.run
    # children live there beside the server.
    kernel="$1"
    socket="$2"
    shift 2
    if ! systemctl is-active --quiet tally-kernel.service; then
      echo "tally-kernel is not running"
      exit 0
    fi
    for row in "$@"; do
      if reply="$("$kernel" call --socket "$socket" --verb rows.read --body "{\"row\":\"$row\"}")" &&
        holders="$(jq -er '.body.holders' <<<"$reply")"; then
        if [ "$holders" != 0 ]; then
          echo "tally-kernel row $row has $holders holder(s)"
          exit 1
        fi
      else
        cg="$(systemctl show -P ControlGroup tally-kernel.service)"
        procs="/sys/fs/cgroup$cg/cgroup.procs"
        if [ -r "$procs" ] && [ "$(wc -l <"$procs")" -gt 1 ]; then
          echo "tally-kernel socket silent and its cgroup has child processes"
          exit 1
        fi
        echo "tally-kernel socket did not answer rows.read for $row"
        exit 2
      fi
    done
    exit 0
    ;;

  tally-daemon-idle)
    # tally-daemon-idle <user> <socket> — the LIVE tally daemon: busy while any
    # pool holds a lease (`tally query pools`, schemaVersion 1).
    user="$1"
    socket="$2"
    if [ ! -S "$socket" ]; then
      echo "tally daemon socket absent"
      exit 0
    fi
    if ! pools="$(runuser -u "$user" -- env HOME="/home/$user" tally --socket "$socket" query pools)"; then
      echo "tally query pools failed"
      exit 2
    fi
    if ! held="$(jq -er '[.pools[] | select(.held > 0) | "\(.pool)=\(.held)"] | join(" ")' <<<"$pools")"; then
      echo "tally query pools was not parseable"
      exit 2
    fi
    if [ -n "$held" ]; then
      echo "tally leases held: $held"
      exit 1
    fi
    exit 0
    ;;

  # ── probes ───────────────────────────────────────────────────────────────
  halogen-healthy)
    port="${1:-8731}"
    if [ -z "$(halogen_units_active)" ]; then
      # Whether it SHOULD be active is the critical-unit diff's question.
      echo "no halogen unit is active"
      exit 0
    fi
    if health="$(curl -fsS -m 5 "http://127.0.0.1:$port/health")" &&
      [ "$(jq -r .status <<<"$health")" = ok ]; then
      exit 0
    fi
    echo "halogen /health is not ok yet"
    exit 1
    ;;

  ping-host)
    if ping -c 1 -W 2 "$1" >/dev/null 2>&1; then exit 0; fi
    echo "$1 does not answer ping"
    exit 1
    ;;

  mounts-present)
    for path in "$@"; do
      if ! findmnt -rn --target "$path" >/dev/null 2>&1 || ! mountpoint -q "$path"; then
        echo "$path is not mounted"
        exit 1
      fi
    done
    exit 0
    ;;

  *)
    echo "usage: update-adopt-gates <verb> …" >&2
    exit 64
    ;;
esac
