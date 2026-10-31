#!/usr/bin/env bash
# runs INSIDE dbus-run-session: a private session bus, so the live bus never sees the test player.
set -u
BUN=/home/tom/today/2026-10-14-convergence-soak/build/bun/bin/bun; PC=/etc/profiles/per-user/tom/bin/playerctl
$BUN mpris-probe.mjs > mpris-calls.json 2> mpris-server.err & SRV=$!
for i in $(seq 1 30); do $PC -l 2>/dev/null | grep -q gpuixshell && break; sleep 0.1; done
echo "players: $($PC -l 2>&1 | tr '\n' ' ')"
echo "status: $($PC -p gpuixshell status 2>&1)"
echo "metadata:"; $PC -p gpuixshell metadata 2>&1
echo "fmt: $($PC -p gpuixshell metadata --format '{{artist}} — {{title}} [{{duration(mpris:length)}}] vol={{volume}}' 2>&1)"
$PC -p gpuixshell play-pause; sleep 0.2; echo "status after play-pause: $($PC -p gpuixshell status 2>&1)"
$PC -p gpuixshell next; $PC -p gpuixshell previous; $PC -p gpuixshell position 30; $PC -p gpuixshell position 5+; $PC -p gpuixshell volume 0.5; $PC -p gpuixshell shuffle on; $PC -p gpuixshell loop Playlist
sleep 0.3; echo "position now: $($PC -p gpuixshell position 2>&1)"; echo "shuffle: $($PC -p gpuixshell shuffle 2>&1) loop: $($PC -p gpuixshell loop 2>&1) volume: $($PC -p gpuixshell volume 2>&1)"
kill -TERM $SRV; wait $SRV 2>/dev/null; echo "server log: $(cat mpris-server.err)"; echo "calls: $(cat mpris-calls.json)"
