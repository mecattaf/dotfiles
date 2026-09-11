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

  # From a roaming host the `nas` nickname still has to hop through the
  # coordinator, which resolves `nas` → 10.42.0.1 via networking.hosts (the
  # BE550 LAN; formerly the /30 cable). The pinned host key checked at the far
  # end is still `nas`, so no trust changes.
  #
  # The REASON changed on 2026-09-01 and the old one was becoming a lie. This
  # said "the NAS has no tailnet identity", true only until 2026-08-21; the
  # appliance has had one since, and since 2026-09-01 it has its own control
  # plane for it (hosts/nas/headscale.nix). The jump survives anyway, for a
  # sharper reason: a roaming host reaches the house over the coordinator's
  # tailscale.com rail, the NAS's node lives on headscale, and two nodes on
  # different control planes share no netmap and cannot address each other. So
  # there is no tailnet-direct path to the NAS from a roaming session — not for
  # want of an identity, but for want of a SHARED one.
  # Revisit when headscale's publicEndpoint gate flips and a roaming client can
  # join the NAS's own tailnet: at that point the jump becomes unnecessary for
  # clients on that plane and still necessary for anything on tailscale.com.
  needsJump = target: target == "nas" && hostName != "nas" && hostName != "coordinator";

  # The worker has ONE rail from anywhere: the house LAN (it is wired into the
  # BE550's Ethernet port 2 in another room). Every host, the coordinator
  # included, dials the name — which resolves to the static 10.42.0.5 on the
  # twins via modules/fleet-hosts.nix and on the NAS via hosts/nas/network.nix.
  # The address is a registry alias, so the pinned host key is checked and no
  # TOFU prompt appears.
  workerRail = "worker";

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
