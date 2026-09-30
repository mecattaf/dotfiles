# The Apple Magic Trackpad (2, 004C:0265) on Bluetooth, not the dock's USB.
# Since 2026-09-17 it is bonded to this box's MediaTek radio (0e8d:0717) and
# charged over its cable only now and then. Plugged in, it is a USB device
# again (05AC:0265). Unplugged, it pages back here on the next click.
#
# The bond itself is state, not config: the link key lives in
# /var/lib/bluetooth/AC:F2:3C:35:1E:D2/C0:95:6D:05:4A:4E and a reinstall
# loses it. Re-pair as tom, cable out, trackpad switched off then on so it
# is discoverable. Order matters. The first attempt paired the plain way
# (scan, pair, then trust and connect ~12 s later). bluetoothd dropped the
# link right after "Pairing successful", every connect from this side failed
# with "control_connect_cb() … Invalid exchange (52)", clicks did nothing, and
# a scan showed the trackpad still discoverable, so it had not kept the bond.
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
