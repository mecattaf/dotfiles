{ config, lib, pkgs, ... }:
let
  # The Freebox uplink PSK ships as an agenix secret (secrets/wifi.age). Until
  # that ciphertext is committed the whole declarative-wifi block stays inert so
  # nothing here can break eval or clobber the live imperative connection.
  wifiReady = builtins.pathExists ../../secrets/wifi.age;
in
# The coordinator's internet uplink + directly-attached NAS.
#
# HISTORY: this file was `router.nix` and made the coordinator a LAN gateway /
# DHCP / DNS server for a downstream 10.42.0.0/24 wifi segment on enp191s0,
# fronted by a TP-Link BE550 in AP mode. The BE550 was RETIRED 2026-07-13 and
# physically unplugged, so that entire router plane is gone — the shared-mode
# gateway profile, the dnsmasq-shared DHCP drop-ins, the BE550 lease pin, the
# nftables :53 DNAT + encrypted-DNS-bypass drops, the enp191s0 firewall holes,
# and the DNSStubListener=no hack that only existed so the old rootless AdGuard
# quadlet could own :53 for those wifi clients. DNS filtering now lives per-box
# in modules/adguardhome.nix (loopback resolver) instead of a LAN service here.
#
# What remains is genuinely BE550-independent:
#   - the Freebox wifi uplink (wlp192s0), this box's actual internet, and
#   - the LaCie 4TB USB NAS (/mnt/nas) + its thermal/power suite.
{
  # Internet uplink: the Freebox AP over wifi (wlp192s0). Ported from the live
  # imperative NM profile that was hand-copied off the worker on flash night
  # (refs #37); field-for-field mirror of `nmcli connection show Freebox-AB3ACE`
  # (2026-07-11), minus the PSK, which comes from secrets/wifi.age via
  # `environmentFiles` `$FREEBOX_PSK` substitution. Both halves are gated on
  # `wifiReady` so this never lands a half-substituted profile that would fight
  # the live connection.
  networking.networkmanager.ensureProfiles.profiles.freebox-uplink =
    lib.mkIf wifiReady {
      connection = {
        id = "Freebox-AB3ACE";
        type = "wifi";
        interface-name = "wlp192s0";
        autoconnect = true;
        autoconnect-priority = 100;
      };
      wifi = {
        mode = "infrastructure";
        ssid = "Freebox-AB3ACE";
        # Pinned HARD to the Freebox's 5GHz radio (2026-07-16). The mt7925e
        # driver has a wcid list-corruption race on the same-SSID band-steering
        # roam path (2.4↔5GHz hop): `list_add corruption` → `kernel BUG at
        # lib/list_debug.c:32` inside a locked section → instant full lockup,
        # no oops, no video, no network, power-cycle required. It killed this
        # box TWICE in 12h (boots ending 2026-07-16 01:06 and 13:17, journal
        # -2/-1), both times at the exact instant of a roam to this BSSID.
        # Kernel 7.1 already carries the known upstream fixes for this bug
        # class (double-wcid-init + wcid_cleanup poll_list, verified in-tree),
        # so this is a remaining unfixed race; BIOS 3.05 (2026-07-14) armed it:
        # 11 roams / 8 days / 0 crashes on 3.02 vs 9 roams / 2 crashes on 3.05.
        # No roam, no crash. Trade-off: no 2.4GHz fallback if the 5GHz radio
        # drops — fine for a stationary desktop; see also the disable_aspm +
        # watchdog hardening in modules/strix.nix.
        bssid = "8C:97:EA:FE:FA:E0";
        band = "a";
      };
      wifi-security = {
        key-mgmt = "wpa-psk";
        psk = "$FREEBOX_PSK";
      };
      ipv4.method = "auto";
      ipv6.method = "auto";
    };
  networking.networkmanager.ensureProfiles.environmentFiles =
    lib.mkIf wifiReady [ config.age.secrets.wifi.path ];

  # LaCie 4TB, attached DIRECTLY to this box via USB (Tom's ruling 2026-07-05;
  # the old BE550-SMB path is retired). nofail + automount keep boot clean when
  # the drive is unplugged. Label/device confirmed live 2026-07-11:
  # `lsblk -f` → sda2, LABEL=LaCie, NTFS. The old `fsType = "auto"` failed every
  # boot because no NTFS driver was configured; the in-kernel ntfs3 driver
  # (mature on kernel 7.1, built in — `ntfs3` in /proc/filesystems) mounts it
  # natively with no ntfs-3g/FUSE dependency. uid/gid are honoured by ntfs3.
  fileSystems."/mnt/nas" = {
    device = "/dev/disk/by-label/LaCie";
    fsType = "ntfs3";
    options = [
      "uid=1000"
      "gid=100"
      "nofail"
      "noauto"
      "x-systemd.automount"
      # Requires= + After= on the dirty-flag cleaner below, so every mount
      # attempt (incl. automount triggers) self-heals first.
      "x-systemd.requires=ntfsfix-lacie.service"
    ];
  };

  # Self-heal the NTFS dirty flag before every mount. An unclean unmount
  # (power cut, USB yank) sets the volume dirty bit and ntfs3 then refuses to
  # mount at all — found live 2026-07-12 as a silently empty /mnt/nas with
  # mnt-nas.mount stuck in start-limit-hit. We deliberately do NOT mount with
  # `force`: that would also rw-mount a genuinely inconsistent volume.
  # ntfsfix -d verifies/repairs $MFT/$MFTMirr and the boot sector, resets the
  # journal and clears the dirty flag; on a clean volume it is a verified
  # no-op (exit 0). If the fix itself fails the mount stays down — correct,
  # since that means real corruption needing a Windows chkdsk.
  systemd.services.ntfsfix-lacie = {
    description = "ntfsfix — clear NTFS dirty flag on the LaCie before mounting";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = pkgs.writeShellScript "ntfsfix-lacie" ''
        set -eu
        dev=/dev/disk/by-label/LaCie
        # Drive unplugged → nothing to fix; the nofail mount handles absence.
        [ -b "$dev" ] || exit 0
        # Already mounted (manual/test mount) → ntfsfix would refuse; skip.
        ${pkgs.util-linux}/bin/findmnt -S "$dev" >/dev/null && exit 0
        ${pkgs.ntfs3g}/bin/ntfsfix -d "$dev"
      '';
    };
  };

  # ── LaCie thermal + power suite ─────────────────────────────────────────────
  # Health/temperature monitoring and idle spin-down for the LaCie 4TB above.
  # The drive is a Seagate BarraCuda ST4000LM024 (2.5" SMR, 5526 rpm) behind a
  # USB-SATA bridge (TRAN usb), so it exposes NO SATA hwmon node — drivetemp is
  # SATA-only — and its own firmware idle timer is NOT honoured through the
  # bridge (probed live 2026-07-11: `hdparm -S 12` accepted but the platters
  # never parked after 80s of zero I/O). Both facts shape the choices below.
  # Stable handle: /dev/disk/by-id/ata-…_WCK19ZT3 (serial WCK19ZT3), which the
  # bridge passes through so smartctl auto-detects the SAT layer.

  # smartd — declarative SMART monitoring of the LaCie ONLY.
  #   -d sat        : talk ATA through the USB bridge's SCSI/ATA translation.
  #   -a            : full attribute + self-test-log monitoring.
  #   -n standby,q  : NON-NEGOTIABLE. Never issue a poll that would spin a parked
  #                   drive back up; `q` also suppresses the "skipped, standby"
  #                   log line so journald isn't spammed every 30 min.
  #   -W 4,45,50    : warn on a 4°C jump, log INFO at 45°C, CRIT at 50°C. Worst
  #                   ever seen is 55°C; 45/50 sit just above the ~45°C idle temp.
  # Consumer surface: smartd writes these temperature/health events to journald
  # (`journalctl -u smartd`) — that is where future thermal tripwires read from.
  # autodetect=false is deliberate: a DEVICESCAN line would re-add /dev/sda with
  # the default `-a` and NO `-n standby,q`, waking the drive on every poll.
  services.smartd = {
    enable = true;
    autodetect = false;
    extraOptions = [ "-i 1800" ]; # poll every 30 min (also smartd's default)
    devices = [
      {
        device = "/dev/disk/by-id/ata-ST4000LM024-2AN17V_WCK19ZT3";
        options = "-a -d sat -n standby,q -W 4,45,50";
      }
    ];
  };

  # Spin-down after ~20 min idle. The drive's internal -S timer is ignored by
  # the bridge (see above) and hd-idle's default SCSI STOP command is a no-op on
  # it too (probed: exit 0 but platters stay spinning), so we drive hd-idle in
  # `-c ata` mode — ATA STANDBY through the SAT layer, the ONE command this
  # bridge honours (`hdparm -y` parks it in ~0s; a cold read wakes it in ~3.3s).
  # hd-idle watches /proc/diskstats and parks the disk after -i seconds of no
  # I/O; NixOS ships no services.hd-idle module, hence this hand-rolled unit.
  #
  # hd-idle keys its per-disk idle timer on the KERNEL name as it appears in
  # /proc/diskstats ("sda"); its symlink handling does NOT feed that match, so
  # `-a <by-id>` silently falls back to the default timer and never fires
  # (probed live 2026-07-11). We therefore resolve the stable by-id → current
  # kernel name at start and hand hd-idle that. On this box the LaCie is the
  # only sd* block device (the system disk is NVMe), but resolving keeps the
  # unit correct even if the kernel name ever shifts (sdb, …).
  #   -i 0            : default idle 0 (disabled) for every other disk.
  #   -c ata          : issue ATA STANDBY (the command the bridge honours).
  #   -a <dev> -i 1200: park THIS disk after 20 min (1200 s) idle.
  systemd.services.hd-idle = {
    description = "hd-idle — spin down the LaCie NAS drive after 20 min idle";
    documentation = [ "man:hd-idle(8)" ];
    after = [ "mnt-nas.mount" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = pkgs.writeShellScript "hd-idle-lacie" ''
        set -eu
        dev=$(${pkgs.coreutils}/bin/basename \
          "$(${pkgs.coreutils}/bin/readlink -f /dev/disk/by-id/ata-ST4000LM024-2AN17V_WCK19ZT3)")
        exec ${pkgs.hd-idle}/bin/hd-idle -i 0 -c ata -a "$dev" -i 1200
      '';
      Restart = "on-failure";
      RestartSec = 30;
    };
  };
}
