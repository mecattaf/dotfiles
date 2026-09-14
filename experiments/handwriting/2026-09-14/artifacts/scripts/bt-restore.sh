#!/usr/bin/env bash
# Undo the session's temporary Bluetooth setup: FIFO agent, hand-run patched
# bluetoothd, /run udev rule. Restarts the stock bluetooth.service.
# Kills by exact PID/comm only — never pkill/pgrep -f (it matches the caller's own cmdline).

for pid in $(pgrep -x bluetoothctl); do kill "$pid" 2>/dev/null; done
for pid in $(pgrep -x tail); do
  tr '\0' ' ' </proc/$pid/cmdline 2>/dev/null | grep -q 'bt-agent.fifo' && kill "$pid" 2>/dev/null
done
for pid in $(pgrep -x bluetoothd); do
  exe=$(tr '\0' ' ' </proc/$pid/cmdline 2>/dev/null)
  case "$exe" in *" -n -d "*) sudo kill "$pid" && echo "stopped hand-run bluetoothd $pid" ;; esac
done
sleep 2
if [ -e /run/udev/rules.d/99-huion-note-x10.rules ]; then
  sudo rm -f /run/udev/rules.d/99-huion-note-x10.rules && sudo udevadm control --reload && echo "temp udev rule removed"
fi
sudo systemctl restart bluetooth
sleep 2
echo "bluetooth.service: $(systemctl is-active bluetooth)"
ps -o pid,args -C bluetoothd
