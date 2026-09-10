# Wired NAS and BE550 in the cupboard

Deployed on 2026-09-10. Freebox configuration and the existing Wi-Fi band
choices are unchanged. The TV connection and USB Wi-Fi intake are retired.

```text
Freebox Ethernet port 3 → BE550 WAN (router mode)
                          BE550 LAN 10.42.0.3
                            ├─ Ethernet → NAS enp1s0, 10.42.0.1
                            └─ thomas-6ghz → coordinator .2, worker .5
```

The NAS remains the normal gateway, DHCP server and AdGuard resolver. Clients
use `.1` for gateway and DNS. The NAS forwards through its single Ethernet NIC
back to BE550 `.3`; source NAT sends replies back through the NAS, and ICMP
redirects are disabled so clients do not learn to bypass it. BE550 routes its
WAN through Freebox. Its LAN address must be static `.3`, and its DHCP server
must be disabled. Keep IPv6 disabled on the primary LAN so it cannot provide an
unfiltered parallel route.

Keep `10.42.0.0/24` and the existing identities: NAS `.1`, coordinator `.2`,
BE550 `.3`, printer `.4`, worker `.5`. The DHCP pool remains `.10`–`.200`.
NAS storage, SSH, discovery, media relays, cache and journal endpoints retain
their addresses and access rules. Ordinary LAN traffic stays on the LAN.

DNS redirection and the existing encrypted-DNS restrictions apply to clients
using NAS routing. Selecting BE550 `.3` directly is an accepted manual bypass;
this arrangement does not enforce filtering against a client choosing another
gateway. Coordinator automates three tiers: NAS gateway/DNS, BE550 gateway with
public DNS, then Freebox Wi-Fi. Its saved primary profile remains NAS-backed.
Fallback restores internet access, not services on an unavailable NAS. Freebox
fallback also loses the direct BE550 LAN path. Other devices keep their normal
NAS dependency unless deliberately configured otherwise.

## Deployment and recovery

The NAS booted the wired configuration after relocation. The BE550 is an Archer
BE550 v1.0, firmware 1.2.4 Build 20260402 rel.18154(4555), in router mode. Its
WAN uses DHCP and upstream DNS from Freebox; the observed WAN lease was
`192.168.1.17`, gateway and DNS `192.168.1.254`. That lease is not a static
address requirement. LAN is `10.42.0.3/24`, DHCP is off and IPv6 is off.

Wireless retains `thomas` on 2.4 GHz and `thomas-6ghz` on 6 GHz. The 5 GHz
radio, Smart Connect, MLO, guest networks and IoT networks are off. Existing
passwords/security and radio tuning are preserved. AP Isolation and device
Access Control are off; Wi-Fi authentication and the router firewall remain.

The coordinator configuration can be activated while it stays on Freebox.
Its boot reconciliation ignores activations after the first five minutes of
uptime. The worker's Ethernet management link and BE550 Wi-Fi provided access
throughout this migration; coordinator Wi-Fi is switched only after setup.

Router backups before and after the mode change and the system deployment
receipt are kept privately under `~/.local/state/nas-wired-cutover/` on the
coordinator. The original NAS generation and private uplink backup are retained
under `/var/lib/nas-wired-cutover` with a GC root for the previous system.
The one migration PR preserves the removed implementation for future recovery.

The saved primary coordinator profile always names NAS `.1`; bypass modifies
only the active route/DNS. Recovery is checked at boot and 04:00, or explicitly
with `systemctl start uplink-rail-revert.service`. Probes select the intended
upstream independently of the currently working default route.

The NAS Ethernet profile keeps its existing ID. Obsolete NAS Freebox Wi-Fi
profiles and `/var/lib/nas-router/freebox-uplink.env` are retired after checking
the wired path; removing a declaration alone does not remove persistent
NetworkManager profiles. Kernel selection is unchanged.

The coordinator's independent SaaS Tailscale emergency path stays enabled.
Preserve NAS Headscale identity, policy and signed laptop updates; overseas
control-plane reachability is a [separate follow-up](overseas-headscale.md).
Rollback means restoring the saved router mode/configuration, wiring and NixOS
generations together. The deleted USB/TV implementation remains in Git history.

AdGuard serves LAN clients directly, preserving their individual query records.
The tailnet listener at `100.64.0.1` is a resolved proxy into AdGuard; queries
through that listener appear as loopback in AdGuard. Tailnet enrollment cannot
prevent the LAN resolver from binding.
