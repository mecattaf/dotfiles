{
  config,
  lib,
  pkgs,
  ...
}:
# myTripwire — a declarative sensor/threshold/sustain/act state machine.
#
# The fleet's observability substrate is journald plus systemd, and this module
# adds nothing to it: each tripwire is one timer and one oneshot, with its
# hysteresis state in a file under /var/lib. There is no daemon, no scrape
# endpoint and no polling agent to keep alive.
#
# The generalisation exists because the coordinator's GPU thermal poller was a
# bespoke bash state machine, and the second one would have been another. What
# is genuinely per-tripwire is the sensor and the action; the arming,
# accumulating, firing, and re-arming are the same every time and live in
# tripwire-poll.sh.
#
# Emission is structured: every poll writes journald fields (SENSOR_KIND=,
# THRESHOLD=, HELD_FOR=, DECISION=, and a per-instance value field) rather than
# a sentence, so `journalctl TEMP_C=93` answers a forensic question as data.
#
# tally is deliberately NOT a dependency. Observation is plain systemd; a
# tripwire that wants to enqueue work says so inside its own `onFire`, which is
# the single place a tally-shaped change can reach.
let
  cfg = config.myTripwire;

  pollScript = pkgs.writeShellApplication {
    name = "tripwire-poll";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.util-linux # logger --journald
    ];
    text = builtins.readFile ./tripwire-poll.sh;
  };

  tripwireOpts =
    { name, ... }:
    {
      options = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Whether this tripwire's timer is installed.";
        };

        description = lib.mkOption {
          type = lib.types.str;
          default = "${name} tripwire";
          description = "Unit description for the poller and its timer.";
        };

        sensor = lib.mkOption {
          type = lib.types.lines;
          description = ''
            Shell script printing ONE line to stdout: `<value> [<kind>] [<threshold>]`.
            `value` is an integer sample; `kind` labels the sample source and
            defaults to the tripwire name; `threshold` overrides
            `options.threshold` for this sample, which is how a sensor that
            chooses between sources with different trip points reports its
            choice. A non-zero exit fails the poll loudly rather than running blind.
          '';
        };

        sensorPath = lib.mkOption {
          type = with lib.types; listOf package;
          default = [ ];
          description = "runtimeInputs available on the sensor's PATH.";
        };

        threshold = lib.mkOption {
          type = lib.types.int;
          description = "Trip point, unless the sensor reports its own.";
        };

        comparison = lib.mkOption {
          type = lib.types.enum [
            "ge"
            "le"
          ];
          default = "ge";
          description = ''
            Direction of the trip. "ge" fires at or above the threshold (heat,
            queue depth, error counts); "le" fires at or below it (free bytes,
            battery charge).
          '';
        };

        rearm = lib.mkOption {
          type = with lib.types; nullOr int;
          default = null;
          description = ''
            Hysteresis point. Under "ge" the tripwire re-arms once the sample
            falls below this; under "le", once it rises above it. Defaults to
            `threshold`, i.e. no hysteresis gap.
          '';
        };

        sustainSeconds = lib.mkOption {
          type = lib.types.int;
          default = 0;
          description = "How long the condition must hold before firing. 0 fires on the first over-threshold poll.";
        };

        refractorySeconds = lib.mkOption {
          type = lib.types.int;
          default = 0;
          description = ''
            Quiet window after a successful fire during which no further fire is
            attempted, regardless of the sample. Independent of `rearm`: both
            must clear.
          '';
        };

        onFire = lib.mkOption {
          type = lib.types.lines;
          default = "";
          description = ''
            Shell script run when the tripwire fires, with the sample as
            `$1 $2 $3 $4` = value, kind, threshold, episode id, and the same
            values in TRIPWIRE_VALUE / TRIPWIRE_SENSOR_KIND / TRIPWIRE_THRESHOLD /
            TRIPWIRE_EPISODE_ID / TRIPWIRE_EPISODE_START / TRIPWIRE_HELD_FOR.

            The episode id is the alert's identity — `<kind>-<episode start>` —
            and is stable across retries of the same episode, so it is the
            correct dedup key for anything idempotent downstream.

            A non-zero exit leaves the tripwire armed on the same episode: the
            next poll retries under the same identity, and the poll unit fails
            so the failure itself gets surfaced.
          '';
        };

        onFirePath = lib.mkOption {
          type = with lib.types; listOf package;
          default = [ ];
          description = "runtimeInputs available on the onFire script's PATH.";
        };

        intervalSeconds = lib.mkOption {
          type = lib.types.int;
          default = 30;
          description = "Poll cadence.";
        };

        onBootSec = lib.mkOption {
          type = lib.types.str;
          default = "2min";
          description = "Delay before the first poll after boot.";
        };

        user = lib.mkOption {
          type = with lib.types; nullOr str;
          default = null;
          description = "User to poll as. Null polls as root.";
        };

        valueField = lib.mkOption {
          type = lib.types.str;
          default = "VALUE";
          description = ''
            journald field name carrying the sample, e.g. "TEMP_C". Naming it
            per-instance is what makes `journalctl TEMP_C=93` work as a query
            rather than a grep over prose.
          '';
        };

        environment = lib.mkOption {
          type = with lib.types; attrsOf str;
          default = { };
          description = "Extra environment for the poll, the sensor, and the onFire script.";
        };

        stateDirectory = lib.mkOption {
          type = lib.types.str;
          default = "tripwire/${name}";
          description = "StateDirectory= for the poll unit, relative to /var/lib.";
        };
      };
    };

  enabled = lib.filterAttrs (_: i: i.enable) cfg;

  sensorPkg =
    name: i:
    pkgs.writeShellApplication {
      name = "tripwire-${name}-sensor";
      runtimeInputs = i.sensorPath;
      text = i.sensor;
    };

  onFirePkg =
    name: i:
    pkgs.writeShellApplication {
      name = "tripwire-${name}-onfire";
      runtimeInputs = i.onFirePath;
      text = i.onFire;
    };
