{ inputs, osConfig ? null, ... }:
# tally — contention and proof for agent sessions, consumed via the flake
# input's homeManagerModules.tally (the load-bearing packaging channel: the
# module generates the systemd user units, producer timers and the build-time
# `checkedConfig` validator). The module is imported on every host but only
# ENABLED where the daemon should run.
#
# home/home.nix is shared by every host (coordinator, worker, zenbook-duo, and
# the standalone tom@bridge). Pools are local to one daemon: the coordinator
# owns the agent/build slot, while the worker owns its GPU cooldown slot.
# Everywhere else the module stays inert (all of its config is under
# `mkIf cfg.enable`, so a disabled import builds nothing).
#
# `osConfig` is injected by home-manager when it runs as a NixOS module; on the
# standalone bridge it is absent (defaulted null → treated as a non-coordinator).
#
# NOTE ON THE OPTION SURFACE: `conductorHost` and `role` are GONE. conductorHost
# was cut — client reach is subsumed by pool addressing, and pool addressing is
# itself deferred (RemoteLease / cross-host re-adoption are not built). The
# module declares no remote surface at all, and rejects unknown options rather
# than ignoring them, so a stale field here fails evaluation loudly instead of
# silently doing nothing. That strictness is deliberate.
let
  hostName = if osConfig == null then "bridge" else osConfig.networking.hostName;
  isCoordinator = hostName == "coordinator";
  isWorker = hostName == "worker";
in
{
  imports = [ inputs.tally.homeManagerModules.tally ];

  services.tally = {
    enable = isCoordinator || isWorker;

    # Contention is expressed purely as pools. `enforce = "cooperative"` is the
    # complete accepted enum — dmem/cgroup enforcement is deferred and the
    # module declares no option for it.
    #
    # This mirrors the stock pool the repo's own stock-host activation test
    # exercises, and is the starting surface: add pools (vram, cpu-slot, budget,
    # mutex) as real contention shows up. Every pool field has a default, so a
    # pool can be declared with `{ }` and refined later.
    pools =
      if isCoordinator then
        {
          build = {
            resource = "build-slot";
            capacity = 1;
            enforce = "cooperative";
          };
        }
      else if isWorker then
        {
          # The thermal tripwire enqueues a local hold here. New tally pools
          # are deliberately host-local, so this cannot live on coordinator.
          worker-gpu = {
            resource = "vram";
            capacity = 1;
            enforce = "cooperative";
          };
        }
      else
        { };

    # Everything else (package, adapters incl. the frozen codex preset, drain
    # timer, witness emitter, state/data dirs) is defaulted by the module — a
    # bare enable Just Works. Extra adapters are declared as an open map without
    # a recompile; the codex preset's argv prefix is frozen
    # (["codex" "exec" "--json" "--"]), so anything needing -C / -p /
    # --output-schema declares its own adapter rather than editing that one.
  };
}
