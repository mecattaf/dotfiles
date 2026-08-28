{
  lib,
  pkgs,
  ...
}:
let
  a8500 = import ./a8500.nix;
  a8500Known = a8500.mac != null && a8500.usbVid != null;
in
# ── wan0 watchdog: detect a wedged uplink, recover it in software ──────────
# Born from the 2026-08-23 incident (#235 post-mortem, verified from the
# attic DB + coordinator journal): the A8500's mt7925u firmware wedged at
# 10:30:51 — within a minute of update-center's ExecStopPost gc SIGKILL —
# and stayed wedged for 4.5 DAYS. Not for lack of doze hardening (router.nix
# already pins BSSID, kills 802.11 powersave AND USB autosuspend): the
# firmware simply stopped, wpa_supplicant hung so hard that every NM D-Bus
# call timed out every ~20s until Tom walked to the box and power-cycled it.
# The same dongle re-associated in 9 seconds after the cycle — the recovery
# was the USB re-enumeration, and THAT we can do from software.
#
# Detection mirrors the coordinator's uplink-failover-watchdog and encodes
# the same hard lesson: end-to-end probes only. During the outage the NAS's
# LAN face (dnsmasq, NFS, atticd, journald-remote) stayed perfectly healthy
# — any local liveness signal would have said "fine" for five days.
#
# Recovery is an escalation ladder, gentlest first, because each rung is
# more disruptive than the last and the gentle ones handle the mundane
# causes (AP reboot, lease hiccup) that don't deserve a device bounce:
#   1. `nmcli connection up` — reactivation, for the NM-recoverable cases.
#   2. debugfs chip_reset — the driver's own System Error Recovery, the
#      mechanism purpose-built for the MCU-wedge class (research 08-28:
#      the wedge is a known mt7925 issue, comprehensive fixes still in
#      upstream review; kernel 7.1.5 already carries the high-load ABBA
#      deadlock fix and wedged anyway). SER's own recovery path has had
#      2026 bugfixes, so it gets one shot before the USB hammer.
#   3. USB deauthorize/reauthorize — logical unplug/replug: full re-probe,
#      firmware re-download, NM autoconnect. This is the power-cycle
#      equivalent that the 08-23 wedge actually needed. (sysfs driver
#      unbind/bind has a documented failure precedent on mt7925u —
#      morrownr/USB-WiFi#688 — which is why it's not a rung.)
#   4. restart wpa_supplicant + NetworkManager — for the daemon-side hang
#      the wedge leaves behind (a supplicant stuck in a dead ioctl may only
#      come unstuck once the device node is gone; restart sweeps the rest).
# 10-minute cooldown between ladders, forever — a router must keep trying,
# but must not flap the radio every 30s while the Freebox itself is down
# (upstream ISP outage looks identical to a wedge from here; the ladder is
# harmless in that case and the cooldown keeps it polite).
#
# Journal discipline (the AdGuard vacuum lesson, #235): healthy rounds are
# SILENT; strikes and remediations log, heartbeats never.
{
  config = lib.mkIf a8500Known {
    systemd.services.wan0-watchdog = {
      description = "Recover the A8500 uplink when internet via wan0 is dead";
      serviceConfig = {
        Type = "oneshot";
        ExecStart = pkgs.writeShellScript "wan0-watchdog" ''
          PATH=${
            lib.makeBinPath [
              pkgs.networkmanager
              pkgs.iputils
              pkgs.coreutils
              pkgs.systemd
            ]
          }
          strikes=/run/wan0-watchdog.strikes
          lastfix=/run/wan0-watchdog.last-remedy

          probe() {
            for target in 1.1.1.1 9.9.9.9; do
              ping -c1 -W2 -I wan0 "$target" >/dev/null 2>&1 && return 0
            done
            return 1
          }

          if probe; then
            if [ -s "$strikes" ] && [ "$(cat "$strikes")" != 0 ]; then
              echo "internet reachable again via wan0; debounce reset"
            fi
            rm -f "$strikes"
            exit 0
          fi

          n=$(($(cat "$strikes" 2>/dev/null || echo 0) + 1))
          echo "$n" >"$strikes"
          # Log the first strikes of an episode, then shut up until action:
          # a Freebox outage would otherwise print 2 lines/min for its whole
          # duration — the exact spam class that ate the 08-23 forensics.
          [ "$n" -le 5 ] && echo "internet unreachable via wan0 (strike $n/5)"
          [ "$n" -lt 5 ] && exit 0

          now=$(date +%s)
          last=$(cat "$lastfix" 2>/dev/null || echo 0)
          [ $((now - last)) -lt 600 ] && exit 0
          echo "$now" >"$lastfix"
          rm -f "$strikes"

          # Rung 1: reactivation. timeout matters — nmcli talks to NM talks
          # to wpa_supplicant, and a wedged supplicant makes that chain hang
          # (observed: 4.5 days of 20s D-Bus timeouts).
          echo "WAN DEAD ~2.5min: rung 1 — nmcli reactivation"
          if timeout 45 nmcli connection up Freebox-AB3ACE >/dev/null 2>&1; then
            sleep 5
            probe && {
              echo "recovered via nmcli reactivation"
              exit 0
            }
          fi

          # Rung 2: the driver's System Error Recovery — full chip/firmware
          # reset. debugfs knob verified present on this phy (2026-08-28).
          phy=$(cat /sys/class/net/wan0/phy80211/name 2>/dev/null || echo phy0)
          ser=/sys/kernel/debug/ieee80211/$phy/mt76/chip_reset
          if [ -w "$ser" ]; then
            echo "rung 2 — driver chip_reset (SER) on $phy"
            echo 1 >"$ser" 2>/dev/null || true
            sleep 20
            probe && {
              echo "recovered via chip_reset"
              exit 0
            }
          fi

          # Rung 3: logical unplug/replug. Find the A8500 by VID/PID (the
          # sysfs path shifts with port/hub topology; the identity doesn't).
          echo "rung 3 — USB re-enumeration of the A8500"
          for dev in /sys/bus/usb/devices/*; do
            [ -f "$dev/idVendor" ] || continue
            [ "$(cat "$dev/idVendor")" = "${a8500.usbVid}" ] || continue
            [ "$(cat "$dev/idProduct")" = "${a8500.usbPid}" ] || continue
            echo 0 >"$dev/authorized"
            sleep 3
            echo 1 >"$dev/authorized"
            break
          done
          sleep 25 # re-probe + firmware load + NM autoconnect
          probe && {
            echo "recovered via USB re-enumeration"
            exit 0
          }

          # Rung 4: sweep the daemons the wedge may have left hanging.
          echo "rung 4 — restarting wpa_supplicant + NetworkManager"
          systemctl restart wpa_supplicant.service NetworkManager.service
          sleep 25
          timeout 45 nmcli connection up Freebox-AB3ACE >/dev/null 2>&1 || true
          sleep 5
          if probe; then
            echo "recovered via daemon restart"
          else
            echo "STILL DEAD after full ladder — next attempt in 10min (Freebox itself down?)"
          fi
        '';
      };
    };
    systemd.timers.wan0-watchdog = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        # Boot association + NM settling get a grace window; the strikes
        # debounce covers the rest.
        OnBootSec = "5min";
        OnUnitActiveSec = "30s";
        AccuracySec = "10s";
      };
    };
  };
}
