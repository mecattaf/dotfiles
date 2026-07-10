{ inputs, osConfig ? null, ... }:
# tally — agent-session orchestration, consumed via the flake input's
# homeManagerModules.tally (the load-bearing packaging channel; tally DECISIONS
# Q1 / V0.1-PATH step 1). The module is imported on every host but only ENABLED
# where the daemon should run.
#
# home/home.nix is shared by every host (coordinator, worker, zenbook-duo, and
# the standalone tom@bridge). The daemon runs ONLY on the conductor (tally SPEC
# "Module option surface"), so we gate `enable` on the hostname: the coordinator
# is the conductor; everywhere else the module stays inert (all of its config is
# under `mkIf cfg.enable`, so a disabled import builds nothing).
#
# `osConfig` is injected by home-manager when it runs as a NixOS module; on the
# standalone bridge it is absent (defaulted null → treated as a non-conductor).
let
  hostName = if osConfig == null then "bridge" else osConfig.networking.hostName;
  isConductor = hostName == "coordinator";
in
{
  imports = [ inputs.tally.homeManagerModules.tally ];

  services.tally = {
    enable = isConductor;

    # The coordinator hosts the daemon; it is the conductor. conductorHost is
    # pure client-reach config (tally DECISIONS Q9 — no hostname is frozen in
    # tally itself). "coordinator" is the mesh-resolvable name (modules/
    # mesh-registry.nix), so it works both on the box and from receivers over
    # the tailnet once they enable a receiver role.
    role = "conductor";
    conductorHost = "coordinator";

    # Everything else (package, pls client/broker source, runtimeInputs, the two
    # default GPU pools, drain timer, watcher-script export) is defaulted by
    # tally's flake — a bare enable Just Works.
  };
}
