{
  config,
  inputs,
  lib,
  pkgs,
  ...
}:
# update-adopt — the fleet's ADOPTION plane (#354, 2026-09-13).
#
# Tom's App Store model (2026-08-21: "NAS builds and publishes, every device
# pulls and decides") had a publisher and no adopter: hosts/nas/update-center.nix
# builds every closure and pushes it to Attic, and activation stayed a manual
# `nixos-rebuild switch` per box. This module is the device half. Each enrolled
# host, on its own, independently of the others:
#
#   stage     (hourly) fetch http://nas:8734/candidates/<host>/manifest.json
#             and its .sig, verify with `ssh-keygen -Y verify -n fleet-update`
#             against the NAS host key from ./mesh-registry.nix, check host
#             and store-path shape, refuse a downgrade, then
#             `nix-store --realise <exact store path>` from the fleet Attic
#             under Nix's own signature trust — no flake eval, no source, no
#             moving `main` — and root it at gcroots/update-adopt/candidate.
#   activate  (every 30 min, and kicked by stage) take the lock, run the
#             gates, snapshot failed units, move the system profile, then
#             `switch-to-configuration switch` in a transient unit — or `boot`
#             when kernel/initrd/params differ from the BOOTED system — probe
#             for up to 10 min, and mark known-good or roll back locally to the
#             previous generation, re-probe, reject the candidate and exit 1 so
#             failure-surfacing writes a marker. If the profile moves under
#             the probe (someone else switched) it is `superseded`, never rolled
#             back; a switch that outlives its wait is `switch-hung`, never raced.
#
# THE EXIT-CODE CONTRACT. Busy is not broken: a gate deferral, a newer local
# generation, a manual policy or an unreachable NAS each exit 0 with a receipt
# under /var/lib/update-adopt/receipts (capped at 50). A bad signature, a
# failed realise or a failed probe exit 1. `update-adopt status --json` prints
# current / booted / candidate / last attempt / last refusal / last deferral /
# last known-good / pending reboot — "an old node should be visibly old".
#
# THE DOWNGRADE GUARD (challenger correction, mandatory). Tom and agents switch
# from local checkouts that run AHEAD of pushed main, and the NAS candidate is
# whatever main was at 01:30. Comparing only store paths would silently roll a
# box BACK. So every closure now carries its source revision
# (system.configurationRevision, and $out/fleet-revision.json with rev, dirty,
# lastModified — below, for every host), and adoption is refused unless the
# running generation is clean, recorded, and strictly older (by commit
# lastModified) than the candidate's own file inside its closure. A dirty or
# unknown current generation is refused too: a hand-switched dirty tree means a
# human is mid-change. `update-adopt adopt --force` is the operator's override;
# it skips this guard and the rejected list, never the gates.
#
# RESTART-SENSITIVE PINS. herdr, tally-b and tally-lake are
# rev-pinned and move only by commit; the rolling class is flake.nix's
# `rollingInputOverrides`. Moving closures still must not kill live state:
# home/herdr.nix sets X-SwitchMethod=keep-old (asserted by the
# herdr-oom-isolation check), browser-desktop is restartIfChanged=false, and
# the coordinator's gates below refuse while any Herdr agent is not idle/done,
# while the browser desktop or an operator-started Halogen server is active,
# and while a tally lease is held.
# Both update-adopt units are restartIfChanged=false/stopIfChanged=false, so a
# switch never kills the activation that is running it.
#
# POLICIES (hosts/*/default.nix): worker rolling, coordinator stage-only until
# the live downgrade refusal is seen (DEFERRED DF-354-1), then rolling; client
# manual (R-18: activated only by Tom's own switch — it discovers and reports),
# NAS NOT ENROLLED (2026-08-21 ruling: not built nightly, manual pinned bump;
# the flake's update-adopt check asserts it). rebootPolicy is `notify`
# everywhere: a boot-installed kernel writes the failure marker
# `update-adopt-reboot-pending` after 72 h and never reboots by itself.
let
  cfg = config.myUpdateAdopt;
  self = inputs.self;
  registry = import ./mesh-registry.nix;

  # Every host records where its closure came from (see the header). Dirty
  # trees carry dirtyRev and are refused as adoption bases.
  fleetRevision = {
    rev = self.rev or self.dirtyRev or "unknown";
    dirty = !(self ? rev);
    lastModified = self.lastModified or 0;
  };

  allowedSigners = pkgs.writeText "update-adopt-allowed-signers" ''
    nas namespaces="fleet-update" ${registry.nas.hostKey}
  '';

  gatesBin = pkgs.writeShellApplication {
    name = "update-adopt-gates";
    runtimeInputs = [
      pkgs.bash
      pkgs.coreutils
      pkgs.curl
      pkgs.gawk
      pkgs.iproute2
      pkgs.iputils
      pkgs.jq
      pkgs.systemd
      pkgs.util-linux
    ];
    # herdr and the live tally client come from tom's profile on the
    # coordinator: the gate must ask the SAME binaries the panes run.
    text = ''
      export PATH="$PATH:/etc/profiles/per-user/tom/bin:/run/current-system/sw/bin"
      exec bash ${./update-adopt-gates.sh} "$@"
    '';
  };

  configFile = pkgs.writeText "update-adopt.json" (
    builtins.toJSON {
      host = config.networking.hostName;
      inherit (cfg) policy;
      candidate_url = cfg.candidateUrl;
      allowed_signers = "${allowedSigners}";
      signer_identity = "nas";
      min_free_gib = cfg.minFreeGiB;
      psi_avg60_max = 20;
      settle_sec = 60;
      probe_window_sec = 600;
      probe_interval_sec = 15;
      gate_timeout_sec = 60;
      reboot_pending_alert_hours = cfg.rebootPendingAlertHours;
      marker_dir = config.myFailureSurfacing.markerDir;
      user_managers = cfg.userManagers;
      gates = map (g: { inherit (g) name argv; }) cfg.gates;
      probes =
        map (p: {
          inherit (p) name argv;
          timeout_sec = p.timeoutSec;
        }) cfg.probes
        ++ [
          {
            name = "nas-reachable";
            argv = [
              (lib.getExe gatesBin)
              "ping-host"
              "nas"
            ];
            timeout_sec = 10;
          }
        ]
        ++ lib.optional (cfg.requiredMounts != [ ]) {
          name = "required-mounts";
          argv = [
            (lib.getExe gatesBin)
            "mounts-present"
          ]
          ++ cfg.requiredMounts;
          timeout_sec = 10;
        };
      critical_units = [
        {
          unit = "sshd.service";
          user = null;
        }
      ]
      ++ map (u: { inherit (u) unit user; }) cfg.criticalUnits;
    }
  );

  cli = pkgs.writeShellApplication {
    name = "update-adopt";
    runtimeInputs = [
      config.nix.package
      pkgs.coreutils
      pkgs.curl
      pkgs.openssh
      pkgs.procps
      pkgs.python3
      pkgs.systemd
      pkgs.util-linux
    ];
    text = ''
      export UPDATE_ADOPT_CONFIG=${configFile}
      exec python3 ${./update-adopt.py} "$@"
    '';
  };

  entry = lib.types.submodule {
    options = {
      name = lib.mkOption { type = lib.types.str; };
      argv = lib.mkOption { type = lib.types.listOf lib.types.str; };
      timeoutSec = lib.mkOption {
        type = lib.types.int;
        default = 30;
      };
    };
  };
