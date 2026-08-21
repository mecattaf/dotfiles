{
  config,
  lib,
  pkgs,
  ...
}:
# GPU thermal cooldown tripwire (worker-only).
#
# A systemd timer polls this box's amdgpu junction temperature every 30s (falling
# back to k10temp Tctl where junction is absent — still the live case here,
# re-verified 2026-08-21: the amdgpu hwmon exposes only `edge`). On a SUSTAINED
# over-threshold reading it sheds the GPU load.
#
# Two layers (see the .sh files, which carry the detail):
#   LAYER 1  gpu-cooldown-poll.sh  — sensor read + trip logic + hysteresis.
#                                    Restored byte-identical from the retired
#                                    tree; only its prose changed.
#   LAYER 2  gpu-cooldown-shed.sh  — the action. REWRITTEN for #229: it now
#                                    unloads every resident llama-swap model
#                                    locally instead of SSH-ing to the
#                                    coordinator to take a `worker-gpu` Tally
#                                    lease that no longer exists. The full
#                                    reasoning lives in that file's header.
#
# Consequences of the Layer 2 rewrite, stated plainly so nobody has to rederive
# them: the tripwire no longer needs the fleet SSH key, no longer needs the
# coordinator to be up, no longer needs /etc/ssh/ssh_known_hosts, and no longer
# holds a lease that other GPU consumers cooperate with. It is now a local,
# self-contained reflex — which is the right shape for a thermal protection on a
# headless box in another room, and it is why the unit no longer runs as `tom`
# with a key: DynamicUser suffices for a loopback POST.
let
  cfg = config.services.gpuCooldownTripwire;

  pollScript = pkgs.writeShellApplication {
    name = "gpu-cooldown-poll";
    runtimeInputs = [ pkgs.coreutils ];
    text = builtins.readFile ./gpu-cooldown-poll.sh;
  };

  shedScript = pkgs.writeShellApplication {
    name = "gpu-cooldown-shed";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.curl
    ];
    text = builtins.readFile ./gpu-cooldown-shed.sh;
  };
in
{
  options.services.gpuCooldownTripwire = {
    enable = lib.mkEnableOption "the worker GPU thermal cooldown tripwire";

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
      description = "k10temp Tctl trip threshold (deg C), used when junction is absent — the live rail on this box.";
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
      description = "How long after a shed the tripwire stays suppressed, giving the box a real rest window.";
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.gpu-cooldown-tripwire = {
      description = "GPU thermal cooldown tripwire — poll junction/Tctl, shed llama-swap GPU load on a sustained trip";
      serviceConfig = {
        Type = "oneshot";
        # Was User=tom, because the old Layer 2 needed to read tom's mesh SSH
        # key. The loopback unload needs no identity at all, so the unit drops
        # to an ephemeral user; only the hwmon reads (world-readable) and the
        # state file (StateDirectory) are touched.
        DynamicUser = true;
        StateDirectory = "gpu-cooldown";
        ExecStart = "${pollScript}/bin/gpu-cooldown-poll";
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectHome = true;
        ProtectSystem = "strict";
        RestrictAddressFamilies = [
          "AF_INET"
          "AF_INET6"
          "AF_UNIX"
        ];
        Environment = [
          "COOLDOWN_ADAPTER=${shedScript}/bin/gpu-cooldown-shed"
          "LLAMA_SWAP_PORT=${toString config.services.llama-swap.port}"
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
