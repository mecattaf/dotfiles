# Moving ax/k3s volumes and the registry onto the NVMe (2026-09-30)

Tom's ruling (2026-09-30): "moving ax to the NAS ssd where it will NOT make
the nas hdd run constantly is the move - and it always was." This is sweep
`06-SHEET-DOTFILES-NAS.md` row **F2-1, option (b)**: move
`myAxFleet.localPathRoot` and `myAxFleet.registryRoot` from the data pool
(`/mnt/nas`, the HDD — `sda`, WD40EFZZ) to the fast tier (`/mnt/fast`, the
NVMe). Option (a) — tear the ax/k3s workloads down — was the sweep's
**default**; this ruling overrides it.

**What the dotfiles change did NOT do:** move any bytes. `modules/ax-fleet/
interface.nix` now defaults `localPathRoot` to `/mnt/fast/ax-fleet/local-path`
and `registryRoot` to `/mnt/fast/ax-fleet/registry` (also set explicitly in
`hosts/nas/default.nix`'s `myAxFleet` block). `--default-local-storage-path`
only governs *new* PersistentVolumes the `local-path` StorageClass
provisions, and `services.dockerRegistry.storagePath` is read fresh by
`docker-registry.service` on its next start — neither one moves a byte that
already exists under the old root. The three PVCs below, and the registry's
existing blobs, need the manual migration in this runbook, run by hand, with
the cluster's own controllers doing the scaling and binding.

**Why the runbook is not itself the deploy.** `nixos-rebuild switch` and any
cluster mutation are explicitly out of scope for the branch that carries this
document (`nas/ax-volumes-nvme`) — this file is the plan Tom runs by hand
(or supervises an agent running), not something this PR executes. `nix build`
against `.#nixosConfigurations.nas...toplevel` is the only thing verified
here.

## Before you start

- **Check the local-path-provisioner version and PV shape first.** Rancher's
  `local-path-provisioner` has shipped both `hostPath`- and `local`-typed
  PersistentVolumes across its history, and in every version the
  provisioner's `PersistentVolumeSource` is immutable once the PV object
  exists (the API server rejects a patch to `spec.hostPath.path` or
  `spec.local.path` with "field is immutable"). So this runbook always
  **recreates** the PV rather than patching it in place — do not try
  `kubectl patch pv ... spec.local.path` or `spec.hostPath.path` even if it
  looks tempting; it will be rejected, and if a future provisioner version
  ever does allow it, recreate is still safe and portable, so there is no
  reason to special-case the patch path.

  ```
  ssh nas
  sudo kubectl -n kube-system get pods -l app=local-path-provisioner \
    -o jsonpath='{.items[0].spec.containers[0].image}{"\n"}'
  sudo kubectl get pv -o yaml | grep -E 'name:|hostPath:|local:|  path:'
  ```

- **Know the exact current paths before moving anything.** Don't assume the
  directory-naming convention; read it off the live PV objects.

  ```
  sudo kubectl get pv -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.claimRef.namespace}/{.spec.claimRef.name}{"\t"}{.spec.hostPath.path}{.spec.local.path}{"\n"}{end}'
  ```

  Every path printed should currently start with
  `/mnt/nas/services/ax-fleet/local-path/`.

- **110 GB free on the NVMe** per the sweep's spot-check (`df -h /mnt/fast`
  — re-check before starting; the model-archive and eMMC-relief runbooks
  also write to this disk).

- **This is a live cluster with live agent sessions.** Per
  `~/.local/bin/runtime-test` discipline (a different box, but the same
  principle): do not restart k3s, Herdr, or any host's whole service manager
  to "fix" a stuck step. If a step fails, stop, capture `kubectl describe`
  / `journalctl -u k3s -u docker-registry` output, and reassess by hand
  before retrying — do not script a blind retry loop against a live
  cluster's storage.

## 0. Dump ate's Postgres first, before touching anything

Belt-and-suspenders ahead of a StatefulSet PV move: a `pg_dump` that predates
any `rsync` is the fallback if the PV copy goes wrong in a way the `rsync`
verify step (§3) doesn't catch.

