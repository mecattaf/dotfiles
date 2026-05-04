# Network services on harness

The image bakes in three containerised services and a small DNS-routing
layer. They start at boot via the system-preset (no manual enable). All run
as **root podman quadlets** under `/usr/share/containers/systemd/`.

| Service | Port(s) | Volumes |
|---|---|---|
| `adguard.service` | 53/tcp+udp, 853/tcp, 784/udp, 3000, 8443, 8844 | `adguard-config`, `adguard-work`, `adguard-logs` |
| `immich-server.service` (+ postgres/redis/ml) | 2283 | `immich-pgdata`, `immich-redis`, `immich-ml-cache`, `immich-upload` |
| `navidrome.service` | 4533 | `navidrome-data`, bind: `/mnt/nas/music` |
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
  - This corresponds to the host bind mount `/mnt/nas/photos`.
- Trigger an initial scan.

ML model cache (`immich-ml-cache` volume) starts empty and downloads ~1–2 GB
of models on first face-detection / smart-search run. Expect some delay.

### 3. Navidrome

Open `http://localhost:4533`. First-load screen creates the admin user.
Music library is bind-mounted at `/music` from `/mnt/nas/music`. Library
scan runs every hour (`ND_SCANSCHEDULE=1h`); first scan happens at startup.

### 4. BE550 (TP-Link Archer) AP setup

Done once per router, not per host. Use the **TP-Link Tether** app on a phone
or `http://tplinkwifi.net` from a phone connected to the BE550's default SSID:

- Operation mode: **Access Point** (NOT Router — avoids double-NAT).
- SSID / password: keep factory or set your own.
- Save → reboot.

After reboot, the BE550 requests DHCP from harness's `nm-shared` dnsmasq
and lands somewhere in `10.42.0.x`. Verify with `ip neigh show dev enp191s0`
(interface name varies by hardware).

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
