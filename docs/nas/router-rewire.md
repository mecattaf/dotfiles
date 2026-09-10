# Wired NAS and BE550 in the cupboard

This is the deployment target. The PR prepares configuration; merge does not
activate it. Freebox configuration and the existing Wi-Fi band choices stay as
configured. The TV connection and USB Wi-Fi intake are retired.

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

## Cutover

1. Build all affected configurations and run the topology/fallback checks. Copy
   the NAS closure and install it for **next boot only**. Keep the running NAS
   Wi-Fi uplink and services intact. Keep the coordinator closure ready locally;
   activate it after reconnecting following the move.
2. Hand the browser agent the BE550 pass: record/export existing settings,
   select router mode, static LAN `.3/24`, WAN Dynamic IP, DHCP off, primary-LAN
   IPv6 off, and preserve radio bands/SSIDs/security. Freebox stays untouched.
   Mode changes can briefly reboot Wi-Fi; the NAS still supplies the current
   internet path until it is shut down.
3. Tom switches the coordinator to Freebox Wi-Fi and confirms this agent is
   reachable. Shut down the NAS cleanly before removing power, move both boxes,
   retire the USB Wi-Fi adapter and TV cable, then wire Freebox port 3 → BE550
   WAN and NAS Ethernet → BE550 LAN. Power up; the NAS boots its staged system.
4. Tom returns the coordinator to `thomas-6ghz`. Activate its prepared closure
   and finish verification: NAS route `.3`, client gateway/DNS `.1`, AdGuard
   filtering and internal names, NFS/SSH/media/cache/Headscale, and coordinator
   NAS → direct BE550 → Freebox fallback. Return to Freebox if troubleshooting
   needs independent internet. Hardware-only checks remain coverage/airflow.

The saved primary coordinator profile always names NAS `.1`; bypass modifies
only the active route/DNS. Recovery is checked at boot and 04:00, or explicitly
with `systemctl start uplink-rail-revert.service`. Probes select the intended
upstream independently of the currently working default route.

NetworkManager keeps old profiles after their declarations disappear. Retain
the existing NAS Ethernet profile ID during cutover; inspect and retire the
obsolete NAS Freebox Wi-Fi profile and `/var/lib/nas-router/freebox-uplink.env`
after the wired path is proven. Unplugging the adapter does not delete them.
Keep the existing kernel selection during this move; reconsider it separately.

The coordinator's independent SaaS Tailscale emergency path stays enabled.
Preserve NAS Headscale identity, policy and signed laptop updates; overseas
control-plane reachability is a [separate follow-up](overseas-headscale.md).
Rollback means restoring the saved router mode/configuration, wiring and NixOS
generations together. The deleted USB/TV implementation remains in Git history.

AdGuard serves LAN clients directly, preserving their individual query records.
The tailnet listener at `100.64.0.1` is a resolved proxy into AdGuard; queries
through that listener appear as loopback in AdGuard. Tailnet enrollment cannot
prevent the LAN resolver from binding.
