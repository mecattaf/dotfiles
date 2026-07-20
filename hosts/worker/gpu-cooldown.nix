{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
# GPU thermal cooldown tripwire (worker-only).
#
# A systemd timer polls the worker's amdgpu junction temperature every 30s
# (falling back to k10temp Tctl where junction is absent — the live case on this
# box, whose amdgpu hwmon exposes only `edge`). On a SUSTAINED over-threshold
# reading it enqueues a fixed 30-minute job through the worker-local tally
# daemon. That job holds the single `worker-gpu` lease for the whole rest window,
# so every other local GPU consumer sees the pool as busy and backs off while the
# GPU cools. The 30-minute rest applies ONLY to the worker-gpu pool.
#
# Two layers (see the .sh files):
#   LAYER 1  gpu-cooldown-poll.sh    — sensor read + trip logic + hysteresis.
#   LAYER 2  gpu-cooldown-enqueue.sh — the tally seam; loud no-op fallback.
#
# Runs as `tom` (User=tom), matching the Home Manager tally daemon and its
# private socket under /run/user/$UID/tally.
let
  cfg = config.services.gpuCooldownTripwire;

  holdScript = pkgs.writeShellApplication {
    name = "gpu-cooldown-hold";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.util-linux
    ];
    text = builtins.readFile ./gpu-cooldown-hold.sh;
  };

  pollScript = pkgs.writeShellApplication {
    name = "gpu-cooldown-poll";
    runtimeInputs = [ pkgs.coreutils ];
    text = builtins.readFile ./gpu-cooldown-poll.sh;
  };

  enqueueScript = pkgs.writeShellApplication {
    name = "gpu-cooldown-enqueue";
    runtimeInputs = [
      pkgs.coreutils
      inputs.tally.packages.${pkgs.stdenv.hostPlatform.system}.tally
    ];
    text = builtins.readFile ./gpu-cooldown-enqueue.sh;
  };
in
{
  options.services.gpuCooldownTripwire = {
    enable = lib.mkEnableOption "the worker GPU thermal cooldown tripwire";

    user = lib.mkOption {
      type = lib.types.str;
      default = "tom";
      description = "User the poller runs as; must own the local tally daemon.";
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
      description = "Re-arm hysteresis: a fresh trip is allowed only after the temp drops below this since the last trip.";
    };

    sustainSeconds = lib.mkOption {
      type = lib.types.int;
      default = 60;
      description = "The reading must stay over threshold this long before tripping (~2-3 polls).";
    };

    cooldownMinutes = lib.mkOption {
      type = lib.types.int;
      default = 30;
      description = "Duration of the worker-gpu lease hold the cooldown job takes.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.gpu-cooldown-tripwire = {
      description = "GPU thermal cooldown tripwire — poll junction/Tctl, enqueue worker-gpu cooldown on a sustained trip";
      serviceConfig = {
        Type = "oneshot";
        User = cfg.user;
        StateDirectory = "gpu-cooldown";
        ExecStart = "${pollScript}/bin/gpu-cooldown-poll";
        Environment = [
          "HOME=/home/${cfg.user}"
          "COOLDOWN_ADAPTER=${enqueueScript}/bin/gpu-cooldown-enqueue"
          "COOLDOWN_HOLDER=${holdScript}/bin/gpu-cooldown-hold"
          "JUNCTION_THRESHOLD_C=${toString cfg.junctionThresholdC}"
          "TCTL_THRESHOLD_C=${toString cfg.tctlThresholdC}"
          "REARM_THRESHOLD_C=${toString cfg.rearmThresholdC}"
          "SUSTAIN_SECONDS=${toString cfg.sustainSeconds}"
          "COOLDOWN_MINUTES=${toString cfg.cooldownMinutes}"
        ];
      };
    };

    systemd.timers.gpu-cooldown-tripwire = {
      description = "Poll the worker GPU temperature for the cooldown tripwire";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "2min";
        OnUnitActiveSec = "${toString cfg.pollSeconds}s";
        AccuracySec = "5s";
      };
    };
  };
}
