# Network services on harness

The image bakes in three containerised services and a small DNS-routing
layer. They start at boot via the system-preset (no manual enable). All run
as **root podman quadlets** under `/usr/share/containers/systemd/`.

| Service | Port(s) | Volumes |
|---|---|---|
| `adguard.service` | 53/tcp+udp, 853/tcp, 784/udp, 3000, 8443, 8844 | `adguard-config`, `adguard-work`, `adguard-logs` |
| `immich-server.service` (+ postgres/redis/ml) | 2283 | `immich-pgdata`, `immich-redis`, `immich-ml-cache`, `immich-upload` |
| `navidrome.service` | 4533 | `navidrome-data`, bind: `/var/mnt/nas/music` |
| `dns-hijack.service` | n/a (nftables) | n/a |

## DNS architecture

```
┌─ desktop apps ─┐                       ┌─ wifi clients ─┐
│ resolved (127.0.0.53) │               │ DHCP option 6 │
└────────┬───────┘                       └────────┬───────┘
         │ DNS=127.0.0.1                          │ → 10.42.0.1
         ▼                                        ▼
              ┌───────────────────────────┐
              │ AdGuard Home (0.0.0.0:53) │
              └─────────────┬─────────────┘
                            ▼ upstream (DoH)
                       1.1.1.1 / 9.9.9.9
```

- `NM dnsmasq-shared` keeps doing DHCP + NAT, but its DNS responder is
  disabled (`port=0`) so AdGuard can bind `:53`. See
  `/etc/NetworkManager/dnsmasq-shared.d/00-adguard.conf`.
- `dns-hijack.service` loads an nftables table that DNAT's any `:53`
  traffic from `10.42.0.0/24` (the BE550 LAN) to `10.42.0.1` — catches
  IoT devices that hardcode `8.8.8.8`. See `/etc/nftables/dns-hijack.nft`.
- Tailscale's per-link DNS for `*.ts.net` (via `100.100.100.100`) wins
  over the global `DNS=127.0.0.1`, so MagicDNS stays functional.

## First-boot runbook

After the first boot of a freshly-installed harness host, do the following
in order. **DNS resolution on the desktop will be limited until the AdGuard
wizard is complete**, so step 1 first.

### 1. AdGuard wizard

