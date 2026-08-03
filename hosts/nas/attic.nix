{
  config,
  lib,
  ...
}:
# ─── #130 ws5: move the fleet binary cache onto the NAS's bulk disk ─────────
#
# Option (c) of the three in #130, and the one it recommends: atticd RUNS here,
# next to its own storage, and the coordinator relays 8080 across the /30 cable.
# Every host keeps the unchanged `http://coordinator:8080/fleet` substituter URL
# from modules/common.nix, so nothing about the consumer side moves.
#
# Rejected alternatives, recorded so nobody re-litigates them:
#   (a) give the NAS agenix + a tailnet identity. Discards the appliance's
#       defining property and requires reverting mkForces that checks.nas-topology
#       exists specifically to protect.
#   (b) keep atticd on the coordinator, point only its storage at /mnt/nas. Puts
#       a SQLite database over NFS, which is a genuine corruption hazard, and
#       leaves the service and its bytes on opposite ends of a cable anyway.
#
# ── NOT StopWhenUnneeded, deliberately ─────────────────────────────────────
# Every other user-facing NAS service is socket-activated so the disk can park
# (#130 convention 2). This one is not, and must not be. It sits in the
# substituter hot path: deploy-rs relies on every node substituting from Attic
# (`fastConnection = false` in flake.nix), and a cache that takes several
# seconds of spin-up before answering the first query does not read as "slow",
# it reads as "broken", and Nix will quietly fall back to building from source.
# #130 calls this out explicitly. The disk stays awake while atticd is up.
#
# ── THE SIGNING-KEY TRAP — read this before running anything ───────────────
# modules/common.nix trusts `fleet:G5pAUpKmPtVsYbhFZAQsUUcuKHGsrHo9CFAJG7x5jNM=`.
# That keypair was generated SERVER-SIDE when the cache was created and it lives
# in atticd's SQLite database. A fresh atticd here generates a DIFFERENT key,
# which invalidates every signature in the existing cache, requires editing
# common.nix, and leaves every host silently building from source until a
# fleet-wide rebuild lands. So: MOVE THE STATE, do not recreate the cache. The
# layout below is chosen to make that move a single rsync — atticd's default
# StateDirectory layout (server.db + storage/) is reproduced verbatim under
# /mnt/nas/services/attic.
#
# ── RUNBOOK — cutover ──────────────────────────────────────────────────────
# The gate flip and the coordinator's atticd shutdown MUST be one commit: both
# want tcp/8080, and the coordinator's relay socket cannot bind while its own
# atticd holds the port. hosts/coordinator/nas-client.nix asserts this, and
# checks.nas-topology asserts the two hosts agree.
#
#   1. Measure first, so you know what you are moving and for how long:
#        ssh coordinator du -sh /var/lib/atticd
#   2. On the NAS, prepare the destination:
#        btrfs subvolume create /mnt/nas/services/attic   # if services/ is a
#          # subvolume this nests fine; a plain mkdir also works, it is inside
#          # the already-exported services subvolume either way
#        btrfs property set /mnt/nas/services/attic compression none
#      NARs are already zstd-compressed by attic; zstd:3 over them is pure CPU.
#   3. STOP the coordinator's atticd before copying. Copying a live SQLite file
#      is how you get a corrupt cache database:
#        ssh coordinator systemctl stop atticd
#   4. Move the state wholesale — database AND storage, in one pass:
#        ssh coordinator rsync -aHAX --info=progress2 \
#          /var/lib/atticd/ nas:/mnt/nas/services/attic/
#        ssh nas chown -R atticd:atticd /mnt/nas/services/attic
#      Verify server.db and storage/ both arrived before continuing.
#   5. Copy the RS256 signing secret across as a PLAIN FILE. The NAS has no
#      agenix (mySecrets.enable = false) and is not getting any; #130 accepts a
#      runbook-placed file here because the cache is `--public`, so PULLS NEED
#      NO TOKEN AT ALL and this key only signs push/admin tokens.
#        ssh coordinator sudo cat /run/agenix/atticd-server-token   # one line,
#          # ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64=...
#        # on the NAS, paste it into:
#        install -d -m 0700 -o root -g root /var/lib/atticd-secrets
#        install -m 0400 /dev/null /var/lib/atticd-secrets/env && vi /var/lib/atticd-secrets/env
#      It lives on the eMMC root, not on the exported data disk.
#   6. ONE commit, both sides:
#        hosts/nas/default.nix:         myNas.attic.enable = true;
#        hosts/coordinator/default.nix: myNasClient.relayAttic = true;
#                                       services.atticd.enable = lib.mkForce false;
#      Deploy the NAS first, then the coordinator.
#   7. Verify the key survived — this is the whole point of steps 3–4:
#        attic cache info fleet     # public key must still read
#                                   # fleet:G5pAUpKmPtVsYbhFZAQsUUcuKHGsrHo9CFAJG7x5jNM=
#      If it does NOT match, STOP. Do not paper over it by editing common.nix
#      in a hurry: roll back, and redo the move with atticd stopped. A rotation
#      is recoverable but it costs a fleet-wide rebuild with every host on
#      source builds in the meantime.
#   8. Then prove substitution actually works end to end, from a third host:
#        nix store info --store http://coordinator:8080/fleet
#        nix build --substituters http://coordinator:8080/fleet <something cached>
#   9. Measure the relay, which is #130's open question: a socket-proxyd hop in
#      the substituter hot path is cheap in theory and this is where you find
#      out. `iperf3 -c nas` over the /30 for the ceiling, then time a real
#      substitution of a large closure before and after. If it regresses badly,
#      the fallback is option (b) or moving back — the state move is symmetric.
#  10. Only once all of the above passes, delete /var/lib/atticd on the
#      coordinator. Not before. It is your rollback.
#
# NOTE, minor and harmless: the NAS itself substitutes from
# http://coordinator:8080/fleet (modules/common.nix), so after this it fetches
# from itself via the coordinator's relay — one extra round trip over a 10GbE
# cable. Not worth a per-host override; recorded so it is not mistaken for a
# loop bug later.
let
  cfg = config.myNas.attic;
  storageRoot = "/mnt/nas";
  # Mirrors atticd's own StateDirectory layout so step 4's rsync is a
  # like-for-like copy rather than a reshuffle.
  atticRoot = "${storageRoot}/services/attic";
  # Root filesystem, NOT the exported data disk: this file is a credential.
  environmentFile = "/var/lib/atticd-secrets/env";
