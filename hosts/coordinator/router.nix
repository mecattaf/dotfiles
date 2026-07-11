{ config, lib, pkgs, ... }:
let
  # The Freebox uplink PSK ships as an agenix secret (secrets/wifi.age). Until
  # that ciphertext is committed the whole declarative-wifi block stays inert so
  # nothing here can break eval or clobber the live imperative connection.
  wifiReady = builtins.pathExists ../../secrets/wifi.age;
in
# The coordinator's LAN router plane. The TP-Link BE550 runs in AP mode (dumb
# layer-2 bridge + USB NAS); THIS box is the gateway, DHCP and DNS for the
# 10.42.0.0/24 wifi segment on enp191s0, with internet uplink over wifi
# (wlp192s0 → Freebox). Ported 2026-07-05 from the harness image
# (archive/harness/main mkosi.extra) + the live box's NM profile.
#
# DNS architecture: NM's shared-mode dnsmasq does DHCP ONLY (port=0) and
# advertises the gateway IP as resolver; AdGuard Home (rootless quadlet, see
# services.nix) owns :53; an nftables DNAT catches clients that hardcode
# 8.8.8.8; this host's own resolved also points at AdGuard. Tailscale MagicDNS
# keeps winning for *.ts.net via per-link DNS.
#
# refs #46: the DNAT above only ever catches PLAINTEXT port 53. Verified live
# 2026-07-11 that AdGuard's querylog has zero entries from real LAN clients
# despite a valid DHCP lease (Pixel-8 got 10.42.0.19 fine) — every logged
# query was container-internal (10.89.0.2). That's the signature of a client
# using encrypted DNS (Android "Private DNS" over DoT/853, or DoH/443 to a
# fixed provider) which sails straight past a plaintext-only hijack. The
# forward-chain rules below drop outbound DoT and DoH-to-known-DNS-IPs from
# the LAN segment so "Automatic"/opportunistic Private DNS on the client
# falls back to plaintext 53, which the DNAT above then redirects to AdGuard.
# This does NOT help a client with Private DNS pinned to a hostname (strict
# mode) — that's a phone-side setting, see the issue for the manual step.
{
  # Gateway profile for the BE550 segment. ipv4.method=shared = NM runs dnsmasq
  # (DHCP+NAT) on this interface — same profile the Fedora box ran imperatively.
  networking.networkmanager.ensureProfiles.profiles.share-to-new = {
    connection = {
      id = "share-to-new";
      type = "ethernet";
      interface-name = "enp191s0";
      autoconnect = true;
    };
    ipv4 = {
      method = "shared";
      addresses = "10.42.0.1/24";
    };
    ipv6.method = "disabled";
  };

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

  environment.etc."NetworkManager/dnsmasq-shared.d/00-adguard.conf".text = ''
    # AdGuard owns :53 — NM's dnsmasq does DHCP only.
    port=0
    # DHCP option 6: hand BE550 wifi clients the gateway IP (= AdGuard) as resolver.
    dhcp-option=6,10.42.0.1
  '';

  environment.etc."NetworkManager/dnsmasq-shared.d/01-be550-pin.conf".text = ''
    # Pin the BE550's DHCP lease to 10.42.0.2 — /mnt/nas hardcodes it.
    # If the BE550 is ever replaced, find the new MAC with:
    #   ip neigh show dev enp191s0
    dhcp-host=98:03:8e:6b:61:e2,be550,10.42.0.2,infinite
  '';

  # Redirect :53 from clients that ignore DHCP option 6 (Chromecasts, IoT).
  # Own table, so the NixOS firewall's rules are untouched.
  networking.nftables = {
    enable = true;
    tables.dns_hijack = {
      family = "inet";
      content = ''
        chain prerouting {
          type nat hook prerouting priority dstnat; policy accept;
          ip daddr 10.42.0.1 return
          ip saddr 10.42.0.0/24 udp dport 53 dnat ip to 10.42.0.1
          ip saddr 10.42.0.0/24 tcp dport 53 dnat ip to 10.42.0.1
        }

        # refs #46: force encrypted-DNS bypass back onto plaintext 53 (above).
        # DoT (853) has no legitimate destination on this segment — AdGuard's
        # own DoT listener is disabled (tls.enabled=false in its runtime
        # config), so dropping 853 outright costs nothing today and closes
        # the "Automatic" Private DNS escape hatch. DoH shares 443 with
        # ordinary HTTPS, so only known DNS-only provider IPs are dropped,
        # not all of 443 — regular browsing on this segment is unaffected.
        chain forward {
          type filter hook forward priority filter; policy accept;
          ip saddr 10.42.0.0/24 tcp dport 853 drop
          ip saddr 10.42.0.0/24 ip daddr {
            8.8.8.8, 8.8.4.4,
            1.1.1.1, 1.0.0.1,
            9.9.9.9, 149.112.112.112,
            208.67.222.222, 208.67.220.220
          } tcp dport 443 drop
        }
      '';
    };
  };

  # AdGuard serves the BE550 wifi clients ONLY (Tom's ruling 2026-07-05 flash
  # night: "ad-free internet for devices like my phone, nothing else"). This
  # host resolves through its normal uplink DNS (Freebox via wifi DHCP) — the
  # original port wrongly chained the host's own lookups to AdGuard, which made
  # coordinator DNS dead until the AdGuard wizard ran.
  # DNSStubListener stays off: resolved's stubs (127.0.0.53/54:53) hold the
  # port and AdGuard's wildcard 0.0.0.0:53 bind gets EADDRINUSE — found as a
  # crashloop on first NixOS boot. Host lookups go via nss-resolve → resolved
  # → link DNS, so MagicDNS keeps working.
  services.resolved.enable = true;
  environment.etc."systemd/resolved.conf.d/50-adguard.conf".text = ''
    [Resolve]
    DNSStubListener=no
  '';

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

  # AdGuard runs ROOTLESS (user quadlet) yet must bind :53.
  boot.kernel.sysctl."net.ipv4.ip_unprivileged_port_start" = 53;

  # LAN DNS/DoT/AdGuard-admin + the app ports, reachable from the BE550 segment.
  networking.firewall.interfaces.enp191s0.allowedTCPPorts = [ 53 853 3000 8844 8443 2283 4533 ];
  networking.firewall.interfaces.enp191s0.allowedUDPPorts = [ 53 67 784 ];
}
