# NAS Headscale operations

The NAS runs its own Headscale control plane at `http://10.42.0.1:8090` and is a
client of that control plane. The coordinator retains independent SaaS Tailscale
as an emergency path; worker has no tailnet membership. Since September 10 the
public control URL is `https://nas-saas.tail8dd1.ts.net:8443`, served by Funnel
through a separate NAS personal-account container. The original NAS client keeps
its LAN URL. The disabled Caddy public option is not the active ingress path.

Headscale state lives in `/var/lib/headscale`. The NAS enrollment unit waits for
the local control socket and verifies saved identity/preferences. Only a strictly
pristine client may receive a short-lived enrollment key. An established client
is never automatically logged out or re-enrolled; a URL mismatch fails closed.
Restarting `tailscaled-autoconnect` rechecks that guard, not a forced enrollment.
Existing laptop control URLs still require deliberate preference migration.

The current NAS tailnet IPv4 identity is `100.64.0.1`. Preserve it and the NAS SSH
and Attic signing identities: the restricted fleet policy and deployed laptop
update clients depend on them. Follow [verified backups](headscale-backup.md)
before identity-affecting maintenance.

The reviewed policy is `hosts/nas/headscale-policy.hujson`, reloaded with
`systemctl reload headscale`. It grants NAS-to-fleet SSH and fleet-to-NAS cache
and signed-offer access only. Advertising `10.42.0.0/24` does not itself grant
clients access: route approval, client settings and ACLs still apply. The NAS
retains subnet-routing capability without granting lent laptops the house LAN.

Headscale publishes DNS settings, not a DNS listener. MagicDNS owns
`hs.mecattaf.internal`; configured split DNS sends `internal` to NAS `.1` when
client settings and policy permit. Global DNS override is disabled. The laptop
fleet does not accept Headscale DNS or subnet routes. LAN AdGuard is separate.

The embedded DERP server is disabled and public relays remain available. This
does not expose the private control endpoint to overseas clients. The current
listener firewall admits port 8090 on the NAS LAN and established tailnet, with
a scoped admission for the isolated Funnel backend. Metrics/debug stay on
loopback; remote TCP gRPC is disabled by the deployed TLS/insecure settings.

For deployed laptop updates and signed publication, see
[Omarchy offers](omarchy-update-center.md). For verified public transport and
the remaining local-console migration/unrelated-network checks on the shipped
laptops, see [overseas Headscale](overseas-headscale.md). No Freebox changes or
replacement fleet identities were required.
