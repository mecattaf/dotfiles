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
# untouched: the flake node, deploy-rs target, agenix recipient, and MagicDNS name
# of the laptop all remain `zenbook-duo`; only the typed nickname is `zenbook`.
#
# Deliberately NOT touched here:
#   - ~/.ssh/known_hosts stays mutable and user-owned (GitHub, LAN IPs, …); fleet
#     trust keeps arriving through /etc/ssh/ssh_known_hosts (modules/mesh.nix).
#   - automation (deploy-rs, the zenbook preflight, GPU cooldown) passes
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
    zenbook = "zenbook-duo";
    nas = "nas";
    # Back since 2026-08-21 (#229). Plain name like every other fleet host: it
    # resolves through the fleet-wide 10.42.0.5 pin in modules/common.nix, and
    # the registry authorizes that name plus both addresses behind it, so there
    # is no TOFU prompt whichever rail answers. If the LAN is ever down, the
    # Thunderbolt address 10.99.0.2 is the documented fallback and is a registry
    # alias too — reach it explicitly rather than by this nickname.
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

  mkBlock =
    _alias: target:
    {
      HostName = target;
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
