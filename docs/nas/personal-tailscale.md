# NAS personal Tailscale, separate from the laptop fleet

The September 10 decision restores NAS access through Tom's existing Tailscale
account **in addition to**, not instead of, the NAS-hosted Headscale fleet.
Marwan's ASUS and Omar's Dell remain exclusively registered with Headscale.
The coordinator's independent SaaS connection and Freebox Wi-Fi fallback remain.

## Reuse and boundaries

- `33fb9a15` previously shipped NAS SaaS membership and home subnet advertisement.
  Issue [#233](https://github.com/mecattaf/dotfiles/issues/233) records the primary
  NAS / emergency coordinator decision; an internet exit node was a non-goal then.
- `4ba20bfb` verified the existing NAS media relays. `1bec433d` added private
  `.internal` Caddy names. Preserve those old entry points while adding new ones.
- The artifact configuration already uses private custom-domain DNS. The dormant
  Headscale HTTPS block provides the Cloudflare DNS-01 / NixOS ACME pattern.
- The additional SaaS daemon must not share the host daemon's state, network
  namespace, routing table 52, firewall marks or MagicDNS address.
- Host Headscale remains `100.64.0.1`; the existing registrations and signed
  update endpoints remain unchanged. Personal access does not grant the laptop
  fleet media access or bridge the two tailnets.

## Intended endpoints

| Endpoint | Access |
| --- | --- |
| `music.mecattaf.dev` | Personal tailnet only; NAS Navidrome |
| `plex.mecattaf.dev` | Personal tailnet only; NAS Plex |
| NAS personal exit node | Optional, explicitly selected by personal clients |
| Headscale through Funnel, port 8443 | Public control endpoint only; requires protocol and off-LAN validation |
| Fleet offers/cache | Existing private Headscale addresses only |

Private media HTTPS and the prospective public Funnel listener use distinct ports
and backends. Never point Funnel at the private media Caddy listener. Cloudflare
records for private media are DNS-only, pointing at the enrolled personal NAS
address; knowing that address does not grant tailnet access. Do not publish a
private Headscale address as an overseas bootstrap solution.

The desired setup needs no Freebox forwarding, DMZ, bridge mode, DNS changes or
password reset. Funnel's `*.ts.net` name is separate from the private custom
domains; compatibility must be proven before changing any laptop control URL.

## Commissioning gates

1. Evaluate and build the isolated configuration; validate firewall rules before
   deployment. Preserve the deployed NAS generation and an encrypted identity
   snapshot. No NAS reboot is required for adding the service.
2. Enroll **only the new NAS personal instance** through Tom's existing account.
   Inspect and restrict the SaaS policy, approve optional exit-node capability,
   and confirm that the coordinator's emergency permissions remain intact.
   Do not silently delete or revive the old offline NAS account entry.
3. Supply a Cloudflare token limited to `mecattaf.dev`, Zone Read and DNS Edit.
   Deliver it using agenix with the NAS host and existing operator recovery
   recipient only. Never put the coordinator's broad OAuth credentials on NAS.
4. Create the private DNS records and DNS-01 certificates. Verify media through
   the personal tailnet, application authentication, and denial from unrelated
   networks and the Headscale fleet. Preserve socket-activated Navidrome behavior.
5. Test exit routing from an external personal client, including public IPv4,
   DNS and IPv6 fail-closed behavior. Advertising an exit node is not proof that
   any client is using it; do not force all devices through it.
6. Enable only the Headscale Funnel backend. Prove the actual control-protocol
   upgrade, registration/reconnection using disposable identity, then migrate
   fleet preferences with backups and verify original laptop identities.
7. On an unrelated network, prove permitted NAS-to-fleet SSH and fleet-to-NAS
   offers/cache. Then offer the completed kernel update through the existing
   owner-consent UI. A successful LAN test is not overseas validation.
8. Capture both NAS client identities using the updated recovery helper and copy
   ciphertext off the NAS. Retain the previous snapshot; no keys go in Attic.

This document is a commissioning checklist, not a deployment receipt. Record
actual results and remaining operator gates here before declaring completion.
