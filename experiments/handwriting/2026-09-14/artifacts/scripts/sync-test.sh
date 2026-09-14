#!/usr/bin/env bash
# One sync attempt, no manual unbind — tests whether the udev rule handles HOGP on reconnect.
# Usage: sync-test.sh <out-dir>
S=/tmp/claude-1001/-home-tom-huion/4231dd92-1251-4d46-bffd-365f0c42cb71/scratchpad
M=25:6C:20:F5:D8:25
OUT=${1:?out dir}

echo "before: $(bluetoothctl info $M | grep -E 'Connected:' | xargs)"
bluetoothctl info $M | grep -q 'Connected: yes' || bluetoothctl --timeout 20 connect $M | grep -E 'successful|Failed'
sleep 2
for d in /sys/bus/hid/devices/0005:256C:*; do
  [ -e "$d" ] && echo "hid $(basename "$d"): driver=$([ -e "$d/driver" ] && basename "$(readlink -f "$d/driver")" || echo none)"
done
cd "$S/huion-note-x10-ble" && timeout 150 ./huion-x10-notes.sh dump --mac $M --keep -o "$OUT" 2>&1 | grep -v 'Nix search path'
echo "exit=${PIPESTATUS[0]}"
