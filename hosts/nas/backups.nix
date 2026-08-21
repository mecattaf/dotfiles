{
  config,
  lib,
  pkgs,
  ...
}:
# ─── #130 ws2b: append-only borg repository server on the NAS ───────────────
#
# The push model: each source host runs `borg create` over SSH against a repo
# that lives here. The NAS never mounts anything, never holds a passphrase, and
# never initiates a connection — it just runs `borg serve --append-only` behind
# a forced-command SSH key. The client half is hosts/coordinator/backups.nix.
#
# Why borg and not restic-over-NFS (#130 asked): APPEND-ONLY. The coordinator's
# key physically cannot delete or rewrite what it has already written, so a
# compromised or confused coordinator — or a `rm -rf` that follows the NFS mount
# — cannot destroy its own backup history. Restic writing to /mnt/nas would have
# exactly the delete authority we are trying to remove. That property is what
# makes a backup a backup, and it is worth the extra moving part.
#
# NO SECRET LIVES ON THIS BOX. The NAS has mySecrets.enable = false and no
# agenix (hosts/nas/default.nix, deliberate). Borg repo authorisation is an
# authorized_keys restriction keyed on a PUBLIC key, so the entire server side
# is declarable in plaintext — this is the concrete reason #130 chose borg over
# anything needing a keyfile here. The repo's encryption passphrase belongs to
# the CLIENT and never reaches the NAS; a stolen NAS disk yields ciphertext.
#
# The key used is the coordinator's SSH HOST key from modules/mesh-registry.nix.
# It is already the fleet's committed single source of truth for that host's
# identity, it is root-readable on the coordinator (which is who runs the backup
# job), and using it means this workstream adds no new key material anywhere.
#
# ── /mnt/nas/backups MUST be its own subvolume. Two independent reasons ──
#  1. NFS containment. storage.nix exports the root plus one explicit fsid per
#     subvolume; `backups` gets NO export entry, so — same mechanism as
#     .snapshots — the coordinator cannot see, let alone delete, the repo
#     through /mnt/nas. If it were a plain directory it would sit inside the
#     fsid=0 root export with no_root_squash, and the append-only guarantee
#     above would be worth nothing.
#  2. compress=none. Borg data is already compressed and encrypted, so
#     zstd:3 on this tree burns CPU on every write for ~0 bytes saved.
# The upstream module's repo-directory unit does a plain `mkdir -p`, which would
# happily manufacture that plain directory for us. The ExecStartPre below exists
# to make that impossible: it refuses to start unless the path is genuinely a
# separate subvolume.
#
# RUNBOOK — enable
#   1. On the NAS, create the subvolume and turn compression off for it:
#        btrfs subvolume create /mnt/nas/backups
#        btrfs property set /mnt/nas/backups compression none
#        btrfs property get /mnt/nas/backups compression   # -> compression=none
#      (The property is inherited by files created afterwards, not retroactive —
#      do this BEFORE the first backup, not after.)
#   2. hosts/nas/default.nix: myNas.backups.enable = true; deploy the NAS.
#      The repo unit will fail loudly if step 1 was skipped. That is the point.
#   3. Confirm containment from the COORDINATOR:
#        ls /mnt/nas/backups     # must be empty or ENOENT, never a listing
#   4. Then do the client half — hosts/coordinator/backups.nix has its own
#      runbook, including the one-time repo init and the passphrase secret.
#
# ── THE APPEND-ONLY GOTCHA, read before you wonder where the space went ──
# `borg prune` from the coordinator marks archives deleted in the manifest but
# the server keeps every segment: an append-only repo NEVER shrinks from the
# client side. Reclaiming space is a deliberate, local, in-person operation ON
# THE NAS, as the borg user:
#        sudo -u borg borg compact /mnt/nas/backups/coordinator
# Do that only after `borg check` passes and only when you are satisfied the
# pruned archives are genuinely unwanted — it is the one irreversible step in
# this design, which is exactly why it is manual, local, and not in any timer.
let
  cfg = config.myNas.backups;
  storageRoot = "/mnt/nas";
  backupsRoot = "${storageRoot}/backups";
  repoPath = "${backupsRoot}/coordinator";
  registry = import ../../modules/mesh-registry.nix;

  # Fail closed if the runbook's subvolume step was skipped. Every Btrfs
  # subvolume is its own st_dev, so a device-number comparison against the
  # mountpoint is an exact test — no parsing of `btrfs subvolume show` output,
  # and it cannot be fooled by a same-named plain directory.
  requireSubvolume = pkgs.writeShellScript "borg-repo-require-subvolume" ''
    set -eu
    export PATH=${
      lib.makeBinPath [
        pkgs.coreutils
        pkgs.btrfs-progs
      ]
    }
    if [ ! -d ${backupsRoot} ]; then
      echo "${backupsRoot} does not exist: run 'btrfs subvolume create ${backupsRoot}' (see the runbook in hosts/nas/backups.nix)" >&2
      exit 1
    fi
    if [ "$(stat -c %d ${backupsRoot})" = "$(stat -c %d ${storageRoot})" ]; then
      echo "${backupsRoot} is a plain DIRECTORY, not a subvolume." >&2
      echo "It would therefore sit inside the fsid=0 NFS export and the coordinator could delete its own backups. Refusing to serve." >&2
      exit 1
    fi
    compression=$(btrfs property get ${backupsRoot} compression || true)
    case "$compression" in
      *none*|"") ;;
      *) echo "WARNING: ${backupsRoot} has $compression; borg data is already compressed. Run: btrfs property set ${backupsRoot} compression none" >&2 ;;
    esac
  '';
in
{
  options.myNas.backups.enable = lib.mkEnableOption "the append-only borg repository server for fleet host backups (#130 ws2b)";

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.myNas.storage.enable;
        message = "myNas.backups requires the verified myNas.storage mount";
      }
      {
        assertion = registry.coordinator.hostKey != "";
        message = "myNas.backups needs the coordinator's SSH host key in modules/mesh-registry.nix to authorise the repo";
      }
    ];

    services.borgbackup.repos.coordinator = {
      path = repoPath;
      user = "borg";
      group = "borg";
      # authorizedKeysAppendOnly, not authorizedKeys: this key forces
      # `borg serve --append-only --restrict-to-repository`, so the coordinator
      # can write new archives and read old ones but cannot destroy either.
      authorizedKeysAppendOnly = [ registry.coordinator.hostKey ];
      # One repo per key, no nesting. Keeps --restrict-to-repository exact.
      allowSubRepos = false;
      # 600G against the 500G budget line in #130. The headroom is not slack:
      # an append-only repo carries pruned-but-not-yet-compacted segments until
      # someone runs the manual compact above, so it legitimately overshoots
      # the live set for a while.
      quota = "600G";
    };

    systemd.services.borgbackup-repo-coordinator = {
      unitConfig.RequiresMountsFor = [ storageRoot ];
      serviceConfig.ExecStartPre = requireSubvolume;
    };

    # A restore during an actual disaster happens from the NAS console, with the
    # coordinator possibly dead — the CLI has to be here, not just on the
    # client. Added, never mkForce'd: modules/headless.nix builds its list with
    # a plain `=` for exactly this reason (see the comment there), so a host
    # module can extend it without discarding the module system's own base.
    environment.systemPackages = [ pkgs.borgbackup ];

    # No new firewall rule: borg rides SSH, and network.nix already admits
    # tcp/22 from the coordinator only (legacy /30 + pinned LAN lease).
  };
}
