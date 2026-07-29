{
  inputs,
  lib,
  osConfig ? null,
  pkgs,
  ...
}:
# tally — the single coordinator for user-decided impure work.
#
# home/home.nix is shared by the fleet and the standalone bridge, but the daemon,
# logical pools, local executor, and calendar producers exist ONLY on coordinator.
# zenbook-duo remains a best-effort target of the coordinator-owned deploy
# workflow and is not required for coordinator maintenance.
#
# The calendar remains systemd's clock, while tally owns admission, ordering,
# execution, and proof. One nightly item leases the build lane and coordinator GPU
# for the complete local build/deploy transaction, so it waits for active work
# while keeping maintenance local to the coordinator.
let
  hostName = if osConfig == null then "bridge" else osConfig.networking.hostName;
  isCoordinator = hostName == "coordinator";
  tallyPackage = inputs.tally.packages.${pkgs.stdenv.hostPlatform.system}.tally;

  systemService = unit: [
    # NixOS installs sudo's setuid entry point in security.wrapperDir. The
    # package symlink under /run/current-system/sw/bin is deliberately not
    # setuid, so it cannot be used by Tally's unprivileged local/SSH executors.
    "${osConfig.security.wrapperDir}/sudo"
    "-n"
    "/run/current-system/sw/bin/systemctl"
    "--wait"
    "start"
    unit
  ];

  # Fixed receiver used by the coordinator's hardware tripwire. The sleep holds
  # the logical coordinator-gpu gate for 30 minutes.
  # Interrupt priority makes it next, while hardPreempt=false means it never kills
  # the current GPU holder.
  cooldownReceiver = pkgs.writeShellApplication {
    name = "tally-gpu-cooldown";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      temp_c="''${1:?usage: tally-gpu-cooldown <temp_c> <sensor_kind> <threshold_c> <seconds>}"
      sensor_kind="''${2:?}"
      threshold="''${3:?}"
      seconds="''${4:?}"

      [[ "$temp_c" =~ ^[0-9]+$ ]]
      [[ "$threshold" =~ ^[0-9]+$ ]]
      [[ "$seconds" =~ ^[1-9][0-9]*$ ]]
      [[ "$sensor_kind" =~ ^[A-Za-z0-9:_-]+$ ]]

      stamp="$(${pkgs.coreutils}/bin/date -u +%Y%m%dT%H%M%SZ)"
      dedup="gpu-cooldown-coordinator-''${sensor_kind}-''${temp_c}C-''${stamp}"
      socket="/run/user/$(id -u)/tally/tally.sock"

      exec ${tallyPackage}/bin/tally --socket "$socket" enqueue \
        --source calendar \
        --pool coordinator-gpu \
        --priority interrupt \
        --dedup-key "$dedup" \
        --no-enqueue \
        --evidence exit:0 \
        -- ${pkgs.coreutils}/bin/sleep "$seconds"
    '';
  };

in
{
  imports = [
    inputs.tally.homeManagerModules.tally
    ../flows/tally-flows.nix
  ];

  home.packages = lib.optionals isCoordinator [
    cooldownReceiver
    pkgs.local-ai-monthly
  ];

  services.tally = {
    enable = isCoordinator;

    # errata-map deliberately permits a bounded 400-node review wave. Tally
    # v0.1.0 checks declared flow width against this daemon guardrail while
    # building the generation.
    enqueue.fanoutCap = 400;

    # These are real contention lanes, not synthetic maintenance pools.
    pools = lib.optionalAttrs isCoordinator {
      build = {
        resource = "build-slot";
        capacity = 1;
        enforce = "cooperative";
        hardPreempt = false;
      };
      # "build" is reserved by Tally v0.1.0 for drv() nodes. Shell nodes in
      # these flows use a distinct lane, and the nightly deploy leases both so
      # it remains exclusive with either kind of flow build.
      flow-build = {
        resource = "build-slot";
        capacity = 1;
        enforce = "cooperative";
        hardPreempt = false;
      };
      coordinator-gpu = {
        resource = "vram";
        capacity = 1;
        enforce = "cooperative";
        hardPreempt = false;
      };
      local-ai-review = {
        resource = "mutex";
        capacity = 1;
        enforce = "cooperative";
        hardPreempt = false;
      };
      # Tally v0.1.0 models a capacity-one subscription concurrency lane as a
      # mutex; windowed-consumption budget pools are intentionally unavailable
      # to flow nodes.
      codex-window = {
        resource = "mutex";
        capacity = 1;
        enforce = "cooperative";
        hardPreempt = false;
      };
    };

    # All jobs execute locally on coordinator; no daemonless SSH executor is
    # part of the active topology.
    executors = { };

    # One low-priority durable row replaces the old 02:00/03:30/04:30/06:00 chain.
    # It holds the build and coordinator GPU lanes end-to-end, making the measured
    # single-node build plus activation one exclusive maintenance window.
    # The system service handles Zenbook's successful offline/low-power skip internally.
    producers = lib.optionalAttrs isCoordinator {
      # The parent serializes one monthly review but does not reserve the GPU.
      # After deterministic Git/Nix/HF preparation it enqueues one low-priority
      # coordinator-gpu child for Pi, waits for the commentary, then verifies and
      # publishes without a GPU lease. noEnqueue=false is the deliberate child
      # capability; Tally injects the parent identity and socket for that call.
      monthly-local-ai-review = {
        kind = "calendar";
        onCalendar = "*-*-01 00:30:00";
        enqueue = {
          argv = [
            "${pkgs.local-ai-monthly}/bin/local-ai-monthly-tally"
            "--tally"
            "${tallyPackage}/bin/tally"
          ];
          pool = "local-ai-review";
          priority = "low";
          dedupKey = "monthly-local-ai-review-%Y-%m";
          evidence = [
            "exit:0"
            "artifact:/home/tom/.local/state/local-ai-monthly/last-run.json"
            "hash:sha256"
          ];
          runtimeMaxSec = 43200;
          noEnqueue = false;
        };
      };

      nightly-fleet-deploy = {
        kind = "calendar";
        onCalendar = "02:00";
        enqueue = {
          pool = [
            "build"
            "flow-build"
            "coordinator-gpu"
          ];
          argv = systemService "fleet-deploy.service";
          priority = "low";
          dedupKey = "nightly-fleet-deploy-%Y-%m-%d";
          evidence = [ "exit:0" ];
          noEnqueue = true;
        };
      };
    };
  };
}