```
ssh nas
sudo kubectl -n ate-system get pods -l app=postgres   # find the running pod, e.g. postgres-0
sudo kubectl -n ate-system exec postgres-0 -- \
  sh -c 'pg_dumpall -U postgres' \
  > /mnt/nas/documents/archive/ate-postgres-2026-09-30.sql
ls -la /mnt/nas/documents/archive/ate-postgres-2026-09-30.sql
```

(Use `pg_dumpall` over `pg_dump` unless ate's Postgres is known single-database
— it costs nothing extra and covers a database you didn't think to name. If
the pod only exposes `pg_dump` for a specific db, substitute
`pg_dump -U postgres <dbname>`.) Confirm the file is non-trivial in size
before proceeding — an empty or truncated dump is worse than none, because it
looks like a safety net that isn't there.

## 1. Deploy the dotfiles change

Merge/switch this PR onto the NAS (`nixos-rebuild switch --target-host nas`,
or from the NAS itself) **before** step 2, so that:

- `ax-fleet-dirs.service` creates `/mnt/fast/ax-fleet/local-path` (mode
  `0711`) and `/mnt/fast/ax-fleet/registry` (mode `0750`,
  `docker-registry:docker-registry`) with the right ownership, the same way
  it already creates the old directories — nothing extra to `chown` by hand.
- `docker-registry.service` restarts already reading `storagePath =
  /mnt/fast/ax-fleet/registry`. Its data directory will be **empty** until
  §4 rsyncs into it, so expect pulls to serve nothing (and the periodic
  `ax-fleet-registry-seed.service` to reseed from the store, which is
  harmless and idempotent — `skopeo copy` just re-pushes the seeded images)
  until that rsync lands. Either accept a short gap in `docker pull` service
  from this registry (nothing serves from it but this cluster) or do steps 1
  and 4 back-to-back in the same maintenance window.
