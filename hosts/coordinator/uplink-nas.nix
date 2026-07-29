{
  config,
  lib,
  pkgs,
  ...
}:
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
  # imperative NM profile that was hand-copied during flash night
  # (refs #37); field-for-field mirror of `nmcli connection show Freebox-AB3ACE`
  # (2026-07-11), minus the PSK, which comes from secrets/wifi.age via
  # `environmentFiles` `$FREEBOX_PSK` substitution. Both halves are gated on
  # `wifiReady` so this never lands a half-substituted profile that would fight
  # the live connection.
  networking.networkmanager.ensureProfiles.profiles.freebox-uplink = lib.mkIf wifiReady {
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
  networking.networkmanager.ensureProfiles.environmentFiles = lib.mkIf wifiReady [
    config.age.secrets.wifi.path
  ];

  # --- JBL Authentics 200 on a dedicated wire (enp191s0), 2026-07-25 ---
  # The speaker is cabled DIRECTLY to this box's RTL8126 port. This is not a
  # revival of the BE550 router plane above: it is a point-to-point segment with
  # exactly one appliance on it.
  #
  # Why the cable exists: audio to the JBL stuttered badly over wifi, and the
  # coordinator's own uplink is an mt7925e that has hard-locked this box twice
  # (see modules/strix.nix). Measured on the wire vs the wifi path: 0.465ms RTT
  # / 0.088ms jitter against 7.06ms / 4.94ms — ~15x the latency and ~55x the
  # jitter removed, and the audio no longer crosses the flaky radio at all.
  #
  # Why each piece is needed (all four were established empirically 2026-07-25;
  # the speaker sat unusable with any one of them missing):
  #   - an address on our end: nothing else serves this segment;
  #   - dnsmasq: the JBL broadcasts a DHCP request every ~60s and had nobody to
  #     answer it, so it never obtained an IPv4 and AirPlay could not run. It is
  #     DHCP-ONLY (port = 0) — AdGuard owns DNS on 127.0.0.1:53 and must not be
  #     fought with (see modules/adguardhome.nix);
  #   - trustedInterfaces: common.nix's firewall dropped the DHCP broadcast
  #     before dnsmasq ever saw it. RAOP also needs the speaker's timing/control
  #     packets back on unsolicited UDP ports, which RELATED,ESTABLISHED does not
  #     cover. Trusting a dedicated one-appliance cable keeps that exception
  #     constrained to a physical point-to-point segment;
  #   - NAT: without it the speaker reaches this box and nothing else — no
  #     firmware updates, no streaming services, no app control.
  #
  # NB: the JBL must have its OWN wifi turned off (JBL One app). While it was on
  # both networks it advertised the SAME mDNS service name from both interfaces,
  # avahi could not resolve it, and PipeWire tore the sink down on a loop
  # ("mod.raop-discover: Resolving of 'E809590727EA@Office speaker' failed:
  # Timeout reached") — which is what made the speaker vanish from the audio
  # menu. One interface, one service, stable sink.
  # NM keeps ownership of the NIC and carries the static address itself. The
  # first cut of this marked enp191s0 `unmanaged` and set the address through
  # networking.interfaces instead; that FAILED on activation 2026-07-25 — NM
  # released the link, nothing else brought it back up, so the interface sat
  # DOWN with no carrier and dnsmasq died with "unknown interface enp191s0".
  # network-addresses-<iface>.service only adds an address, it never does
  # `ip link set up`, and with NM enabled there is no network-link unit to do it.
  # Letting NM own the interface keeps link-up and addressing in one place.
  # never-default: this segment must never become a default route — the internet
  # uplink is the wifi profile above.
  networking.networkmanager.ensureProfiles.profiles.jbl-wire = {
    connection = {
      id = "jbl-wire";
      type = "ethernet";
      interface-name = "enp191s0";
      autoconnect = true;
      autoconnect-priority = 50;
    };
    ipv4 = {
      method = "manual";
      address1 = "10.42.0.1/24";
      never-default = true;
    };
    ipv6.method = "ignore";
  };

  services.dnsmasq = {
    enable = true;
    settings = {
      port = 0; # DHCP only; never bind :53 (AdGuard owns it on loopback)
      interface = "enp191s0";
      # bind-dynamic, NOT bind-interfaces: dnsmasq starts before NM has finished
      # bringing enp191s0 up, and bind-interfaces makes that a hard startup
      # failure ("unknown interface"). bind-dynamic watches for the interface
      # appearing instead, so a cold boot — or the cable being unplugged and
      # replugged — cannot leave a failed unit behind for the nightly deploy.
      bind-dynamic = true;
      dhcp-range = "10.42.0.50,10.42.0.150,12h";
      dhcp-authoritative = true;
    };
  };

  networking.nat = {
    enable = true;
    internalInterfaces = [ "enp191s0" ];
    externalInterface = "wlp192s0";
  };

  networking.firewall.trustedInterfaces = [ "enp191s0" ];

  # LaCie 4TB, attached DIRECTLY to this box via USB (Tom's ruling 2026-07-05;
  # the old BE550-SMB path is retired). nofail + automount keep boot clean when
  # the drive is unplugged. Partition 2 was migrated from NTFS to Btrfs on
  # 2026-07-23 while retaining the GPT and partition boundaries. Pin the new
  # filesystem UUID rather than the reusable label, and use conservative
  # single-rotating-disk options. POSIX ownership now lives on disk.
  fileSystems."/mnt/nas" = {
    device = "/dev/disk/by-uuid/20e38790-a639-4ffc-8f1a-3921d1aedb97";
    fsType = "btrfs";
    options = [
      "noatime"
      "compress=zstd:3"
      "nofail"
      "noauto"
      "x-systemd.automount"
    ];
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
