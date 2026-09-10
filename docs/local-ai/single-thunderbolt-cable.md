# Single Thunderbolt cable between the twins

2026-09-10: Tom physically unplugged the TB3 cable, cable B / `rail2`.
The TB5 cable, cable A / `rail0`, is the sole USB4 connection. Leave it in its existing ports; the
interface name and stream provisioner are pinned to those physical controllers.

| Link | Coordinator | Worker | Role |
| --- | --- | --- | --- |
| Cable A / `rail0` | `0000:c5:00.6`, `10.99.0.1/30` | `0000:c4:00.5`, `10.99.0.2/30` | Tensor traffic, RDMA, USB4 streams; fleet identity fallback at metric 50 |
| Ethernet / `enp191s0` | `10.99.1.1/30` | `10.99.1.2/30` | Preferred fleet administration at metric 20 |

The retired link used coordinator `0000:c5:00.5` and worker `0000:c4:00.6`,
with `10.99.2.1/30` and `10.99.2.2/30`. Its `tb-fleet2` profiles, `10-rail2`
udev link, firewall admission, MTU target, reachability tripwire, cable-B option,
and `usb4-stream-bench-cable` command are removed. The main link keeps its
addressing, recovery service, physical pin, and stream identity gates.

USB4 streams still use cable A. Only one stream can be open at a time while
its network interface is up; two provisioned stream groups do not imply two
concurrent streams. A+B aggregation and cable-B benchmarks no longer apply.
[PR #359](https://github.com/mecattaf/dotfiles/pull/359) is the recovery point
for the deleted implementation; use its parent revision to inspect the former
two-cable setup. No disabled copies of the retired code are retained.

## Live cleanup receipt — 2026-09-10

Inspected both live hosts after the unplug. Each had `rail0` and Ethernet up,
with no `rail2`. The coordinator still had the
`tripwire-tb-rail2-reachability.timer` scheduled. Stopped both that timer and its
service. NixOS owns the unit directory in the read-only store, so an ordinary
runtime mask did not override the installed units. The temporary guard is a
`90-cable-retired.conf` drop-in under `/run/systemd/system/<unit>.d/` for each,
with `ConditionPathExists=/sys/class/net/rail2`. A start attempt confirmed both
stay inactive with `ConditionResult=no` while the cable is absent.

Deleted the inactive `tb-fleet2` NetworkManager profile on both hosts by UUID
`42a4a3ba-0d17-3fb7-b2e5-8ea87006d2d3`. No benchmark processes targeting the
retired interface/address were found in command lines or process environments;
a root scan of `/proc/*/fd` found no open `/dev/tbstream*` devices. Neither
host had a `keep-foreign` marker. Each retained only its rail-0 stream service (coordinator
`1-2.1`, worker `0-2.1`). The shared USB4 provisioner belongs to that surviving
cable and remains available.

These runtime changes bridge the interval until deployment. Rebooting the old
closure drops the temporary guard and recreates the old network profile; an
old-configuration switch can also regenerate the profile. The worktree removes
the profile and tripwire declaratively on the next deployment. After that,
remove the two temporary `/run/systemd/system/<unit>.d/90-cable-retired.conf`
files and reload systemd, or let the next reboot clear them.

## Deployment transition

Apply the new configuration to both twins using the normal fleet deployment.
No live deployment is performed by this worktree change.

NixOS `ensureProfiles` leaves removed profiles in `/run` until reboot. After
switching both hosts, either reboot them one at a time or inspect
`nmcli -f NAME,UUID,DEVICE connection show` on each and delete every retired
`tb-fleet2` profile by UUID with `sudo nmcli connection delete uuid <UUID>`.
This also handles an old edited copy persisted under `/etc`. A normal switch
alone does not remove those profiles. Keep `tb-fleet` and `eth-fleet`.

The removed tripwire may leave a historical marker on the coordinator. Once
the new configuration has stopped its timer, clear it with
`sudo rm -f /var/lib/failure-markers/tb-rail2-reachability`.

Run `sudo fleet-postboot-verify` on both twins after the transition. It expects
`rail0` at the physical controller above, its peer reachable over that interface,
and one stream service. Missing `rail2` is expected. Check that `tb-fleet2` no
longer appears in NetworkManager and the rail-2 tripwire timer is gone.

## Validation

Both coordinator and worker NixOS toplevel derivations evaluate successfully.
All evaluated host assertions pass; the retired profiles, link, firewall entry,
MTU target, tripwire, and benchmark package are absent. The two generated
`fleet-postboot-verify` packages build, and running the matching verifier on
each live host passes every check. Both fleet identity routes still prefer
`enp191s0`. Formatting and `git diff --check` pass. This validates the worktree
and the current surviving link; the full host closures have not been built or
switched from this branch.
