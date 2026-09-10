# NAS Headscale operations

The NAS runs its own Headscale control plane at `http://10.42.0.1:8090` and is a
client of that control plane. The coordinator retains independent SaaS Tailscale
as an emergency path; worker has no tailnet membership. The control URL is
currently LAN-only. Public HTTPS is disabled.

Headscale state lives in `/var/lib/headscale`. The NAS enrollment unit waits for
the local control socket, ensures user `tom`, mints a short-lived runtime key and
joins the configured control URL. It logs out and re-enrolls if that URL changes;
never change it casually during a network move. Restarting
`tailscaled-autoconnect` reruns enrollment with a fresh runtime key.

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
listener firewall admits port 8090 on the NAS LAN and established tailnet.
Metrics and gRPC stay on loopback.

For deployed laptop updates and signed publication, see
[Omarchy offers](omarchy-update-center.md). For the unresolved overseas control
URL and public ingress, see [overseas Headscale](overseas-headscale.md). That
follow-up prioritizes no Freebox changes and does not enable public services or
re-enroll devices as part of the [wired NAS move](router-rewire.md).