in
{
  options.myTripwire = lib.mkOption {
    type = with lib.types; attrsOf (submodule tripwireOpts);
    default = { };
    description = "Declarative sensor tripwires, each one systemd timer and one oneshot.";
  };

  config = lib.mkIf (enabled != { }) {
    systemd.services = lib.mapAttrs' (
      name: i:
      lib.nameValuePair "tripwire-${name}" {
        description = i.description;
        environment = {
          TRIPWIRE_NAME = name;
          TRIPWIRE_SENSOR = "${sensorPkg name i}/bin/tripwire-${name}-sensor";
          TRIPWIRE_ONFIRE = "${onFirePkg name i}/bin/tripwire-${name}-onfire";
          TRIPWIRE_THRESHOLD = toString i.threshold;
          TRIPWIRE_REARM = toString (if i.rearm == null then i.threshold else i.rearm);
          TRIPWIRE_SUSTAIN = toString i.sustainSeconds;
          TRIPWIRE_REFRACTORY = toString i.refractorySeconds;
          TRIPWIRE_COMPARISON = i.comparison;
          TRIPWIRE_VALUE_FIELD = i.valueField;
        }
        // i.environment;
        serviceConfig = {
          Type = "oneshot";
          ExecStart = "${pollScript}/bin/tripwire-poll";
          StateDirectory = i.stateDirectory;
        }
        // lib.optionalAttrs (i.user != null) { User = i.user; };
      }
    ) enabled;

    systemd.timers = lib.mapAttrs' (
      name: i:
      lib.nameValuePair "tripwire-${name}" {
        description = "Poll ${i.description}";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnBootSec = i.onBootSec;
          OnUnitActiveSec = "${toString i.intervalSeconds}s";
          AccuracySec = "5s";
        };
      }
    ) enabled;
  };
}
