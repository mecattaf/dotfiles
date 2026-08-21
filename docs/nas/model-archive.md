# Retiring and restoring a local model

How to take a model out of service without destroying its weights, and how to
bring it back. Refs [#130](https://github.com/mecattaf/dotfiles/issues/130)
workstream 4.

## The problem, stated precisely

There is no models directory on this fleet. `lib/local-models.nix` is a
declarative catalog: each artifact carries an `hfUrl`, a `revision`, and per-file
`path` / `bytes` / `oid` / `hash`. `lib/model-store.nix` turns every file into a
fixed-output `pkgs.fetchurl` derivation and assembles them with `linkFarm`.
**The weights live in `/nix/store`.** `modules/local-models.nix` materialises
only the artifacts named by `services.local-models.allow` for the current host.

So "retiring" a model means dropping it from `allow`. Its store paths become
unreferenced — and `modules/common.nix` enables `nix.gc` weekly with
`--delete-older-than 14d`.

> **Retiring a model silently deletes the bytes about two weeks later.**

That delay is the entire window. Everything below exists to use it.

The good news is that a fixed-output derivation is self-verifying: a restored
model is byte-identical **by construction**, or it does not restore at all. That
is why no bespoke manifest format is needed here — the catalog entry *is* the
manifest.

## Where the archive lives

`/mnt/nas/models/weights/<artifact-id>/`, on the NAS, provisioned by
`hosts/nas/archive.nix` behind `myNas.archive.enable`. Read that file's header
before the first use: `archive` must be its own Btrfs subvolume with
`compression=none` (GGUF weights are already quantised and do not compress), and
the gate only turns on after the subvolume exists.

From the coordinator it is a plain path under the NFS mount:
`/mnt/nas/models/weights`.

**It is not in the LaCie disaster mirror.** `hosts/nas/lacie-mirror.nix` mirrors
`photos music documents videos` and nothing else. The reasoning, which is a
budget decision and not an oversight: these weights are re-downloadable from
HuggingFace, and the LaCie is a 4 TB drive that also has to hold photos, video
and backups. This archive is insurance against `nix-gc`, not against HuggingFace.

If you are ever archiving a model *specifically* because you think the repo may
disappear or the revision may be rewritten — which does happen — then for that
model the calculus is different and it belongs in the mirror. Say so at retire
time, add `archive` to the `for tree in ...` loop in `lacie-mirror.nix`, and
accept that something else gives up space on the LaCie.

## Retire

Do this **before** the next GC, not after. There is no recovery step after.

1. **Flip the catalog status.** In `lib/local-models.nix`, set the deployment's
   `status = "retired"`. The enum already has that value (alongside `canonical`,
   `candidate`, `experimental`, `negative`) and, until now, nothing has used it.
   Leave the artifact's `hash` / `hfUrl` / `revision` / `oid` fields exactly as
   they are — those are what make the restore reproducible.

2. **Find the store paths while they still exist.** On the host that
   materialised the model (normally the coordinator). There are two cases,
   because `modules/local-models.nix` surfaces the two option lists
   differently:

   - Anything in `services.local-models.artifacts` has an `/etc` symlink
     straight to its linkFarm directory:

     ```sh
     ls -l /etc/local-models/artifacts/<artifact-id>/
     readlink -f /etc/local-models/artifacts/<artifact-id>/*
     ```

     (Snapshot-style artifacts also appear under
     `/etc/local-models/snapshots/<localName>`.)

   - Anything reached only through a `services.local-models.allow` deployment
     has no `/etc` entry, but its resolved absolute store path is written into
     the rendered llama-swap config:

     ```sh
     conf=$(systemctl cat llama-swap | grep -o '/nix/store/[^ ]*\.yaml' | head -1)
     grep -o '/nix/store/[^ "]*' "$conf" | sort -u
     ```

   Either way you want the real `/nix/store/...` files, not the farm symlinks.
   `/etc/local-models/catalog.json` is the catalog itself (hashes, `hfUrl`,
   `revision`, per-file `path`) and is what you cross-check against in step 6 —
   it contains no store paths.

3. **Copy the bytes to the archive**, laid out under the catalog's `path` values
   so the tree mirrors what the catalog describes:

   ```sh
   mkdir -p /mnt/nas/models/weights/<artifact-id>
   cp -L --no-preserve=mode /nix/store/...-<file> \
      /mnt/nas/models/weights/<artifact-id>/<catalog path>
   ```

   `-L` because you are copying through symlinks; `--no-preserve=mode` because
   store files are read-only and you want a normal file in the archive.

4. **Copy the catalog entry alongside it as the manifest.** The entry *is* the
   manifest — it carries the hash that makes step 3 of the restore verifiable.

   ```sh
   $EDITOR /mnt/nas/models/weights/<artifact-id>/catalog-entry.nix
   ```

   Paste the artifact's block from `lib/local-models.nix` verbatim.

5. **Record the date.** Append one line to
   `/mnt/nas/models/weights/<artifact-id>/ARCHIVED`:

   ```
   2026-08-03  retired from services.local-models.allow on coordinator; superseded by <what>
   ```

   Say *why* it was retired. In two years that sentence is the only thing that
   will tell you whether restoring it is worth the disk.

6. **Verify before you let GC run.** Compare against the catalog hash — if this
   does not match, the archive is worthless and you still have ~14 days to
   notice:

   ```sh
   nix hash file --type sha256 --base32 /mnt/nas/models/weights/<artifact-id>/<file>
   ```

7. Only now drop the artifact from `services.local-models.allow` and deploy.

## Restore

Because every artifact is a fixed-output derivation, re-adding the bytes
reproduces the **exact same store path** the catalog expects. Nothing needs to be
re-downloaded and nothing needs to be re-hashed.

1. Flip `status` back from `"retired"` and re-add the artifact to
   `services.local-models.allow` for the host that needs it.

2. Add the archived file back to the store under its fixed hash:

   ```sh
   nix-store --add-fixed sha256 /mnt/nas/models/weights/<artifact-id>/<file>
   ```

   This prints the store path. It must equal the path the catalog's `hash`
   implies; if it does not, the archived file is not the file the catalog
   describes and you should stop rather than force it.

   Repeat for each file in the artifact.

3. Deploy. The `fetchurl` derivations are now already satisfied from the local
   store, so the build does not touch HuggingFace at all — which is the point,
   and is what makes this work even if the upstream repo has since been pulled
   or its revision rewritten.

### Restoring several files at once

For a multi-file artifact, a loop over the archive directory is fine:

```sh
find /mnt/nas/models/weights/<artifact-id> -type f ! -name 'catalog-entry.nix' ! -name 'ARCHIVED' \
  -exec nix-store --add-fixed sha256 {} \;
```

An alternative worth knowing about, though it has not been needed yet: point Nix
at the archive as a `file://` substituter. That is more machinery than
`--add-fixed` for the handful of files a retire actually involves, so it stays
unbuilt until there is a reason.

## What this deliberately does not do

There is **no automation** — no timer, no hook on GC, no watcher. A retire is an
occasional, considered decision about tens of gigabytes, and a job that copied
weights around on a guess would be worse than the `cp` above. The module in
`hosts/nas/archive.nix` provides the directory and its filesystem properties;
this page provides the procedure. That is the whole of workstream 4.

## Related

- `hosts/nas/archive.nix` — the subvolume, its gate, and its NFS export
- `lib/local-models.nix` — the catalog, including the `status` enum
- `lib/model-store.nix` / `modules/local-models.nix` — how catalog entries
  become store paths
- `hosts/nas/lacie-mirror.nix` — the quarterly cold mirror this tree is
  excluded from