in
{
  options.myNas.attic.enable = lib.mkEnableOption "the fleet binary cache server on the NAS, relayed by the coordinator (#130 ws5)";

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.myNas.storage.enable;
        message = "myNas.attic requires the verified myNas.storage mount";
      }
    ];

    services.atticd = {
      enable = true;
      # Placed by step 5 of the runbook above, not by agenix — the NAS has none.
      inherit environmentFile;
      # Same single-process shape the coordinator ran: API + GC + storage.
      mode = "monolithic";
      settings = {
        # The firewall rule below is the access control, exactly as on the
        # coordinator; the NAS's only network is the /30 cable.
        listen = "[::]:8080";
        # Both the DB and the NARs under one directory, so the state move is
        # one rsync and the signing key travels with it. SQLite on the rotating
        # disk is acceptable here precisely because this service is NOT
        # spin-down-managed — the platters are already turning whenever atticd
        # is answering. If cache metadata latency ever becomes the bottleneck,
        # the tuning move is database.url onto the /mnt/fast NVMe while storage
        # stays here; that splits the rsync and is a deliberate later decision.
        database.url = "sqlite://${atticRoot}/server.db?mode=rwc";
        storage = {
          type = "local";
          path = "${atticRoot}/storage";
        };
      };
    };

    # A STATIC atticd user, which the upstream module does not create: it sets
    # `DynamicUser = true` with `User = "atticd"`, and systemd's documented
    # behaviour is to use a statically allocated user of that name if one
    # exists and only allocate a transient one otherwise. Declaring it is not
    # optional here for two reasons:
    #   - tmpfiles below cannot chown to a name that only exists for the
    #     lifetime of a running unit; activation would fail with "Unknown user".
    #   - this service's entire state lives on a persistent shared disk and is
    #     placed there by an rsync in the runbook. A UID that is reallocated on
    #     a whim would make `chown atticd:atticd` meaningless across reboots.
    users.users.atticd = {
      isSystemUser = true;
      group = "atticd";
      home = atticRoot;
    };
    users.groups.atticd = { };

    systemd = {
      tmpfiles.rules = [
        "d /var/lib/atticd-secrets 0700 root root -"
        # 'z' not 'd': the runbook creates these while moving real state into
        # them. Manufacturing empty ones would start a FRESH cache with a NEW
        # signing key — the exact trap documented above.
        "z ${atticRoot} 0750 atticd atticd -"
        "z ${atticRoot}/storage 0750 atticd atticd -"
      ];
      services.atticd = {
        unitConfig.RequiresMountsFor = [ storageRoot ];
        # The module derives ReadWritePaths from settings.storage.path ALONE,
        # so with the sandbox on, the SQLite database one level up would be
        # read-only and atticd would fail to open it rwc. Grant the whole
        # atticRoot: it covers server.db plus the -wal/-shm files SQLite
        # creates beside it, which are just as load-bearing and just as easy
        # to forget.
        serviceConfig.ReadWritePaths = [ atticRoot ];
      };
    };

    networking.firewall.extraInputRules = ''
      ip saddr 10.77.0.1 tcp dport 8080 accept comment "attic binary cache from coordinator"
    '';
  };
}
