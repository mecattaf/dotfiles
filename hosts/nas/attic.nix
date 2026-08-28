{
  config,
  lib,
  unstablePkgs,
  ...
}:
# ─── ws5: the fleet binary cache lives ON the NAS ───────────────────────────
#
# Executed 2026-08-21 (cutover evening), superseding this module's original
# HDD staging on two of Tom's same-day rulings:
#
#   1. "attic on the 256GB M.2" — state lives at /var/lib/atticd on the NAS
#      root NVMe, atticd's stock StateDirectory layout. No HDD involvement:
#      the substituter hot path never wakes the data disk, and the disk's
#      spin-down life is untouched by cache traffic. (The original HDD plan
#      is in git history; its "NOT StopWhenUnneeded" reasoning still stands.)
#   2. "the NAS is the tailscale sink" — there is NO coordinator relay. Every
#      LAN host dials http://nas:8080/fleet directly (modules/common.nix);
#      remote hosts reach it over the NAS's own tailnet identity once that
#      lands. myNasClient.relayAttic stays OFF forever; the option remains
#      only as dead code to delete with nas-client.nix's next cleanup.
#
# ── THE SIGNING-KEY TRAP — still the one law ───────────────────────────────
# modules/common.nix trusts `fleet:igImm/3XfdWs2g7L0j94HKcCh9ndv1WtJ5fVK6Svwz4=`
# (the 2026-08-03 rotation; the staged version of this header named the old
# key — corrected at move time). That keypair lives in atticd's SQLite
# database (server.db). The state was
# MOVED wholesale from the coordinator (rsync with atticd stopped), never
# recreated: a fresh database means a fresh key, every signature in the cache
# invalidated, and the whole fleet silently building from source. If this box
# is ever reprovisioned, restore /var/lib/atticd from the coordinator's
# retained copy or a backup — do not let a fresh atticd start empty.
#
# ── The RS256 token secret: a runbook-placed file, not agenix ──────────────
# The cache is `--public`: pulls need no token at all. The RS256 secret only
# signs push/admin tokens, so #130's ruling stands — a root-owned env file
# placed by hand (runbook below) keeps the appliance's no-agenix doctrine.
#
# ── RUNBOOK — the move as actually performed (kept for reprovision) ────────
#   1. ssh coordinator systemctl stop atticd        # never copy a live SQLite
#   2. rsync -aH --info=progress2 coordinator:/var/lib/atticd/ /var/lib/atticd/
#   3. Place the env file (one line, ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64=…):
#        install -d -m 0700 /var/lib/atticd-secrets
#        install -m 0400 <file> /var/lib/atticd-secrets/env
#   4. Flip myNas.attic.enable, deploy the NAS; deploy the coordinator (its
#      atticd disabled + tripwire repointed) in the SAME commit.
#   5. Verify the key survived:  attic cache info fleet  → the fleet:… line
#      above, byte-identical. If not: STOP, redo the move.
#   6. Prove substitution: nix store info --store http://nas:8080/fleet
#   7. The coordinator keeps /var/lib/atticd as rollback until the first
#      healthy week, then deletes it.
let
  cfg = config.myNas.attic;
  # State: /var/lib/atticd (systemd DynamicUser symlink -> /var/lib/private/atticd).
  environmentFile = "/var/lib/atticd-secrets/env";
