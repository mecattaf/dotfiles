{
  config,
  lib,
  ...
}:
# ─── #130 ws2b, client half: the coordinator's nightly borg push to the NAS ──
#
# Server half is hosts/nas/backups.nix (append-only repo, no secret on the NAS).
# Read that file's header first — especially the append-only compaction gotcha,
# which is the one thing about this design that will surprise you later.
#
# WHAT IS BACKED UP, and the reasoning for each exclusion. The rule is: back up
# what is irreplaceable or expensive to reconstitute; exclude anything a rebuild
# or a re-download regenerates byte-for-byte.
#   IN   /home/tom      — the notes repo, the dotfiles checkout, ~/.claude, ssh
#                         keys, shell state. The actual irreplaceable material.
#   IN   /var/lib       — service state: tally, adguardhome, fleet-deploy,
#                         tailscale, systemd machine identity.
#   OUT  /nix/store     — not under either path, and reproducible from the flake
#                         by definition. Backing up a store is a category error.
#   OUT  /var/lib/atticd — the fleet binary cache. Hundreds of GB whose entire
#                         purpose is to be a rebuildable cache; if it were worth
#                         backing up it would not be a cache. (And #130 ws5 may
#                         move it to the NAS entirely, at which point backing it
#                         up here would be copying the NAS to the NAS.)
#   OUT  /var/lib/microvms — multi-GB guest images, declaratively rebuildable
#                         (modules/microvm-host.nix).
#   OUT  model weights  — /home/tom/.cache/huggingface and friends. These are
#                         fixed-output derivations pinned by hash in
#                         lib/local-models.nix; re-fetch is exact. Cold-archiving
#                         retired ones is #130 ws4, a different mechanism with a
#                         different retention story (docs/nas/model-archive.md).
#   OUT  caches         — ~/.cache, node_modules, target/, result symlinks.
#   OUT  /mnt/nas       — not under either path, but worth saying out loud: the
#                         NAS is the backup TARGET. Its own copies are the btrbk
#                         snapshots (ws2a) and the quarterly LaCie mirror (ws3).
#
# ENCRYPTION: repokey-blake2. The key material lives inside the repo on the NAS,
# encrypted with a passphrase that never leaves the coordinator — so a stolen
# NAS disk yields ciphertext, and a coordinator reflash recovers with nothing
# but the agenix secret. `keyfile` mode would be marginally stronger and
# considerably more dangerous: losing the client-side key file makes every
# archive permanently unreadable, which converts a disk failure into a total
# loss. One secret to protect, restorable from any host that can decrypt it.
#
# ── RUNBOOK — enable (do the NAS half first) ────────────────────────────────
#   1. Mint and encrypt the passphrase (one time, on the coordinator):
#        openssl rand -base64 48 > /tmp/borg-pass && cat /tmp/borg-pass
#      Record it in the password manager NOW — without it the backups are
#      unreadable, and that is not recoverable by any amount of cleverness.
#        nix develop -c agenix -e secrets/borg-passphrase.age   # paste it
#        shred -u /tmp/borg-pass
#      This needs a matching recipient line in the repo-root secrets.nix:
#        "secrets/borg-passphrase.age".publicKeys = editors ++ coordinatorOnly;
#      (Coordinator-only tier: the NAS must never be able to decrypt it, and no
#      other host runs this job yet.) Until that ciphertext exists this module
#      stays inert even with the gate on — same pathExists pattern
#      modules/secrets.nix uses for huggingface-token.
#   2. hosts/coordinator/default.nix: myCoordinatorBackups.enable = true;
#   3. Deploy, then run the first backup by hand and watch it:
#        systemctl start borgbackup-job-nas.service
#        journalctl -fu borgbackup-job-nas.service
#      The first run inits the repo and copies everything — hours, not minutes.
#   4. Verify from the coordinator that you can actually read it back. An
#      unverified backup is a rumour:
#        export BORG_REPO=borg@nas:/mnt/nas/backups/coordinator
#        export BORG_PASSCOMMAND='cat /run/agenix/borg-passphrase'
#        export BORG_RSH='ssh -i /etc/ssh/ssh_host_ed25519_key'
#        borg list && borg info
#        borg mount ::<archive> /mnt/restore && ls /mnt/restore/home/tom
#        borg umount /mnt/restore
#      That `borg mount` is the "browsable, restore-to-a-point-in-time" half of
#      what #130 called Time Machine semantics; there is no separate UI.
#   5. Schedule interaction: this runs at 04:30 daily, deliberately clear of the
#      NAS's 02:15 pg_dump and the Sunday 03:30 journal archive. It does NOT yet
#      take the `nas-hdd` Tally lease that home/tally.nix declares for exactly
#      this purpose — see the follow-up note at the bottom of this file.
let
  cfg = config.myCoordinatorBackups;
  passphraseCiphertext = ../../secrets/borg-passphrase.age;
  haveSecret = builtins.pathExists passphraseCiphertext;
