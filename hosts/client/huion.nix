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
#
# ── the sync: dump on connect, spool, push, retry ──────────────────────────
# Opening the cover near the laptop is the whole gesture. BlueZ reconnects the
# trusted notepad on its own, the uhid add fires the unbind above AND wants
# huion-sync.service, and that one-shot, as tom:
#
#   1. dumps every stored page into /var/lib/huion-sync/spool/<ts>/ and lets
#      the extractor CLEAR the device (no --keep — Tom: clearing synced pages
#      "is indeed desirable"). The extractor deletes a page only once its SVG
#      and JSON are on local disk and never an incomplete one; it cannot wait
#      for the push, so the spool is the durability buffer, not the device.
#   2. pushes every spooled batch, oldest first, to
#      coordinator:~/Paper/inbox/<ts>/ and removes the local copy only after
#      rsync succeeded.
#
# huion-push.timer re-runs step 2 alone (never a dump: that only happens when
# the notepad connects) for anything a down or unreachable coordinator left in
# the spool. One lock serialises the two.
#
# Why a folder per sync: filenames are page{N}-{DD}-{MM} and N restarts at 1
# after every clearing sync, so two syncs on one day would overwrite each
# other in a flat inbox. `inbox/` holds nothing but these folders — printable
# markdown is `intake/`, the print loop's (home/paper.nix). OCR is a later
# coordinator-side consumer of `inbox/` and is not declared anywhere yet.
#
# A system unit with User=tom rather than a user unit: udev can want a system
# unit directly, and tom is all it needs — his ssh key and config for the push,
# the system bus for BlueZ. It runs whether or not a niri session is up.
let
  mac = "25:6C:20:F5:D8:25";

  huion-sync = pkgs.writeShellApplication {
    name = "huion-sync";
    runtimeInputs = with pkgs; [
      bluez
      coreutils
      huion-notes
      openssh
      rsync
      util-linux
    ];
    text = ''
      usage() { echo "usage: huion-sync dump|push" >&2; exit 2; }
      [[ $# -eq 1 ]] || usage

      state=''${STATE_DIRECTORY:?run me as huion-sync.service or huion-push.service}
      spool=$state/spool
      mkdir -p "$spool"

      # Wait rather than skip: a timer push holding the lock is seconds, and
      # the notepad stays connected until the cover closes.
      exec 9>"$state/lock"
      flock -w 300 9

      push() {
        local d rc=0
        for d in "$spool"/*/; do
          [[ -d $d ]] || continue
          local batch
          batch=$(basename "$d")
          if rsync -a --remove-source-files --timeout=60 \
            -e 'ssh -o BatchMode=yes -o ConnectTimeout=10' \
            "$d" "coordinator:Paper/inbox/$batch/"; then
            rmdir "$d"
            echo "pushed $batch -> coordinator:~/Paper/inbox/$batch/"
          else
            echo "push of $batch failed; kept in $spool for huion-push.timer" >&2
            rc=1
          fi
        done
        return "$rc"
      }

      # The extractor only creates -o when there are pages, and page numbers
      # restart after a partial clear, so every attempt gets its own folder.
      dump_once() {
        local out rc=0
        out=$spool/$(date +%Y-%m-%d_%H%M%S)
        huion-notes dump --mac ${mac} -o "$out" || rc=$?
        rmdir "$out" 2>/dev/null || true
        return "$rc"
      }

      case $1 in
        dump)
          rc=0
          # Let GATT resolve and the unbind land before the first frame.
          sleep 3
          if ! dump_once; then
            # A dump that times out (HOGP won the race, a slow resolve) leaves
            # every incomplete page on the device; one more try is safe.
            sleep 5
            if [[ $(bluetoothctl info ${mac}) == *"Connected: yes"* ]]; then
              dump_once || rc=1
            else
              echo "notepad disconnected before the retry" >&2
              rc=1
            fi
          fi
          # A failed push is not this unit's failure: the batch is safe in the
          # spool, and huion-push.service owns that state — it fails on its
          # next tick while the coordinator is unreachable and recovers on
          # its own once the batch lands. Failing here would leave this unit
          # red until the next opening, long after the pages arrived.
          push || true
          exit "$rc"
          ;;
        push) push ;;
        *) usage ;;
      esac
    '';
  };

  unit = verb: {
    after = [ "bluetooth.service" ];
    # Only udev and the timer start these. Left to its defaults, a switch
    # restarts a changed unit that is failed — seen 2026-09-13: it killed one
    # dump and started another with the notepad in reach. A deploy must never
    # dump, nor kill a dump mid-transfer.
    restartIfChanged = false;
    serviceConfig = {
      Type = "oneshot";
      User = "tom";
      ExecStart = "${huion-sync}/bin/huion-sync ${verb}";
      StateDirectory = "huion-sync";
      StateDirectoryMode = "0700";
    };
  };
in
{
  # A switch does not restart bluetooth.service ("NOT restarting the
  # following changed units"), so a changed package only runs after
  # `systemctl restart bluetooth` or a reboot.
  hardware.bluetooth.package = pkgs.bluez.overrideAttrs (old: {
    patches = (old.patches or [ ]) ++ [ pkgs.huion-notes.bluezPatch ];
  });

  services.udev.extraRules = ''
    SUBSYSTEM=="hid", KERNEL=="0005:256C:8251.*", ACTION=="add", RUN+="${pkgs.runtimeShell} -c 'echo %k > /sys/bus/hid/drivers/hid-generic/unbind 2>/dev/null || true'", TAG+="systemd", ENV{SYSTEMD_WANTS}+="huion-sync.service"
  '';

  # Every opening is a new HID instance (.000E, .0010, …), so the add — and
  # the want — fires once per opening; a start while a run is still active
  # merges into it.
  systemd.services.huion-sync = unit "dump" // {
    description = "Pull pages off the Huion Note X10 into coordinator:~/Paper/inbox";
  };

  systemd.services.huion-push = unit "push" // {
    description = "Push spooled Huion pages to coordinator:~/Paper/inbox";
  };
  systemd.timers.huion-push = {
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnBootSec = "2min";
      OnUnitActiveSec = "15min";
    };
  };
}
