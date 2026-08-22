# eMMC relief: getting the build/cache plane off the 57G root

**Status:** config landed, runbook NOT yet walked. Steps 2 and 3 move live data
and must be done in order, on the box, before `nixos-rebuild switch`.

## What happened

Found 2026-08-22 ~06:40 during an unrelated "why is the NAS fan loud" check:

```
/dev/mmcblk0p2   57G   56G     0 100% /
```

Zero bytes free on the root filesystem. `update-center.service` was in failed
state and had been failing silently:

```
error: write of 26 bytes: No space left on device
update-center: build FAILED for worker
error: write of 51 bytes: No space left on device
update-center: build FAILED for zenbook-duo
```

This matters more than a normal full disk because this box is the house
router, DNS (AdGuard) and the tailnet subnet router. A root filesystem at 0
bytes on the machine that is also everyone's default gateway is not a
contained failure, and it was found by accident.

## Root cause: `/` is the eMMC, not the M.2

The box has three devices and the config confused two of them:

| device | size | mount | role |
|---|---|---|---|
| `mmcblk0p2` | 57G eMMC | `/` | OS **and `/nix/store`** |
| `nvme0n1p1` | 256G M.2 | `/mnt/fast` | postgres, immich-generated, navidrome, journal |
| `sda` | 3.7T HDD | `/mnt/nas` | bulk data |

`hosts/nas/attic.nix` states its state "lives at /var/lib/atticd on the NAS
root NVMe" and bounds cache retention "against the 256GB M.2 it now shares
with the OS". Both sentences describe a machine where root is the M.2. Root is
the eMMC. The M.2 is `/mnt/fast` and was **17% used with 186G free** while the
eMMC sat at 100%.

Consequences, all on the smallest and slowest disk in the box:

- **18G** of atticd state (the fleet-wide binary cache — an *accumulating*
  artifact by design)
- the nix store that `update-center.nix` fills nightly with three host closures
- every build's transient scratch

This is the **second** time this eMMC has filled. The first was the initial
update-center run with model-weight FODs, which is why the whole weight plane
was moved out of nix (see `hosts/nas/models.nix`). Twice is a pattern.

## Immediate mitigation (already done, 2026-08-22 06:56)

Plain `nix-store --gc` — **not** `-d`, per the standing rule in
`modules/gc-retention.nix`:

```
100% (0 bytes)  →  66% (19G free)
```

All three system generations (36, 37, 38) survived; rollback depth intact.
23,350 dead store paths were collected. This bought headroom but fixed
nothing structural — hence the rest of this document.

## The fix

**`hosts/nas/attic.nix`** — bind-mount atticd's state onto the NVMe. A bind
mount rather than a custom storage path, so the module's hard-won DynamicUser
shape is untouched: `/var/lib/atticd` stays the systemd-managed symlink into
`/var/lib/private/atticd`, only the backing disk changes.

Guarded with `RequiresMountsFor`, because `/mnt/fast` is `nofail` and a silent
missing mount would let `StateDirectory` create an empty state dir — which
means **a brand new signing key** and the whole fleet silently building from
source. That is the header's "one law" reached by mounting instead of by `rm`.
The guard turns it into a service that refuses to start.

**`hosts/nas/nix-builds.nix`** (new) — build scratch to `/mnt/fast/nix-build`,
plus `min-free`/`max-free` so nix collects garbage mid-build instead of running
the disk to zero and dying with ENOSPC. This is the setting that would have
prevented the incident outright.

`/nix` itself deliberately stays on the eMMC: the store must be present for the
box to boot, `/mnt/fast` is a budget NVMe mounted `nofail` because it is treated
as expendable, and making the house router unbootable on that disk's failure is
a worse trade than a tight eMMC.

**`hosts/nas/media.nix`** — Plex `dataDir` to `/mnt/fast/plex`. Unrelated to the
eMMC (it was on the HDD), same principle: 683M of chatty, rebuildable SQLite was
keeping the 5400rpm spindle busy all day. `lacie-mirror.nix` already excluded it
from cold storage as "regenerable by a rescan", which is precisely the argument
for the expendable fast tier.

## Runbook

### 1. Confirm headroom

```bash
df -h / /mnt/fast
```

Root should have several GB free (post-GC) and `/mnt/fast` ~186G. If root is
still at 0, run `nix-store --gc` first — **never** `nix-collect-garbage -d`.

### 2. Move atticd state to the NVMe

The signing key is in `server.db`. Move it; never recreate it.

```bash
sudo systemctl stop atticd
sudo mv /var/lib/private/atticd /mnt/fast/atticd
sudo ls -la /mnt/fast/atticd/server.db     # must exist, ~263M
```

The bind mount has no tmpfiles rule on purpose: if this move is skipped the
mount fails and atticd stays down, rather than starting with a fresh key.

### 3. Move the Plex library to the NVMe

```bash
sudo systemctl stop plex
sudo mv "/mnt/nas/services/plex" /mnt/fast/plex
sudo chown -R tom:users /mnt/fast/plex
```

### 4. Switch

```bash
sudo nixos-rebuild switch --flake ~/mecattaf/dotfiles#nas
```

### 5. Verify

```bash
findmnt /var/lib/private/atticd          # bind onto /mnt/fast/atticd
systemctl is-active atticd plex
df -h / /mnt/fast
```

Signing key intact — this must print the key `modules/common.nix` trusts
(`fleet:igImm/3XfdWs2g7L0j94HKcCh9ndv1WtJ5fVK6Svwz4=`), not a new one:

```bash
curl -s http://nas:8080/fleet/nix-cache-info
nix store info --store http://nas:8080/fleet
```

Then confirm a device still substitutes rather than building from source, and
that the nightly build recovers:

```bash
sudo systemctl start update-center && journalctl -u update-center -f
```

## Left undone

- `.previous-versions` on the LaCie is **502G** of parked deletions. The
  cold-storage doc says to prune by hand; nobody has. That is most of the
  drive's remaining headroom.
- `min-free`/`max-free` is scoped to this host. It is good hygiene fleet-wide
  and `modules/gc-retention.nix` is the natural home, but that changes every
  machine's behaviour and was left for a separate decision.
- The `models` leg of the cold-storage dump (652G, never yet copied to the
  LaCie) was deliberately skipped on 2026-08-22 — see the mirror's own log.
