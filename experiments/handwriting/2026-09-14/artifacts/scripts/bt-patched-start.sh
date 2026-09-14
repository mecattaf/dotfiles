#!/usr/bin/env bash
# Temporarily replace the system bluetoothd with the patched build and hold a
# NoInputNoOutput agent open. Undo with bt-restore.sh.
set -euo pipefail
S=/tmp/claude-1001/-home-tom-huion/4231dd92-1251-4d46-bffd-365f0c42cb71/scratchpad
BTD="$(readlink -f "$S/bluez-patched")/libexec/bluetooth/bluetoothd"
[ -x "$BTD" ] || { echo "patched bluetoothd missing: $BTD" >&2; exit 1; }

sudo systemctl stop bluetooth
# Start the patched daemon before anything touches org.bluez, so D-Bus
# activation doesn't bring the stock service back.
sudo nohup "$BTD" -n -d -f /etc/bluetooth/main.conf >"$S/bluetoothd-patched.log" 2>&1 &
for _ in $(seq 20); do
  busctl --system status org.bluez >/dev/null 2>&1 && break
  sleep 0.5
done
busctl --system status org.bluez | grep -E '^(PID|Comm|CommandLine)='

# Agent: answers the "just works" confirmation the HID profile triggers.
nohup bash -c '{ echo "power on"; echo "agent NoInputNoOutput"; echo "default-agent"; exec sleep infinity; } | bluetoothctl' \
  >"$S/bt-agent.log" 2>&1 &
echo $! >"$S/bt-agent.pid"
sleep 2
grep -E 'Agent registered|Default agent request successful' "$S/bt-agent.log" || { echo "agent log:"; cat "$S/bt-agent.log"; }
