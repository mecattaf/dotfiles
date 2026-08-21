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

    systemd.tmpfiles.rules = [
      "d /var/lib/atticd-secrets 0700 root root -"
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
