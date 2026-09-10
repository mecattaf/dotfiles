# Overseas Headscale follow-up

The cupboard move preserves the existing Headscale control plane and identities.
It does not establish overseas access and does not change Freebox configuration.
Public ingress is a separate follow-up, not a blocker for the wired migration.

## State that must survive

- Headscale listens at `http://10.42.0.1:8090`; the public HTTPS option is off.
  A successful LAN connection does not demonstrate off-LAN control access.
- NAS Headscale IPv4 identity is `100.64.0.1`. The restrictive ACL, signed-offer
  listener and laptop distribution endpoints depend on that address. Preserve
  `/var/lib/headscale`, NAS tailscaled state, the NAS SSH host key used to sign
  offers, and the Attic signing identity. Do not re-enroll or rebuild identities
  as a network-cleanup step. Use the [verified backup workflow](headscale-backup.md).
- The deployed laptops already consume signed updates. The NAS offers manifest
  and signature at `100.64.0.1:8091` and cache at `100.64.0.1:8080`; clients
  verify the pinned NAS signing key and cache signatures. Publication and owner
  installation remain separate actions. See the [deployment receipts and update
  workflow](omarchy-update-center.md).
- `headscale-policy.hujson` is deny-by-default: NAS may SSH into `tag:fleet`,
  and fleet devices may fetch NAS offers/cache. It does not grant fleet devices
  the house subnet, NAS SSH or each other's services. Keep this policy intact.
- The coordinator remains on independent SaaS Tailscale with Freebox fallback.
  NAS and laptops do not silently migrate to that separate control plane.

## What still needs design and verification

Public DERP relays do not publish the private Headscale control URL. Existing
peer connections or a successful LAN update cannot establish that laptops can
register, reconnect or obtain updated network information from overseas.

Prioritize an ingress design requiring no Freebox changes. That likely requires
an outbound connection from home to a public ingress host; select and test the
transport in the follow-up. Do not assume Cloudflare proxy or Tunnel supports
Headscale's control-protocol upgrade. A proposed ingress must be tested against
the actual deployed Headscale/client versions before choosing it.

Define the stable public control URL, TLS/certificate ownership, protocol
forwarding and failure recovery before enabling the dormant public endpoint.
Changing the control URL requires a planned migration of already-deployed
clients; the existing NAS enrollment unit re-enrolls on a URL change. Preserve
its identity and pinned distribution addresses deliberately throughout that work.

Acceptance must use an external network/hotspot: fresh registration or planned
re-authentication, reconnect after restart, NAS-to-laptop administrative SSH,
manifest signature verification, cache retrieval and restrictive ACL negatives.
Record which tests have actually passed; do not infer overseas readiness from
LAN deployment or existing tunnel continuity.

## Preserve these remaining operational tasks

- Select and validate a public endpoint such as `headscale.mecattaf.dev` before
  migrating clients. Standard HTTPS 443 is the intended candidate to evaluate;
  the dormant 8443 value is not an instruction to change the Freebox.
- Choose one certificate owner. Existing staged Caddy uses NixOS ACME/lego
  DNS validation; credentials belong in the NAS agenix flow, never the store.
- Verify public DNS/HTTPS before any fleet tunnel exists, including the NAS's
  own connection. Avoid permanent private-IP overrides on roaming laptops.
- Already-enrolled laptop daemons need preference migration, not merely an
  enrollment option change. Review the NAS's logout/re-enroll logic before
  changing its URL; do not blindly delete state or lose `100.64.0.1`.
- The prior handoff reported encrypted identity archives on NAS and coordinator,
  but operator recovery-key decryption was not yet proven. Verify recovery,
  retain an offsite/offline copy, and test isolated restoration without duplicate
  live nodes. Cache data recovery is separate from signing-key recovery.
- Keep public relay-map fallback initially; no additional DERP service or home
  UDP forwarding is required by this migration. Measure remote throughput later.
- Test each laptop off-LAN: authenticated NAS administration, denied lateral
  access, signed offer decline/accept, exact target installation, reconnect and
  suspend/resume. Existing LAN installation receipts are not these tests.
- Complete certificate/endpoint, disk and backup monitoring; document private
  coordinator-assisted recovery. NAS downtime may interrupt management/updates,
  while ordinary laptop use remains independent.
