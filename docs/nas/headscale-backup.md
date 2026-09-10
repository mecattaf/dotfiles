# Headscale identity backup and recovery

`myNas.headscale.backup.enable` adds a weekly Sunday 08:30 backup and a manual
service. This copies the control plane from the NAS root disk to its separate
data disk. It is **not an offsite backup** and does not protect against loss of
the entire NAS or both disks.

```sh
sudo systemctl start headscale-backup
sudo journalctl -u headscale-backup -n 50
sudo headscale-backup-verify /mnt/nas/services/headscale-backups/current
```

The service refuses to run unless `/mnt/nas` is actually mounted. It creates
`/mnt/nas/services/headscale-backups` as root:root 0700 beneath the existing
root:root 0711 `services` parent. Backup files are 0600. The `current` and
`previous` symlinks name the only two retained successful snapshots. A failed
backup or failed restore check leaves the last good snapshot available. Nothing
in this service copies private keys into a Nix derivation or a public directory.

Each snapshot contains:

- `db.sqlite`: the SQLite online-backup API captures committed WAL data while
  Headscale runs. No naive copy of the live database is used.
- `noise_private.key`: the existing Headscale server identity, checked for a
  concurrent key change during the database snapshot.
- `config.yaml` and `policy.hujson`: actual server configuration and policy
  reference copies. The module uses `services.headscale.configFile`, the YAML
  passed to the server in its systemd command; `/etc/headscale/config.yaml` is
  only a CLI socket stub and is not a recoverable server configuration.
- `manifest.json`: hashes for all four files.

Publication follows a successful SQLite integrity check, checksum verification,
and restoration into a temporary database followed by another integrity check.
`headscale-backup-verify` repeats those checks without touching the live database.
It does not start a second Headscale instance or contact enrolled devices.

`myNas.headscale.backup.schedule.enable = false` disables the clock but keeps
manual backup and verification available. The timer does not catch up after a
missed run. Check backup age before sending a device overseas and after enrollment
or a policy change; run the manual service after those operations.

## Restoring the control plane

Restoration is deliberately an operator procedure, not a scheduled command.
Use a LAN or console connection and the independent coordinator emergency rail.
Keep the public name and NAS host identity consistent with the enrolled fleet.

1. Select `current` or `previous` and run `headscale-backup-verify` on it. Record
   the resolved snapshot path so the choice cannot change during recovery.
2. Stop `headscale-backup.timer`, ensure its service is idle, and stop
   `headscale.service`. Do not replace a live SQLite database or mix its old
   `db.sqlite-wal` / `db.sqlite-shm` files with a restored main database.
3. Move the entire existing `/var/lib/headscale` directory to a uniquely named
   recovery directory on the same filesystem. Preserve it for rollback, including
   its database, WAL, shared-memory sidecar and Noise key.
4. Create a new `/var/lib/headscale` owned by `headscale:headscale`, mode 0700.
   Install only the selected snapshot's `db.sqlite` and `noise_private.key` there,
   owned by `headscale:headscale`, mode 0600. The backup database is a standalone
   SQLite file with journal mode DELETE; Headscale will re-establish WAL mode.
5. Compare the backed-up YAML/policy with the current declarative configuration.
   Restore needed settings through the dotfiles repository, preserving the public
   URL and compatible Headscale package version. Do not overwrite `/etc`'s
   Nix-managed files with the backup copies.
6. Start `headscale.service`; inspect its journal and run `sudo headscale users list`
   and `sudo headscale nodes list`. Verify the existing NAS and laptop identities,
   access restrictions, and the public endpoint before declaring recovery complete.
7. Re-arm the backup timer when healthy. Retain the displaced state until both
   laptops reconnect successfully and a fresh verified snapshot is available.

The snapshot does not include `/var/lib/tailscale`, ACME material, or the NAS SSH
host key used to sign update offers. Those identities retain their existing
separate recovery requirements. A Headscale database/key restore does not replace
the need to preserve the pinned NAS SSH host key.
