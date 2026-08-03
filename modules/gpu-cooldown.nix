{
  config,
  lib,
  pkgs,
  ...
}:
# Coordinator GPU thermal cooldown tripwire — the first myTripwire instance.
#
# This module used to carry its own poller and state machine; both now live in
# ./tripwire.nix, and what is left here is the part that is genuinely about
# this GPU: which hwmon node to read, at what temperature to act, and what
# acting means (a bounded coordinator-gpu hold enqueued through tally). The
# option surface is unchanged, so hosts keep configuring it the same way.
let
  cfg = config.services.gpuCooldownTripwire;
in
{
  imports = [ ./tripwire.nix ];

  options.services.gpuCooldownTripwire = {
    enable = lib.mkEnableOption "the coordinator GPU thermal cooldown tripwire";

    user = lib.mkOption {
      type = lib.types.str;
      default = "tom";
      description = "User running the poller; its tally socket receives the hold.";
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
    myTripwire.gpu-cooldown = {
      description = "GPU thermal cooldown tripwire for coordinator-gpu";
      user = cfg.user;
      # Unchanged from the bespoke poller, so an in-flight episode's hysteresis
      # survives the migration rather than starting from a blank state file.
      stateDirectory = "gpu-cooldown";
      valueField = "TEMP_C";

      intervalSeconds = cfg.pollSeconds;
      sustainSeconds = cfg.sustainSeconds;
      rearm = cfg.rearmThresholdC;
      # The sensor reports the threshold belonging to whichever node it read;
      # this is the fallback for the case where it reports none.
      threshold = cfg.junctionThresholdC;
      # Hold off re-firing until the enqueued sleep has expired, plus a poll's
      # grace. Re-arming on temperature alone would let a die that cools and
      # re-heats inside the window take a second overlapping lease.
      refractorySeconds = cfg.cooldownMinutes * 60 + 60;

      sensorPath = [ pkgs.coreutils ];
      sensor = builtins.readFile ./tripwire-gpu-sensor.sh;

      onFirePath = [ pkgs.coreutils ];
      onFire = builtins.readFile ./gpu-cooldown-enqueue.sh;

      environment = {
        HOME = "/home/${cfg.user}";
        JUNCTION_THRESHOLD_C = toString cfg.junctionThresholdC;
        TCTL_THRESHOLD_C = toString cfg.tctlThresholdC;
        COOLDOWN_MINUTES = toString cfg.cooldownMinutes;
        # tally lives in the user profile, not the system one; the poller runs
        # as cfg.user and enqueues against that user's daemon socket.
        TALLY_BIN = "/etc/profiles/per-user/${cfg.user}/bin/tally";
        SLEEP_BIN = "${pkgs.coreutils}/bin/sleep";
      };
    };
  };
}
