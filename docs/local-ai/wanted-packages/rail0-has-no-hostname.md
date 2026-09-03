# rail0 has no hostname, so `ssh worker` takes the 5 GbE wire and not the 40

**Filed 2026-09-03 from the flashnix trinity staging.** Measured on coordinator.
Not yet acted on.

## The three wires, and which one a name reaches

```
$ for i in enp191s0 rail0 wlp192s0; do cat /sys/class/net/$i/speed; done
enp191s0     5000 Mb/s     10.99.1.1/30
rail0       40000 Mb/s     10.99.0.1/30      (Thunderbolt)
wlp192s0     (wifi)        10.42.0.2/24      (the NAS path)

$ getent hosts worker
10.99.9.2

$ ip route get 10.99.9.2
10.99.9.2 via 10.99.1.2 dev enp191s0 src 10.99.1.1
```

**`worker` routes over the 5 GbE wire.** rail0 is eight times faster and has no name at
all — `worker-rail0`, `worker-rail` and `rail0-worker` all fail to resolve, and
`/etc/hosts` has no rail entry.

So every twin-to-twin tool that takes a hostname — `ssh worker`, `rsync -e ssh
worker:…`, anything reading `FN_WORKER_HOST` — silently uses the slow wire unless its
author knew to hardcode `10.99.0.2`. Nothing warns; it just runs at an eighth of the
available rate, which reads as "the copy is slow" rather than "the copy is on the wrong
cable."

## Why it surfaced

flashnix's `stage-weights.sh:132` replicates an already-staged tree between twins with
`rsync -a --partial --inplace -e ssh "$PEER:$SRC/" "$DEST/"`, where `$PEER` is a
hostname. The whole point of that path is to cross the contended wifi once and then
move the second copy over the fast rail. With `PEER=worker` it never touches the rail.

Measured for scale: rail0 does 1.2 GB/s coordinator→worker; the NAS over wifi tops out
near 70 MB/s **for the whole fleet**, shared.

## What would fix it

A name for each twin's rail address, so the fast path is reachable by the same idiom as
the slow one — `worker-rail0` / `coordinator-rail0`, or a `rail` suffix convention —
declared wherever the hosts entries live. Then tools take a name and the choice of wire
becomes explicit and greppable instead of accidental.

Deliberately not claimed: that every twin-to-twin transfer *should* use rail0. Control
traffic and small RPCs do not care, and pinning them to a Thunderbolt link that may not
be up is a worse default than 5 GbE. The gap is that there is currently no way to ask
for the rail *at all* except by literal IP.

## Decides what

Wherever the twins' `/etc/hosts` entries or the fleet's DNS names are declared, plus any
module that sets `FN_WORKER_HOST` or an equivalent peer name.
