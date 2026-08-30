{
  lib,
  osConfig,
  ...
}:
# SSH CLIENT INVENTORY — the operator-facing address book (~/.ssh/config).
#
# This is a fourth, distinct SSH layer, and the only one the fleet was missing:
#
#   networking.hostName / MagicDNS  canonical network identity
#   authorized_keys (modules/mesh.nix)     which keys may log IN
#   known_hosts     (modules/mesh.nix)     which host key is trusted for a name
#   Host block      (this file)            operator nickname → target + defaults
#
# A known-host entry is NOT a nickname: it records trust for a name that already
# resolves. So this module never adds trust — it only names destinations, sets
# `tom` as the default user, and pins the fleet key. Machine identities stay
# untouched: the flake node, deploy-rs target, agenix recipient and MagicDNS name
# are always the real hostname, and only the typed nickname differs. The one
# nickname that ever differed was `zenbook` -> `zenbook-duo`, dropped with that
# host on 2026-08-30; every remaining alias is now an identity map.
#
# Deliberately NOT touched here:
#   - ~/.ssh/known_hosts stays mutable and user-owned (GitHub, LAN IPs, …); fleet
#     trust keeps arriving through /etc/ssh/ssh_known_hosts (modules/mesh.nix).
#   - automation (deploy-rs) passes
#     -F /dev/null precisely so these preferences can never steer a deploy or a
#     rollback. Nothing below is on an operational path.
#
# API NOTE: the pinned home-manager (2026-07-24) DEPRECATED `programs.ssh.matchBlocks`
# in favour of the free-form `programs.ssh.settings`, whose attrs are literal
# ssh_config(5) directive names. Using matchBlocks would emit an eval warning on
# every host, so the blocks below are written in the new API. `enableDefaultConfig`
# is off for the same reason: leaving it on warns, and its `*` block only restates
# OpenSSH's own defaults — which is exactly the behaviour these hosts have today,
# having had no ~/.ssh/config at all.
let
  registry = import ../modules/mesh-registry.nix;
  hostName = osConfig.networking.hostName;

  # Operator nickname → canonical target name. The right-hand side must be a
  # registry attribute name (which is the real hostname); the left-hand side is a
  # presentation-layer name that exists nowhere else in the fleet.
  operatorAliases = {
    coordinator = "coordinator";
    nas = "nas";
    # Back since 2026-08-21 (#229). The right-hand side is the registry name;
    # mkBlock rewrites its HostName to the fleet identity on the coordinator —
    # see `workerRail` below for the #240 ruling behind that.
    worker = "worker";
  };

  unknownTargets = lib.filter (t: !(registry ? ${t})) (lib.attrValues operatorAliases);

  # The NAS has no tailnet identity (phase 1 of the 2026-08-20 rewire keeps it
  # that way), so from a roaming host the nickname still has to hop through the
  # coordinator, which resolves `nas` → 10.42.0.1 via networking.hosts (the
  # BE550 LAN; formerly the /30 cable). The pinned host key checked at the far
  # end is still `nas`, so no trust changes. Revisit if the phase-2
  # tailnet-direct decision ever lands.
  needsJump = target: target == "nas" && hostName != "nas" && hostName != "coordinator";

  # The worker has THREE rails from the coordinator, and which one the nickname
  # uses is a RULING, not taste (dotfiles#240, 2026-08-28): Thunderbolt
  # (10.99.0.x) is reserved for LLM-parallelism / tensor traffic ONLY; admin
  # traffic — interactive SSH, reboots, deploys, health checks — prefers the
  # dedicated 5GbE cable (eth-fleet) and rides the stable fleet identity.
  #
  # The 2026-08-21 measurement that put this nickname on the TB rail compared
  # TB against WIFI (0.6 ms vs 105 ms avg, mdev 54 ms) — a real 170x, but
  # eth-fleet.nix landed the SAME NIGHT and was never entered in the race.
  # Re-measured 2026-08-28 with PM QoS held (modules/lowlat-cluster.nix), 200
  # samples each:
  #
  #   TB   10.99.0.2 : rtt min/avg/max = 33/58/122 us, mdev 18 us
  #   eth  10.99.1.2 : rtt min/avg/max = 58/72/142 us, mdev  9 us
  #
  # 14 us of average and a TIGHTER tail on the wire — indistinguishable under
  # an interactive shell. The latency case for TB is dead, and what remains is
  # the reliability case AGAINST it: the TB link's whole failure class lives in
  # the USB-C/PD stack (tb-fleet.nix doctrine), it is the rail deliberate USB4
  # experiments run on, and a `reboot` typed over it competes with the tensor
  # traffic it exists to carry.
  #
  # The nickname therefore targets 10.99.9.2 — the fleet identity on the
  # worker's loopback, reachable via BOTH cables. Since #240 the eth-fleet
  # route to it costs metric 20 against the imperative TB route's 50, so admin
  # traffic prefers the wired rail and falls over to TB only when the 5GbE
  # cable itself dies (eth-fleet.nix owns that doctrine). Tensor traffic keeps
  # naming 10.99.0.x explicitly and never competes with this block.
  #
  # This is a COORDINATOR-ONLY preference. The cables have exactly two ends, so
  # from any non-twin host — the NAS today — the nickname must use the LAN
  # identity, which is
  # also the fleet-facing one every other consumer uses — the NAS's Immich ML
  # URL, the journal ACL, the networking.hosts pin. All addresses are registry
  # aliases, so the pinned host key is checked whichever rail answers and no
  # TOFU prompt appears either way.
  workerRail = if hostName == "coordinator" then "10.99.9.2" else "worker";

  mkBlock =
    _alias: target:
    {
      HostName = if target == "worker" then workerRail else target;
      User = "tom";
      # The fleet key delivered by agenix (modules/secrets.nix seeds it here).
      # IdentitiesOnly keeps a loaded agent from offering unrelated keys first.
      IdentityFile = "~/.ssh/id_ed25519";
      IdentitiesOnly = true;
      # Every fleet host key is pre-seeded in /etc/ssh/ssh_known_hosts, so a TOFU
      # prompt on these three names would mean something is wrong. Refuse instead.
      StrictHostKeyChecking = "yes";
    }
    // lib.optionalAttrs (needsJump target) { ProxyJump = "coordinator"; };
in
assert lib.assertMsg (unknownTargets == [ ]) (
  "home/ssh.nix: operator alias(es) point at hosts absent from mesh-registry.nix: "
  + lib.concatStringsSep ", " unknownTargets
);
{
  programs.ssh = {
    enable = true;
    enableDefaultConfig = false;
    settings = lib.mapAttrs mkBlock operatorAliases;
  };
}