in
{
  options.myUpdateAdopt = {
    enable = lib.mkEnableOption "per-host adoption of the NAS's signed candidate closures (#354)";
    policy = lib.mkOption {
      type = lib.types.enum [
        "rolling"
        "stage-only"
        "manual"
      ];
      default = "manual";
      description = ''
        rolling: stage and activate when the gates allow. stage-only: realise
        the candidate, never activate. manual: fetch, verify and report only.
      '';
    };
    candidateUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://nas:8734/candidates";
    };
    gates = lib.mkOption {
      type = lib.types.listOf entry;
      default = [ ];
      description = "Host-specific gates: exit 0 clear, 1 busy, other unknown (defers).";
    };
    probes = lib.mkOption {
      type = lib.types.listOf entry;
      default = [ ];
      description = "Host-specific post-switch probes: exit 0 healthy.";
    };
    criticalUnits = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            unit = lib.mkOption { type = lib.types.str; };
            user = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = null;
            };
          };
        }
      );
      default = [ ];
      description = "Units that, if active before a switch, must be active after it.";
    };
    userManagers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Users whose managers must not gain failed units across a switch.";
    };
    requiredMounts = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
    };
    minFreeGiB = lib.mkOption {
      type = lib.types.int;
      default = 10;
    };
    rebootPolicy = lib.mkOption {
      type = lib.types.enum [ "notify" ];
      default = "notify";
      description = "Kernel changes install with `boot`; a marker after rebootPendingAlertHours. Never an unattended reboot.";
    };
    rebootPendingAlertHours = lib.mkOption {
      type = lib.types.int;
      default = 72;
    };
    gatesBin = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      default = lib.getExe gatesBin;
      description = "The gate/probe helper, for host gate argv lists.";
    };
  };

  config = lib.mkMerge [
    {
      system.configurationRevision = lib.mkDefault fleetRevision.rev;
      system.systemBuilderCommands = ''
        printf '%s\n' ${lib.escapeShellArg (builtins.toJSON fleetRevision)} > "$out/fleet-revision.json"
      '';
    }

    (lib.mkIf cfg.enable {
      environment.systemPackages = [ cli ];

      systemd.services.update-adopt-stage = {
        description = "Fetch, verify and realise this host's signed fleet candidate";
        after = [ "network-online.target" ];
        wants = [ "network-online.target" ];
        restartIfChanged = false;
        stopIfChanged = false;
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${lib.getExe cli} stage";
          StateDirectory = "update-adopt";
          StateDirectoryMode = "0700";
          # A cold closure over the LAN; a hung fetch must end as a failure.
          TimeoutStartSec = "6h";
          Nice = 10;
        };
      };
      systemd.timers.update-adopt-stage = {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "hourly";
          RandomizedDelaySec = "20min";
          Persistent = false;
        };
      };

      systemd.services.update-adopt-activate = {
        description = "Gate, switch, probe and keep or roll back the staged fleet candidate";
        after = [ "update-adopt-stage.service" ];
        restartIfChanged = false;
        stopIfChanged = false;
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${lib.getExe cli} activate";
          StateDirectory = "update-adopt";
          StateDirectoryMode = "0700";
          TimeoutStartSec = "2h";
        };
      };
      systemd.timers.update-adopt-activate = lib.mkIf (cfg.policy == "rolling") {
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "*:0/30";
          RandomizedDelaySec = "5min";
          Persistent = false;
        };
      };
    })
  ];
}
