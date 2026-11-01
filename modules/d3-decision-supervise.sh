# Included verbatim in the D3 launcher after it starts $server. Keep the
# launcher alive until both children are reaped: llama-swap owns this PID and
# must not release its model slot while the GPU worker is still shutting down.
d3_cleanup() {
  local status=$?
  trap - EXIT
  # Avoid re-entering cleanup or exiting early on another graceful signal.
  # llama-swap's unloadTimeout still escalates the whole group with SIGKILL.
  trap '' TERM INT
  kill -TERM "$server" "$guard" 2>/dev/null || true
  wait "$server" 2>/dev/null || true
  wait "$guard" 2>/dev/null || true
  exit "$status"
}

d3_supervise() {
  (
    while kill -0 "$server" 2>/dev/null; do
      available="$("${memory_probe[@]}")"
      if [ "$available" -lt "$reserve_kib" ]; then
        echo "d3-decision: stopping after host MemAvailable fell below $reserve_gib GiB" >&2
        kill -TERM "$server"
        exit 1
      fi
      "${poll_sleep[@]}"
    done
  ) &
  guard=$!
  trap d3_cleanup EXIT
  trap 'exit 143' TERM
  trap 'exit 130' INT
  wait "$server"
}
