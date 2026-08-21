#!/usr/bin/env bash
# gpu-cooldown-shed — LAYER 2 (what to do about the heat).
#
# REPLACES gpu-cooldown-enqueue.sh, which is deleted. That adapter SSH'd to the
# coordinator and asked the sole Tally daemon to enqueue a 30-minute sleep
# holding a logical `worker-gpu` lease. Every part of that seam is gone as of the
# 2026-08 architecture:
#   * `worker-gpu` is not a pool — home/tally.nix declares pools only on the
#     coordinator and the retired lane was never re-added;
#   * `executors = { }` — Tom's ruling is that all jobs execute locally on the
#     coordinator, with no daemonless SSH executor in the active topology;
#   * the `tally-gpu-cooldown` receiver it invoked no longer exists; and
#   * the flake's fleet-connectivity check actively fails the build if a
#     worker-shaped Tally executor or pool reappears.
# Restoring it verbatim would have shipped a tripwire wired to a dead endpoint —
# a thermal protection that logs "queued" and does nothing. So Layer 2 now acts
# LOCALLY, which is also strictly better: the thing consuming this box's GPU is
# its own llama-swap (modules/llama-swap.nix), and the honest response to a
# sustained over-temperature is to make it let go of the GPU right now rather
# than to ask another machine for permission to be idle.
#
# The mechanism is llama-swap's own unload API, called bare so it unloads
# EVERY resident model — the same door the `llama-swap-unload` operator CLI uses.
# llama-swap reloads on the next request, so the cost of being wrong is one
# transparent cold load, never an error.
#
# Fallback stays deliberately loud and non-zero, exactly as before: Layer 1 stays
# armed and retries on its next poll rather than pretending the heat was handled.
# The journal line is the signal, and since 2026-08-21 this box's journal leaves
# it for the NAS (./journal-upload.nix), so a thermal event on an unattended
# headless machine is legible after the fact even if the box locks up.
set -euo pipefail

temp_c="${1:?usage: gpu-cooldown-shed <temp_c> <sensor_kind> <threshold_c>}"
sensor_kind="${2:?}"
threshold="${3:?}"

port="${LLAMA_SWAP_PORT:-9292}"

[[ "$temp_c" =~ ^[0-9]+$ ]]
[[ "$threshold" =~ ^[0-9]+$ ]]
[[ "$sensor_kind" =~ ^[A-Za-z0-9:_-]+$ ]]
[[ "$port" =~ ^[1-9][0-9]*$ ]]

# Loopback only: the proxy binds 0.0.0.0 for its LAN/tailnet doors, but this
# adapter has no business leaving the box.
if curl -fsS --max-time 10 -X POST "http://127.0.0.1:${port}/api/models/unload" >/dev/null; then
  echo "gpu-cooldown-shed: unloaded all llama-swap models (trigger ${temp_c}C on ${sensor_kind} >= ${threshold}C)"
  exit 0
fi

echo "gpu-cooldown-shed: FALLBACK no-op — llama-swap on 127.0.0.1:${port} did not accept the unload. GPU is HOT: ${temp_c}C on ${sensor_kind} >= ${threshold}C. NOTHING was shed; if llama-swap is simply not running, the heat is coming from somewhere this tripwire cannot reach." >&2
exit 1
