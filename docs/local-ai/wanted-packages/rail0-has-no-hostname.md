# rail0 has no hostname, so `ssh worker` takes the 5 GbE wire

**Filed 2026-09-03 from the flashnix trinity staging. Corrected the same night** —
the gap is real, the payoff is 1.9x and not the 8x the link speeds imply.

## The three wires, and which one a name reaches

```
$ for i in enp191s0 rail0 wlp192s0; do cat /sys/class/net/$i/speed; done
enp191s0     5000 Mb/s     10.99.1.1/30
rail0       40000 Mb/s     10.99.0.1/30      (Thunderbolt, /30 = exactly two hosts)
wlp192s0     (wifi)        10.42.0.2/24      (the NAS path)

$ getent hosts worker      -> 10.99.9.2
$ ip route get 10.99.9.2   -> via 10.99.1.2 dev enp191s0
```

`worker` routes over the 5 GbE wire. rail0 is nameless — `worker-rail0`, `worker-rail`
and `rail0-worker` all fail to resolve, and `/etc/hosts` has no rail entry. So any
twin-to-twin tool taking a hostname silently uses the slower wire unless its author knew
to write `10.99.0.2`.

## What the difference is actually worth

Not 8x. Measured with `rsync -a` on one cold 2,136,177,320 B file (staged Aug 30, so not
in page cache):

| path | time | rate |
|---|---|---|
| `10.99.0.2` (rail0) | 2.02 s | **1058 MB/s** |
| `worker` (enp191s0) | 3.81 s | **561 MB/s** |

**1.9x.** 5 GbE was already running near its 625 MB/s theoretical, and rail0 at 1.06 GB/s
is NVMe/CPU-bound far below its 40 Gb line rate. The link-speed numbers overstate the
gap by 4x because neither transfer is limited by the wire.

Worth keeping in proportion: both wired paths are 8-15x the NAS-over-wifi path, which
tops out near 75 MB/s for the whole estate. **Choosing a wired wire at all is the win;
choosing which wired wire is a refinement.** A 156 GB replication is under three minutes
on either.

A second figure that dissolved on re-measurement: single-stream rsync was claimed at
8.5 MB/s and used to argue for parallel buckets on this path. Its author retracted it —
it was arithmetic under NAS contention, not a rail measurement. Single-stream rsync is
not the bottleneck on either wired path, and parallelism belongs against the NAS, not
here.

## The shape of a fix, from the implementation that worked

flashnix's `stage-weights.sh` peer mode now splits the two paths rather than picking one:
the **control** path keeps the hostname, because ssh config and host keys are written
against it, while the **data** path goes over rail0. It derives the peer's rail address
rather than hardcoding it — rail0 is a `/30`, exactly two usable addresses, so the peer's
address is our own with the host bit flipped. That works in both directions with no
per-host constant, and it warns and falls back to the hostname on any node with no rail0.

That is a better answer than a hosts entry: it cannot go stale, and it degrades safely.
A name would still help every *other* tool, which is why this page stays open.

Deliberately not claimed: that all twin-to-twin traffic should use rail0. Control traffic
and small RPCs do not care, and pinning them to a Thunderbolt link that may be down is a
worse default than 5 GbE. The gap is that there is currently no way to *ask* for the rail
except by literal IP.

## Decides what

Wherever the twins' `/etc/hosts` entries or fleet DNS names are declared, plus anything
setting `FN_WORKER_HOST` or an equivalent peer name.
