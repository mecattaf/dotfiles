#!/usr/bin/env bash
# Replace the stdin-less bluetoothctl agent with one fed from a FIFO, so pairing
# prompts ("Accept pairing (yes/no)") can be answered by writing to the FIFO.
S=/tmp/claude-1001/-home-tom-huion/4231dd92-1251-4d46-bffd-365f0c42cb71/scratchpad

# Kill old agent by PID only (pkill -f on a pattern would match this script's own caller).
for pid in $(pgrep -x bluetoothctl); do kill "$pid" 2>/dev/null; done
for pid in $(pgrep -x sleep); do
  [ "$(tr '\0' ' ' </proc/$pid/cmdline 2>/dev/null)" = "sleep infinity " ] && kill "$pid" 2>/dev/null
done
for pid in $(pgrep -x tail); do
  tr '\0' ' ' </proc/$pid/cmdline 2>/dev/null | grep -q 'bt-agent.fifo' && kill "$pid" 2>/dev/null
done
sleep 1

rm -f "$S/bt-agent.fifo"; mkfifo "$S/bt-agent.fifo"
nohup bash -c "tail -f '$S/bt-agent.fifo' | bluetoothctl" >"$S/bt-agent.log" 2>&1 &
sleep 1
printf 'agent NoInputNoOutput\ndefault-agent\nscan on\n' >>"$S/bt-agent.fifo"
sleep 2
tr -d '\033' <"$S/bt-agent.log" | sed 's/\[[0-9;]*m//g; s/\[K//g' | grep -E 'Agent registered|Default agent request successful|Discovery started'
