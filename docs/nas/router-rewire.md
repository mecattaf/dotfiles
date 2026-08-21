# The NAS is the house router (2026-08-20 rewire)

## Topology

    Freebox ~~5GHz~~> A8500 USB adapter ("wan0") on the NAS
                         |  NAS: NAT, DHCP, AdGuard :53 for the LAN
                         |       (hosts/nas/router.nix)
                         +-- enp1s0 --> BE550 in AP mode (TV corner)
                         |       ~~wifi 7~~> phones, laptops, coordinator
                         +-- HDMI --> TV

    LAN 10.42.0.0/24: NAS .1 (gw+DNS) | coordinator .2 (MAC pin) | BE550 .3 (MAC pin)

The BE550's stock firmware has no WISP/repeater mode and the NAS has no
radio; the A8500 (MT7925U, in-kernel `mt7925u`) is the wifi *client* half
of the "repeater". OpenWrt on the BE550 was investigated and rejected:
PR #20778 is a draft whose wifi does not work and whose install path needs
a soldered UART (signature-checked recovery). Revisit only if that lands.

The coordinator is an ordinary client of the repeated wifi (`be550-lan`
profile, uplink-nas.nix) with the Freebox as its fallback rail. Its old
router-era duties are gone: it keeps immich-ml (:3003), llama-swap (:9292),
attic (:8080), and the Caddy `.internal` front doors + media relays.

## How phones reach media (previously undocumented)

Phone apps dial `coordinator.tail8dd1.ts.net:<port>` over Tailscale —
Immich 2283, Navidrome 4533, Plex 32400 — which land on the coordinator's
socket-proxyd relays and are forwarded to the NAS by NAME (`nas`). Browsers
on fleet machines and LAN clients use `photos/music/videos.internal`
(AdGuard rewrites → the coordinator's Caddy). The rewire does not change
any phone URL. Phones on the house wifi additionally get NAS AdGuard as
their DNS now — the first time since the BE550 retirement that they have
ad-blocking.

## Transition state (dual rail)

Everything is staged so each cutover step keeps the previous rail live:

- NAS enp1s0 carries BOTH 10.42.0.1/24 and the legacy 10.77.0.2/30; its
  transitional /30 default route has metric 700 so wan0 (wifi metric 600)
  wins the moment the A8500 associates.
- NAS firewall admissions and NFS export ACLs accept the coordinator on
  both 10.77.0.1 and 10.42.0.2.
- Coordinator admits the NAS's service dials on both enp191s0 (cable) and
  wlp192s0 (LAN wifi).
- `networking.hosts` already point at the LAN identities: 10.42.0.1 is
  reachable over the /30 cable too, so the physical move changes nothing
  about addressing.

## Cutover phases

1. **Plug the A8500 into the NAS while still cabled.** Fill
   `hosts/nas/a8500.nix` (MAC, USB VID/PID from lsusb), deploy the NAS,
   verify association + default route via wan0. PSK file already placed:
   `/var/lib/nas-router/freebox-uplink.env` (root, 600, runbook-placed —
   the NAS stays off the delivered secrets tier).
2. **The move**: unplug /30, NAS to TV corner, HDMI + cable to BE550 LAN
   port + BE550 power. BE550 boots into its old AP-mode config.
3. **Coordinator onto the LAN**: read the BE550's SSID/PSK from its admin
   page (SSH tunnel via NAS), set per-band SSIDs / Smart Connect OFF, mint
   `secrets/wifi-lan.age`, add the 5GHz BSSID pin to `be550-lan` — the
   nas-topology check REFUSES a wifi profile without a bssid pin (mt7925e
   wcid roam hard-lock, see uplink-nas.nix) — deploy coordinator, verify
   end to end.
4. **Cleanup commit** (after soak): drop the /30 addresses, the legacy
   saddr/export entries, the coordinator's nas-fast-lane + installer
   dnsmasq + NAT blocks, the enp191s0 admissions and their asserts.

## Strix Halo protections (unchanged, now asserted)

`mt7925e disable_aspm=1` + sp5100_tco watchdog (modules/strix.nix) + the
single-BSSID rule are asserted in `checks.nas-topology`. The internet path
change does not touch BIOS, ASPM, or watchdog behavior on coordinator or
worker.

## Deferred, deliberately

- **Phase-2 tailnet-direct serving**: give the NAS a tailnet identity and
  retire the coordinator relays. Costs: secrets-tier reversal (declined
  twice before), four flake assertion inversions, re-pointing every phone
  URL. Independent of this rewire; decide separately.
- **NAS reachability tripwire**: none exists (audit 2026-08-20); the NAS
  is now the house router, so a silent-failure alarm is worth building.
- **A8500 new_id shim removal** once the NAS kernel reaches >= 7.2.
- **NFS consumer diet**: drain corpus + music staging hardcode /mnt/nas
  paths (code edits); revisit if wifi-borne NFS annoys.
