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
# host on 2026-08-30; the laptop came back on 2026-09-11 as `client`, and every
# alias is an identity map.
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
    # The thin client (2026-09-11). Identity map like the rest; resolves via
    # modules/fleet-hosts.nix on the twins. The reverse direction is NOT that
    # file: fleet-hosts.nix is twins-only, so ON the client `coordinator` and
    # `worker` resolve from its own networking.hosts entries
    # (hosts/client/default.nix:91-92 — 10.42.0.2 and 10.42.0.5), and `nas`
    # from the LAN resolver. Same names, three different sources, one answer
    # each, so the pinned host keys still match and nothing ever TOFUs.
    client = "client";
  };

  unknownTargets = lib.filter (t: !(registry ? ${t})) (lib.attrValues operatorAliases);

  # THE JUMP IS THE WORKER'S ALONE (2026-09-11).
  #
  # The rule it encodes: a host that can only reach the house over the
  # COORDINATOR's tailscale.com rail cannot address the NAS directly, because
  # the NAS's node lives on its own headscale control plane
  # (hosts/nas/headscale.nix, 2026-09-01) and two nodes on different control
  # planes share no netmap. Not for want of an identity — the appliance has had
  # one since 2026-08-21 — but for want of a SHARED one. Such a host hops
  # through the coordinator, which resolves `nas` → 10.42.0.1 from
  # networking.hosts. The pinned host key checked at the far end is still `nas`,
  # so the jump changes no trust.
  #
  # Three hosts are exempt, and the third is new. `nas` is itself. The
  # coordinator is on the LAN with it. And the CLIENT — the thin client that
  # arrived on 2026-09-11 — is exempt for BOTH of its rails, which is why the
  # old `hostName != "coordinator"` spelling was not merely redundant here but
  # wrong:
  #
  #   * on the LAN the client dials `nas` = 10.42.0.1 directly from its own
  #     networking.hosts. Routing a 10.42.0.16 → 10.42.0.1 session through
  #     10.42.0.2 is a pointless extra hop and an extra failure mode.
  #   * off-LAN the client rides the NAS's OWN headscale (node 100.64.0.4) and
  #     reaches the house through the subnet route the NAS advertises. The
  #     coordinator is reachable only THROUGH that route — so `ProxyJump
  #     coordinator` for `ssh nas` would dial the NAS to get to the coordinator
  #     to get to the NAS. A loop, and the thing the client does most when it is
  #     away from the house is exactly this.
  #
  # That leaves the worker: LAN-wired, no tailnet identity of its own, roamed to
  # only via the coordinator. Revisit if the worker ever joins the NAS's plane.
  #
  # CONTROLMASTER: not here, and that is a decision (plan section 6.2, option
  # (B)). No ControlMaster/ControlPersist/ServerAlive* in these blocks. The two
  # paths that actually carry long sessions bring their own multiplexing —
  # herdr --remote opens a private control socket per attach, and `kitten ssh`
  # has share_connections — so a fleet-wide master would only add a socket that
  # can wedge across a laptop suspend and outlive the network it was opened on.
  # Plain ssh pays roughly 200 ms per connection and can never be stale.
  needsJump =
    target:
    target == "nas"
    && !(builtins.elem hostName [
      "nas"
      "coordinator"
      "client"
    ]);

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
