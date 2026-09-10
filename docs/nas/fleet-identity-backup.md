# NAS fleet identity recovery archive

`hosts/nas/fleet-identity-backup.py` is a manual, operator-encrypted supplement to
the existing Headscale snapshots. It does not stop services, deploy configuration,
restore live state or schedule itself. No archive belongs in Git, the Nix store,
an update manifest, or Attic's publicly readable cache—even encrypted.

It captures the existing NAS SSH host/signing identity, Headscale SQLite database
and Noise key, Tailscale persistent state (including supplementary files, excluding
diagnostic logs), Attic `server.db` containing the existing fleet signing key, the
Attic RS256 signing environment file, and the actual Headscale server YAML/policy.
It preserves the identities the installed laptops already trust; it generates no
replacement service key and changes no recipient on those laptops.

When `/var/lib/tailscale-personal` exists, its independent personal-Tailscale
identity is captured too, under its own archive path. It never replaces the
Headscale client's `/var/lib/tailscale`. An incomplete personal state directory
fails capture rather than silently omitting that identity. Diagnostic logs from
both daemons are excluded. Neither daemon's private state belongs in Attic.

## Capture and retain

Run as root on the NAS after putting the reviewed helper outside Git's secret
storage path. The YAML argument must be the file passed to the running Headscale
server, not `/etc/headscale/config.yaml`'s CLI-only stub. Resolve that path from
`headscale.service`'s `ExecStart`. The policy is the reviewed deployed policy.

```sh
sudo python3 /root/fleet-identity-backup.py \
  --headscale-config <actual-server-yaml> \
  --policy <deployed-headscale-policy>
```

The default age recipient is the existing operator-only recipient in `secrets.nix`
(`editors` and the operator vault). If that recipient changes, update/review this
helper's public constant before using it. Do not add laptop keys or the NAS host
key as recipients: losing that machine must not lose the only decryption path.
The helper needs `python3`, `ssh-keygen` and `age` on PATH; no new NixOS service or
rebuild is required. Never pass secret material as an argument.

Plaintext exists only under a temporary root-owned 0700 directory below `/run`.
Files are 0600. SQLite online backup includes committed WAL data while services
continue running; both copied databases pass integrity checks. The helper checks
that Attic contains an active fleet signing identity, SSH private/public halves
match, required signing/state files exist, and identity files remain stable across
the database snapshots. A concurrent rotation fails the capture for retry.

Before encryption it verifies the tar member names, types, modes, ownership, sizes
and SHA-256 hashes, then restores each archived database only into private scratch
and repeats SQLite integrity checks. The NAS destination is
`/mnt/nas/services/fleet-identity-backups`, root:root 0700, on the mounted data disk.
Only a successfully encrypted 0600 `.tar.gz.age` file is published under a unique
name. The JSON receipt reports ciphertext path/hash and whether decryption was
actually tested. No private key or token value is printed. Temporary plaintext is
removed on ordinary success/failure; `/run` is volatile, and abrupt process death
may leave its root-only temporary directory until cleanup or reboot.

Copy the **ciphertext only** to a private coordinator backup directory outside all
repositories, for example `/home/tom/.local/share/fleet-recovery/nas/` (0700, archive
0600). Verify the copied SHA-256 against the NAS receipt. Keep at least two known
good encrypted generations; do not delete earlier copies during commissioning.
The root operator handles the actual transfer and records its exact location/hash.

`/mnt/nas/services` is excluded from existing btrbk and LaCie coverage. The NAS copy
alone is not off-box recovery; the coordinator copy is a second host, but still
not geographically separate. A further private offline/offsite copy remains useful.

## Decryption and restore rehearsal

The admin age private identity is documented in Tom's Password Manager. Known
coordinator age/agenix/sops identity paths were absent during the September 10
read-only inventory; no usable local admin decryption identity has been confirmed.
The coordinator's ordinary SSH key is not a substitute for that admin age key.

