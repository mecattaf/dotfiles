# The Apple Magic Trackpad (2, 004C:0265) on Bluetooth, not the dock's USB.
# Moving from Strix to the Zenbook (2026-10-08). Bluetooth bonds are per adapter;
# the old Strix key cannot be copied to the client's A0:B3:39:06:75:AB adapter.
# Pair physically with the cable unplugged and the trackpad switched off/on.
# Leave the Huion bond intact. Remove the old Strix bond only after client input
# is verified. The steps below record the successful pairing sequence.
# What worked, in ONE bluetoothctl session holding the agent (a bluetoothctl
# with no stdin hangs, see ../client/huion.nix):
#
#   agent NoInputNoOutput / default-agent / scan on
#   trust C0:95:6D:05:4A:4E      (as soon as it is listed, BEFORE pairing)
#   scan off
#   pair C0:95:6D:05:4A:4E
#   connect C0:95:6D:05:4A:4E    (immediately, while it is still awake)
#
# `bluetoothctl remove` first if a half bond is left over.
#
# Input settings are unchanged. The kernel's magicmouse driver binds it
# over uhid like it did over USB, libinput reports it as a touchpad
# (bluetooth:004c:0265, pointer+gesture), so niri's `touchpad {}` block in
# home/dot_config/niri/input.kdl (tap, natural-scroll, clickfinger) applies
# as before. There never was a per-device niri block. The battery shows up as
# /sys/class/power_supply/hid-c0:95:6d:05:4a:4e-battery-*.
{
  # Page scan in interlaced mode, so the click that wakes a sleeping trackpad
  # reconnects promptly. Costs radio power, which a desk machine can spare.
  # A switch does not restart bluetooth.service; this applies after
  # `systemctl restart bluetooth` or a reboot.
  hardware.bluetooth.settings.General.FastConnectable = true;
}
