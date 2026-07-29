{
  config,
  lib,
  pkgs,
  ...
}:
# Coordinator GPU thermal cooldown tripwire.
#
# A systemd timer polls amdgpu junction temperature every 30 seconds, falling
# back to k10temp Tctl when junction is absent. A sustained over-threshold
# reading invokes a fixed local receiver in Tom's Home Manager profile. The
# receiver enqueues a 30-minute, interrupt-priority sleep against
# `coordinator-gpu`; that pool remains non-preemptive, so an active GPU job is
# never killed. Failed enqueue attempts are loud and retried by the next poll.
let
  cfg = config.services.gpuCooldownTripwire;

  pollScript = pkgs.writeShellApplication {
    name = "gpu-cooldown-poll";
    runtimeInputs = [ pkgs.coreutils ];
    text = builtins.readFile ./gpu-cooldown-poll.sh;
  };

  enqueueScript = pkgs.writeShellApplication {
    name = "gpu-cooldown-enqueue";
    runtimeInputs = [ pkgs.coreutils ];
    text = builtins.readFile ./gpu-cooldown-enqueue.sh;
  };
in
{
  options.services.gpuCooldownTripwire = {
    enable = lib.mkEnableOption "the coordinator GPU thermal cooldown tripwire";

    user = lib.mkOption {
      type = lib.types.str;
      default = "tom";
      description = "User running the poller and local Tally receiver.";
    };

    pollSeconds = lib.mkOption {
      type = lib.types.int;
      default = 30;
      description = "Poll cadence of the hwmon read.";
    };

    junctionThresholdC = lib.mkOption {
      type = lib.types.int;
      default = 90;
      description = "amdgpu junction trip threshold (deg C).";
    };

    tctlThresholdC = lib.mkOption {
      type = lib.types.int;
      default = 85;
      description = "k10temp Tctl trip threshold (deg C), used when junction is absent.";
    };

    rearmThresholdC = lib.mkOption {
      type = lib.types.int;
      default = 75;
      description = "Re-arm only after temperature drops below this threshold.";
    };

    sustainSeconds = lib.mkOption {
      type = lib.types.int;
      default = 60;
      description = "Required sustained over-threshold interval before tripping.";
    };

    cooldownMinutes = lib.mkOption {
      type = lib.types.int;
      default = 30;
      description = "Duration of the coordinator-gpu lease hold.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.gpu-cooldown-tripwire = {
      description = "GPU thermal cooldown tripwire for coordinator-gpu";
      environment = {
        HOME = "/home/${cfg.user}";
        COOLDOWN_ADAPTER = "${enqueueScript}/bin/gpu-cooldown-enqueue";
        TALLY_COOLDOWN_RECEIVER = "/etc/profiles/per-user/${cfg.user}/bin/tally-gpu-cooldown";
        JUNCTION_THRESHOLD_C = toString cfg.junctionThresholdC;
        TCTL_THRESHOLD_C = toString cfg.tctlThresholdC;
        REARM_THRESHOLD_C = toString cfg.rearmThresholdC;
        SUSTAIN_SECONDS = toString cfg.sustainSeconds;
        COOLDOWN_MINUTES = toString cfg.cooldownMinutes;
      };
      serviceConfig = {
        Type = "oneshot";
        User = cfg.user;
        StateDirectory = "gpu-cooldown";
        ExecStart = "${pollScript}/bin/gpu-cooldown-poll";
      };
    };

    systemd.timers.gpu-cooldown-tripwire = {
      description = "Poll coordinator GPU temperature for the cooldown tripwire";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "2min";
        OnUnitActiveSec = "${toString cfg.pollSeconds}s";
        AccuracySec = "5s";
      };
    };
  };
}
