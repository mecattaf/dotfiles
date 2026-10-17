#!/usr/bin/env bash
# Write the failure marker for one failed system unit. Every system service
# reaches this through the OnFailure= top-level drop-in of failure-surfacing.nix.
set -euo pipefail

unit="${1:?usage: failure-notify <unit>}"
dir="${FAILURE_MARKER_DIR:?FAILURE_MARKER_DIR must be set}"
safe="$(printf '%s' "$unit" | tr / _)"
when="$(date '+%Y-%m-%d %H:%M')"

journal() {
  printf '%s\n' "$@" | logger --journald || true
}

# Podman runs every container healthcheck probe as a transient service named
# <64-hex container id>-<hex>, so the blanket drop-in reaches it too. A single
# failed probe is not the container's verdict: podman counts failures against
# --health-retries and does not count them during --health-start-period. One
# slow probe used to write a marker against a container that stayed healthy.
# Ask podman for the verdict and write no marker while the container is still
# starting or healthy. An inspect that fails or hangs proves nothing either
# way, so the probe failure is surfaced (fail open).
detail=
if [[ "$unit" =~ ^([0-9a-f]{64})-[0-9a-f]+$ ]]; then
  container_id="${BASH_REMATCH[1]}"
  if health="$(timeout 15 podman container inspect \
    --format '{{.Name}} {{.State.Health.Status}}' "$container_id" 2>/dev/null)"; then
    read -r container status _ <<<"$health"
    case "${status:-}" in
      starting | healthy)
        journal \
          "MESSAGE=healthcheck probe failure not surfaced: $unit (container $container is still $status)" \
          "PRIORITY=5" \
          "SYSLOG_IDENTIFIER=failure-notify" \
          "FAILED_UNIT=$unit" \
          "CONTAINER=$container" \
          "HEALTH_STATUS=$status" \
          "DECISION=probe-below-verdict"
        exit 0
        ;;
    esac
    detail="container ${container:-$container_id} is ${status:-without a health status} — "
  fi
fi

install -d -m 0755 "$dir"
exec 9>"$dir/.failure-marker-reconcile.lock"
flock 9
printf '%s failed at %s — %sjournalctl -u %s -b\n' \
  "$unit" "$when" "$detail" "$unit" >"$dir/$safe"
chmod 0644 "$dir/$safe"

# Fields, not prose: the NAS journal copy can then answer "which units
# failed this week" without parsing sentences.
journal \
  "MESSAGE=unit failure surfaced: $unit" \
  "PRIORITY=3" \
  "SYSLOG_IDENTIFIER=failure-notify" \
  "FAILED_UNIT=$unit" \
  "DECISION=marker-written"
