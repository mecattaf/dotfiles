# the NAS mount has no nconnect — but that is not what makes a reader slow

**Filed 2026-09-03 from the flashnix trinity staging. Corrected the same night**,
after the measurement it rested on turned out to have been taken under contention.
Not acted on, and the case for acting is weaker than the first version claimed.

## The fact that is solid

Both twins reach the NAS over wifi — `ip route get 10.42.0.1` returns `dev wlp192s0`
— and the mount carries no `nconnect=`:

```
nas:/ on /mnt/nas type nfs4 (rw,noatime,vers=4.2,rsize=1048576,wsize=1048576,
                             ...,proto=tcp,timeo=100,retrans=3,...)
```

The NAS's only network is a USB wifi adapter (`mt76-usb-rx` / `mt76-tx phy3` are its
busiest kernel threads).

**The estate aggregate is at least 107.7 MB/s**, measured with one lane on each twin:

| | |
|---|---|
| coordinator, pulling GLM rank0 | 40.9 MB/s |
| worker, pulling DeepSeek-V4 | 66.8 MB/s |
| **aggregate** | **107.7 MB/s** |

Earlier readings of "~70 MB/s, and that is the whole fleet" were every one of them
taken while two lanes shared a single twin. There is no 70 MB/s fleet ceiling; that
number was a property of the contention, not of the AP.

## The claim this page originally made, and why it was wrong

It said a single NFS reader is capped near 15 MB/s — a fifth of the link — because one
mount uses one TCP connection, and offered `nconnect=8` as the fix.

The 15.3 MB/s figure came from a stream sweep taken while two other staging jobs were
running. The disproof came from the other twin, same AP, same second:

| | streams | rate |
|---|---|---|
| rank0, coordinator (sharing the box with ~7 other rsync streams) | 1 | 7.1-7.8 MB/s |
| rank1, worker (alone on that box) | 1 | 56-65 MB/s |

**A single NFS stream demonstrably reaches ~65 MB/s on this fleet.** There is no
per-connection ceiling near 15 MB/s to lift.

The real mechanism is contention share: rsync fair-shares by stream, so one logical
stream competing against seven gets roughly an eighth. Parallelising a slow reader works
by *winning back share* from the other readers on the same box, not by lifting a
per-connection cap. That distinction matters, because share-winning is zero-sum between
local jobs while a cap-lift would not be.

The related figure that also collapsed: a "single-stream rsync is 8.5 MB/s" claim was
retracted by its author as arithmetic (34 MB/s ÷ 4 workers under contention) rather than
a measurement.

## What this leaves

`nconnect` may still be worth setting — spreading one client's traffic over several TCP
connections is generally good on a lossy radio, and nothing here argues against it. But
this repo now has **no evidence that it would help**, and the page should not be read as
providing any. Anyone picking this up should measure a single cold reader on an
otherwise-idle fleet first, and only then decide.

The finding that survives intact is about *scheduling*, not mount options. The twins have
independent shares of the AP, so **where** bytes land changes total time. Two jobs on one
twin starved each other to the point where one reached 0 MB/s while the other twin's
identical job ran at 60; moved apart, the same two jobs summed to 107.7 MB/s.

So the operating rule is **not** "serialize the lanes" — that was the wrong lesson drawn
from the contaminated ceiling, and following it would have idled half the fleet. It is
**do not stack two lanes on one twin.** Placement, not scheduling.

That also re-founds the case for crossing the wifi once and replicating over a wired
rail. The reason is not that the AP is scarce; it is that an artifact identical on both
twins should cross the radio once rather than twice. An artifact that is genuinely
different per host — GLM's pre-sharded ranks — has nothing to save and should simply be
pulled to each twin in parallel.

## The measurement lesson, which is the durable part

Three separate throughput figures on this fleet in one night were taken under
uncontrolled contention and each was presented as a property of the link:
15.3 MB/s single-stream, 8.5 MB/s single-stream rsync, and a ~20 MB/s "coordinator link
cap" that turned out to be one competing job — the same host sustained 48 MB/s the
moment that job stopped. Measure with `iflag=direct`, on a quiet fleet, and say what
else was running. A number without its conditions is not a measurement.

## Decides what

Nothing today. If ever acted on: wherever the `/mnt/nas` NFS mount is declared.
