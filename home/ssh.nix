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
#   - automation (deploy-rs, the zenbook preflight) passes
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
    # Back since 2026-08-21 (#229). The right-hand side is the registry name;
    # mkBlock rewrites its HostName to the Thunderbolt address on the
    # coordinator — see `workerRail` above for the measurements behind that.
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

  # The worker has TWO rails, and which one the nickname should use is not a
  # matter of taste. From the coordinator it is the THUNDERBOLT CABLE, always:
  #
  #   TB   10.99.0.2 : rtt min/avg/max/mdev = 0.109/0.625/0.803/0.260 ms
  #   wifi 10.42.0.5 : rtt min/avg/max/mdev = 42.115/104.817/197.654/54.229 ms
  #
  # (measured 2026-08-21, both boxes idle). ~170x the latency, and a mdev of
  # 54ms against 0.26ms — the wifi path is not merely slower, it is jittery,
  # because it is a 6GHz association bounced through the AP and the NAS's router
  # plane. The cable is a dedicated point-to-point link between these two boxes
  # that depends on no AP, no DHCP lease, no dnsmasq and no router: it is up
  # whenever both machines are, which is exactly what you want underneath an
  # interactive shell and underneath multi-gigabyte closure copies (the
  # reintegration itself pushed ~39GB of model weights across it).
  #
  # This is a COORDINATOR-ONLY preference. The cable has exactly two ends, so
  # from the zenbook or the NAS the nickname must use the LAN identity, which is
  # also the fleet-facing one every other consumer uses — the NAS's Immich ML
  # URL, the journal ACL, the networking.hosts pin. Both addresses are registry
  # aliases, so the pinned host key is checked whichever rail answers and no
  # TOFU prompt appears either way.
  #
  # NB an earlier revision of this file routed here for a WRONG reason (a
  # misdiagnosed "AP client isolation"; see hosts/worker/default.nix for the
  # retraction). The rail choice survived the retraction on its own merits,
  # which are the numbers above — not any claim that wifi is broken. It works
  # fine; it is just the slow, indirect way to reach a box on the other end of a
  # cable.
  workerRail = if hostName == "coordinator" then "10.99.0.2" else "worker";

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