When the real admin identity is available in a private file outside Git, supplying
`--verify-identity <private-identity-file>` decrypts the newly encrypted archive into
the same root-only scratch area and checks exact byte equality with the already
verified archive. Decrypted content is never sent to stdout. Without that option,
the receipt honestly reports `decryptionVerified: false`; synthetic-key round-trip
tests do not establish possession of the real operator recovery key.

Restore is a separate, explicit recovery operation. Stop the affected services
before replacing their state, retain displaced state for rollback, and avoid mixing
restored standalone SQLite databases with old WAL/SHM sidecars. Restore the same NAS
SSH and Headscale Noise identities and Tailscale state; never boot two machines with
the same active identity. Recover file ownership/service-managed directories using
the current host configuration (Attic has a DynamicUser directory and bind mount).

This archive preserves Attic's signing identity and metadata, **not its NAR/chunk
storage**. Restoring its database without matching storage does not restore a usable
cache. Preserve/recover that storage separately or carry out a reviewed Attic recovery
that retains the existing signing key and repairs stale metadata before republishing.
It also does not replace per-laptop host-key bundles, owner secrets or the separately
required 2-of-3 owner escrow. Recheck pinned public identities and both laptop update
paths before declaring recovery complete.

Validation: `python3 -m unittest discover -s tests/fleet-identity-backup -v`.
Tests use synthetic SQLite WAL databases and newly generated disposable SSH/age
identities, including a real encrypted/decrypted round-trip when age is installed.

ABSORB ← `hosts/nas/headscale-backup.py` online SQLite capture/verification;
`hosts/nas/attic.nix` signing-key preservation; `secrets.nix` operator-only recovery.

## Verified capture receipt — September 10, 2026

The reviewed helper captured the live identities without stopping services.
Archive: `fleet-identities-2026-09-10T09-28-39Z-ydfmqgb1.tar.gz.age`,
164,531,787 bytes. Identical ciphertext is retained at:

- NAS: `/mnt/nas/services/fleet-identity-backups/`.
- Coordinator: `/home/tom/.local/share/fleet-recovery/nas/`.

Both archive directories are 0700 and files 0600. SHA-256 on both hosts:
`5e373632e666947c98167971f05c0ac12143d25f7d73f4cf69bb15ac4b1be2f3`.
The coordinator also retains a private JSON receipt alongside the ciphertext.
Stable-file, SSH-keypair, SQLite integrity, archive metadata/checksum and isolated
database-restoration checks passed. Encryption used only the existing operator
age recipient. `decryptionVerified` is **false**: the real Password Manager
identity was not retrieved; the eight passing tests use disposable identities.
This is not a full live-service disaster-recovery rehearsal.

The regular Headscale snapshot and isolated verification also succeeded:
`2026-09-10T09-27-48Z-33chgu16`, retaining predecessor
`2026-09-10T07-34-11Z-yve_6v1f`. Its normal two-snapshot retention removed the
older `2026-09-10T07-31-05Z-9jh_suce`; no encrypted identity archive was removed.
No global garbage collection ran. NAS failed system units remained zero.

## Post-public-ingress capture — September 10, 16:09 Paris

After public-control, personal-daemon recovery and off-LAN migration tests, all
disposable registrations/credentials were cleaned up before a fresh live capture.
Archive `fleet-identities-2026-09-10T14-09-31Z-s2jazk9g.tar.gz.age`
(165,185,589 bytes) is retained in the same private NAS and coordinator directories.
Independent SHA-256 checks on both hosts matched:
`cdc7d54526d6eed7064c8242718a313b3e78bf9dd7c20d6e90d072682aa2fb10`.

This capture includes both independent NAS Tailscale identities and the deployed
public Headscale configuration, plus the unchanged SSH/Headscale/Attic identities.
Archive verification and isolated database checks passed. Both ciphertext files
are 0600 under 0700 directories; previous encrypted archives were retained.
The coordinator also holds a private JSON receipt. No service was stopped and
no secret was uploaded to Attic or committed. Real operator-key decryption is
still **unverified**; that requires the separately held operator recovery key.