- `--default-local-storage-path` now points new PVs at the NVMe. The three
  existing PVs are untouched by the switch (§ "What the dotfiles change did
  NOT do" above) — they still resolve to the old HDD path until §3–4.

## 2. Stop the writers

Scale everything that writes to the three PVCs to zero, in this order (ate's
control plane depends on Postgres, so stop the dependents first):

```
sudo kubectl -n ate-system get all   # confirm the exact controller kind/name for rustfs before scaling it
sudo kubectl -n ate-system scale statefulset/postgres --replicas=0
sudo kubectl -n ate-system scale <rustfs-controller-kind>/<rustfs-controller-name> --replicas=0
sudo kubectl -n ax-system get all    # confirm ax-redis's controller kind/name
sudo kubectl -n ax-system scale <ax-redis-controller-kind>/<ax-redis-controller-name> --replicas=0
sudo kubectl -n ate-system get pods -w   # wait for postgres-0, rustfs's pod(s) to terminate
sudo kubectl -n ax-system get pods -w    # wait for ax-redis's pod to terminate
```

Do not delete the PVCs or PVs yet — that is §4, after the data is copied.

## 3. Copy each PV's directory, NVMe destination, HDD source still intact

For each of the three PVs (use the exact `hostPath`/`local` paths from the
"Before you start" listing — do not guess the directory name):

```
for pv in <postgres-pv-name> <rustfs-pv-name> <ax-redis-pv-name>; do
  old=$(sudo kubectl get pv "$pv" -o jsonpath='{.spec.hostPath.path}{.spec.local.path}')
  new=${old/\/mnt\/nas\/services\/ax-fleet\/local-path/\/mnt\/fast\/ax-fleet\/local-path}
  echo "$pv: $old -> $new"
  sudo install -d -m 0711 "$(dirname "$new")"
  sudo rsync -aHAX --info=progress2 "$old"/ "$new"/
  sudo diff -rq --no-dereference "$old" "$new"   # must print nothing
done
```

`-aHAX` matches the pattern already used by `hosts/nas/nix-on-nvme.nix`'s
runbook for the same reason: preserve hardlinks, ACLs and extended
attributes, and Postgres's data directory in particular cares about file
permissions being exact. Do **not** delete `$old` yet — §6 is the only place
that happens, after verification.

## 4. Recreate PV + PVC bound to the new path

Reclaim policy matters here: if the existing PVs are `Delete` (local-path-
provisioner's default), deleting the PVC deletes the on-disk directory the
provisioner tracks — but by this point that's the **old** HDD directory
we're about to remove anyway in §6, so it is safe to let that happen, as
long as it's the PVC that gets deleted, never a stray `rm` racing the
provisioner's own deleter. Sequence, per PVC:

```
sudo kubectl get pvc -n <ns> <pvc-name> -o yaml > /root/ax-nvme-migration/<pvc-name>.pvc.yaml   # keep the original spec (size, storageClassName, accessModes)
sudo kubectl get pv <pv-name> -o yaml > /root/ax-nvme-migration/<pv-name>.pv.yaml                # keep the original spec (capacity, accessModes, nodeAffinity)

sudo kubectl delete pvc -n <ns> <pvc-name>    # triggers the Delete reclaim on the OLD path; data already copied to NVMe in §3
sudo kubectl delete pv <pv-name>              # if it didn't already disappear with the PVC
```

Then create a **new** PV, same name is fine (the old object is gone), same
`capacity`/`accessModes`/`storageClassName: local-path`/`nodeAffinity`
(matching `nas`) as the saved YAML, but with `hostPath.path` (or
`spec.local.path`, whichever "Before you start" found) rewritten to the
`/mnt/fast/...` path, and pre-bind it to the PVC with `claimRef` so the PVC
you're about to recreate binds to *this* PV and not to a fresh dynamically
provisioned one:

```yaml
apiVersion: v1
kind: PersistentVolume
metadata:
  name: <pv-name>
spec:
  capacity:
    storage: <from saved YAML>
  accessModes: [ReadWriteOnce]
  persistentVolumeReclaimPolicy: Delete
  storageClassName: local-path
  claimRef:
    namespace: <ns>
    name: <pvc-name>
  local:              # or hostPath: {path: ..., type: DirectoryOrCreate} — match what "Before you start" found
    path: /mnt/fast/ax-fleet/local-path/<...>
  nodeAffinity:
    required:
      nodeSelectorTerms:
      - matchExpressions:
        - key: kubernetes.io/hostname
          operator: In
          values: [nas]
```

Apply the PV, then recreate the PVC from the saved YAML (strip
`resourceVersion`, `uid`, `status`) with the same name/namespace/size — it
will bind to the PV above because of `claimRef`, not provision a new empty
one. Confirm:

```
sudo kubectl get pv <pv-name> -o jsonpath='{.status.phase}{"\n"}'     # Bound
sudo kubectl get pvc -n <ns> <pvc-name> -o jsonpath='{.status.phase}{"\n"}'  # Bound
```

## 5. Scale back up, verify

```
sudo kubectl -n ate-system scale statefulset/postgres --replicas=1
sudo kubectl -n ate-system scale <rustfs-controller>/<rustfs-name> --replicas=<original>
sudo kubectl -n ax-system scale <ax-redis-controller>/<ax-redis-name> --replicas=1
sudo kubectl -n ate-system get pods -w
sudo kubectl -n ax-system get pods -w
```

Verify data present, not just "pod Running":

```
sudo kubectl -n ate-system exec postgres-0 -- psql -U postgres -c '\l'   # databases still listed
sudo kubectl -n ate-system exec postgres-0 -- psql -U postgres -Atc 'select count(*) from pg_stat_user_tables'  # sanity, non-zero on a populated db
# rustfs: hit its health/API endpoint and list a known bucket/object
# ax-redis: kubectl exec ... -- redis-cli DBSIZE   (non-zero if it held data)
```

If anything looks wrong, **stop** — do not delete the old HDD directories
(they're still there; §3 never deleted them) and do not restart Herdr, k3s,
or the node to "retry clean." Capture `kubectl describe pod`, `kubectl logs`,
and `journalctl -u k3s` output and reassess.

## 6. Remove the old HDD directories, and the old registry data

Only after §5's verification is solid (give it a day if the workload's data
integrity isn't instantly obvious, e.g. Postgres table row counts that need
comparing to the pre-migration dump from §0):

```
sudo diff -rq --no-dereference /mnt/nas/services/ax-fleet/local-path /mnt/fast/ax-fleet/local-path   # re-confirm, one more time, before deleting
sudo rm -rf /mnt/nas/services/ax-fleet/local-path
```

## 7. The registry: stop, copy, verify, remove old

The registry isn't a PV/PVC — `docker-registry.service` reads
`storagePath` directly, and it already restarted against the new (empty)
path in step 1. Do this in the same maintenance window as step 1, or accept
the registry serving nothing from local storage until this step runs (pulls
that miss fall through to the upstream registry per
`modules/ax-fleet/k3s.nix`'s `registriesYaml` mirror config, so this is a
gap, not an outage, for anything not already cached on a node).

```
sudo systemctl stop docker-registry.service ax-fleet-registry-seed.service
sudo rsync -aHAX --info=progress2 /mnt/nas/services/ax-fleet/registry/ /mnt/fast/ax-fleet/registry/
sudo chown -R docker-registry:docker-registry /mnt/fast/ax-fleet/registry
sudo diff -rq --no-dereference /mnt/nas/services/ax-fleet/registry /mnt/fast/ax-fleet/registry
sudo systemctl start docker-registry.service
sudo systemctl start ax-fleet-registry-seed.service   # re-seeds/verifies; idempotent
curl -fsS http://10.42.0.1:5000/v2/_catalog   # from a host on the LAN leg; confirm the expected repos are listed
```

Once confirmed:

```
sudo rm -rf /mnt/nas/services/ax-fleet/registry
```

## 8. Verify the HDD actually reaches standby

This is the point of the whole exercise (F2). Give it a few hours after
step 6/7 land and the nightly/weekly writers (D22, D21, D23a, snapshots,
scrub) have had a chance to run at least once, then:

```
sudo hdparm -C /dev/disk/by-id/ata-WDC_WD40EFZZ-68CPAN0_WD-WXB2D166SAR7
# want: drive state is:  standby   (most checks, most of the day)

journalctl -u hd-idle --since -24h | tail -50
# hd-idle (hosts/nas/storage.nix F2-4, already deployed) logs spin-down/up events

sudo smartctl -A /dev/disk/by-id/ata-WDC_WD40EFZZ-68CPAN0_WD-WXB2D166SAR7 | grep -i start_stop_count
# F2-6's acceptance bar: over 48h this should rise by about 1-3/day, not
# dozens — a climbing count means something is still waking the disk hourly
# (re-check Paperless/Immich/Plex per the F2 "what writes to it" table in
# the sweep, and F2-2's D-section removals if they haven't landed yet).
```

If `hdparm -C` keeps reading `active/idle` rather than `standby` during quiet
hours, do not chase it by lowering `hd-idle`'s timeout or adding `hdparm -S`
(the sweep already ruled that out — WD Red firmware may ignore it); instead
find the remaining writer the same way this runbook found ax: `iotop`/`blktrace`
on `sda`, or re-read the F2 "what writes to it" table for what's still
un-migrated or un-landed (F2-2, F2-3, F2-7).

## Rollback

At any point before §6/§7's `rm -rf`, rollback is: scale the workload(s)
back to 0, recreate the PV/PVC (or docker-registry storagePath) pointing at
the **old** `/mnt/nas/...` path from the saved YAML, scale back up. The old
directories are the source of truth until deliberately deleted — nothing in
this runbook deletes them earlier than that.

## Loose ends for Tom

- The exact PV names, the `rustfs`/`ax-redis` controller kind (Deployment vs
  StatefulSet) and current replica counts are not recorded in dotfiles — they
  live only in the live cluster. "Before you start" and §2 above read them
  off `kubectl` rather than hardcoding a guess.
- Whether local-path-provisioner on this k3s version uses `local` or
  `hostPath` PVs is likewise unverified here (no cluster access from this
  worktree) — confirm with the "Before you start" command before writing the
  new PV YAML in §4.
