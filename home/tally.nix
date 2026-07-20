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
# zenbook-duo merely accepts a best-effort SSH-dispatched update when it is online.
#
# The calendar remains systemd's clock, while tally owns admission, ordering,
# execution, and proof. Nightly work is low priority and atomically leases every
# affected resource, so an upgrade waits for active builds/LLM jobs and cannot
# admit a new conflicting job halfway through acquisition.
let
  hostName = if osConfig == null then "bridge" else osConfig.networking.hostName;
  isCoordinator = hostName == "coordinator";
  tallyPackage = inputs.tally.packages.${pkgs.stdenv.hostPlatform.system}.tally;

  # The coordinator reads the declaratively delivered mesh key directly. The
  # mutable ~/.ssh seed remains useful interactively but is not a daemon input.
  meshIdentity = if isCoordinator then osConfig.age.secrets.ssh-user-key.path else "/dev/null";
  knownHosts = "/etc/ssh/ssh_known_hosts";

  systemService = unit: [
    "/run/current-system/sw/bin/sudo"
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

  # The laptop intentionally has no tally daemon or remote helper. An offline
  # probe is a successful skip; once the probe succeeds, a dropped update SSH is
  # a real failure and is retained in tally's witness rather than disguised.
  zenbookUpgrade = pkgs.writeShellApplication {
    name = "tally-zenbook-upgrade";
    runtimeInputs = [ pkgs.openssh ];
    text = ''
      ssh_args=(
        -F /dev/null
        -n
        -o BatchMode=yes
        -o PasswordAuthentication=no
        -o KbdInteractiveAuthentication=no
        -o IdentitiesOnly=yes
        -o IdentityAgent=none
        -o ForwardAgent=no
        -o ClearAllForwardings=yes
        -o StrictHostKeyChecking=yes
        -o UserKnownHostsFile=${knownHosts}
        -o ConnectTimeout=10
        -o ConnectionAttempts=1
        -o ServerAliveInterval=15
        -o ServerAliveCountMax=3
        -i ${meshIdentity}
      )

      if ! ssh "''${ssh_args[@]}" root@zenbook-duo /run/current-system/sw/bin/true; then
        echo "tally fleet update: zenbook-duo offline at its nightly window; skipping"
        exit 0
      fi

      exec ssh "''${ssh_args[@]}" root@zenbook-duo \
        /run/current-system/sw/bin/systemctl --wait start nixos-upgrade.service
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

    # The old native timers are disabled in modules/auto-update.nix and
    # hosts/worker/fleet-prebuild.nix. Equal low-priority jobs serialize on build;
    # worker/coordinator activation also atomically waits for that host's GPU lane.
    producers = lib.optionalAttrs isCoordinator {
      nightly-fleet-prebuild = {
        kind = "calendar";
        onCalendar = "02:00";
        enqueue = {
          argv = systemService "fleet-prebuild.service";
          pool = "build";
          executor = "worker";
          priority = "low";
          dedupKey = "nightly-fleet-prebuild-%Y-%m-%d";
          evidence = [ "exit:0" ];
          noEnqueue = true;
        };
      };

      nightly-worker-upgrade = {
        kind = "calendar";
        onCalendar = "03:30";
        enqueue = {
          argv = systemService "nixos-upgrade.service";
          pool = [
            "build"
            "worker-gpu"
          ];
          executor = "worker";
          priority = "low";
          dedupKey = "nightly-worker-upgrade-%Y-%m-%d";
          evidence = [ "exit:0" ];
          noEnqueue = true;
        };
      };

      nightly-coordinator-upgrade = {
        kind = "calendar";
        onCalendar = "04:30";
        enqueue = {
          argv = systemService "nixos-upgrade.service";
          pool = [
            "build"
            "coordinator-gpu"
          ];
          priority = "low";
          dedupKey = "nightly-coordinator-upgrade-%Y-%m-%d";
          evidence = [ "exit:0" ];
          noEnqueue = true;
        };
      };

      nightly-zenbook-upgrade = {
        kind = "calendar";
        onCalendar = "06:00";
        enqueue = {
          argv = [ "${zenbookUpgrade}/bin/tally-zenbook-upgrade" ];
          pool = "build";
          priority = "low";
          dedupKey = "nightly-zenbook-upgrade-%Y-%m-%d";
          evidence = [ "exit:0" ];
          noEnqueue = true;
        };
      };
    };
  };
}
