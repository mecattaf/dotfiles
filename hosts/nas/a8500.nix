# Netgear A8500 (BE5000, MT7925U) hardware facts — the NAS's Freebox uplink
# radio. Captured at first plug-in (phase 1 of the 2026-08-20 router cutover);
# null until then, which keeps every device-specific piece of the router plane
# (wan0 link naming, the new_id shim) inert while letting the rest of the
# topology evaluate and deploy.
#
#   mac    — the adapter's permanent MAC, `lsusb`/`ip link` at plug-in.
#   usbVid/usbPid — hex WITHOUT 0x prefix, from `lsusb` (vendor 0846 = Netgear).
#
# The new_id shim exists because the A8500's USB device ID enters the upstream
# mt7925u id table only in kernel 7.2; this box runs 7.1.x. Delete the shim
# (and these two usb fields) once the NAS kernel reaches >= 7.2.
{
  # Captured live at first plug-in, 2026-08-20. lsusb's database mislabels
  # 0846:9050 as an "A6200 (BCM43526)" — stale usb.ids; the silicon is
  # MT7925U and the mt7925u driver binds and loads firmware cleanly
  # (validated by hand before this file was filled). The MAC below is the
  # PERMANENT address (ethtool -P); the runtime address is NM-randomized
  # and must never be used for matching.
  mac = "28:94:01:c7:9c:5c";
  usbVid = "0846";
  usbPid = "9050";
}
