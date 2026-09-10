# Public Headscale and remaining laptop handover

## Current state — September 10, 2026

The public control endpoint is **`https://nas-saas.tail8dd1.ts.net:8443`**.
It reaches the existing NAS Headscale through an outbound Tailscale Funnel;
no Freebox/BE550 forwarding, paid VPS or Cloudflare token is required.
The separate `nas-saas` personal-account node supplies ingress only. ASUS and
Dell remain on private Headscale, not the personal Tailscale account.

Headscale still listens privately at `10.42.0.1:8090`. Its own NAS client keeps
that LAN control URL and its existing node `1`, `100.64.0.1`. The dedicated
public Caddy option is off; this does not mean the Funnel endpoint is off.
AdGuard keeps its existing DNS listener. Funnel exposes only the Headscale
backend, never media, SSH, update offers/cache or metrics.

The Linux 7.2.4 release `bc866db` is **built, verified and published for both
laptops**, with the ASUS-only VMD patch included. All 3,273 cache paths passed
signature and availability checks through public Headscale with LAN access
blocked; six complete new boot payloads were downloaded and hash-verified.
There is no remaining NAS build or publication step before the onsite visit.
The one-time laptop connection step below is still required. Exact receipts and
bounded retention are in [omarchy-update-center.md](omarchy-update-center.md).

Public DNS was first observed working at 15:49 Paris after earlier negative
answers. Exact Tailscale 1.98.9 disposable clients subsequently proved:

- LAN-to-public control migration and daemon restart with the same full private
  configuration, machine/node keys, Headscale node ID/IP and other preferences.
- Pristine registration directly through public HTTPS and reconnection after
  restart, confirmed by fresh server timestamps and actual public TCP sockets.
- Verification of the existing signed update manifest and retrieval of both
  laptop cache records over the private Headscale data path.
- Public TLS health HTTP 200 and administrative API HTTP 401 for missing and
  invalid credentials. TLS certificate verification remained enabled.

These are genuine public-internet transport tests from the coordinator, **not
an unrelated-network test on either owner's laptop**. Initial disposable nodes
and credentials were removed without changing real nodes `1`, `2` or `4`.
Detailed deployment and test receipts are in [personal-tailscale.md](personal-tailscale.md).

## Next: local access to the laptops

Both laptops left home before their daemon preferences could be migrated.
Their old `http://10.42.0.1:8090` control URL cannot bootstrap from friends'
Wi-Fi. Merely changing the source configuration or seeing an old peer online
does not repair those saved preferences.

Use the reviewed operator tool in `omarchy-fleet`:
`docs/fleet-endpoint-migration.md`, `scripts/fleet-endpoint-migrate.py` and
`scripts/fleet-endpoint-launch.sh`. Follow its preflight and recovery gates;
run independently of the SSH connection it may interrupt. Never log out,
force re-authentication, delete state or mint replacement laptop identities.

For each laptop, record the original identity, migrate the existing **fleet**
daemon (not the logged-out personal daemon), restart that daemon and prove a
fresh public-control connection. Preserve Dell node `2` / `100.64.0.2` and ASUS
node `4` / `100.64.0.4`; keep DNS and subnet-route acceptance disabled.

The September 10 operator instruction is to finish both builds, verify their
artifacts, publish the signed update and prove public-Headscale cache downloads
before the onsite visit. Publication does not migrate or install either laptop.
Then, from the unrelated Wi-Fi, verify NAS-to-laptop SSH, signed offers/cache,
denied lateral/household access and reconnect after suspend/resume. Once those
checks pass, accept the already-published update through the laptop's Nix icon.
No forced update or reboot is part of endpoint migration. Installing a new kernel
requires a later reboot to run it; app-only changes should not request a reboot.
ASUS boot reliability remains unproven until the patched kernel is installed
and actual boot/display behavior is checked.

## Recovery and independent follow-ups

- Preserve `/var/lib/headscale`, the original `/var/lib/tailscale`, independent
  `/var/lib/tailscale-personal`, NAS SSH/signing and Attic identities. See the
  [Headscale snapshot](headscale-backup.md) and [encrypted identity archive](fleet-identity-backup.md)
  procedures. Keys do not belong in Attic's package cache.
- Encrypted archives are held privately on NAS and coordinator. Real operator-key
  decryption and a full service-restoration rehearsal still require the operator
  recovery identity; database-only scratch restoration is not that proof.
- The existing restrictive ACL remains: NAS may SSH to fleet; fleet may fetch
  NAS offers/cache on ports 8091/8080. No household or laptop-to-laptop access.
- Keep the coordinator's independent SaaS connection and Freebox Wi-Fi fallback.
  NAS downtime interrupts management/updates, not ordinary laptop use.
- The personal ingress node currently reports key expiry on March 9, 2027.
  Disable expiry for that exact unattended node in the personal account, or plan
  renewal before then. No account-wide expiry policy was changed here.
- Private `music.mecattaf.dev` / `plex.mecattaf.dev` DNS-01 HTTPS and off-LAN
  personal exit-node testing are separate tasks. Their missing zone-scoped
  Cloudflare credential does not block this `*.ts.net` fleet endpoint.
