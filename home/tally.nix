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
# logical pools, remote executor, and calendar producers exist ONLY on coordinator.
# worker contributes execution/GPU capacity through the daemonless SSH executor;
# zenbook-duo remains a best-effort target of the coordinator-owned deploy workflow.
#
# The calendar remains systemd's clock, while tally owns admission, ordering,
# execution, and proof. One nightly item now replaces the old staggered prebuild +
# three per-host switches. It atomically leases build and both core GPU lanes for
# the complete deploy-rs transaction, so it waits for active builds/LLM jobs and
# cannot admit conflicting work between worker and coordinator activation.
let
  hostName = if osConfig == null then "bridge" else osConfig.networking.hostName;
  isCoordinator = hostName == "coordinator";
  tallyPackage = inputs.tally.packages.${pkgs.stdenv.hostPlatform.system}.tally;

  # The coordinator reads the declaratively delivered mesh key directly. The
  # mutable ~/.ssh seed remains useful interactively but is not a daemon input.
  meshIdentity = if isCoordinator then osConfig.age.secrets.ssh-user-key.path else "/dev/null";
  knownHosts = "/etc/ssh/ssh_known_hosts";

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

  # Fixed receiver used by worker's hardware tripwire. The sleep runs locally on
  # coordinator: it needs only to hold the logical worker-gpu gate for 30 minutes.
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
      dedup="gpu-cooldown-worker-''${sensor_kind}-''${temp_c}C-''${stamp}"
      socket="/run/user/$(id -u)/tally/tally.sock"

      exec ${tallyPackage}/bin/tally --socket "$socket" enqueue \
        --source calendar \
        --pool worker-gpu \
        --priority interrupt \
        --dedup-key "$dedup" \
        --no-enqueue \
        --evidence exit:0 \
        -- ${pkgs.coreutils}/bin/sleep "$seconds"
    '';
  };

in
{
  imports = [ inputs.tally.homeManagerModules.tally ];

  home.packages = lib.optionals isCoordinator [ cooldownReceiver ];

  services.tally = {
    enable = isCoordinator;

    # These are real contention lanes, not synthetic maintenance pools. All are
    # centrally owned even when their physical resource is on worker.
    pools = lib.optionalAttrs isCoordinator {
      build = {
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
      worker-gpu = {
        resource = "vram";
        capacity = 1;
        enforce = "cooperative";
        hardPreempt = false;
      };
    };

    # worker runs only tally's short-lived remote helper under tom's user systemd
    # manager. Lease ownership and the durable row never leave coordinator.
    executors = lib.optionalAttrs isCoordinator {
      worker = {
        host = "worker-tb";
        user = "tom";
        identityFile = meshIdentity;
        knownHostsFile = knownHosts;
        program = "${tallyPackage}/bin/tally";
        stateDir = "/home/tom/.local/state/tally-remote";
      };
    };

    # One low-priority durable row replaces the old 02:00/03:30/04:30/06:00 chain.
    # It is intentionally conservative: all three real contention lanes are held
    # end-to-end, making build + worker→coordinator rollback one maintenance window.
    # The system service handles Zenbook's successful offline/low-power skip internally.
    producers = lib.optionalAttrs isCoordinator {
      nightly-fleet-deploy = {
        kind = "calendar";
        onCalendar = "02:00";
        enqueue = {
          pool = [
            "build"
            "coordinator-gpu"
            "worker-gpu"
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
