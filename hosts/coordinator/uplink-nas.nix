{
  config,
  lib,
  ...
}:
let
  # The Freebox uplink PSK ships as an agenix secret (secrets/wifi.age). Until
  # that ciphertext is committed the whole declarative-wifi block stays inert so
  # nothing here can break eval or clobber the live imperative connection.
  wifiReady = builtins.pathExists ../../secrets/wifi.age;
  # BE550-LAN credentials, minted at cutover phase 3 (2026-08-20 rewire).
  lanReady = builtins.pathExists ../../secrets/wifi-lan.age;
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
#   - a private routed fast lane to the headless NixOS host `nas`.
#
# 2026-08-20/21 REWIRE, COMPLETE: the BE550 came back as a dumb AP, but the
# router plane did not come back here — the NAS ingests the Freebox on a USB
# A8500 and is the LAN's gateway/DHCP/DNS (hosts/nas/router.nix); this box is
# an ordinary client of the repeated wifi (thomas-6ghz profile below, static
# .2). Every transitional rail (nas-fast-lane, installer dnsmasq, NAT,
# enp191s0 admissions, the /30 itself) was deleted on cutover day.
#
# The LaCie 4TB USB plane that used to live here (the /mnt/nas automount, the
# SAT smartd thermal watch, the hd-idle spin-down suite) was RETIRED 2026-08-02
# with the NAS cutover (#131): the real NAS owns /mnt/nas now, the LaCie hangs
# off the NAS as the rollback copy, and if it ever mounts anywhere again the
# path is /mnt/lacie — never /mnt/nas — with no monitoring attached. See git
# history for the retired blocks (they carried the probed USB-bridge lore:
# `-n standby,q`, `-c ata`, kernel-name resolution for hd-idle).
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
  networking.networkmanager.ensureProfiles.environmentFiles =
    lib.optional wifiReady config.age.secrets.wifi.path
    ++ lib.optional lanReady config.age.secrets.wifi-lan.path;

  # The repeated LAN (2026-08-20 rewire): once the NAS routes the house and
  # the BE550 rebroadcasts at the TV corner, this box becomes an ordinary
  # wifi client of that segment — its pinned lease is 10.42.0.2
  # (hosts/nas/router.nix dhcp-host). Higher autoconnect-priority than the
  # freebox-uplink above, which stays as the fallback rail: if the repeated
  # LAN is down (NAS rebuild, BE550 unplugged), NM falls back to the Freebox
  # and this box keeps internet + tailnet, including its SSH path to the
  # NAS's uplink leg.
  #
  networking.networkmanager.ensureProfiles.profiles.thomas-6ghz = lib.mkIf lanReady {
    connection = {
      id = "thomas-6ghz";
      type = "wifi";
      interface-name = "wlp192s0";
      autoconnect = true;
      autoconnect-priority = 110;
    };
    wifi = {
      mode = "infrastructure";
      # thomas-6ghz since the 2026-08-21 6GHz ruling (via wifi-lan.age).
      # Deliberately NO bssid pin and NO band: this SSID exists on exactly
      # one radio (the BE550's 6GHz; its 5GHz radio is disabled and 2.4
      # carries a different SSID), so the mt7925 same-SSID roam crash has no
      # surface here — and the 6GHz MLD BSSID differs between scan and
      # association (seen live), so a pin actively breaks activation. The
      # flake check carries a matching by-name exemption for this profile.
      ssid = "$BE550_SSID";
    };
    wifi-security = {
      # WPA3-SAE — mandatory on 6GHz, with protected management frames.
      key-mgmt = "sae";
      pmf = 3;
      psk = "$BE550_PSK";
    };
    # STATIC addressing (2026-08-21 hardening ruling: "anything dns/dhcp
    # related must never bite"). This box's 10.42.0.2 is load-bearing — NAS
    # firewall admissions, NFS export ACLs, and AdGuard's .internal answers
    # all name it — so its most important client must not depend on the
    # DHCP round-trip at association time or lease renewal. The dnsmasq
    # dhcp-host pin (hosts/nas/router.nix) stays as the guard that keeps
    # the pool from ever handing .2 to anyone else. DNS is the NAS resolver,
    # stated here rather than learned, with ignore-auto-dns for good measure.
    ipv4 = {
      method = "manual";
      address1 = "10.42.0.2/24";
      gateway = "10.42.0.1";
      dns = "10.42.0.1";
      ignore-auto-dns = true;
    };
    ipv6.method = "ignore";
  };

  # nas-fast-lane RETIRED 2026-08-21 (Tom: "no longer desired at all
  # whatsoever"): the /30 point-to-point rail (nas-fast-lane NM profile,
  # installer dnsmasq, NAT relay, enp191s0 admissions here and in
  # attic/caddy-artifacts/llama-swap/immich-ml) is gone — the physical cable
  # was unplugged at the TV-corner move and the NAS reaches the internet
  # through its own wan0 now. The NAS-SIDE dual-rail leftovers (10.77.0.2
  # address, 10.77.0.1 export/admission entries across the NAS modules)
  # retire in the post-soak cleanup commit. NOTE: ensureProfiles never
  # deletes a profile it stopped ensuring — `nmcli connection delete
  # nas-fast-lane` was run by hand at retirement.
  #
  # NM at INFO explicitly (2026-08-21): this box's NetworkManager had logged
  # nothing since Aug 05 — every wifi incident of cutover day was forensically
  # blind. Whatever suppressed it, pin the level so it cannot regress.
  networking.networkmanager.logLevel = "INFO";

  # The `nas` hosts pin moved to modules/common.nix (fleet-wide) at the
  # 2026-08-21 attic move — every host dials the substituter by that name.
}