Open a browser **on the desktop itself** (DNS isn't needed for loopback):

```
http://127.0.0.1:3000
```

Walk through the wizard:

- **Admin web interface:** leave at `0.0.0.0:80` (this is what the `8844:80`
  PublishPort exposes externally as `:8844`).
- **DNS server:** listen on **`0.0.0.0:53`** (all interfaces). Don't restrict.
- **Username / password:** pick something memorable.
- After submit, the wizard finishes and AdGuard binds `:53`.
- Log in, go to **Settings → DNS settings** and set upstream resolvers
  (suggested: `https://dns.cloudflare.com/dns-query` and
  `https://dns.quad9.net/dns-query` for DoH).

Verify:

```bash
resolvectl query example.com   # should resolve
resolvectl status | grep -A2 "Global"   # should show DNS=127.0.0.1
ss -tlnp | grep ':53\b'   # 0.0.0.0:53 owned by conmon/podman
sudo nft list table inet dns_hijack   # rules present
```

### 2. Immich initial admin

Open `http://localhost:2283`. First-load screen asks you to create the
admin account. After that, log in and:

- **Administration → External Libraries → Add Library**
  - Path inside container: `/mnt/photos`
  - This corresponds to the host bind mount `/var/mnt/nas/photos`.
- Trigger an initial scan.

ML model cache (`immich-ml-cache` volume) starts empty and downloads ~1–2 GB
of models on first face-detection / smart-search run. Expect some delay.

### 3. Navidrome

Open `http://localhost:4533`. First-load screen creates the admin user.
Music library is bind-mounted at `/music` from `/var/mnt/nas/music`. Library
scan runs every hour (`ND_SCANSCHEDULE=1h`); first scan happens at startup.

### 4. BE550 router-side setup

See **[Configuring the BE550 (router-side recovery)](#configuring-the-be550-router-side-recovery)** below.
This is a one-time-per-router setup; if the existing BE550 is already in AP mode
with USB sharing enabled and Secure Sharing off, skip this step.

## Configuring the BE550 (router-side recovery)

Everything below is **router-side** state: it lives in the BE550's own
firmware, not in this image. If the BE550 is factory-reset, replaced, or
swapped for a different model, walk through this checklist to recreate the
config the rest of harness depends on.

The BE550 is a **TP-Link Archer BE550 (BE9300, Wi-Fi 7)**. It's used here
purely as a wifi-to-ethernet bridge + USB NAS — no routing, no DHCP, no DNS
of its own. All those roles belong to the desktop.

### One-time setup (or after a factory reset)

1. **Power on the BE550 standalone first.** Don't plug ethernet to the
   desktop yet.

2. **Connect a phone** to the factory SSID printed on the router's label.
   Open **TP-Link Tether** (or browse to `http://tplinkwifi.net`).

3. **Operation Mode → Access Point.**
   - Tether: Tools (or three-dot menu) → Operation Mode → **Access Point**.
   - Web UI: Advanced → System → Operation Mode → **Access Point Mode**.
   - Confirm. Router reboots.
   - **Critical** — Router mode would create double-NAT and break the entire
     architecture. AP mode makes it a dumb layer-2 bridge.

4. **Wi-Fi.** Keep the factory SSID/password (printed on the bottom of the
   router) so a new image / new device can always join with the label
   credentials. Or set custom — your call.

5. **Plug ethernet** from a BE550 LAN port (any of the `2.5G LAN` ports,
   *not* the WAN port) to the desktop's ethernet jack.

6. **USB storage sharing.**
   - Plug the LaCie 4TB SSD into the BE550 USB 3.0 port (rear, blue).
   - Tether: Advanced → USB → USB Storage Device → enable.
   - Web UI: Advanced → USB Sharing → USB Storage Device.
   - **Disable "Secure Sharing"** under File Sharing — gives guest access,
     which is what `var-mnt-nas.mount` expects. (Alternative: keep Secure
     Sharing and deploy `/etc/cifs.creds` per the comment in the mount unit.)
   - The share will be exposed as `\\<be550-ip>\<partition-label>`. Currently
     that's `\\10.42.0.2\LaCie`.

7. **Power-cycle the BE550 once** after step 6 so it picks up a fresh DHCP
   lease from the desktop's `nm-shared` dnsmasq, which will pin it to
   `10.42.0.2` via `01-be550-pin.conf`.

### Verifying the BE550 is healthy

```bash
# BE550 reachable on the pinned IP
ping -c 2 10.42.0.2

# SMB port open
timeout 2 bash -c "echo > /dev/tcp/10.42.0.2/445" && echo OK

# Drive shows up via mount
sudo systemctl restart var-mnt-nas.automount
ls /var/mnt/nas/

# DHCP pin in effect
ip neigh show 10.42.0.2   # should show MAC 98:03:8e:6b:61:e2
```

### If you replace the BE550 with a different unit

The new BE550 will have a different MAC, so the dnsmasq pin won't match.

```bash
# After plugging in the replacement and powering it up:
ip neigh show dev enp191s0   # find its MAC (the unfamiliar lladdr entry)
```

Then update the MAC in
`mkosi.extra/etc/NetworkManager/dnsmasq-shared.d/01-be550-pin.conf`,
commit, rebuild harness, reboot. The new unit picks up `10.42.0.2`.

### State recap (what lives where)

| Where | What |
|---|---|
| BE550 firmware (router-side) | AP mode, Wi-Fi SSID/password, USB sharing on, Secure Sharing off |
| harness `01-be550-pin.conf` | MAC `98:03:8e:6b:61:e2` → `10.42.0.2` |
| harness `var-mnt-nas.mount` | `What=//10.42.0.2/LaCie`, guest auth |
| harness `00-adguard.conf` | DHCP option 6 → `10.42.0.1` (host gateway = AdGuard) |

## Volume locations (root quadlet storage)

```
/var/lib/containers/storage/volumes/
├── adguard-config/        # AdGuard config + filter lists
├── adguard-work/          # AdGuard runtime state
├── adguard-logs/          # AdGuard log dir (mounted as /var/log/AdGuardHome.log)
├── immich-pgdata/         # photo DB + metadata index
├── immich-redis/          # cache (rebuildable)
├── immich-ml-cache/       # model cache (rebuildable, ~1–2 GB)
├── immich-upload/         # photos uploaded via Immich UI (≠ NAS-mounted library)
└── navidrome-data/        # music library scan index (rebuildable)
```

Backups: `immich-pgdata` and `immich-upload` are the only volumes with data
that doesn't trivially regenerate. Everything else is cache or rebuilds from
the NAS mount.

## Files in this image

```
/usr/share/containers/systemd/      ← system quadlets (image-baked, read-only)
/etc/NetworkManager/dnsmasq-shared.d/00-adguard.conf
/etc/systemd/resolved.conf.d/50-adguard.conf
/etc/nftables/dns-hijack.nft
/usr/lib/systemd/system/dns-hijack.service
/usr/lib/systemd/system-preset/01-harness.preset    ← enables the four services
```

## Troubleshooting

```bash
# Service status
systemctl status adguard.service immich-server.service navidrome.service dns-hijack.service

# AdGuard still in restart loop?
journalctl -u adguard.service -n 50 --no-pager
ss -tlnp | grep ':53\b'   # who else is on 53?

# DNS chain broken?
resolvectl status
resolvectl query example.com   # works = AdGuard responding

# nft hijack inactive?
sudo nft list ruleset | grep -A5 dns_hijack

# Force-rebuild ML cache
podman volume rm immich-ml-cache && systemctl restart immich-ml.service
```