in
{
  options.myNas.attic.enable = lib.mkEnableOption "the fleet binary cache server on the NAS M.2 (#130 ws5, executed 2026-08-21)";

  config = lib.mkIf cfg.enable {
    # Deliberately the coordinator's EXACT working shape: pure DynamicUser
    # with default StateDirectory paths (db + storage under /var/lib/atticd,
    # which for a DynamicUser service is a systemd-managed symlink into
    # /var/lib/private/atticd — the rsync'd state lives THERE; move-day
    # lesson: a real directory at /var/lib/atticd breaks the sandbox with
    # sqlite "unable to open database file"). No static user, no tmpfiles on
    # the state tree, no custom paths — DynamicUser owns and chowns its
    # private dir itself on every start.
    services.atticd = {
      enable = true;
      # UNSTABLE package, deliberately (move-day lesson): the server.db was
      # written by the coordinator's unstable attic, whose 2026 migrations
      # (m20260508/0611/0624…) the stable-26.05 attic predates — it refused
      # to start against a database "from the future". atticd is
      # version-coupled to its data exactly like Immich, and rides the same
      # unstablePkgs exception (see ./unstable-pkgs.nix).
      package = unstablePkgs.attic-server;
      # Placed by runbook step 3, not by agenix — the NAS has none.
      inherit environmentFile;
      # Same single-process shape the coordinator ran: API + GC + storage.
      mode = "monolithic";
      settings = {
        # nftables is the access control: 8080 admitted from the LAN below,
        # never from wan0 (the router firewall admits nothing unsolicited
        # from the Freebox side).
        listen = "[::]:8080";
        # ── Chunking, sized for THIS cache and not for a public one (#234) ──
        # attic's defaults are avg 64 KiB / min 16 KiB / max 256 KiB, with
        # everything above 64 KiB chunked. Measured 2026-08-28 with a single
        # push on an otherwise idle machine (load 0.23):
        #
        #   mesa-26.1.5 — 264 MiB, 2,943 chunks, 478s  →  0.55 MiB/s
        #   atticd  99% of one core, start to finish   →  0.16s per chunk
        #   attic push (the client)  0.1% CPU          →  asleep throughout
        #
        # A sixth of a second per 90 KiB chunk is not compression work — no
        # zstd level on this Zen+ core runs at 0.55 MiB/s. It is FIXED
        # PER-CHUNK work: content hash, a SQLite row, a storage file, its own
        # zstd frame, repeated 616k times across this database.
        #
        # The arithmetic closes on the 2026-08-23 run exactly. That night was
        # one store path: `therock-rocm-sdk-gfx1151`, 8512 MiB in ONE NAR,
        # 96,139 chunks (nar id 3508, first chunk 00:04:22 UTC, last 07:30:26
        # — the 8h SIGTERM). 51,090 of those chunks were new, over 17,019s of
        # non-idle push time: 0.33s per chunk, the same order as the 0.16s
        # measured above on an idle box. Either constant, the run's length is
        # CHUNK COUNT times a fixed cost. It is not bytes, not
        # bandwidth, and not anything on the client — which is also why -j5
        # cannot help: attic parallelises across PATHS, and this is one path,
        # one NAR, one serial stream. The 08-22 attempt at the same path is
        # still in the database as a Pending 8512 MiB NAR (id 3161), killed
        # the same way, so the job had been re-uploading the same 8.5 GiB from
        # scratch every night and losing to the ceiling every night.
        #
        # So: fewer, bigger chunks. 16x fewer of them — that SDK path goes
        # from 96k chunks to ~8.5k. The honest bound on the win is NOT 16x:
        # compression is per-byte and does not shrink, and at 0.55 MiB/s it
        # can be at most about a third of the cost, so expect 3-10x. That is
        # the difference between most of a night and well inside the hour.
        # The defaults are tuned for a
        # shared multi-tenant cache where fine-grained dedup between unrelated
        # tenants pays for itself; this cache has exactly one producer
        # (./update-center.nix, same box) and already dedups whole NARs, so
        # sub-64 KiB dedup buys very little and was charging the entire push
        # budget for it.
        #
        # Costs, stated: dedup gets coarser, so the cache grows somewhat, and
        # existing chunks keep their old boundaries — a re-uploaded NAR will
        # not match them, so there is a one-off re-store of whatever gets
        # pushed again. Both are bounded by the retention policy below and by
        # 128G free on a 234G filesystem. NEITHER touches server.db's keypair:
        # these parameters affect new uploads only and are not a migration.
        chunking = {
          nar-size-threshold = 1048576; # 1 MiB — below this, store the NAR whole
          min-size = 262144; # 256 KiB
          avg-size = 1048576; # 1 MiB
          max-size = 4194304; # 4 MiB
        };
        # Retention carried over from the coordinator config (#133 doctrine:
        # accumulating artifact, declared policy): last-accessed keeps what
        # the fleet actually USES; only month-cold paths expire. Bounds the
        # cache against the 256GB M.2 it now shares with the OS and
        # /mnt/fast.
        garbage-collection = {
          interval = "12 hours";
          default-retention-period = "1 month";
        };
      };
    };

    # ── THE eMMC/NVMe CONFLATION, corrected 2026-08-22 ──────────────────────
    # Ruling 1 in the header above says this state "lives at /var/lib/atticd on
    # the NAS root NVMe", and the retention comment bounds the cache "against
    # the 256GB M.2 it now shares with the OS". Both sentences are false about
    # this machine and always were. Per ./disko.nix, `/` is the 57G eMMC
    # (mmcblk0p2); the 256G M.2 is NOT the root — it is /mnt/fast. So ws5 put
    # an accumulating, fleet-wide binary cache on the smallest and slowest
    # device in the box, beside the nix store that ./update-center.nix fills
    # nightly with three host closures.
    #
    # Found 2026-08-22 with / at 100% and ZERO bytes free, update-center in
    # failed state ("error: write of 26 bytes: No space left on device", build
    # FAILED for worker and zenbook-duo), and 18G of the 57G being this
    # service's own state. The intent in the header was right all along; only
    # the disk was wrong. This mount makes the sentence true.
    #
    # A BIND MOUNT, not a custom storage path, because the DynamicUser shape
    # documented above must not change: /var/lib/atticd stays the
    # systemd-managed symlink into /var/lib/private/atticd, StateDirectory
    # still owns and chowns that dir on every start, and the "unable to open
    # database file" sandbox trap stays avoided. All we change is which
    # spindle backs it.
    fileSystems."/var/lib/private/atticd" = {
      device = "/mnt/fast/atticd";
      fsType = "none";
      options = [
        "bind"
        # NOFAIL IS LOAD-BEARING AND IS NOT ABOUT CONVENIENCE. Without it a
        # fileSystems entry becomes REQUIRED by local-fs.target, so a bind
        # whose source is missing does not merely skip — it fails the target
        # and drops the machine into EMERGENCY MODE at boot. On the box that
        # is the house router, DNS and the tailnet subnet router, that is an
        # unreachable brick and a household with no internet, i.e. strictly
        # worse than the full disk this whole commit exists to fix.
        #
        # `nofail` costs nothing here because it does NOT reopen the
        # fresh-signing-key hole: the mount unit still exists and still fails
        # loudly, and atticd's RequiresMountsFor below keeps the service down
        # rather than letting StateDirectory conjure an empty state tree. So
        # the failure mode is "the binary cache is offline until someone
        # looks", which is a Tuesday, instead of either a brick or a silently
        # re-keyed fleet.
        "nofail"
      ];
      depends = [ "/mnt/fast" ];
    };

    # ── THE SIGNING-KEY TRAP, SECOND EDITION ────────────────────────────────
    # The one law in the header is about `rm`. This is the same catastrophe
    # reached by mounting. /mnt/fast is `nofail` (./disko.nix) — correct for a
    # budget NVMe holding regenerable state, lethal here: if that disk ever
    # fails to mount, the bind above silently does not happen, StateDirectory
    # cheerfully creates a fresh EMPTY /var/lib/private/atticd, and atticd
    # generates a BRAND NEW keypair. server.db carries the fleet's signing key,
    # so every signature ../../modules/common.nix trusts is invalidated at once
    # and every device on the LAN silently starts building from source.
    #
    # RequiresMountsFor turns that into a service that refuses to start, which
    # is a Tuesday rather than a fleet-wide outage. If atticd is ever found
    # dead with "Unit var-lib-private-atticd.mount not found", the answer is to
    # fix the NVMe — never to let it start without its state.
    systemd.services.atticd.unitConfig.RequiresMountsFor = [ "/var/lib/private/atticd" ];

    systemd.tmpfiles.rules = [
      "d /var/lib/atticd-secrets 0700 root root -"
      # NB deliberately no rule for /mnt/fast/atticd: the move is a runbook
      # step (stop atticd, `mv /var/lib/private/atticd /mnt/fast/atticd`,
      # rebuild) and a tmpfiles rule would race it by creating an empty
      # directory for the bind to find — which is exactly the fresh-key
      # scenario above. If the source is missing the mount fails and the
      # service stays down. That is the intended behaviour.
    ];

    # Every fleet device substitutes: coordinator .2, worker .5, zenbook and
    # anything else from the pool. LAN-wide by subnet, same doctrine as SMB
    # (discovery.nix). A tailscale0 admission joins here when the NAS's
    # tailnet identity lands, so roaming hosts can substitute from anywhere.
    networking.firewall.extraInputRules = ''
      ip saddr 10.42.0.0/24 tcp dport 8080 accept comment "attic binary cache, whole LAN"
    '';
  };
}