in
{
  options.myCoordinatorBackups.enable = lib.mkEnableOption "nightly borg backup of the coordinator to the NAS append-only repo (#130 ws2b)";

  config = lib.mkMerge [
    # Assertions live OUTSIDE the haveSecret guard on purpose: flipping the gate
    # without the ciphertext must fail the build with this message, not silently
    # evaluate to an empty module and leave Tom believing he has backups.
    (lib.mkIf cfg.enable {
      assertions = [
        {
          assertion = config.mySecrets.enable;
          message = "myCoordinatorBackups needs agenix (mySecrets.enable) for the repo passphrase";
        }
        {
          assertion = haveSecret;
          message = "myCoordinatorBackups needs secrets/borg-passphrase.age; see step 1 of the runbook in hosts/coordinator/backups.nix";
        }
      ];
    })

    (lib.mkIf (cfg.enable && haveSecret) {
      age.secrets.borg-passphrase = {
        file = passphraseCiphertext;
        # Read by the job, which runs as root.
        mode = "400";
      };

      services.borgbackup.jobs.nas = {
        paths = [
          "/home/tom"
          "/var/lib"
        ];
        exclude = [
          # Rebuildable caches — see the reasoning block in this file's header.
          "/var/lib/atticd"
          "/var/lib/microvms"
          "/var/lib/systemd/coredump"
          "/var/lib/private/*/cache"
          "/home/tom/.cache"
          "/home/tom/.local/share/Trash"
          "/home/tom/.local/state/nix"
          # Model weights: hash-pinned and re-fetchable (lib/local-models.nix).
          # The huggingface cache is already covered by ~/.cache above.
          "/home/tom/.ollama"
          # Build output, per-project. sh: glob patterns, borg's default style.
          "sh:/home/tom/**/node_modules"
          "sh:/home/tom/**/.direnv"
          "sh:/home/tom/**/target/debug"
          "sh:/home/tom/**/result"
          "sh:/home/tom/**/result-*"
        ];
        repo = "borg@nas:/mnt/nas/backups/coordinator";
        encryption = {
          mode = "repokey-blake2";
          passCommand = "cat ${config.age.secrets.borg-passphrase.path}";
        };
        # The coordinator's own SSH host key is the credential. Its public half is
        # already committed in modules/mesh-registry.nix and is what the NAS pins
        # in authorizedKeysAppendOnly, so this workstream introduces no new key
        # material. modules/mesh.nix pre-seeds nas's host key into known_hosts, so
        # host verification is real here — no StrictHostKeyChecking=no.
        environment.BORG_RSH = "ssh -i /etc/ssh/ssh_host_ed25519_key";
        # `auto,` lets borg skip its compressor on files that are already
        # compressed (the bulk of /home/tom by bytes) instead of paying CPU to
        # not shrink them. The repo subvolume on the NAS is compress=none for the
        # same reason at the filesystem layer.
        compression = "auto,zstd,3";
        startAt = "*-*-* 04:30:00";
        persistentTimer = true;
        # Borg exits 1 ("warning") for perfectly routine things on a live system —
        # most often a file that changed between stat and read under /var/lib. A
        # partial-but-consistent archive is still written and is still useful, so
        # a warning must not mark the job failed and mask a real failure later.
        # Genuine failures are exit 2 and still fail the unit.
        failOnWarnings = false;
        prune.keep = {
          within = "1d"; # everything from the last day
          daily = 14;
          weekly = 8;
          monthly = 12;
        };
        # Remember: prune only rewrites the manifest on an append-only repo. Space
        # comes back when someone runs `borg compact` locally on the NAS. That is
        # intentional and documented in hosts/nas/backups.nix.
      };

      systemd.services.borgbackup-job-nas = {
        # Do not fight the fleet's nightly deploy or a media stream for the cable.
        serviceConfig = {
          Nice = 10;
          IOSchedulingClass = "idle";
        };
      };

    })
  ];

  # ── FOLLOW-UPS (deliberately not implemented here) ────────────────────────
  # • Tally `nas-hdd` lease. home/tally.nix declares a capacity-1 pool for the
  #   NAS spindle and its comment names "future borg backups" as an intended
  #   consumer. Wiring this job to it means replacing startAt with a Tally
  #   calendar producer (the weekly-journal-archive block is the template) and
  #   lives in home/tally.nix, which this change does not own.
  # • zenbook-duo and bridge jobs. Same repo server, one repo and one
  #   authorizedKeysAppendOnly entry each. NOT done here because neither host
  #   can reach the NAS at all — the NAS is on the /30 cable with no tailnet
  #   identity, so those hosts need either a coordinator-side SSH relay or a
  #   different transport, and that needs testing on real hardware rather than
  #   a plausible-looking config.
}
