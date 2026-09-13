{ pkgs, ... }:
# client — the Huion Note X10 is the paper inbox. Tom writes on it anywhere,
# presses the button for each new page, and opens the cover near this laptop;
# the pages come off the notepad over Bluetooth and land on the coordinator.
# The radio is on this box, so this file is the client's one deliberate
# exception to "runs nothing" (DECISIONS.md, 2026-09-13).
#
# Proven by hand on this metal on 2026-09-13 before a line of it was declared
# (the handoff bundle, transcripts, frame traces and bluetoothd logs are in
# coordinator:~/huion/). Three things stood between stock NixOS and a dump,
# hit in this order:
#
# ── 1. BlueZ drops the link on the X10's duplicate MTU request ──────────────
# The notepad sends a second ATT MTU request while the first is pending, and
# bluetoothd's src/shared/att.c answers that with io_shutdown — the link dies
# before GATT resolves. Still true on 5.86. The extractor repo's two-line patch
# drops the duplicate instead; the patched daemon logs "Received request while
# another is pending: 0x02 (dropping duplicate)" on every good connect. Only
# the service package changes, so nothing else that links bluez rebuilds.
#
# ── 2. pairing: ONE-TIME, already done, no permanent agent ──────────────────
# The X10's HID service asks for "just works" authorization. With no agent
# bluetoothd refuses and the device loops reconnecting every ~2 s; after one
# accepted pairing it is Paired+Bonded+Trusted in /var/lib/bluetooth and
# reconnects never prompt again. If the bond is ever lost (new adapter,
# /var/lib/bluetooth wiped, notepad reset), re-pair as tom with the cover open:
#
#   bluetoothctl
#   agent NoInputNoOutput
#   default-agent
#   scan on                      # wait for "Huion Note-X10"
#   trust 25:6C:20:F5:D8:25
#   connect 25:6C:20:F5:D8:25    # answer "yes" at "Accept pairing (yes/no)"
#
# (A bluetoothctl with no stdin hangs at that prompt forever — run it in a
# terminal.)
#
# ── 3. HOGP hands it to hid-generic, which silences notifications ───────────
# On connect BlueZ's input plugin creates a uhid device 0005:256C:8251.<n>
# (n increments every reconnect), hid-generic binds it as a keyboard, and the
# extractor's GATT notifications stall until the dump times out with an empty
# "error: dump failed: ". Unbinding on EVERY add fixes it — by hand a moment
# too late failed, with this rule loaded the first try succeeded and sysfs
# showed no driver on the fresh instance. Not the alternatives:
# UserspaceHID=true does not stop HOGP, and disabling the input plugin would
# take the Duo's own Bluetooth keyboard (D9:D8:5B:AC:01:05) down with it. The
# repo's other rule line (uinput group) is for its live pen driver; tablet mode
# is not wanted here.
#
# Opening the notepad with the cover: LED green = on and recording offline;
# closed = asleep, link drops. Upstream's README says "cover closed" for note
# mode — wrong for this unit.
{
  hardware.bluetooth.package = pkgs.bluez.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ pkgs.huion-notes.bluezPatch ];
  });

  services.udev.extraRules = ''
    SUBSYSTEM=="hid", KERNEL=="0005:256C:8251.*", ACTION=="add", RUN+="${pkgs.runtimeShell} -c 'echo %k > /sys/bus/hid/drivers/hid-generic/unbind 2>/dev/null || true'"
  '';
}
