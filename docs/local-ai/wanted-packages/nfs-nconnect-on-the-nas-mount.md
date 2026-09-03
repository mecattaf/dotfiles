# the NAS NFS mount has no nconnect, and one stream gets a fifth of the link

**Filed 2026-09-03 from the flashnix trinity staging.** Measured. Not yet acted on.

## What was measured

The NAS is reached over wifi on both twins — `ip route get 10.42.0.1` returns
`dev wlp192s0`. The mount carries no `nconnect=`:

```
nas:/ on /mnt/nas type nfs4 (rw,noatime,vers=4.2,rsize=1048576,wsize=1048576,
                             ...,proto=tcp,timeo=100,retrans=3,...)
```

Read throughput off that mount, `dd iflag=direct`:

| concurrent streams | aggregate |
|---|---|
| 1 | 15.3 MB/s |
| 4 | 64 MB/s |
| 8 | 70 MB/s |

So ~70 MB/s is the ceiling for the whole fleet, and **a single reader gets about a
fifth of it**. The gap is not the radio; it is that one NFS mount uses one TCP
connection, and a single connection cannot fill this link.

By contrast `rail0` (Thunderbolt, 10.99.0.x) measured **1.2 GB/s** coordinator→worker,
roughly 18x the NAS path.

## Why it is worth acting on

Every consumer that reads the Library serially — `library-fetch`, a plain `rsync`, a
single `cp` — is capped near 15 MB/s no matter how idle the rest of the link is. The
flashnix staging lanes worked around it in application code, with parallel `--files-from`
buckets and by crossing the wifi once per artifact and replicating over rail0. That
workaround is correct for them and does nothing for anything else that mounts the NAS.

`nconnect=8` on the mount would hand the same improvement to every reader without any
application changing, since NFS would spread one client's traffic over eight TCP
connections. It is a mount option, so it lands wherever the NAS mount is declared, and
it needs an activation to take effect.

Not claimed: that `nconnect=8` reaches exactly 70 MB/s for a single reader. The 8-stream
figure came from eight independent `dd` processes, which is a different shape from one
process over eight connections. The direction is well established; the number is not.

## Worth checking at the same time

The NAS's only network is a USB wifi adapter (`mt76-usb-rx` / `mt76-tx phy3` are its
busiest kernel threads). Wifi is half-duplex, so a download *into* the NAS competes for
airtime with NFS reads *out* of it — the two are not independent budgets. Any wired path
to the NAS would dominate every tuning option on this page.

## Decides what

Wherever the `/mnt/nas` NFS mount is declared (`x-systemd.automount`, `_netdev`,
`nas-reachable.service` in its requires list). No change made.
